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
        migrator.registerMigration("v6_portfolio") { db in
            // 平台（券商）
            try db.create(table: "platforms") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("url", .text).notNull().defaults(to: "")
            }
            // 账户
            try db.create(table: "accounts") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull().defaults(to: "securities")
                t.column("currency", .text).notNull().defaults(to: "USD")
                t.column("platform_id", .text)
                t.column("is_default", .boolean).notNull().defaults(to: false)
                t.column("is_active", .boolean).notNull().defaults(to: true)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.foreignKey(["platform_id"], references: "platforms", columns: ["id"], onDelete: .setNull)
            }
            // 资产（标的规范化，id = market:code）
            try db.create(table: "assets") { t in
                t.primaryKey("id", .text)
                t.column("market", .text).notNull()
                t.column("code", .text).notNull()
                t.column("name", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("asset_type", .text).notNull().defaults(to: "stock")
                t.column("is_active", .boolean).notNull().defaults(to: true)
            }
            try db.create(index: "assets_code", on: "assets", columns: ["code"])
            // 交易活动（唯一事实来源，替代 transactions 的 buy/sell 两态）
            try db.create(table: "activities") { t in
                t.primaryKey("id", .text)
                t.column("account_id", .text).notNull()
                t.column("asset_id", .text)
                t.column("type", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("quantity", .double).notNull().defaults(to: 0)
                t.column("unit_price", .double).notNull().defaults(to: 0)
                t.column("amount", .double).notNull().defaults(to: 0)
                t.column("fee", .double).notNull().defaults(to: 0)
                t.column("currency", .text).notNull().defaults(to: "USD")
                t.column("fx_rate", .double)
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("option_json", .text)
                t.column("status", .text).notNull().defaults(to: "POSTED")
                t.foreignKey(["account_id"], references: "accounts", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["asset_id"], references: "assets", columns: ["id"], onDelete: .setNull)
            }
            try db.create(index: "activities_account_date", on: "activities", columns: ["account_id", "date"])
            try db.create(index: "activities_asset_date", on: "activities", columns: ["asset_id", "date"])
            // 税务批次（FIFO）
            try db.create(table: "lots") { t in
                t.primaryKey("id", .text)
                t.column("account_id", .text).notNull()
                t.column("asset_id", .text).notNull()
                t.column("open_date", .datetime).notNull()
                t.column("open_activity_id", .text)
                t.column("original_quantity", .double).notNull()
                t.column("cost_per_unit", .double).notNull()
                t.column("original_cost_basis", .double).notNull()
                t.column("remaining_cost_basis", .double).notNull()
                t.column("fee_allocated", .double).notNull().defaults(to: 0)
                t.column("remaining_quantity", .double).notNull()
                t.column("split_ratio", .double).notNull().defaults(to: 1)
                t.column("is_closed", .boolean).notNull().defaults(to: false)
                t.column("close_date", .datetime)
                t.column("close_activity_id", .text)
                t.column("currency", .text).notNull().defaults(to: "USD")
                t.foreignKey(["account_id"], references: "accounts", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["asset_id"], references: "assets", columns: ["id"], onDelete: .cascade)
            }
            try db.create(index: "lots_account_asset", on: "lots", columns: ["account_id", "asset_id"])
            try db.create(index: "lots_asset_open", on: "lots", columns: ["asset_id", "is_closed", "open_date"])
            // 批次处置（已实现盈亏）
            try db.create(table: "lot_disposals") { t in
                t.primaryKey("id", .text)
                t.column("lot_id", .text).notNull()
                t.column("account_id", .text).notNull()
                t.column("asset_id", .text).notNull()
                t.column("disposal_activity_id", .text).notNull()
                t.column("disposal_date", .datetime).notNull()
                t.column("quantity", .double).notNull()
                t.column("proceeds", .double).notNull()
                t.column("cost_basis", .double).notNull()
                t.column("realized_pnl", .double).notNull()
                t.column("fee", .double).notNull().defaults(to: 0)
                t.column("currency", .text).notNull().defaults(to: "USD")
                t.foreignKey(["lot_id"], references: "lots", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["account_id"], references: "accounts", columns: ["id"], onDelete: .cascade)
                t.foreignKey(["asset_id"], references: "assets", columns: ["id"], onDelete: .cascade)
            }
            try db.create(index: "disposals_account_date", on: "lot_disposals", columns: ["account_id", "disposal_date"])
            // 组合历史快照（每日估值）
            try db.create(table: "portfolio_history") { t in
                t.primaryKey("id", .text)
                t.column("account_id", .text).notNull()
                t.column("date", .datetime).notNull()
                t.column("total_value", .double).notNull()
                t.column("market_value", .double).notNull()
                t.column("cash_balance", .double).notNull()
                t.column("cost_basis", .double).notNull()
                t.column("net_contribution", .double).notNull()
                t.column("total_gain", .double).notNull()
                t.column("total_gain_percent", .double).notNull()
                t.column("day_gain", .double).notNull()
                t.column("day_gain_percent", .double).notNull()
                t.foreignKey(["account_id"], references: "accounts", columns: ["id"], onDelete: .cascade)
            }
            try db.create(index: "history_account_date", on: "portfolio_history", columns: ["account_id", "date"])
            // 汇率
            try db.create(table: "exchange_rates") { t in
                t.column("from_ccy", .text).notNull()
                t.column("to_ccy", .text).notNull()
                t.column("rate", .double).notNull()
                t.column("updated_at", .datetime).notNull()
                t.primaryKey(["from_ccy", "to_ccy"])
            }

            // 种子数据：默认平台「手动」+ 默认账户
            let manualPlatformID = "platform-manual"
            try db.execute(sql: "INSERT OR IGNORE INTO platforms (id, name, url) VALUES (?, 'Manual', '')",
                           arguments: [manualPlatformID])
            let defaultAccountID = "account-default"
            try db.execute(sql: """
                INSERT OR IGNORE INTO accounts (id, name, type, currency, platform_id, is_default, is_active, sort_order)
                VALUES (?, '默认账户', 'securities', 'USD', ?, 1, 1, 0)
                """, arguments: [defaultAccountID, manualPlatformID])

            // 老数据迁移（v5 的 transactions → activities；holdings → 初始买入）
            // 老 transactions 表存在时迁移（只迁移无 option 的买卖；期权行跳过保留旧表）
            let hasTransactions = try db.tableExists("transactions")
            if hasTransactions {
                let legacyCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions") ?? 0
                if legacyCount > 0 {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO activities
                            (id, account_id, asset_id, type, date, quantity, unit_price, amount, fee, currency, notes, status)
                        SELECT
                            t.id, ?, t.id, CASE t.direction WHEN 'buy' THEN 'buy' ELSE 'sell' END,
                            t.date, t.quantity, t.price, t.quantity * t.price, t.fee, 'USD', t.notes, 'POSTED'
                        FROM transactions t
                        WHERE t.option_json IS NULL
                        """, arguments: [defaultAccountID])
                    // 资产同步
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO assets (id, market, code, name, currency, asset_type, is_active)
                        SELECT DISTINCT t.id, t.market, t.code, t.name, 'USD', t.asset_type, 1
                        FROM transactions t
                        WHERE t.option_json IS NULL
                        """)
                }
            }
            // 老 holdings 表存在时迁移（转为初始买入活动；期权行跳过）
            let hasHoldings = try db.tableExists("holdings")
            if hasHoldings {
                let holdingCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM holdings") ?? 0
                if holdingCount > 0 {
                    // 资产同步
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO assets (id, market, code, name, currency, asset_type, is_active)
                        SELECT DISTINCT h.symbol_id, h.market, h.code, h.name, h.currency, h.asset_type, 1
                        FROM holdings h
                        WHERE h.option_json IS NULL
                        """)
                    // 每个持仓 → 初始买入活动（日期用 imported_at，成本 = cost_basis/股）
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO activities
                            (id, account_id, asset_id, type, date, quantity, unit_price, amount, fee, currency, notes, status)
                        SELECT
                            'migrate-' || h.symbol_id,
                            ?, h.symbol_id, 'buy',
                            h.imported_at, h.quantity, h.cost_basis,
                            h.quantity * h.cost_basis, 0, h.currency, '迁移自旧持仓', 'POSTED'
                        FROM holdings h
                        WHERE h.option_json IS NULL AND h.quantity > 0
                        """, arguments: [defaultAccountID])
                }
            }
        }
        return migrator
    }
}
