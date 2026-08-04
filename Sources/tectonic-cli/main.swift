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
                if t.avgVolume20 > 0 { print("  20日均量: \(Int(t.avgVolume20))") }
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
