import Foundation

// MARK: - 平台（券商）

/// 券商/交易平台。账户挂在平台下（可空，手动账户可不选平台）。
public struct Platform: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var url: String

    public init(id: String = UUID().uuidString, name: String, url: String = "") {
        self.id = id
        self.name = name
        self.url = url
    }
}

// MARK: - 账户

public enum AccountType: String, Codable, Sendable, CaseIterable, Identifiable {
    case securities   // 证券账户
    case cash         // 现金账户
    case crypto       // 加密账户
    case creditCard   // 信用卡/负债

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .securities: L10n.l("account.type.securities")
        case .cash: L10n.l("account.type.cash")
        case .crypto: L10n.l("account.type.crypto")
        case .creditCard: L10n.l("account.type.creditCard")
        }
    }
}

/// 账户。交易活动挂在账户下；每个账户有自己的币种。
public struct Account: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var type: AccountType
    public var currency: String      // 账户币种（USD/CNY/HKD...）
    public var platformID: String?   // 关联券商（可空）
    public var isDefault: Bool
    public var isActive: Bool
    public var sortOrder: Int

    public init(id: String = UUID().uuidString, name: String, type: AccountType = .securities,
                currency: String = "USD", platformID: String? = nil,
                isDefault: Bool = false, isActive: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.platformID = platformID
        self.isDefault = isDefault
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}

// MARK: - 资产（标的规范化）

/// 资产实体。id = symbol.id（market:code），复用现有行情体系；
/// 交易录入时自动 upsert（对齐 Wealthfolio assets 表语义）。
public struct Asset: Codable, Sendable, Identifiable, Hashable {
    public var id: String            // market:code
    public var market: Market
    public var code: String
    public var name: String
    public var currency: String
    public var assetType: AssetType
    public var isActive: Bool

    public init(id: String = "", market: Market, code: String, name: String,
                currency: String? = nil, assetType: AssetType = .stock, isActive: Bool = true) {
        let sym = Symbol(market: market, code: code, name: name, currency: currency)
        self.id = id.isEmpty ? sym.id : id
        self.market = market
        self.code = code
        self.name = name
        self.currency = currency ?? market.currency
        self.assetType = assetType
        self.isActive = isActive
    }

    public var symbol: Symbol {
        Symbol(market: market, code: code, name: name, currency: currency)
    }
}

// MARK: - 活动类型（交易账本）

/// 交易活动类型（对齐 Wealthfolio activities）。
public enum ActivityType: String, Codable, Sendable, CaseIterable, Identifiable {
    case buy           // 买入
    case sell          // 卖出
    case split         // 拆股
    case dividend      // 分红
    case interest      // 利息
    case deposit       // 存款
    case withdrawal    // 取款
    case transferIn    // 转入
    case transferOut   // 转出
    case fee           // 费用
    case tax           // 税
    case credit        // 贷记
    case adjustment    // 调整
    case unknown       // 未知

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .buy: L10n.l("activity.buy")
        case .sell: L10n.l("activity.sell")
        case .split: L10n.l("activity.split")
        case .dividend: L10n.l("activity.dividend")
        case .interest: L10n.l("activity.interest")
        case .deposit: L10n.l("activity.deposit")
        case .withdrawal: L10n.l("activity.withdrawal")
        case .transferIn: L10n.l("activity.transferIn")
        case .transferOut: L10n.l("activity.transferOut")
        case .fee: L10n.l("activity.fee")
        case .tax: L10n.l("activity.tax")
        case .credit: L10n.l("activity.credit")
        case .adjustment: L10n.l("activity.adjustment")
        case .unknown: L10n.l("activity.unknown")
        }
    }

    /// 是否需要资产（证券类活动需要标的，现金类不需要）
    public var requiresAsset: Bool {
        switch self {
        case .buy, .sell, .split, .dividend, .interest, .credit, .adjustment: true
        case .deposit, .withdrawal, .transferIn, .transferOut, .fee, .tax, .unknown: false
        }
    }

    /// 是否为价格承载类型（有 unitPrice 语义）
    public var isPriceBearing: Bool {
        switch self {
        case .buy, .sell: true
        default: false
        }
    }
}

// MARK: - 交易活动（替代旧 Trade）

/// 一笔交易/资金活动。交易记录是持仓的唯一事实来源。
public struct Activity: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var accountID: String
    public var assetID: String?      // 证券类活动必有；现金类可空
    public var type: ActivityType
    public var date: Date
    public var quantity: Double      // 数量（买卖/拆股/实物分红）
    public var unitPrice: Double     // 单价（买入/卖出价）
    public var amount: Double        // 总金额（现金类活动用；买卖类 = quantity × unitPrice）
    public var fee: Double
    public var currency: String      // 活动币种（账户币种，可不同于基准币种）
    public var fxRate: Double?       // 活动币种 → 基准币种汇率（可选，估值时换算）
    public var notes: String
    public var option: OptionSpec?   // 期权参数（交易端保留）
    public var status: String        // POSTED / DRAFT（默认 POSTED，参与计算）

    public init(id: String = UUID().uuidString, accountID: String, assetID: String? = nil,
                type: ActivityType, date: Date = Date(), quantity: Double = 0,
                unitPrice: Double = 0, amount: Double = 0, fee: Double = 0,
                currency: String = "USD", fxRate: Double? = nil, notes: String = "",
                option: OptionSpec? = nil, status: String = "POSTED") {
        self.id = id
        self.accountID = accountID
        self.assetID = assetID
        self.type = type
        self.date = date
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
        self.fee = fee
        self.currency = currency
        self.fxRate = fxRate
        self.notes = notes
        self.option = option
        self.status = status
    }

    /// 交易总额（买入支出 / 卖出收入，含手续费，现金流语义）
    public var netCashFlow: Double {
        switch type {
        case .buy:
            return -(quantity * unitPrice * Double(option?.multiplier ?? 1)) - fee
        case .sell:
            return (quantity * unitPrice * Double(option?.multiplier ?? 1)) - fee
        case .deposit, .transferIn, .credit, .dividend, .interest:
            return amount
        case .withdrawal, .transferOut, .fee, .tax:
            return -abs(amount)
        case .split, .adjustment, .unknown:
            return 0
        }
    }

    /// 计入成本的活动（买入增加成本基础）
    public var affectsCostBasis: Bool {
        type == .buy || type == .dividend || type == .interest || type == .credit || type == .adjustment
    }
}

// MARK: - 税务批次（FIFO）

/// 税务批次：一次买入开一个 lot，卖出按 FIFO 关 lot。
public struct Lot: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var accountID: String
    public var assetID: String
    public var openDate: Date
    public var openActivityID: String?
    public var originalQuantity: Double
    public var costPerUnit: Double          // 含费用分摊的每股成本
    public var originalCostBasis: Double    // 开仓成本基础（含费）
    public var remainingCostBasis: Double   // 剩余成本基础
    public var feeAllocated: Double
    public var remainingQuantity: Double
    public var splitRatio: Double           // 开仓后累计拆股比例（1 = 无拆股）
    public var isClosed: Bool
    public var closeDate: Date?
    public var closeActivityID: String?
    public var currency: String

    public init(id: String = UUID().uuidString, accountID: String, assetID: String,
                openDate: Date, openActivityID: String? = nil,
                originalQuantity: Double, costPerUnit: Double,
                originalCostBasis: Double, remainingCostBasis: Double? = nil,
                feeAllocated: Double = 0, remainingQuantity: Double? = nil,
                splitRatio: Double = 1, isClosed: Bool = false,
                closeDate: Date? = nil, closeActivityID: String? = nil,
                currency: String = "USD") {
        self.id = id
        self.accountID = accountID
        self.assetID = assetID
        self.openDate = openDate
        self.openActivityID = openActivityID
        self.originalQuantity = originalQuantity
        self.costPerUnit = costPerUnit
        self.originalCostBasis = originalCostBasis
        self.remainingCostBasis = remainingCostBasis ?? originalCostBasis
        self.feeAllocated = feeAllocated
        self.remainingQuantity = remainingQuantity ?? originalQuantity
        self.splitRatio = splitRatio
        self.isClosed = isClosed
        self.closeDate = closeDate
        self.closeActivityID = closeActivityID
        self.currency = currency
    }

    /// 剩余数量按拆股比例调整后的当前持有股数
    public var effectiveQuantity: Double { remainingQuantity * splitRatio }

    /// 当前持有部分的成本基础（拆股不改变成本）
    public var currentCostBasis: Double { remainingCostBasis }
}

// MARK: - 批次处置（已实现盈亏）

public struct LotDisposal: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var lotID: String
    public var accountID: String
    public var assetID: String
    public var disposalActivityID: String
    public var disposalDate: Date
    public var quantity: Double
    public var proceeds: Double            // 卖出所得
    public var costBasis: Double           // 对应批次成本
    public var realizedPnL: Double         // 已实现盈亏 = proceeds - costBasis
    public var fee: Double
    public var currency: String

    public init(id: String = UUID().uuidString, lotID: String, accountID: String,
                assetID: String, disposalActivityID: String, disposalDate: Date,
                quantity: Double, proceeds: Double, costBasis: Double,
                realizedPnL: Double, fee: Double = 0, currency: String = "USD") {
        self.id = id
        self.lotID = lotID
        self.accountID = accountID
        self.assetID = assetID
        self.disposalActivityID = disposalActivityID
        self.disposalDate = disposalDate
        self.quantity = quantity
        self.proceeds = proceeds
        self.costBasis = costBasis
        self.realizedPnL = realizedPnL
        self.fee = fee
        self.currency = currency
    }
}

// MARK: - 持仓（推导结果，非持久化）

/// 按账户×资产推导出的持仓（交易记录重放结果）。
public struct Position: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(accountID):\(asset.id)" }
    public var accountID: String
    public var asset: Asset
    public var quantity: Double            // 当前持有数量（拆股调整后）
    public var avgCostPerUnit: Double      // 平均成本（含费）
    public var costBasis: Double           // 总成本基础
    public var marketPrice: Double         // 最新价（行情缺失时用成本价）
    public var marketValue: Double         // 市值 = quantity × marketPrice
    public var unrealizedPnL: Double       // 浮动盈亏 = marketValue - costBasis
    public var unrealizedPnLPercent: Double

    public init(accountID: String, asset: Asset, quantity: Double,
                avgCostPerUnit: Double, costBasis: Double,
                marketPrice: Double = 0, marketValue: Double = 0,
                unrealizedPnL: Double = 0, unrealizedPnLPercent: Double = 0) {
        self.accountID = accountID
        self.asset = asset
        self.quantity = quantity
        self.avgCostPerUnit = avgCostPerUnit
        self.costBasis = costBasis
        self.marketPrice = marketPrice
        self.marketValue = marketValue
        self.unrealizedPnL = unrealizedPnL
        self.unrealizedPnLPercent = unrealizedPnLPercent
    }
}

// MARK: - 组合估值（推导结果）

/// 账户组合估值（现金 + 持仓市值，可换算到基准货币）。
public struct PortfolioValuation: Codable, Sendable, Hashable {
    public var accountID: String
    public var cashBalance: Double            // 账户币种现金
    public var marketValue: Double            // 持仓市值（账户币种）
    public var totalValue: Double             // 总价值（账户币种）
    public var costBasis: Double              // 总成本基础（账户币种）
    public var netContribution: Double        // 净投入（账户币种）
    public var unrealizedPnL: Double          // 浮动盈亏
    public var unrealizedPnLPercent: Double
    public var realizedPnL: Double            // 已实现盈亏（账户币种）
    public var positions: [Position]

    public init(accountID: String, cashBalance: Double = 0, marketValue: Double = 0,
                totalValue: Double = 0, costBasis: Double = 0, netContribution: Double = 0,
                unrealizedPnL: Double = 0, unrealizedPnLPercent: Double = 0,
                realizedPnL: Double = 0, positions: [Position] = []) {
        self.accountID = accountID
        self.cashBalance = cashBalance
        self.marketValue = marketValue
        self.totalValue = totalValue
        self.costBasis = costBasis
        self.netContribution = netContribution
        self.unrealizedPnL = unrealizedPnL
        self.unrealizedPnLPercent = unrealizedPnLPercent
        self.realizedPnL = realizedPnL
        self.positions = positions
    }
}

// MARK: - 组合历史快照（每日估值）

public struct PortfolioSnapshot: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(accountID)_\(date.timeIntervalSince1970)" }
    public var accountID: String
    public var date: Date
    public var totalValue: Double          // 基准币种
    public var marketValue: Double
    public var cashBalance: Double
    public var costBasis: Double
    public var netContribution: Double
    public var totalGain: Double           // 总盈亏 = totalValue - netContribution
    public var totalGainPercent: Double
    public var dayGain: Double             // 当日盈亏
    public var dayGainPercent: Double

    public init(accountID: String, date: Date, totalValue: Double, marketValue: Double,
                cashBalance: Double, costBasis: Double, netContribution: Double,
                totalGain: Double, totalGainPercent: Double,
                dayGain: Double = 0, dayGainPercent: Double = 0) {
        self.accountID = accountID
        self.date = date
        self.totalValue = totalValue
        self.marketValue = marketValue
        self.cashBalance = cashBalance
        self.costBasis = costBasis
        self.netContribution = netContribution
        self.totalGain = totalGain
        self.totalGainPercent = totalGainPercent
        self.dayGain = dayGain
        self.dayGainPercent = dayGainPercent
    }
}

// MARK: - 汇率

public struct ExchangeRate: Codable, Sendable, Identifiable, Hashable {
    public var id: String { "\(from)_\(to)" }
    public var from: String
    public var to: String
    public var rate: Double
    public var updatedAt: Date
    public init(from: String, to: String, rate: Double, updatedAt: Date = Date()) {
        self.from = from
        self.to = to
        self.rate = rate
        self.updatedAt = updatedAt
    }
}
