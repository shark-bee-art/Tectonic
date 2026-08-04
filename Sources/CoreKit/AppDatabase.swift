import Foundation
import GRDB

/// SQLite 数据库（GRDB）。存放自选、新闻缓存、持仓等本地数据。
public final class AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    /// 便捷初始化：默认应用支持目录
    public static func makeDefault() throws -> AppDatabase {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        let dir = appSupport.appendingPathComponent("Tectonic", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("tectonic.sqlite")
        let queue = try DatabaseQueue(path: dbURL.path)
        return try AppDatabase(queue)
    }

    /// 测试用内存库
    public static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_watchlist") { db in
            try db.create(table: "watchlist") { t in
                t.primaryKey("symbol_id", .text)          // market:code
                t.column("market", .text).notNull()
                t.column("code", .text).notNull()
                t.column("name", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("group_name", .text).notNull().defaults(to: "默认分组")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("added_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_news") { db in
            try db.create(table: "news") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("url", .text).notNull()
                t.column("source", .text).notNull()
                t.column("published_at", .datetime).notNull()
                t.column("content", .text)
                t.column("markets", .text).notNull().defaults(to: "[]")       // JSON [Market]
                t.column("ai_tag_json", .text)                                 // JSON NewsTag?
            }
            try db.create(index: "news_published_at", on: "news", columns: ["published_at"])
        }
        migrator.registerMigration("v3_holdings") { db in
            try db.create(table: "holdings") { t in
                t.primaryKey("symbol_id", .text)
                t.column("market", .text).notNull()
                t.column("code", .text).notNull()
                t.column("name", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("quantity", .double).notNull()
                t.column("cost_basis", .double).notNull()
                t.column("broker", .text).notNull()
                t.column("imported_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v4_news_feeds") { db in
            try db.create(table: "news_feeds") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("category", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("url", .text).notNull()
                t.column("enabled", .boolean).notNull().defaults(to: true)
            }
        }
        migrator.registerMigration("v5_transactions") { db in
            try db.create(table: "transactions") { t in
                t.primaryKey("id", .text)
                t.column("date", .datetime).notNull()
                t.column("asset_type", .text).notNull()
                t.column("name", .text).notNull()
                t.column("code", .text).notNull()
                t.column("market", .text).notNull()
                t.column("direction", .text).notNull()
                t.column("quantity", .double).notNull()
                t.column("price", .double).notNull()
                t.column("fee", .double).notNull()
                t.column("notes", .text).notNull()
                t.column("option_json", .text)
            }
            // holdings 表扩展：资产类别 + 期权
            try db.alter(table: "holdings") { t in
                t.add(column: "asset_type", .text).defaults(to: "stock")
                t.add(column: "option_json", .text)
            }
        }
        return migrator
    }
}
