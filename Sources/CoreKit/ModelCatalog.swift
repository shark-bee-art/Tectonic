import Foundation

/// 模型目录（ModelCatalog）：静态主流清单 + 网络刷新（各家 /models 端点）+ 7 天缓存。
/// 参考 Tide 实现：设置里模型从 TextField 改为下拉选择栏，选项覆盖各家主流模型，每周自动更新。
public enum ModelCatalog {

    // MARK: - 静态主流清单（无 Key/离线兜底）

    public static func mainstream(for provider: ModelProvider) -> [String] {
        switch provider {
        case .ollama:
            ["qwen3.5:4b", "qwen2.5:7b", "qwen2.5:14b", "llama3.1:8b", "deepseek-r1:7b", "mistral:7b", "phi4:14b"]
        case .openai:
            ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "o3", "o4-mini"]
        case .anthropic:
            ["claude-sonnet-4-20250514", "claude-haiku-4-20250514", "claude-3-5-sonnet-20241022",
             "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case .gemini:
            ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .deepseek:
            ["deepseek-chat", "deepseek-reasoner"]
        case .kimi:
            ["kimi-latest", "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"]
        case .tongyi:
            ["qwen-plus", "qwen-turbo", "qwen-max", "qwen-long", "qwen2.5-72b-instruct"]
        case .zhipu:
            ["glm-4-plus", "glm-4-flash", "glm-4-air", "glm-4-long", "glm-4"]
        case .wenxin:
            ["ernie-4.0-turbo-8k", "ernie-4.0-8k", "ernie-3.5-8k", "ernie-speed-8k", "ernie-lite-8k"]
        case .doubao:
            ["doubao-1-5-pro-32k-250115", "doubao-1-5-lite-32k-250115", "doubao-seed-1-6-250615"]
        }
    }

    // MARK: - 目录（缓存优先，其次静态）

    public static func available(provider: ModelProvider) -> [String] {
        let cached = cached(provider: provider)
        let list = cached ?? mainstream(for: provider)
        return dedupeSorted(list)
    }

    // MARK: - 网络刷新

    /// 拉取真实模型列表（Ollama 本机实时；其他需 Key）。失败返回 nil（UI 静默回退静态清单）。
    public static func refresh(provider: ModelProvider, apiKey: String?) async -> [String]? {
        guard let base = provider.presetBaseURL else { return nil }
        let url: URL?
        var headers: [String: String] = [:]

        switch provider {
        case .ollama:
            // 配置里 baseURL 可能是 http://localhost:11434/v1（OpenAI 兼容前缀），原生 API 在根路径
            var ollamaBase = URL(string: base)
            if ollamaBase?.lastPathComponent == "v1" { ollamaBase?.deleteLastPathComponent() }
            url = ollamaBase?.appendingPathComponent("api/tags")
        case .anthropic:
            url = URL(string: base)?.appendingPathComponent("v1/models")
            if let key = apiKey, !key.isEmpty {
                headers["x-api-key"] = key
                headers["anthropic-version"] = "2023-06-01"
            }
        case .gemini:
            var components = URLComponents(string: base)
            components?.path = "/v1beta/models"
            if let key = apiKey, !key.isEmpty {
                components?.queryItems = [URLQueryItem(name: "key", value: key)]
            }
            url = components?.url
        default:
            // OpenAI 兼容：GET {base}/models，Bearer key
            url = URL(string: base)?.appendingPathComponent("models")
            if let key = apiKey, !key.isEmpty {
                headers["Authorization"] = "Bearer \(key)"
            }
        }

        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var models: [String] = []
        // OpenAI 兼容 / Anthropic: data[].id
        if let dataArr = json["data"] as? [[String: Any]] {
            models = dataArr.compactMap { $0["id"] as? String }
        }
        // Gemini / Ollama: models[].name（Gemini 带 models/ 前缀需剥掉）
        if models.isEmpty, let modelsArr = json["models"] as? [[String: Any]] {
            models = modelsArr.compactMap { item -> String? in
                guard let name = item["name"] as? String else { return nil }
                return name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
            }
        }
        // Ollama 有时返回 name 在顶层 item
        if models.isEmpty, let modelsArr = json["models"] as? [[String: Any]] {
            models = modelsArr.compactMap { $0["name"] as? String }
        }

        let filtered = models.filter { !isNonChat($0) }
        let result = dedupeSorted(filtered)
        guard !result.isEmpty else { return nil }
        saveCache(result, provider: provider)
        return result
    }

    // MARK: - 缓存（UserDefaults，7 天）

    private static let ttl: TimeInterval = 7 * 24 * 3600

    public static func cached(provider: ModelProvider) -> [String]? {
        let d = UserDefaults.standard
        guard let updated = d.object(forKey: "model_catalog_updated_\(provider.rawValue)") as? Date,
              Date().timeIntervalSince(updated) < ttl,
              let list = d.stringArray(forKey: "model_catalog_\(provider.rawValue)"),
              !list.isEmpty else {
            return nil
        }
        return list
    }

    public static func isStale(provider: ModelProvider) -> Bool {
        cached(provider: provider) == nil
    }

    private static func saveCache(_ models: [String], provider: ModelProvider) {
        let d = UserDefaults.standard
        d.set(models, forKey: "model_catalog_\(provider.rawValue)")
        d.set(Date(), forKey: "model_catalog_updated_\(provider.rawValue)")
    }

    // MARK: - 工具

    private static func isNonChat(_ model: String) -> Bool {
        let lower = model.lowercased()
        for keyword in ["embed", "whisper", "tts", "moderation", "dall-e", "rerank", "image"] {
            if lower.contains(keyword) { return true }
        }
        return false
    }

    private static func dedupeSorted(_ list: [String]) -> [String] {
        var seen: Set<String> = []
        return list.filter { seen.insert($0).inserted }.sorted()
    }
}
