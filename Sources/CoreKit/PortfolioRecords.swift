import Foundation
import GRDB

// MARK: - PlatformRecord

public struct PlatformRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "platforms"

    public var id: String
    public var name: String
    public var url: String

    public init(platform: Platform) {
        self.id = platform.id
        self.name = platform.name
        self.url = platform.url
    }

    public func toPlatform() -> Platform {
        Platform(id: id, name: name, url: url)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url
    }
}

// MARK: - AccountRecord

public struct AccountRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "accounts"

    public var id: String
    public var name: String
    public var type: String
    public var currency: String
    public var platformID: String?
    public var isDefault: Bool
    public var isActive: Bool
    public var sortOrder: Int

    public init(account: Account) {
        self.id = account.id
        self.name = account.name
        self.type = account.type.rawValue
        self.currency = account.currency
        self.platformID = account.platformID
        self.isDefault = account.isDefault
        self.isActive = account.isActive
        self.sortOrder = account.sortOrder
    }

    public func toAccount() -> Account {
        Account(id: id, name: name,
                type: AccountType(rawValue: type) ?? .securities,
                currency: currency, platformID: platformID,
                isDefault: isDefault, isActive: isActive, sortOrder: sortOrder)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, type, currency
        case platformID = "platform_id"
        case isDefault = "is_default"
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }
}

// MARK: - AssetRecord

public struct AssetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "assets"

    public var id: String
    public var market: String
    public var code: String
    public var name: String
    public var currency: String
    public var assetType: String
    public var isActive: Bool

    public init(asset: Asset) {
        self.id = asset.id
        self.market = asset.market.rawValue
        self.code = asset.code
        self.name = asset.name
        self.currency = asset.currency
        self.assetType = asset.assetType.rawValue
        self.isActive = asset.isActive
    }

    public func toAsset() -> Asset {
        Asset(id: id, market: Market(rawValue: market) ?? .us, code: code, name: name,
              currency: currency, assetType: AssetType(rawValue: assetType) ?? .stock,
              isActive: isActive)
    }

    enum CodingKeys: String, CodingKey {
        case id, market, code, name, currency
        case assetType = "asset_type"
        case isActive = "is_active"
    }
}

// MARK: - ActivityRecord

public struct ActivityRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "activities"

    public var id: String
    public var accountID: String
    public var assetID: String?
    public var type: String
    public var date: Date
    public var quantity: Double
    public var unitPrice: Double
    public var amount: Double
    public var fee: Double
    public var currency: String
    public var fxRate: Double?
    public var notes: String
    public var optionJSON: String?
    public var status: String

    public init(activity: Activity) {
        self.id = activity.id
        self.accountID = activity.accountID
        self.assetID = activity.assetID
        self.type = activity.type.rawValue
        self.date = activity.date
        self.quantity = activity.quantity
        self.unitPrice = activity.unitPrice
        self.amount = activity.amount
        self.fee = activity.fee
        self.currency = activity.currency
        self.fxRate = activity.fxRate
        self.notes = activity.notes
        self.optionJSON = activity.option.flatMap { try? JSONEncoder().encode($0) }.map { String(data: $0, encoding: .utf8)! }
        self.status = activity.status
    }

    public func toActivity() -> Activity {
        Activity(id: id, accountID: accountID, assetID: assetID,
                 type: ActivityType(rawValue: type) ?? .unknown,
                 date: date, quantity: quantity, unitPrice: unitPrice,
                 amount: amount, fee: fee, currency: currency, fxRate: fxRate,
                 notes: notes,
                 option: optionJSON.flatMap { try? JSONDecoder().decode(OptionSpec.self, from: Data($0.utf8)) },
                 status: status)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case assetID = "asset_id"
        case type, date, quantity
        case unitPrice = "unit_price"
        case amount, fee, currency
        case fxRate = "fx_rate"
        case notes
        case optionJSON = "option_json"
        case status
    }
}

// MARK: - LotRecord

public struct LotRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "lots"

    public var id: String
    public var accountID: String
    public var assetID: String
    public var openDate: Date
    public var openActivityID: String?
    public var originalQuantity: Double
    public var costPerUnit: Double
    public var originalCostBasis: Double
    public var remainingCostBasis: Double
    public var feeAllocated: Double
    public var remainingQuantity: Double
    public var splitRatio: Double
    public var isClosed: Bool
    public var closeDate: Date?
    public var closeActivityID: String?
    public var currency: String

    public init(lot: Lot) {
        self.id = lot.id
        self.accountID = lot.accountID
        self.assetID = lot.assetID
        self.openDate = lot.openDate
        self.openActivityID = lot.openActivityID
        self.originalQuantity = lot.originalQuantity
        self.costPerUnit = lot.costPerUnit
        self.originalCostBasis = lot.originalCostBasis
        self.remainingCostBasis = lot.remainingCostBasis
        self.feeAllocated = lot.feeAllocated
        self.remainingQuantity = lot.remainingQuantity
        self.splitRatio = lot.splitRatio
        self.isClosed = lot.isClosed
        self.closeDate = lot.closeDate
        self.closeActivityID = lot.closeActivityID
        self.currency = lot.currency
    }

    public func toLot() -> Lot {
        Lot(id: id, accountID: accountID, assetID: assetID,
            openDate: openDate, openActivityID: openActivityID,
            originalQuantity: originalQuantity, costPerUnit: costPerUnit,
            originalCostBasis: originalCostBasis,
            remainingCostBasis: remainingCostBasis,
            feeAllocated: feeAllocated, remainingQuantity: remainingQuantity,
            splitRatio: splitRatio, isClosed: isClosed,
            closeDate: closeDate, closeActivityID: closeActivityID,
            currency: currency)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case assetID = "asset_id"
        case openDate = "open_date"
        case openActivityID = "open_activity_id"
        case originalQuantity = "original_quantity"
        case costPerUnit = "cost_per_unit"
        case originalCostBasis = "original_cost_basis"
        case remainingCostBasis = "remaining_cost_basis"
        case feeAllocated = "fee_allocated"
        case remainingQuantity = "remaining_quantity"
        case splitRatio = "split_ratio"
        case isClosed = "is_closed"
        case closeDate = "close_date"
        case closeActivityID = "close_activity_id"
        case currency
    }
}

// MARK: - LotDisposalRecord

public struct LotDisposalRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "lot_disposals"

    public var id: String
    public var lotID: String
    public var accountID: String
    public var assetID: String
    public var disposalActivityID: String
    public var disposalDate: Date
    public var quantity: Double
    public var proceeds: Double
    public var costBasis: Double
    public var realizedPnL: Double
    public var fee: Double
    public var currency: String

    public init(disposal: LotDisposal) {
        self.id = disposal.id
        self.lotID = disposal.lotID
        self.accountID = disposal.accountID
        self.assetID = disposal.assetID
        self.disposalActivityID = disposal.disposalActivityID
        self.disposalDate = disposal.disposalDate
        self.quantity = disposal.quantity
        self.proceeds = disposal.proceeds
        self.costBasis = disposal.costBasis
        self.realizedPnL = disposal.realizedPnL
        self.fee = disposal.fee
        self.currency = disposal.currency
    }

    public func toDisposal() -> LotDisposal {
        LotDisposal(id: id, lotID: lotID, accountID: accountID, assetID: assetID,
                    disposalActivityID: disposalActivityID, disposalDate: disposalDate,
                    quantity: quantity, proceeds: proceeds, costBasis: costBasis,
                    realizedPnL: realizedPnL, fee: fee, currency: currency)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case lotID = "lot_id"
        case accountID = "account_id"
        case assetID = "asset_id"
        case disposalActivityID = "disposal_activity_id"
        case disposalDate = "disposal_date"
        case quantity, proceeds
        case costBasis = "cost_basis"
        case realizedPnL = "realized_pnl"
        case fee, currency
    }
}

// MARK: - PortfolioSnapshotRecord

public struct PortfolioSnapshotRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "portfolio_history"

    public var id: String
    public var accountID: String
    public var date: Date
    public var totalValue: Double
    public var marketValue: Double
    public var cashBalance: Double
    public var costBasis: Double
    public var netContribution: Double
    public var totalGain: Double
    public var totalGainPercent: Double
    public var dayGain: Double
    public var dayGainPercent: Double

    public init(snapshot: PortfolioSnapshot) {
        self.id = "\(snapshot.accountID)_\(Int64(snapshot.date.timeIntervalSince1970))"
        self.accountID = snapshot.accountID
        self.date = snapshot.date
        self.totalValue = snapshot.totalValue
        self.marketValue = snapshot.marketValue
        self.cashBalance = snapshot.cashBalance
        self.costBasis = snapshot.costBasis
        self.netContribution = snapshot.netContribution
        self.totalGain = snapshot.totalGain
        self.totalGainPercent = snapshot.totalGainPercent
        self.dayGain = snapshot.dayGain
        self.dayGainPercent = snapshot.dayGainPercent
    }

    public func toSnapshot() -> PortfolioSnapshot {
        PortfolioSnapshot(accountID: accountID, date: date,
                          totalValue: totalValue, marketValue: marketValue,
                          cashBalance: cashBalance, costBasis: costBasis,
                          netContribution: netContribution,
                          totalGain: totalGain, totalGainPercent: totalGainPercent,
                          dayGain: dayGain, dayGainPercent: dayGainPercent)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case date
        case totalValue = "total_value"
        case marketValue = "market_value"
        case cashBalance = "cash_balance"
        case costBasis = "cost_basis"
        case netContribution = "net_contribution"
        case totalGain = "total_gain"
        case totalGainPercent = "total_gain_percent"
        case dayGain = "day_gain"
        case dayGainPercent = "day_gain_percent"
    }
}

// MARK: - ExchangeRateRecord

public struct ExchangeRateRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "exchange_rates"

    public var from: String
    public var to: String
    public var rate: Double
    public var updatedAt: Date

    public init(rate: ExchangeRate) {
        self.from = rate.from
        self.to = rate.to
        self.rate = rate.rate
        self.updatedAt = rate.updatedAt
    }

    public func toRate() -> ExchangeRate {
        ExchangeRate(from: from, to: to, rate: rate, updatedAt: updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case from = "from_ccy"
        case to = "to_ccy"
        case rate
        case updatedAt = "updated_at"
    }
}
