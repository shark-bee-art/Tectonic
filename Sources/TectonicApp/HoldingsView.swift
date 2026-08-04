import SwiftUI
import CoreKit
import Charts
import UniformTypeIdentifiers

/// 持仓：导入（规则+AI 识别）→ 仓位视图（资产曲线 + 分布饼图 + 列表）
struct HoldingsView: View {
    @EnvironmentObject var app: AppState
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var isParsing = false
    @State private var isAIParsing = false
    @State private var lastImportedCount = 0

    /// 各持仓当前市值（quotes 优先，成本价兜底）
    private var marketValues: [(Holding, Double)] {
        app.store.holdings.map { h in
            let price = app.store.quotes[h.symbol.id]?.price ?? h.costBasis
            return (h, price * h.quantity * Double(h.option?.multiplier ?? 1))
        }
    }

    private var totalValue: Double {
        marketValues.reduce(0) { $0 + $1.1 }
    }

    private var totalCost: Double {
        app.store.holdings.reduce(0) { $0 + $1.costBasis * $1.quantity * Double($1.option?.multiplier ?? 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if app.store.holdings.isEmpty {
                emptyState
            } else {
                holdingsContent
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .json, .data]) { result in
            handleImport(result)
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(L10n.l("holdings.empty"))
                .font(.title3)
            Text(L10n.l("holdings.emptyHint"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                showImporter = true
            } label: {
                Label(L10n.l("holdings.importFile"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            if isAIParsing {
                ProgressView(L10n.l("holdings.aiParsing"))
            }
            if let msg = importMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 持仓内容

    private var holdingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 摘要
                HStack(spacing: 24) {
                    summaryItem(L10n.l("holdings.totalValue"),
                                String(format: "%.2f", totalValue),
                                color: nil)
                    summaryItem(L10n.l("holdings.cost"),
                                String(format: "%.2f", totalCost),
                                color: nil)
                    let pl = totalValue - totalCost
                    summaryItem(L10n.l("holdings.profitLoss"),
                                String(format: "%+.2f", pl),
                                color: pl >= 0 ? .red : .green)
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

                // 资产变化折线图（基于交易记录）
                if !app.store.trades.isEmpty {
                    Text(L10n.l("holdings.assetChart"))
                        .font(.headline)
                    assetCurveChart
                }

                // 持仓分布饼图
                if !marketValues.isEmpty {
                    Text(L10n.l("holdings.distribution"))
                        .font(.headline)
                    allocationPieChart
                }

                // 持仓列表
                Text(L10n.l("sidebar.holdings"))
                    .font(.headline)
                ForEach(app.store.holdings) { h in
                    HoldingRow(holding: h, quote: app.store.quotes[h.symbol.id])
                }

                if let msg = importMessage {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.l("common.import")) { showImporter = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.l("holdings.importToWatchlist")) {
                    if let n = try? app.store.importHoldingsToWatchlist() {
                        importMessage = "\(L10n.l("holdings.imported")) \(n)"
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.l("common.clear")) {
                    try? app.store.removeAllHoldings()
                }
            }
        }
    }

    private func summaryItem(_ title: String, _ value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color ?? .primary)
        }
    }

    // MARK: 资产曲线（交易记录净值）

    private var assetCurveChart: some View {
        let points = app.store.equityCurve()
        return Chart(points, id: \.0) { p in
            LineMark(x: .value("date", p.0), y: .value("equity", p.1))
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)
            AreaMark(x: .value("date", p.0), y: .value("equity", p.1))
                .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.25), .clear],
                                                startPoint: .top, endPoint: .bottom))
        }
        .chartYAxisLabel(L10n.l("holdings.totalValue"))
        .frame(height: 160)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    // MARK: 持仓分布饼图

    private var allocationPieChart: some View {
        let values = marketValues
        let total = max(totalValue, 1)
        return Chart(values, id: \.0.symbol.id) { h, v in
            SectorMark(angle: .value("value", v),
                       innerRadius: .ratio(0.55),
                       angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value("name", h.symbol.name))
        }
        .chartLegend(.visible)
        .frame(height: 200)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay {
            if total <= 0 {
                Text("—")
            }
        }
    }

    // MARK: 导入

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isParsing = true
            importMessage = nil
            Task {
                defer { isParsing = false }
                var holdings = HoldingParser().parse(url: url)
                if holdings.isEmpty {
                    // 规则解析失败 → AI 识别（捕获配置避免跨 actor）
                    isAIParsing = true
                    let provider = app.aiSettings.provider
                    let model = app.aiSettings.model
                    let key = app.aiSettings.apiKey(for: provider)
                    holdings = await HoldingAIParser().parse(url: url, provider: provider, model: model, apiKey: key)
                    isAIParsing = false
                }
                if holdings.isEmpty {
                    importMessage = L10n.l("holdings.importHint")
                } else {
                    try? app.store.upsertHoldings(holdings)
                    lastImportedCount = holdings.count
                    importMessage = "\(L10n.l("holdings.imported")) \(holdings.count)"
                }
            }
        case .failure(let error):
            importMessage = "\(L10n.l("common.failed")): \(error.localizedDescription)"
        }
    }
}

// MARK: - 持仓行

struct HoldingRow: View {
    let holding: Holding
    let quote: Quote?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(holding.symbol.name)
                        .font(.body.weight(.medium))
                    if holding.assetType == .option, let opt = holding.option {
                        Text(opt.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundStyle(.purple)
                    } else if holding.assetType != .stock {
                        Text(holding.assetType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(holding.symbol.market.displayName) \(holding.symbol.code) · \(holding.broker)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let price = quote?.price ?? holding.costBasis
                let value = price * holding.quantity * Double(holding.option?.multiplier ?? 1)
                Text("\(holding.quantity, specifier: "%.4f") × \(price, specifier: "%.4f")")
                    .font(.callout.monospacedDigit())
                Text(String(format: "%.2f %@", value, holding.symbol.currency))
                    .font(.body.monospacedDigit().weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AI 持仓识别（模型辅助解析任意券商导出文件）

struct HoldingAIParser {
    /// 从 MainActor 上下文捕获 AI 配置后传入，避免跨 actor 传递
    func parse(url: URL, provider: ModelProvider, model: String, apiKey: String?) async -> [Holding] {
        guard url.startAccessingSecurityScopedResource() else { return [] }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        guard let key = apiKey else { return [] }

        let prompt = """
        识别以下券商持仓导出文件，输出严格的 JSON 数组（不要任何其他文字）：
        [{"symbol": "代码", "name": "名称", "quantity": 数量, "cost_basis": 成本价, "market": "us|hk|cn|crypto|fund|jp|kr|tw", "asset_type": "stock|bond|fund|currency|crypto|option|other"}]

        文件内容：
        \(String(text.prefix(8000)))

        规则：
        - symbol 填代码（如 AAPL、00700、600519、BTCUSDT）
        - 期权仓位 asset_type 填 option，symbol 填标的代码
        - 无法识别的行跳过
        """
        do {
            let reply = try await ModelGateway().ask(prompt, system: "你是一个精确的持仓文件解析器。只输出 JSON。",
                                                     provider: provider, model: model, apiKey: key)
            return parseHoldingsJSON(reply)
        } catch {
            return []
        }
    }

    private func parseHoldingsJSON(_ text: String) -> [Holding] {
        // 提取 JSON 数组（容错：模型可能带 ```json 包裹）
        var cleaned = text
        if let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var holdings: [Holding] = []
        for item in arr {
            guard let symbol = item["symbol"] as? String,
                  let qty = (item["quantity"] as? Double) ?? Double("\(item["quantity"] ?? "")"),
                  let cost = (item["cost_basis"] as? Double) ?? Double("\(item["cost_basis"] ?? "")"),
                  qty > 0 else { continue }
            let market = Market(rawValue: (item["market"] as? String) ?? "") ?? inferMarket(symbol)
            let assetType = AssetType(rawValue: (item["asset_type"] as? String) ?? "") ?? .stock
            let name = (item["name"] as? String) ?? symbol
            holdings.append(Holding(symbol: Symbol(market: market, code: symbol, name: name),
                                    quantity: qty, costBasis: cost, broker: "AI",
                                    assetType: assetType))
        }
        return holdings
    }

    private func inferMarket(_ code: String) -> Market {
        let up = code.uppercased()
        if up.hasSuffix(".HK") { return .hk }
        if up.hasSuffix(".T") { return .jp }
        if up.hasSuffix(".KS") { return .kr }
        if up.hasSuffix(".TW") { return .tw }
        if up.hasSuffix(".SS") || up.hasSuffix(".SZ") { return .cn }
        if up.hasSuffix("USDT") || up.hasSuffix("USDC") || up.hasSuffix("BTC") { return .crypto }
        if up.allSatisfy(\.isNumber), up.count == 6 {
            return up.hasPrefix("0") || up.hasPrefix("1") ? .fund : .cn
        }
        return .us
    }
}

/// CSV/JSON 持仓解析（规则版；失败时由 AI 识别兜底）
struct HoldingParser {
    func parse(url: URL) -> [Holding] {
        guard url.startAccessingSecurityScopedResource() else { return [] }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        if url.pathExtension.lowercased() == "json" {
            return parseJSON(text)
        }
        return parseCSV(text)
    }

    private func parseCSV(_ text: String) -> [Holding] {
        var rows = text.components(separatedBy: .newlines)
        guard let headerLine = rows.first else { return [] }
        rows.removeFirst()
        let headers = headerLine.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let codeIdx = headers.firstIndex(where: { ["symbol", "ticker", "code", "证券代码"].contains($0) }),
              let qtyIdx = headers.firstIndex(where: { ["quantity", "qty", "shares", "数量", "持仓数量"].contains($0) }),
              let costIdx = headers.firstIndex(where: { ["cost", "cost_basis", "costbasis", "price", "成本价", "持仓成本"].contains($0) }) else {
            return []
        }
        var holdings: [Holding] = []
        for line in rows {
            let cols = line.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard cols.count > max(codeIdx, qtyIdx, costIdx),
                  !cols[codeIdx].isEmpty,
                  let qty = Double(cols[qtyIdx]),
                  let cost = Double(cols[costIdx]),
                  qty > 0 else { continue }
            let code = cols[codeIdx]
            let (market, realCode) = inferMarket(code)
            holdings.append(Holding(symbol: Symbol(market: market, code: realCode, name: realCode),
                                    quantity: qty, costBasis: cost, broker: "CSV"))
        }
        return holdings
    }

    private func parseJSON(_ text: String) -> [Holding] {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var holdings: [Holding] = []
        for item in arr {
            guard let code = (item["symbol"] as? String) ?? (item["ticker"] as? String) ?? (item["code"] as? String),
                  let qty = (item["quantity"] as? Double) ?? (item["qty"] as? Double) ?? (item["shares"] as? Double),
                  let cost = (item["cost"] as? Double) ?? (item["costBasis"] as? Double) ?? (item["price"] as? Double),
                  qty > 0 else { continue }
            let (market, realCode) = inferMarket(code)
            holdings.append(Holding(symbol: Symbol(market: market, code: realCode, name: realCode),
                                    quantity: qty, costBasis: cost, broker: "JSON"))
        }
        return holdings
    }

    /// 从代码推断市场
    private func inferMarket(_ code: String) -> (Market, String) {
        let up = code.uppercased()
        if up.hasSuffix(".HK") { return (.hk, up.replacingOccurrences(of: ".HK", with: "")) }
        if up.hasSuffix(".T") || up.hasSuffix(".TSE") { return (.jp, up.replacingOccurrences(of: ".T", with: "").replacingOccurrences(of: ".TSE", with: "")) }
        if up.hasSuffix(".KS") { return (.kr, up.replacingOccurrences(of: ".KS", with: "")) }
        if up.hasSuffix(".TW") { return (.tw, up.replacingOccurrences(of: ".TW", with: "")) }
        if up.hasSuffix(".SS") || up.hasSuffix(".SZ") {
            let c = up.replacingOccurrences(of: ".SS", with: "").replacingOccurrences(of: ".SZ", with: "")
            return (.cn, c)
        }
        if up.hasSuffix("USDT") || up.hasSuffix("USDC") || up.hasSuffix("BTC") { return (.crypto, up) }
        if up.allSatisfy(\.isNumber), up.count == 6 {
            if up.hasPrefix("0") || up.hasPrefix("1") { return (.fund, up) }
            return (.cn, up)
        }
        return (.us, up)
    }
}
