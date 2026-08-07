import Foundation
import CoreKit
import GRDB

// Tectonic CLI —— 端到端验证工具
// 用法：
//   tectonic-cli quote <market>:<code>         拉取行情，如 us:AAPL hk:00700 cn:600519 crypto:BTCUSDT fund:110022 jp:7203 kr:005930 tw:2330
//   tectonic-cli kline <market>:<code> [day|week|month|m5] [limit]
//   tectonic-cli search <query> [market]
//   tectonic-cli watch add <market>:<code> [group]    添加自选
//   tectonic-cli watch list                          列出自选
//   tectonic-cli watch remove <market>:<code>
//   tectonic-cli ask <问题>                           AI 单轮问答
//   tectonic-cli tag <标题>|<摘要>                    新闻打标
//   tectonic-cli models                              列出可用供应商
//   tectonic-cli markets                             列出市场
//   tectonic-cli ai-set <provider> [model]           设置 AI 供应商/模型
//   tectonic-cli ai-key <provider> <key>             设置 API Key（本地存储）

func parseSymbol(_ raw: String) -> Symbol? {
    let parts = raw.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let market = Market(rawValue: String(parts[0])) else { return nil }
    return Symbol(market: market, code: String(parts[1]), name: String(parts[1]))
}

func fmt(_ v: Double) -> String {
    v >= 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
}

func fmtPercent(_ v: Double) -> String {
    String(format: "%+.2f%%", v)
}

@main
struct TectonicCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            exit(0)
        }

        switch command {
        case "quote":
            guard args.count >= 2, let symbol = parseSymbol(args[1]) else { print("用法: quote <market>:<code>"); exit(1) }
            do {
                let q = try await MarketDataSourceRegistry.shared.fetchQuote(for: symbol)
                print("\(symbol.name) (\(symbol.market.displayName) \(symbol.code))")
                print("  价格: \(fmt(q.price)) \(q.symbol.currency)")
                print("  涨跌: \(fmt(q.change)) \(fmtPercent(q.changePercent))")
                print("  今开: \(fmt(q.open))  最高: \(fmt(q.high))  最低: \(fmt(q.low))  昨收: \(fmt(q.prevClose))")
                if q.volume > 0 { print("  成交量: \(Int(q.volume))") }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "feargreed":
            do {
                let fg = try await FearGreedSource.fetch()
                print("恐惧贪婪指数: \(fg.value)（\(fg.level)/\(fg.classification)）")
                print("更新时间: \(fg.timestamp.formatted(date: .abbreviated, time: .shortened))")
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "kline":
            guard args.count >= 2, let symbol = parseSymbol(args[1]) else { print("用法: kline <market>:<code> [period] [limit]"); exit(1) }
            let period = KLinePeriod(rawValue: args.count >= 3 ? args[2] : "day") ?? .day
            let limit = args.count >= 4 ? Int(args[3]) ?? 320 : 320
            do {
                let bars = try await MarketDataSourceRegistry.shared.fetchKLine(for: symbol, period: period, limit: limit)
                print("\(symbol.code) \(period.displayName) 共 \(bars.count) 根")
                for bar in bars.suffix(10) {
                    let d = bar.time.formatted(date: .abbreviated, time: .shortened)
                    print("  \(d)  O \(fmt(bar.open))  H \(fmt(bar.high))  L \(fmt(bar.low))  C \(fmt(bar.close))  V \(Int(bar.volume))")
                }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "tech":
            guard args.count >= 2, let symbol = parseSymbol(args[1]) else { print("用法: tech <market>:<code>"); exit(1) }
            do {
                let bars = try await MarketDataSourceRegistry.shared.fetchKLine(for: symbol, period: .day, limit: 300)
                let t = TechnicalAnalyzer.analyze(bars: bars)
                print("\(symbol.code) \(symbol.name) — \(t.period)")
                print("  现价: \(fmt(t.currentPrice))")
                print("  支撑: \(t.support.map { fmt($0) } ?? "—")  阻力: \(t.resistance.map { fmt($0) } ?? "—")")
                print("  MA20: \(t.sma20.map { fmt($0) } ?? "—")  MA50: \(t.sma50.map { fmt($0) } ?? "—")  MA200: \(t.sma200.map { fmt($0) } ?? "—")")
                print("  YTD: \(t.ytdChangePercent.map { fmtPercent($0) } ?? "—")  52周高: \(t.high52w.map { fmt($0) } ?? "—")  52周低: \(t.low52w.map { fmt($0) } ?? "—")")
                if let rsi = t.rsi14 { print("  RSI14: \(String(format: "%.1f", rsi))") }
                if let dif = t.macdDIF, let dea = t.macdDEA, let hist = t.macdHistogram {
                    print("  MACD: DIF \(String(format: "%.4f", dif))  DEA \(String(format: "%.4f", dea))  柱 \(String(format: "%.4f", hist))")
                }
                if let bu = t.bollUpper, let bm = t.bollMid, let bl = t.bollLower {
                    print("  BOLL: 上 \(fmt(bu))  中 \(fmt(bm))  下 \(fmt(bl))")
                }
                if let k = t.kdjK, let d = t.kdjD, let j = t.kdjJ {
                    print("  KDJ: K \(String(format: "%.1f", k))  D \(String(format: "%.1f", d))  J \(String(format: "%.1f", j))")
                }
                if let pos = t.rangePosition52w { print("  52周区间位置: \(String(format: "%.1f%%", pos))") }
                if t.avgVolume20 > 0 { print("  20日均量: \(Int(t.avgVolume20))") }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "fund":
            guard args.count >= 2, let symbol = parseSymbol(args[1]) else { print("用法: fund <market>:<code>（SEC EDGAR 基本面，仅美股）"); exit(1) }
            do {
                let fd = try await EDGARSource.shared.fundamental(for: symbol)
                print("\(symbol.code) \(symbol.name) — SEC EDGAR 基本面")
                if let r = fd.revenue { print("  营收(财年\(fd.revenueYear ?? "—")): \(fmt(r))") }
                if let ni = fd.netIncome { print("  净利润: \(fmt(ni))") }
                if let oi = fd.operatingIncome { print("  营业利润: \(fmt(oi))") }
                if let gp = fd.grossProfit { print("  毛利: \(fmt(gp))") }
                if let e = fd.eps { print("  基本EPS: \(String(format: "%.2f", e))") }
                if let a = fd.assets { print("  总资产(\(fd.balanceDate ?? "—")): \(fmt(a))") }
                if let l = fd.liabilities { print("  总负债: \(fmt(l))") }
                if let eq = fd.equity { print("  股东权益: \(fmt(eq))") }
                if let s = fd.sharesOutstanding { print("  流通股: \(Int(s))") }
                if let roe = fd.roe { print("  ROE: \(String(format: "%.1f%%", roe))") }
                if let dr = fd.debtRatio { print("  资产负债率: \(String(format: "%.1f%%", dr))") }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "search":
            guard args.count >= 2 else { print("用法: search <query> [market]"); exit(1) }
            let market = args.count >= 3 ? Market(rawValue: args[2]) : nil
            do {
                let results = try await MarketDataSourceRegistry.shared.search(query: args[1], market: market)
                if results.isEmpty { print("无结果") }
                for s in results {
                    print("  \(s.market.rawValue):\(s.code)  \(s.name)")
                }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "watch":
            do {
                try await watchCommand(args)
            } catch {
                print("watch 失败: \(error)")
                exit(1)
            }

        case "news":
            guard args.count >= 2 else { print("用法: news flash|research|earnings|calendar"); exit(1) }
            guard let cat = NewsFeedCategory(rawValue: args[1]) else { print("分类: flash/research/earnings/calendar"); exit(1) }
            do {
                let db = try AppDatabase.makeDefault()
                let store = Store(db: db)
                try store.importBuiltinFeedsIfNeeded()
                // 调试模式：逐源拉取打印结果
                if args.contains("--debug") {
                    for feed in store.newsFeeds.filter({ $0.category == cat && $0.enabled }) {
                        do {
                            let n = try await NewsSourceRegistry.fetch(feed: feed, limit: 5).count
                            print("[\(feed.name)] → \(n) 条 ✅")
                        } catch {
                            print("[\(feed.name)] → ❌ \(error.localizedDescription)")
                        }
                    }
                    exit(0)
                }
                let items = await store.fetchNews(category: cat)
                print("\(cat.displayName) 共 \(items.count) 条")
                for item in items.prefix(10) {
                    print("  [\(item.source)] \(item.publishedAt.formatted(date: .abbreviated, time: .shortened))")
                    print("    \(item.title.prefix(60))")
                }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "trades":
            guard args.count >= 2 else { print("用法: trades list|add|delete"); exit(1) }
            do {
                let db = try AppDatabase.makeDefault()
                let store = Store(db: db)
                switch args[1] {
                case "list":
                    for t in store.trades {
                        print("  \(t.date.formatted(date: .abbreviated, time: .omitted)) [\(t.direction)] \(t.name) \(t.code) × \(t.quantity) @ \(t.price) fee \(t.fee)")
                    }
                    print("共 \(store.trades.count) 笔")
                case "add":
                    guard args.count >= 8 else { print("用法: trades add <stock|bond|fund|currency|crypto|option|other> <code> <name> <buy|sell> <qty> <price> [fee]"); exit(1) }
                    guard let type = AssetType(rawValue: args[2]),
                          let qty = Double(args[6]), let price = Double(args[7]) else { print("参数错误"); exit(1) }
                    let fee = args.count >= 9 ? (Double(args[8]) ?? 0) : 0
                    let market = type.defaultMarket
                    try store.upsertTrade(Trade(assetType: type, name: args[4], code: args[3].uppercased(),
                                                market: market, direction: args[5], quantity: qty, price: price, fee: fee))
                    print("已添加交易")
                case "delete":
                    guard args.count >= 3, let t = store.trades.first(where: { $0.id.hasPrefix(args[2]) }) else { print("未找到"); exit(1) }
                    try store.deleteTrade(t)
                    print("已删除")
                default:
                    print("未知子命令")
                    exit(1)
                }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "portfolio":
            guard args.count >= 2 else { print("用法: portfolio list|add|del|holdings|valuation|history|disposals|accounts"); exit(1) }
            do {
                let db = try AppDatabase.makeDefault()
                let store = Store(db: db)
                switch args[1] {
                case "list":        // 活动列表
                    for a in store.activities {
                        let assetCode = a.assetID.flatMap { store.assets[$0]?.code } ?? "-"
                        print("  \(a.date.formatted(date: .abbreviated, time: .omitted)) [\(a.type.rawValue)] \(assetCode) qty=\(a.quantity) px=\(a.unitPrice) amt=\(a.amount) fee=\(a.fee)")
                    }
                    print("共 \(store.activities.count) 笔")
                case "add":
                    // portfolio add <buy|sell|deposit|withdrawal|dividend|interest|split|fee|tax|transferIn|transferOut|credit|adjustment> <code> <name> <qty> [price] [fee] [date:YYYY-MM-DD]
                    // 买卖类：qty + price(+fee)；现金类：qty = 金额；split：qty = 拆股比例
                    guard args.count >= 6 else {
                        print("用法: portfolio add <type> <code> <name> <qty> [price] [fee] [date:YYYY-MM-DD]")
                        exit(1)
                    }
                    guard let type = ActivityType(rawValue: args[2]),
                          let qty = Double(args[5]) else { print("参数错误"); exit(1) }
                    let price = args.count >= 7 ? (Double(args[6]) ?? 0) : 0
                    let fee = args.count >= 8 ? (Double(args[7]) ?? 0) : 0
                    var date = Date()
                    if let di = args.firstIndex(where: { $0.hasPrefix("date:") }) {
                        let df = DateFormatter()
                        df.dateFormat = "yyyy-MM-dd"
                        df.locale = Locale(identifier: "en_US_POSIX")
                        date = df.date(from: String(args[di].dropFirst(5))) ?? date
                    }
                    let account = store.defaultAccount()
                    switch type {
                    case .buy, .sell:
                        let market: Market = args[3].hasPrefix("crypto:") ? .crypto : .us
                        let code = args[3].replacingOccurrences(of: "crypto:", with: "")
                        let asset = Asset(market: market, code: code.uppercased(), name: args[4])
                        try store.upsertAsset(asset)
                        try store.upsertActivity(Activity(accountID: account.id, assetID: asset.id, type: type,
                                                          date: date, quantity: qty, unitPrice: price,
                                                          amount: qty * price, fee: fee, currency: account.currency))
                    case .split:
                        let market: Market = args[3].hasPrefix("crypto:") ? .crypto : .us
                        let code = args[3].replacingOccurrences(of: "crypto:", with: "")
                        let asset = Asset(market: market, code: code.uppercased(), name: args[4])
                        try store.upsertAsset(asset)
                        try store.upsertActivity(Activity(accountID: account.id, assetID: asset.id, type: type,
                                                          date: date, quantity: qty, unitPrice: 0,
                                                          amount: 0, fee: 0, currency: account.currency))
                    case .dividend, .interest, .credit, .adjustment:
                        // 资产收益：amount = qty（金额）
                        let market: Market = args[3].hasPrefix("crypto:") ? .crypto : .us
                        let code = args[3].replacingOccurrences(of: "crypto:", with: "")
                        let asset = Asset(market: market, code: code.uppercased(), name: args[4])
                        try store.upsertAsset(asset)
                        try store.upsertActivity(Activity(accountID: account.id, assetID: asset.id, type: type,
                                                          date: date, quantity: 0, unitPrice: 0,
                                                          amount: qty, fee: fee, currency: account.currency))
                    case .deposit, .withdrawal, .transferIn, .transferOut, .fee, .tax, .unknown:
                        // 纯现金活动：amount = qty
                        try store.upsertActivity(Activity(accountID: account.id, type: type,
                                                          date: date, quantity: 0, unitPrice: 0,
                                                          amount: qty, fee: fee, currency: account.currency))
                    }
                    print("已添加 \(type.rawValue)")
                case "del":
                    guard args.count >= 3, let a = store.activities.first(where: { $0.id.hasPrefix(args[2]) }) else { print("未找到"); exit(1) }
                    try store.deleteActivity(a)
                    print("已删除")
                case "holdings":    // 持仓（全部账户合并）
                    let positions = store.positions()
                    if positions.isEmpty { print("（无持仓）") }
                    var totalCost = 0.0, totalValue = 0.0
                    for p in positions {
                        print("  \(p.asset.code) \(p.asset.name) qty=\(String(format: "%.4f", p.quantity)) avgCost=\(String(format: "%.2f", p.avgCostPerUnit)) cost=\(String(format: "%.2f", p.costBasis)) value=\(String(format: "%.2f", p.marketValue)) pnl=\(String(format: "%+.2f", p.unrealizedPnL)) (\(String(format: "%+.2f%%", p.unrealizedPnLPercent)))")
                        totalCost += p.costBasis
                        totalValue += p.marketValue
                    }
                    if !positions.isEmpty {
                        print("合计: 成本 \(String(format: "%.2f", totalCost)) / 市值 \(String(format: "%.2f", totalValue)) / 盈亏 \(String(format: "%+.2f", totalValue - totalCost))")
                    }
                case "valuation":
                    let v = store.valuation()
                    print("现金 \(String(format: "%.2f", v.cashBalance)) / 市值 \(String(format: "%.2f", v.marketValue)) / 总 \(String(format: "%.2f", v.totalValue))")
                    print("成本 \(String(format: "%.2f", v.costBasis)) / 净投入 \(String(format: "%.2f", v.netContribution))")
                    print("浮动盈亏 \(String(format: "%+.2f", v.unrealizedPnL)) (\(String(format: "%+.2f%%", v.unrealizedPnLPercent))) / 已实现 \(String(format: "%+.2f", v.realizedPnL))")
                case "history":
                    let snaps = store.portfolioHistory()
                    for s in snaps {
                        print("  \(s.date.formatted(date: .abbreviated, time: .omitted)) total=\(String(format: "%.2f", s.totalValue)) mv=\(String(format: "%.2f", s.marketValue)) cash=\(String(format: "%.2f", s.cashBalance)) gain=\(String(format: "%+.2f", s.totalGain))")
                    }
                    print("共 \(snaps.count) 个快照")
                case "disposals":
                    let ds = store.disposals()
                    var total = 0.0
                    for d in ds {
                        print("  \(d.disposalDate.formatted(date: .abbreviated, time: .omitted)) \(d.assetID) qty=\(d.quantity) proceeds=\(String(format: "%.2f", d.proceeds)) cost=\(String(format: "%.2f", d.costBasis)) pnl=\(String(format: "%+.2f", d.realizedPnL))")
                        total += d.realizedPnL
                    }
                    print("已实现盈亏合计 \(String(format: "%+.2f", total))")
                case "accounts":
                    for a in store.accounts {
                        let platform = a.platformID.flatMap { pid in store.platforms.first { $0.id == pid }?.name } ?? "-"
                        print("  \(a.name) [\(a.type.rawValue)] \(a.currency) platform=\(platform) default=\(a.isDefault)")
                    }
                    print("共 \(store.accounts.count) 个账户")
                default:
                    print("未知子命令")
                    exit(1)
                }
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "ask":
            guard args.count >= 2 else { print("用法: ask <问题>"); exit(1) }
            let settings = AISettings()
            let question = args.dropFirst().joined(separator: " ")
            print("使用 \(settings.provider.displayName) / \(settings.model) ...")
            do {
                let answer = try await ModelGateway().ask(question, provider: settings.provider,
                                                          model: settings.model,
                                                          apiKey: settings.apiKey(for: settings.provider))
                print(answer)
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "tag":
            guard args.count >= 2 else { print("用法: tag <标题>|<摘要>"); exit(1) }
            let settings = AISettings()
            let parts = args.dropFirst().joined(separator: " ").split(separator: "|", maxSplits: 1)
            let title = String(parts[0])
            let summary = parts.count > 1 ? String(parts[1]) : ""
            print("使用 \(settings.provider.displayName) / \(settings.model) ...")
            do {
                let tag = try await ModelGateway().tagNews(title: title, summary: summary,
                                                           provider: settings.provider,
                                                           model: settings.model,
                                                           apiKey: settings.apiKey(for: settings.provider))
                print("多空: \(tag.stance.rawValue)  利好利空: \(tag.impact.rawValue)")
                print("关联标的: \(tag.relatedSymbols.joined(separator: ", "))")
                print("关联市场: \(tag.relatedMarkets.map(\.displayName).joined(separator: ", "))")
                print("解读: \(tag.brief)")
            } catch {
                print("失败: \(error.localizedDescription)")
                exit(1)
            }

        case "models":
            let refresh = args.contains("--refresh")
            for p in ModelProvider.allCases {
                let keySet = !(AISettings().apiKey(for: p) ?? "").isEmpty
                let catalog = ModelCatalog.available(provider: p)
                print("  \(p.rawValue)  \(p.displayName)  [\(p.group)]  key:\(keySet ? "已设置" : "未设置")  目录:\(catalog.count) 个模型")
                if refresh {
                    let refreshed = await ModelCatalog.refresh(provider: p, apiKey: AISettings().apiKey(for: p))
                    print("    → 刷新: \(refreshed?.count ?? -1) 个（\(refreshed?.prefix(6).joined(separator: ", ") ?? "失败")）")
                } else if p == .ollama || keySet {
                    print("    → \(catalog.prefix(8).joined(separator: ", "))")
                }
            }
            if refresh { print("（已刷新并缓存，7 天有效）") }

        case "markets":
            for m in Market.allCases {
                print("  \(m.rawValue)  \(m.displayName)  \(m.tradingHours)")
            }

        case "twse-diag":
            print("(调试命令已移除)")

        case "ai-set":
            guard args.count >= 2, let p = ModelProvider(rawValue: args[1]) else { print("用法: ai-set <provider> [model]"); exit(1) }
            let settings = AISettings()
            settings.provider = p
            if args.count >= 3 { settings.model = args[2] }
            print("AI 供应商已设为 \(p.displayName)，模型 \(settings.model)")

        case "ai-key":
            guard args.count >= 3, let p = ModelProvider(rawValue: args[1]) else { print("用法: ai-key <provider> <key>"); exit(1) }
            let settings = AISettings()
            settings.setAPIKey(args[2], for: p)
            print("已保存 \(p.displayName) 的 API Key（本地存储）")

        default:
            printUsage()
            exit(1)
        }
    }

    @MainActor
    static func watchCommand(_ args: [String]) async throws {
        guard args.count >= 2 else {
            print("用法: watch add|list|remove ...")
            exit(1)
        }
        let db = try AppDatabase.makeDefault()
        let store = Store(db: db)
        switch args[1] {
        case "add":
            guard args.count >= 3, let symbol = parseSymbol(args[2]) else { print("用法: watch add <market>:<code> [group]"); exit(1) }
            let group = args.count >= 4 ? args[3] : "默认分组"
            let added = try store.addToWatchlist(symbol, group: group)
            if added {
                print("已添加 \(symbol.market.displayName) \(symbol.code) 到「\(group)」")
            } else {
                print("\(symbol.code) 已在自选中（去重跳过）")
            }

        case "list":
            let items = try await db.dbQueue.read { db in
                try WatchlistRecord.order(Column("group_name"), Column("sort_order")).fetchAll(db).map { $0.toItem() }
            }
            if items.isEmpty { print("自选为空") }
            for item in items {
                print("  [\(item.group)] \(item.symbol.market.rawValue):\(item.symbol.code)  \(item.symbol.name)")
            }

        case "remove":
            guard args.count >= 3, let symbol = parseSymbol(args[2]) else { print("用法: watch remove <market>:<code>"); exit(1) }
            try store.removeFromWatchlist(symbol)
            print("已移除 \(symbol.code)")

        default:
            print("未知 watch 子命令")
        }
    }

    static func printUsage() {
        print("""
        Tectonic CLI
          quote <market>:<code>    行情
          kline <market>:<code> [period] [limit]
          search <query> [market]
          watch add|list|remove ...
          ask <问题>                AI 问答
          tag <标题>|<摘要>         新闻打标
          models / markets          列表
          ai-set / ai-key           配置 AI
        """)
    }
}
