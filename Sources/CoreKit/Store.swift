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
        try? reloadFeeds()
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

    /// 添加自选（按 symbolId 查重：已存在则跳过并返回 false）
    @discardableResult
    public func addToWatchlist(_ symbol: Symbol, group: String = "默认分组") throws -> Bool {
        let item = WatchlistItem(symbol: symbol, group: group,
                                 sortOrder: nextSortOrder(group: group))
        var record = WatchlistRecord(item: item)
        var inserted = false
        try db.dbQueue.write { db in
            let exists = try WatchlistRecord.filter(Column("symbol_id") == record.symbolId).fetchCount(db) > 0
            guard !exists else { return }
            try record.insert(db)
            inserted = true
        }
        try reload()
        return inserted
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

    public func kline(for symbol: Symbol, period: KLinePeriod, limit: Int = 320) async throws -> [KLineBar] {
        try await registry.fetchKLine(for: symbol, period: period, limit: limit)
    }

    /// 技术面摘要：拉日K（≥260 根）计算支撑/阻力/均线/YTD/52周高低
    public func technicalSummary(for symbol: Symbol) async throws -> TechnicalSummary {
        let bars = try await registry.fetchKLine(for: symbol, period: .day, limit: 300)
        return TechnicalAnalyzer.analyze(bars: bars)
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

    // MARK: - 内置预置标的

    /// 导入内置标的（幂等：已存在的跳过），返回新增数量
    @discardableResult
    public func importBuiltinSymbols() throws -> Int {
        var added = 0
        try db.dbQueue.write { db in
            for symbol in BuiltinSymbols.all {
                let item = WatchlistItem(symbol: symbol, group: "预置")
                let exists = try WatchlistRecord.filter(Column("symbol_id") == item.symbol.id).fetchCount(db) > 0
                guard !exists else { continue }
                var record = WatchlistRecord(item: item)
                try record.insert(db)
                added += 1
            }
        }
        try reload()
        return added
    }

    /// 首启自动导入（UserDefaults 标志，失败重置下次重试）
    @discardableResult
    public func importBuiltinIfNeeded() throws -> Int {
        let d = UserDefaults.standard
        guard !d.bool(forKey: BuiltinSymbols.importedFlagKey) else { return 0 }
        let added = try importBuiltinSymbols()
        if added > 0 || BuiltinSymbols.all.isEmpty {
            d.set(true, forKey: BuiltinSymbols.importedFlagKey)
        }
        return added
    }

    // MARK: - 资讯订阅源

    @Published public private(set) var newsFeeds: [NewsFeed] = []

    public func reloadFeeds() throws {
        newsFeeds = try db.dbQueue.read { db in
            try NewsFeedRecord.order(Column("category"), Column("name")).fetchAll(db).map { $0.toFeed() }
        }
    }

    /// 强制补全缺失的预置订阅源（供「恢复预置」按钮使用，不受首启标志限制）
    @discardableResult
    public func importMissingBuiltinFeeds() throws -> Int {
        var added = 0
        try db.dbQueue.write { db in
            for feed in NewsFeedCatalog.all {
                let exists = try NewsFeedRecord
                    .filter(Column("url") == feed.url && Column("kind") == feed.kind.rawValue)
                    .fetchCount(db) > 0
                guard !exists else { continue }
                var record = NewsFeedRecord(feed: feed)
                try record.insert(db)
                added += 1
            }
        }
        try reloadFeeds()
        return added
    }

    /// 首启导入预置订阅源（幂等，按 url+kind 查重）
    @discardableResult
    public func importBuiltinFeedsIfNeeded() throws -> Int {
        let d = UserDefaults.standard
        guard !d.bool(forKey: NewsFeedCatalog.importedFlagKey) else { return 0 }
        let added = try importMissingBuiltinFeeds()
        d.set(true, forKey: NewsFeedCatalog.importedFlagKey)
        return added
    }

    /// 启停订阅源
    public func setFeedEnabled(_ feed: NewsFeed, enabled: Bool) throws {
        try db.dbQueue.write { db in
            guard var record = try NewsFeedRecord.fetchOne(db, key: feed.id) else { return }
            record.enabled = enabled
            try record.update(db)
        }
        try reloadFeeds()
    }

    /// 添加自定义 RSS 订阅源
    @discardableResult
    public func addRSSFeed(name: String, url: String, category: NewsFeedCategory) throws -> Bool {
        var record = NewsFeedRecord(feed: NewsFeed(name: name, category: category, kind: .rss, url: url))
        try db.dbQueue.write { db in
            let exists = try NewsFeedRecord.filter(Column("url") == url).fetchCount(db) > 0
            guard !exists else { return }
            try record.insert(db)
        }
        try reloadFeeds()
        return true
    }

    public func removeFeed(_ feed: NewsFeed) throws {
        try db.dbQueue.write { db in
            _ = try NewsFeedRecord.deleteOne(db, key: feed.id)
        }
        try reloadFeeds()
    }

    /// 拉取某分类下所有启用源的资讯（合并按时间排序）
    public func fetchNews(category: NewsFeedCategory) async -> [NewsItem] {
        let feeds = newsFeeds.filter { $0.category == category && $0.enabled }
        guard !feeds.isEmpty else { return [] }
        var all: [NewsItem] = []
        await withTaskGroup(of: [NewsItem].self) { group in
            for feed in feeds {
                group.addTask {
                    (try? await NewsSourceRegistry.fetch(feed: feed, limit: 20)) ?? []
                }
            }
            for await items in group {
                all.append(contentsOf: items)
            }
        }
        // 去重（按 id）+ 时间倒序
        var seen: Set<String> = []
        let deduped = all.filter { seen.insert($0.id).inserted }
        return deduped.sorted { $0.publishedAt > $1.publishedAt }
    }
}
