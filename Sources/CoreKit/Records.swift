import Foundation
import GRDB

/// 自选表记录（GRDB Record 层，与领域模型分离）
public struct WatchlistRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "watchlist"

    public var symbolId: String
    public var market: String
    public var code: String
    public var name: String
    public var currency: String
    public var groupName: String
    public var sortOrder: Int
    public var addedAt: Date

    public init(symbolId: String, market: String, code: String, name: String,
                currency: String, groupName: String, sortOrder: Int, addedAt: Date) {
        self.symbolId = symbolId
        self.market = market
        self.code = code
        self.name = name
        self.currency = currency
        self.groupName = groupName
        self.sortOrder = sortOrder
        self.addedAt = addedAt
    }

    public init(item: WatchlistItem) {
        self.symbolId = item.symbol.id
        self.market = item.symbol.market.rawValue
        self.code = item.symbol.code
        self.name = item.symbol.name
        self.currency = item.symbol.currency
        self.groupName = item.group
        self.sortOrder = item.sortOrder
        self.addedAt = item.addedAt
    }

    public func toItem() -> WatchlistItem {
        let symbol = Symbol(market: Market(rawValue: market) ?? .us,
                            code: code, name: name, currency: currency)
        return WatchlistItem(symbol: symbol, group: groupName,
                             sortOrder: sortOrder, addedAt: addedAt)
    }

    enum CodingKeys: String, CodingKey {
        case symbolId = "symbol_id"
        case market
        case code
        case name
        case currency
        case groupName = "group_name"
        case sortOrder = "sort_order"
        case addedAt = "added_at"
    }
}

/// 持仓表记录
public struct HoldingRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "holdings"

    public var symbolId: String
    public var market: String
    public var code: String
    public var name: String
    public var currency: String
    public var quantity: Double
    public var costBasis: Double
    public var broker: String
    public var importedAt: Date

    public init(holding: Holding) {
        self.symbolId = holding.symbol.id
        self.market = holding.symbol.market.rawValue
        self.code = holding.symbol.code
        self.name = holding.symbol.name
        self.currency = holding.symbol.currency
        self.quantity = holding.quantity
        self.costBasis = holding.costBasis
        self.broker = holding.broker
        self.importedAt = holding.importedAt
    }

    public func toHolding() -> Holding {
        let symbol = Symbol(market: Market(rawValue: market) ?? .us,
                            code: code, name: name, currency: currency)
        return Holding(symbol: symbol, quantity: quantity, costBasis: costBasis,
                       broker: broker, importedAt: importedAt)
    }

    enum CodingKeys: String, CodingKey {
        case symbolId = "symbol_id"
        case market
        case code
        case name
        case currency
        case quantity
        case costBasis = "cost_basis"
        case broker
        case importedAt = "imported_at"
    }
}

/// 新闻订阅源记录
public struct NewsFeedRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "news_feeds"

    public var id: String
    public var name: String
    public var category: String
    public var kind: String
    public var url: String
    public var enabled: Bool

    public init(feed: NewsFeed) {
        self.id = feed.id
        self.name = feed.name
        self.category = feed.category.rawValue
        self.kind = feed.kind.rawValue
        self.url = feed.url
        self.enabled = feed.enabled
    }

    public func toFeed() -> NewsFeed {
        NewsFeed(id: id, name: name,
                 category: NewsFeedCategory(rawValue: category) ?? .flash,
                 kind: NewsFeedKind(rawValue: kind) ?? .rss,
                 url: url, enabled: enabled)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, category, kind, url, enabled
    }
}

/// 新闻表记录
public struct NewsRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "news"

    public var id: String
    public var title: String
    public var summary: String
    public var url: String
    public var source: String
    public var publishedAt: Date
    public var content: String?
    public var marketsJSON: String
    public var aiTagJSON: String?

    public init(news: NewsItem) {
        self.id = news.id
        self.title = news.title
        self.summary = news.summary
        self.url = news.url
        self.source = news.source
        self.publishedAt = news.publishedAt
        self.content = news.content
        let enc = JSONEncoder()
        self.marketsJSON = (try? String(data: enc.encode(news.tags), encoding: .utf8)) ?? "[]"
        self.aiTagJSON = news.aiTag.flatMap { try? String(data: enc.encode($0), encoding: .utf8) }
    }

    public func toNews() -> NewsItem {
        let dec = JSONDecoder()
        let markets = (try? dec.decode([Market].self, from: Data(marketsJSON.utf8))) ?? []
        let aiTag = aiTagJSON.flatMap { try? dec.decode(NewsTag.self, from: Data($0.utf8)) }
        return NewsItem(id: id, title: title, summary: summary, url: url,
                        source: source, publishedAt: publishedAt,
                        content: content, tags: markets, aiTag: aiTag)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case url
        case source
        case publishedAt = "published_at"
        case content
        case marketsJSON = "markets"
        case aiTagJSON = "ai_tag_json"
    }
}
