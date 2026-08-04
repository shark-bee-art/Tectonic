import Foundation

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public let role: String   // system / user / assistant
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ text: String) -> ChatMessage { ChatMessage(role: "system", content: text) }
    public static func user(_ text: String) -> ChatMessage { ChatMessage(role: "user", content: text) }
    public static func assistant(_ text: String) -> ChatMessage { ChatMessage(role: "assistant", content: text) }
}

public struct ModelGatewayError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// 多供应商 LLM 网关：OpenAI 兼容协议（OpenAI/DeepSeek/Kimi/通义/智谱/文心/豆包…）+ Ollama 原生 + Anthropic/Gemini。
/// 每次调用显式传 provider/model/key，不持有可变状态（Sendable）。
public struct ModelGateway: Sendable {

    public init() {}

    // MARK: - 对话

    public func chat(messages: [ChatMessage],
                     provider: ModelProvider,
                     model: String,
                     apiKey: String? = nil,
                     temperature: Double = 0.7,
                     maxTokens: Int = 2048,
                     reasoningEffort: String? = nil) async throws -> String {
        if provider.usesOpenAICompat {
            return try await chatOpenAICompat(messages: messages, provider: provider,
                                              model: model, apiKey: apiKey,
                                              temperature: temperature, maxTokens: maxTokens,
                                              reasoningEffort: reasoningEffort)
        }
        switch provider {
        case .ollama:
            return try await chatOllama(messages: messages, model: model, temperature: temperature)
        case .anthropic:
            return try await chatAnthropic(messages: messages, model: model, apiKey: apiKey)
        case .gemini:
            return try await chatGemini(messages: messages, model: model, apiKey: apiKey)
        default:
            throw ModelGatewayError("不支持的供应商: \(provider.displayName)")
        }
    }

    /// 单轮问答便捷方法
    public func ask(_ userText: String,
                    system: String = "你是一个专业的财经分析助手，回答使用简体中文，数据要注明来源与不确定性。",
                    provider: ModelProvider,
                    model: String,
                    apiKey: String? = nil,
                    reasoningEffort: String? = nil) async throws -> String {
        try await chat(messages: [.system(system), .user(userText)],
                       provider: provider, model: model, apiKey: apiKey,
                       reasoningEffort: reasoningEffort)
    }

    // MARK: - 新闻自动打标（结构化输出）

    /// 对新闻做多空/利好利空/关联标的判断，输出结构化 NewsTag。
    public func tagNews(title: String, summary: String,
                        provider: ModelProvider,
                        model: String,
                        apiKey: String? = nil) async throws -> NewsTag {
        let system = """
        你是一个财经新闻分析器。分析下面这条新闻，输出严格的 JSON（不要 markdown 代码块，只要纯 JSON）：
        {"stance":"bullish|bearish|neutral","impact":"positive|negative|neutral","related_symbols":["AAPL"],"related_markets":["us"],"brief":"一句话影响解读（中文，<50字）"}
        stance=多空倾向（对市场整体），impact=对相关标的是否有利，related_markets 用枚举值：us/crypto/hk/cn/fund/kr/jp/tw。
        """
        let user = "新闻标题：\(title)\n新闻摘要：\(summary)"
        let raw = try await ask(user, system: system, provider: provider, model: model, apiKey: apiKey)
        return try parseTag(from: raw, provider: provider, model: model)
    }

    private func parseTag(from raw: String, provider: ModelProvider, model: String) throws -> NewsTag {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}") else {
            throw ModelGatewayError("打标输出不是 JSON: \(raw.prefix(80))")
        }
        let jsonStr = String(raw[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelGatewayError("打标 JSON 解析失败")
        }
        let stance = NewsTag.Stance(rawValue: obj["stance"] as? String ?? "neutral") ?? .neutral
        let impact = NewsTag.Impact(rawValue: obj["impact"] as? String ?? "neutral") ?? .neutral
        let symbols = (obj["related_symbols"] as? [String]) ?? []
        let markets = ((obj["related_markets"] as? [String]) ?? []).compactMap { Market(rawValue: $0) }
        let brief = obj["brief"] as? String ?? ""
        return NewsTag(stance: stance, impact: impact, relatedSymbols: symbols,
                       relatedMarkets: markets, brief: brief, model: "\(provider.rawValue)/\(model)")
    }

    // MARK: - OpenAI 兼容

    private func chatOpenAICompat(messages: [ChatMessage],
                                  provider: ModelProvider,
                                  model: String,
                                  apiKey: String?,
                                  temperature: Double,
                                  maxTokens: Int,
                                  reasoningEffort: String? = nil) async throws -> String {
        guard let base = provider.presetBaseURL else {
            throw ModelGatewayError("\(provider.displayName) 缺少 baseURL")
        }
        let url = URL(string: base)!
            .appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        // 思考深度（OpenAI 兼容模型：o 系列 / DeepSeek 部分模型支持）
        if let reasoningEffort, !reasoningEffort.isEmpty {
            body["reasoning_effort"] = reasoningEffort
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw ModelGatewayError("请求 \(url.absoluteString) 失败: HTTP \(http.statusCode) \(msg)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ModelGatewayError("响应缺少 choices[0].message.content")
        }
        return content
    }

    // MARK: - Ollama（原生协议）

    private func chatOllama(messages: [ChatMessage], model: String, temperature: Double) async throws -> String {
        guard let base = ModelProvider.ollama.presetBaseURL,
              let url = URL(string: base)?.appendingPathComponent("api/chat") else {
            throw ModelGatewayError("Ollama 地址无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
            "options": ["temperature": temperature],
            "think": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ModelGatewayError("Ollama 请求失败: HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["message"] as? [String: Any],
              let text = content["content"] as? String else {
            throw ModelGatewayError("Ollama 响应解析失败")
        }
        return text
    }

    // MARK: - Anthropic（原生协议）

    private func chatAnthropic(messages: [ChatMessage], model: String, apiKey: String?) async throws -> String {
        guard let base = ModelProvider.anthropic.presetBaseURL,
              let url = URL(string: base)?.appendingPathComponent("v1/messages") else {
            throw ModelGatewayError("Anthropic 地址无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "x-api-key")
        }
        let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        let userMsgs = messages.filter { $0.role != "system" }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": userMsgs.map { ["role": $0.role == "assistant" ? "assistant" : "user", "content": $0.content] },
        ]
        if !system.isEmpty { body["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw ModelGatewayError("Anthropic 请求失败: HTTP \(http.statusCode) \(msg)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ModelGatewayError("Anthropic 响应解析失败")
        }
        return text
    }

    // MARK: - Gemini（原生协议）

    private func chatGemini(messages: [ChatMessage], model: String, apiKey: String?) async throws -> String {
        guard let base = ModelProvider.gemini.presetBaseURL,
              var components = URLComponents(string: base) else {
            throw ModelGatewayError("Gemini 地址无效")
        }
        components.path = "/v1beta/models/\(model):generateContent"
        if let key = apiKey, !key.isEmpty {
            components.queryItems = [URLQueryItem(name: "key", value: key)]
        }
        guard let url = components.url else {
            throw ModelGatewayError("Gemini URL 无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let parts = messages.filter { $0.role != "system" }.map {
            ["role": $0.role == "assistant" ? "model" : "user", "parts": [["text": $0.content]]]
        }
        var body: [String: Any] = ["contents": parts]
        let system = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
        if !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw ModelGatewayError("Gemini 请求失败: HTTP \(http.statusCode) \(msg)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw ModelGatewayError("Gemini 响应解析失败")
        }
        return text
    }

    // MARK: - 错误信息透传

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8).map { String($0.prefix(200)) }
        }
        if let error = json["error"] as? [String: Any] {
            if let msg = error["message"] as? String { return msg }
            if let msg = error["msg"] as? String { return msg }
        }
        if let msg = json["message"] as? String { return msg }
        if let msg = json["error"] as? String { return msg }
        return nil
    }
}
