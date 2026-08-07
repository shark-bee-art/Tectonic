import Foundation

// MARK: - 市场枚举

/// 支持的市场。优先级默认按声明顺序（可在设置中调整显示与排序）。
public enum Market: String, CaseIterable, Codable, Sendable, Identifiable {
    case us      // 美股
    case crypto  // 加密
    case hk      // 港股
    case cn      // A股
    case fund    // 基金
    case kr      // 韩股
    case jp      // 日股
    case tw      // 台股

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .us: "美股"
        case .crypto: "加密"
        case .hk: "港股"
        case .cn: "A股"
        case .fund: "基金"
        case .kr: "韩股"
        case .jp: "日股"
        case .tw: "台股"
        }
    }

    /// 货币代码（用于显示）
    public var currency: String {
        switch self {
        case .us, .crypto: "USD"
        case .hk: "HKD"
        case .cn, .fund: "CNY"
        case .kr: "KRW"
        case .jp: "JPY"
        case .tw: "TWD"
        }
    }

    /// 休市时段（简化的交易时段描述，用于 UI 展示）
    public var tradingHours: String {
        switch self {
        case .us: "9:30–16:00 ET"
        case .crypto: "24/7"
        case .hk: "9:30–16:00 HKT"
        case .cn: "9:30–15:00 CST"
        case .fund: "T日净值"
        case .kr: "9:00–15:30 KST"
        case .jp: "9:00–15:00 JST"
        case .tw: "9:00–13:30 TST"
        }
    }
}

// MARK: - 标的（Symbol）

/// 一个可交易/可关注的标的。
/// symbol 为具体代码：美股 AAPL、港股 00700.HK、A股 600519.SH、加密 BTCUSDT、基金 110022。
public struct Symbol: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(market.rawValue):\(code)" }
    public let market: Market
    public let code: String
    public var name: String          // 显示名（中文优先）
    public var currency: String

    public init(market: Market, code: String, name: String, currency: String? = nil) {
        self.market = market
        self.code = code
        self.name = name
        self.currency = currency ?? market.currency
    }
}

// MARK: - 行情快照（Quote）

/// 单个标的的实时/延迟行情快照。
public struct Quote: Codable, Sendable, Identifiable {
    public var id: String { symbol.id }
    public let symbol: Symbol
    public let price: Double
    public let change: Double          // 涨跌额
    public let changePercent: Double   // 涨跌幅 %
    public let open: Double
    public let high: Double
    public let low: Double
    public let prevClose: Double
    public let volume: Double
    public let timestamp: Date

    public init(symbol: Symbol, price: Double, change: Double, changePercent: Double,
                open: Double, high: Double, low: Double, prevClose: Double,
                volume: Double, timestamp: Date = Date()) {
        self.symbol = symbol
        self.price = price
        self.change = change
        self.changePercent = changePercent
        self.open = open
        self.high = high
        self.low = low
        self.prevClose = prevClose
        self.volume = volume
        self.timestamp = timestamp
    }
}

// MARK: - K线数据（KLineBar）

public enum KLinePeriod: String, Codable, Sendable, CaseIterable {
    case day   // 日K
    case week  // 周K
    case month // 月K
    case year  // 年K（月K聚合）
    /// 分时暂用 5 分钟线实现
    case m5

    public var displayName: String {
        switch self {
        case .day: "日K"
        case .week: "周K"
        case .month: "月K"
        case .year: "年K"
        case .m5: "分时"
        }
    }
}

public struct KLineBar: Codable, Sendable, Identifiable {
    public var id: String { "\(symbolId)-\(period.rawValue)-\(time.timeIntervalSince1970)" }
    public let symbolId: String
    public let period: KLinePeriod
    public let time: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double

    public init(symbolId: String, period: KLinePeriod, time: Date, open: Double,
                high: Double, low: Double, close: Double, volume: Double) {
        self.symbolId = symbolId
        self.period = period
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

// MARK: - 自选（WatchlistItem）

public struct WatchlistItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String { symbol.id }
    public let symbol: Symbol
    public var group: String      // 分组名，默认"默认分组"
    public var sortOrder: Int     // 组内排序
    public var addedAt: Date

    public init(symbol: Symbol, group: String = "默认分组", sortOrder: Int = 0, addedAt: Date = Date()) {
        self.symbol = symbol
        self.group = group
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }
}

// MARK: - 新闻（NewsItem）

/// AI 自动打标结果：抓取新闻时对市场/标的的影响判断。
public struct NewsTag: Codable, Sendable, Hashable {
    public enum Stance: String, Codable, Sendable {
        case bullish    // 看多
        case bearish    // 看空
        case neutral    // 中性
    }
    public enum Impact: String, Codable, Sendable {
        case positive   // 利好
        case negative   // 利空
        case neutral    // 中性
    }

    public var stance: Stance
    public var impact: Impact
    public var relatedSymbols: [String]   // 关联标的代码
    public var relatedMarkets: [Market]   // 关联市场
    public var brief: String              // 一句话影响解读
    public var model: String              // 打标所用模型

    public init(stance: Stance, impact: Impact, relatedSymbols: [String] = [],
                relatedMarkets: [Market] = [], brief: String = "", model: String = "") {
        self.stance = stance
        self.impact = impact
        self.relatedSymbols = relatedSymbols
        self.relatedMarkets = relatedMarkets
        self.brief = brief
        self.model = model
    }
}

public struct NewsItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public let title: String
    public let summary: String
    public let url: String
    public let source: String       // 来源名（RSS 站点名/API 名）
    public let publishedAt: Date
    public var content: String?     // 全文（可选，抓取后填充）
    public var tags: [Market]       // 关联市场（预打标，AI 打标前的基础分类）
    public var aiTag: NewsTag?      // AI 自动打标结果

    public init(id: String = UUID().uuidString, title: String, summary: String, url: String,
                source: String, publishedAt: Date, content: String? = nil,
                tags: [Market] = [], aiTag: NewsTag? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.url = url
        self.source = source
        self.publishedAt = publishedAt
        self.content = content
        self.tags = tags
        self.aiTag = aiTag
    }
}
