import SwiftUI
import CoreKit
import UniformTypeIdentifiers

/// 持仓：导入券商 CSV/JSON → 仓位视图（P3 完整实现，先做导入框架）
struct HoldingsView: View {
    @EnvironmentObject var app: AppState
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var isParsing = false

    var body: some View {
        VStack(spacing: 0) {
            if app.store.holdings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text("暂无持仓数据")
                        .font(.title3)
                    Text("导入券商导出的 CSV / JSON 文件\n支持富途、老虎、IBKR、Robinhood、币安等（模型辅助识别字段）")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button {
                        showImporter = true
                    } label: {
                        Label("导入持仓文件", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(app.store.holdings) { h in
                        HoldingRow(holding: h)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("导入") { showImporter = true }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("清空") {
                            try? app.store.removeAllHoldings()
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .json, .data]) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isParsing = true
            Task {
                defer { isParsing = false }
                let holdings = HoldingParser().parse(url: url)
                if holdings.isEmpty {
                    importMessage = "未能识别文件中的持仓（可尝试其他格式，或后续版本支持模型辅助识别）"
                } else {
                    try? app.store.upsertHoldings(holdings)
                    importMessage = "已导入 \(holdings.count) 条持仓"
                }
            }
        case .failure(let error):
            importMessage = "导入失败: \(error.localizedDescription)"
        }
    }
}

struct HoldingRow: View {
    let holding: Holding

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.symbol.name)
                Text("\(holding.symbol.market.displayName) \(holding.symbol.code) · \(holding.broker)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(holding.quantity, specifier: "%.4f")")
                    .font(.body.monospacedDigit())
                Text("成本 \(holding.costBasis, specifier: "%.4f") \(holding.symbol.currency)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// CSV/JSON 持仓解析（简单规则版；P3 接入模型辅助识别）
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

    /// 通用 CSV：表头映射（symbol/ticker/code、quantity/qty/shares/amount、cost/price/cost_basis）
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
