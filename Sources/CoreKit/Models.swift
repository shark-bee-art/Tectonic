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
    /// 分时暂用 5 分钟线实现
    case m5

    public var displayName: String {
        switch self {
        case .day: "日K"
        case .week: "周K"
        case .month: "月K"
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

// MARK: - 资产类别（持仓与交易记录共用）

public enum AssetType: String, Codable, Sendable, CaseIterable, Identifiable {
    case stock, bond, fund, currency, crypto, option, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .stock: L10n.l("asset.stock")
        case .bond: L10n.l("asset.bond")
        case .fund: L10n.l("asset.fund")
        case .currency: L10n.l("asset.currency")
        case .crypto: L10n.l("asset.crypto")
        case .option: L10n.l("asset.option")
        case .other: L10n.l("asset.other")
        }
    }

    /// 默认市场（导入时推断）
    public var defaultMarket: Market {
        switch self {
        case .crypto: .crypto
        case .fund: .fund
        default: .us
        }
    }
}

// MARK: - 期权（期权仓位/交易）

public struct OptionSpec: Codable, Sendable, Hashable {
    public var callPut: String      // "call" / "put"
    public var strikePrice: Double
    public var expiryDate: Date?
    public var multiplier: Int     // 每张合约对应标的股数（默认 100）

    public init(callPut: String, strikePrice: Double, expiryDate: Date? = nil, multiplier: Int = 100) {
        self.callPut = callPut
        self.strikePrice = strikePrice
        self.expiryDate = expiryDate
        self.multiplier = multiplier
    }

    public var displayName: String {
        let cp = callPut == "call" ? L10n.l("option.call") : L10n.l("option.put")
        let strike = String(format: "%.0f", strikePrice)
        if let expiry = expiryDate {
            return "\(cp) \(strike) \(expiry.formatted(.dateTime.month().day()))"
        }
        return "\(cp) \(strike)"
    }
}

// MARK: - 交易记录

public struct Trade: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var date: Date
    public var assetType: AssetType
    public var name: String
    public var code: String
    public var market: Market
    public var direction: String      // "buy" / "sell"
    public var quantity: Double
    public var price: Double
    public var fee: Double
    public var notes: String
    public var option: OptionSpec?    // 期权仓位

    public init(id: String = UUID().uuidString, date: Date = Date(), assetType: AssetType = .stock,
                name: String, code: String, market: Market = .us, direction: String = "buy",
                quantity: Double, price: Double, fee: Double = 0, notes: String = "",
                option: OptionSpec? = nil) {
        self.id = id
        self.date = date
        self.assetType = assetType
        self.name = name
        self.code = code
        self.market = market
        self.direction = direction
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.notes = notes
        self.option = option
    }

    /// 交易总额（不含手续费：买入正/卖出负）
    public var grossAmount: Double {
        let sign = direction == "sell" ? -1.0 : 1.0
        return sign * quantity * price * Double(option?.multiplier ?? 1)
    }

    /// 含手续费总额
    public var netAmount: Double {
        grossAmount - fee
    }
}

// MARK: - 持仓（含期权与资产类别）

public struct Holding: Codable, Sendable, Identifiable {
    public var id: String { symbol.id }
    public let symbol: Symbol
    public let quantity: Double
    public let costBasis: Double    // 持仓成本价
    public let broker: String       // 来源券商/平台
    public let assetType: AssetType
    public let option: OptionSpec?  // 期权仓位
    public let importedAt: Date

    public init(symbol: Symbol, quantity: Double, costBasis: Double,
                broker: String, assetType: AssetType = .stock, option: OptionSpec? = nil,
                importedAt: Date = Date()) {
        self.symbol = symbol
        self.quantity = quantity
        self.costBasis = costBasis
        self.broker = broker
        self.assetType = assetType
        self.option = option
        self.importedAt = importedAt
    }
}
