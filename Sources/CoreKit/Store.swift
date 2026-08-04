import Foundation
import GRDB

/// 业务仓储：自选 CRUD、行情编排、新闻/持仓存取。
/// 领域模型与 GRDB Record 分离，持久化操作走 Record。
@MainActor
public final class Store: ObservableObject {
    public let db: AppDatabase
    private let registry = MarketDataSourceRegistry.shared

    // 自选
    @Published public private(set) var watchlist: [WatchlistItem] = []
    // 行情缓存（symbolId → Quote）
    @Published public private(set) var quotes: [String: Quote] = [:]
    // 新闻
    @Published public private(set) var news: [NewsItem] = []
    // 持仓
    @Published public private(set) var holdings: [Holding] = []

    public init(db: AppDatabase) {
        self.db = db
        try? reload()
    }

    // MARK: - 自选

    public func reload() throws {
        watchlist = try db.dbQueue.read { db in
            try WatchlistRecord
                .order(Column("group_name"), Column("sort_order"))
                .fetchAll(db)
                .map { $0.toItem() }
        }
        holdings = try db.dbQueue.read { db in
            try HoldingRecord.fetchAll(db).map { $0.toHolding() }
        }
        news = try db.dbQueue.read { db in
            try NewsRecord.order(Column("published_at").desc).limit(500).fetchAll(db)
                .map { $0.toNews() }
        }
    }

    /// 添加自选（按 URL 查重：symbolId 已存在则跳过）
    @discardableResult
    public func addToWatchlist(_ symbol: Symbol, group: String = "默认分组") throws -> Bool {
        let item = WatchlistItem(symbol: symbol, group: group,
                                 sortOrder: nextSortOrder(group: group))
        var record = WatchlistRecord(item: item)
        try db.dbQueue.write { db in
            let exists = try WatchlistRecord.filter(Column("symbol_id") == record.symbolId).fetchCount(db) > 0
            guard !exists else { return }
            try record.insert(db)
        }
        try reload()
        return true
    }

    public func removeFromWatchlist(_ symbol: Symbol) throws {
        try db.dbQueue.write { db in
            _ = try WatchlistRecord.deleteOne(db, key: symbol.id)
        }
        try reload()
    }

    public func isInWatchlist(_ symbol: Symbol) -> Bool {
        watchlist.contains { $0.symbol.id == symbol.id }
    }

    private func nextSortOrder(group: String) -> Int {
        let inGroup = watchlist.filter { $0.group == group }
        return (inGroup.map(\.sortOrder).max() ?? -1) + 1
    }

    public func groups() -> [String] {
        var seen: [String] = []
        for item in watchlist where !seen.contains(item.group) {
            seen.append(item.group)
        }
        return seen.isEmpty ? ["默认分组"] : seen
    }

    // MARK: - 行情

    /// 拉取自选全部行情
    public func refreshQuotes() async {
        let symbols = watchlist.map(\.symbol)
        guard !symbols.isEmpty else { return }
        do {
            let fresh = try await registry.fetchQuotes(for: symbols)
            var merged = quotes
            for q in fresh {
                merged[q.symbol.id] = q
            }
            quotes = merged
        } catch {
            // 静默失败，保留旧缓存
        }
    }

    /// 拉取单个标的全字段行情（含 K线）
    public func quote(for symbol: Symbol) async -> Quote? {
        if let cached = quotes[symbol.id] { return cached }
        return try? await registry.fetchQuote(for: symbol)
    }

    public func kline(for symbol: Symbol, period: KLinePeriod) async throws -> [KLineBar] {
        try await registry.fetchKLine(for: symbol, period: period)
    }

    public func search(query: String, market: Market? = nil) async -> [Symbol] {
        (try? await registry.search(query: query, market: market)) ?? []
    }

    // MARK: - 新闻

    public func upsertNews(_ items: [NewsItem]) throws {
        try db.dbQueue.write { db in
            for item in items {
                var record = NewsRecord(news: item)
                try record.save(db)   // upsert by primary key
            }
        }
        try reload()
    }

    public func updateNewsTag(id: String, tag: NewsTag) throws {
        try db.dbQueue.write { db in
            guard var record = try NewsRecord.fetchOne(db, key: id) else { return }
            let enc = JSONEncoder()
            record.aiTagJSON = try? String(data: enc.encode(tag), encoding: .utf8)
            try record.update(db)
        }
        try reload()
    }

    // MARK: - 持仓

    public func upsertHoldings(_ items: [Holding]) throws {
        try db.dbQueue.write { db in
            for item in items {
                var record = HoldingRecord(holding: item)
                try record.save(db)
            }
        }
        try reload()
    }

    /// 更新单个标的行情缓存（供视图 task 使用）
    public func updateQuote(_ q: Quote) {
        quotes[q.symbol.id] = q
    }

    public func removeAllHoldings() throws {
        try db.dbQueue.write { db in
            try HoldingRecord.deleteAll(db)
        }
        try reload()
    }
}
