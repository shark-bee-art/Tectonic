import Foundation
import GRDB

/// SQLite 数据库（GRDB）。存放自选、新闻缓存、持仓等本地数据。
public final class AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(_ dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    /// 便捷初始化：默认应用支持目录（支持 TECTONIC_DB_PATH 环境变量覆盖，供 CLI 端到端测试）
    public static func makeDefault() throws -> AppDatabase {
        if let override = ProcessInfo.processInfo.environment["TECTONIC_DB_PATH"], !override.isEmpty {
            let queue = try DatabaseQueue(path: override)
            return try AppDatabase(queue)
        }
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
        // v7：删除资产模块残留表（老库曾跑过 v3/v5/v6 迁移；新库 IF EXISTS 安全跳过）
        migrator.registerMigration("v7_drop_portfolio") { db in
            for table in ["platforms", "accounts", "assets", "activities", "lots",
                          "lot_disposals", "portfolio_history", "exchange_rates",
                          "transactions", "holdings"] {
                try db.execute(sql: "DROP TABLE IF EXISTS \(table)")
            }
        }
        return migrator
    }
}
