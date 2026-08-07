import Foundation

// MARK: - 用户设置（UserDefaults 本地存储，无钥匙串）

/// 市场显示开关与排序（UserDefaults 持久化）
public struct MarketSettings: Codable, Sendable {
    public var enabledMarkets: [Market]
    public var order: [Market]     // 显示优先级

    public static let `default` = MarketSettings(
        enabledMarkets: Market.allCases,
        order: Market.allCases
    )
}

// MARK: - 搜索服务商（联网搜索 API，类似大模型提供商：官网申请 Key）

public enum SearchProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case brave, serper, tavily

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .brave: "Brave Search"
        case .serper: "Serper (Google)"
        case .tavily: "Tavily AI"
        }
    }

    /// 官网申请页
    public var signupURL: String {
        switch self {
        case .brave: "https://brave.com/search/api/"
        case .serper: "https://serper.dev/"
        case .tavily: "https://tavily.com/"
        }
    }

    /// 免费额度说明
    public var freeTier: String {
        switch self {
        case .brave: "免费 2000 次/月"
        case .serper: "免费 2500 次"
        case .tavily: "免费 1000 次/月"
        }
    }
}

/// 全局设置入口：市场开关/排序 + 数据源 + AI。
public final class AppSettings: ObservableObject {
    public static let suiteName = "com.tectonic.app"

    @Published public var enabledMarkets: [Market] {
        didSet { save() }
    }
    @Published public var marketOrder: [Market] {
        didSet { save() }
    }
    /// AI 首选语言（zh/en/ja）——整个应用的界面语言
    @Published public var preferredLanguage: String {
        didSet { save() }
    }
    /// 行情自动刷新频率（分钟：5/10/30/60；0 表示仅手动刷新）
    @Published public var refreshIntervalMinutes: Int {
        didSet { save() }
    }
    /// 联网搜索服务商 + API Key（官网申请，类似大模型提供商）
    @Published public var searchProvider: SearchProvider {
        didSet { save() }
    }
    @Published public var searchAPIKey: String {
        didSet { save() }
    }
    /// 界面主题 ID（TectonicThemeCatalog.themes，20 种预置）
    @Published public var themeID: String {
        didSet { save() }
    }

    public init(defaults: UserDefaults = .standard) {
        let d = defaults
        let decoder = JSONDecoder()
        if let data = d.data(forKey: "market_enabled"),
           let list = try? decoder.decode([Market].self, from: data) {
            enabledMarkets = list
        } else {
            enabledMarkets = Market.allCases
        }
        if let data = d.data(forKey: "market_order"),
           let list = try? decoder.decode([Market].self, from: data) {
            marketOrder = list
        } else {
            marketOrder = Market.allCases
        }
        preferredLanguage = d.string(forKey: "preferred_language") ?? "zh"
        refreshIntervalMinutes = d.object(forKey: "refresh_interval_minutes") as? Int ?? 5
        searchProvider = SearchProvider(rawValue: d.string(forKey: "search_provider") ?? "") ?? .brave
        searchAPIKey = d.string(forKey: "search_api_key") ?? ""
        themeID = d.string(forKey: "theme_id") ?? TectonicThemeCatalog.defaultID
    }

    /// AI 回复语言指令（跟随全局界面语言）
    public var languageInstruction: String {
        switch L10n.currentLanguage {
        case "en": "Reply in English."
        case "ja": "日本語で回答してください。"
        default: "回答使用简体中文。"
        }
    }

    public func isEnabled(_ market: Market) -> Bool {
        enabledMarkets.contains(market)
    }

    public func setEnabled(_ market: Market, enabled: Bool) {
        if enabled {
            if !enabledMarkets.contains(market) { enabledMarkets.append(market) }
        } else {
            enabledMarkets.removeAll { $0 == market }
        }
    }

    /// 拖拽排序后重排 marketOrder
    public func setOrder(_ newOrder: [Market]) {
        marketOrder = newOrder
    }

    /// 移动某市场到新位置（支持拖拽 onMove 与上下按钮）
    /// SwiftUI onMove 的 destination 是「移除 source 后的插入位置」，直接插入即可
    public func moveMarket(from source: IndexSet, to destination: Int) {
        guard let fromIdx = source.first, fromIdx < marketOrder.count else { return }
        var order = marketOrder
        let item = order.remove(at: fromIdx)
        order.insert(item, at: min(max(destination, 0), order.count))
        marketOrder = order
    }

    public func moveMarketUp(_ market: Market) {
        guard let idx = marketOrder.firstIndex(of: market), idx > 0 else { return }
        var order = marketOrder
        order.swapAt(idx, idx - 1)
        marketOrder = order
    }

    public func moveMarketDown(_ market: Market) {
        guard let idx = marketOrder.firstIndex(of: market), idx < marketOrder.count - 1 else { return }
        var order = marketOrder
        order.swapAt(idx, idx + 1)
        marketOrder = order
    }

    private func save() {
        let encoder = JSONEncoder()
        let d = UserDefaults.standard
        d.set(try? encoder.encode(enabledMarkets), forKey: "market_enabled")
        d.set(try? encoder.encode(marketOrder), forKey: "market_order")
        d.set(preferredLanguage, forKey: "preferred_language")
        d.set(refreshIntervalMinutes, forKey: "refresh_interval_minutes")
        d.set(searchProvider.rawValue, forKey: "search_provider")
        d.set(searchAPIKey, forKey: "search_api_key")
        d.set(themeID, forKey: "theme_id")
    }
}

// MARK: - AI 网关设置（复用 Tide 模式：OpenAI 兼容协议 + Ollama 原生）

public enum ModelProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    // 本地
    case ollama
    // 国际云端
    case openai
    case anthropic
    case gemini
    // 国内云端
    case deepseek
    case kimi
    case tongyi
    case zhipu
    case wenxin
    case doubao

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: "Ollama（本地）"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        case .kimi: "Kimi"
        case .tongyi: "通义千问"
        case .zhipu: "智谱"
        case .wenxin: "文心一言"
        case .doubao: "豆包"
        }
    }

    public var group: String {
        switch self {
        case .ollama: "本地"
        case .openai, .anthropic, .gemini: "国际云端"
        default: "国内云端"
        }
    }

    /// 预设 baseURL（OpenAI 兼容协议）
    public var presetBaseURL: String? {
        switch self {
        case .ollama: "http://localhost:11434"
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com"
        case .deepseek: "https://api.deepseek.com/v1"
        case .kimi: "https://api.moonshot.cn/v1"
        case .tongyi: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .wenxin: "https://qianfan.baidubce.com/v2"
        case .doubao: "https://ark.cn-beijing.volces.com/api/v3"
        }
    }

    /// 预设模型名
    public var presetModel: String {
        switch self {
        case .ollama: "qwen2.5:7b"
        case .openai: "gpt-4o-mini"
        case .anthropic: "claude-3-5-sonnet-20241022"
        case .gemini: "gemini-1.5-flash"
        case .deepseek: "deepseek-chat"
        case .kimi: "moonshot-v1-8k"
        case .tongyi: "qwen-plus"
        case .zhipu: "glm-4-flash"
        case .wenxin: "ernie-4.0-turbo-8k"
        case .doubao: "doubao-1-5-lite-32k-250115"
        }
    }

    /// 是否走 OpenAI 兼容协议
    public var usesOpenAICompat: Bool {
        self != .ollama && self != .anthropic && self != .gemini
    }
}

public final class AISettings: ObservableObject {
    @Published public var provider: ModelProvider {
        didSet { save() }
    }
    @Published public var model: String {
        didSet { save() }
    }
    @Published public var apiKeys: [String: String] {
        didSet { save() }
    }
    /// 思考深度（low/medium/high）——固定适中，不再暴露 UI
    @Published public var reasoningEffort: String {
        didSet { save() }
    }
    /// 联网搜索：默认开启（不再暴露 UI 开关）
    @Published public var webSearchEnabled: Bool {
        didSet { save() }
    }

    public init(defaults: UserDefaults = .standard) {
        let d = defaults
        let p = ModelProvider(rawValue: d.string(forKey: "ai_provider") ?? "") ?? .deepseek
        provider = p
        model = d.string(forKey: "ai_model") ?? p.presetModel
        apiKeys = d.dictionary(forKey: "ai_api_keys") as? [String: String] ?? [:]
        reasoningEffort = d.string(forKey: "ai_reasoning_effort") ?? "medium"
        // 联网默认开启
        webSearchEnabled = d.object(forKey: "ai_web_search") as? Bool ?? true
    }

    public func apiKey(for provider: ModelProvider) -> String? {
        apiKeys[provider.rawValue]
    }

    public func setAPIKey(_ key: String, for provider: ModelProvider) {
        var keys = apiKeys
        if key.isEmpty {
            keys.removeValue(forKey: provider.rawValue)
        } else {
            keys[provider.rawValue] = key
        }
        apiKeys = keys
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(provider.rawValue, forKey: "ai_provider")
        d.set(model, forKey: "ai_model")
        d.set(apiKeys, forKey: "ai_api_keys")
        d.set(reasoningEffort, forKey: "ai_reasoning_effort")
        d.set(webSearchEnabled, forKey: "ai_web_search")
    }
}
