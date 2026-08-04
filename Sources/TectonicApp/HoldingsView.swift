import SwiftUI
import CoreKit
import Charts

/// 持仓：手动添加 → 仓位视图（资产曲线 + 分布饼图 + 列表）
struct HoldingsView: View {
    @EnvironmentObject var app: AppState
    @State private var importMessage: String?
    @State private var showManualAdd = false

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
        .sheet(isPresented: $showManualAdd) {
            HoldingEditor { holding in
                if let h = holding {
                    try? app.store.upsertHoldings([h])
                    importMessage = "\(L10n.l("holdings.imported")) 1"
                }
                showManualAdd = false
            }
            .environmentObject(app)
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
            Text(L10n.l("holdings.emptyHintManual"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                showManualAdd = true
            } label: {
                Label(L10n.l("holdings.add"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help(L10n.l("holdings.add"))
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
                Button {
                    showManualAdd = true
                } label: {
                    Label(L10n.l("holdings.add"), systemImage: "plus")
                }
                .help(L10n.l("holdings.add"))
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

struct HoldingEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let onSave: (Holding?) -> Void

    @State private var code: String = ""
    @State private var name: String = ""
    @State private var market: Market = .us
    @State private var assetType: AssetType = .stock
    @State private var quantity: String = ""
    @State private var costBasis: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.l("holdings.add"))
                .font(.title2.weight(.semibold))

            Form {
                Section {
                    TextField(L10n.l("tx.code"), text: $code)
                        .onSubmit { inferFromCode() }
                    TextField(L10n.l("tx.name"), text: $name)
                    Picker(L10n.l("sidebar.markets"), selection: $market) {
                        ForEach(Market.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .onChange(of: assetType) { _, t in
                        if market == .us || market == .crypto || market == .fund {
                            market = t.defaultMarket
                        }
                    }
                    Picker(L10n.l("tx.assetType"), selection: $assetType) {
                        ForEach(HoldingAssetTypes.allCases) { t in
                            Text(t.displayName).tag(t.rawValueAsAssetType)
                        }
                    }
                    TextField(L10n.l("tx.quantity"), text: $quantity)
                    TextField(L10n.l("holdings.cost"), text: $costBasis)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L10n.l("common.cancel")) { onSave(nil) }
                Button(L10n.l("common.save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || Double(quantity) == nil || Double(costBasis) == nil)
            }
        }
        .padding(20)
        .frame(width: 400, height: 400)
    }

    /// 从代码推断市场/名称
    private func inferFromCode() {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !c.isEmpty else { return }
        let m = RobustCSV.inferMarket(c)
        if market == .us || market == .hk || market == .cn || market == .tw || market == .crypto {
            market = m
        }
        if name.isEmpty { name = c }
    }

    private func save() {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let holding = Holding(symbol: Symbol(market: market, code: c, name: name.isEmpty ? c : name),
                              quantity: Double(quantity) ?? 0,
                              costBasis: Double(costBasis) ?? 0,
                              broker: "手动",
                              assetType: assetType)
        onSave(holding)
        dismiss()
    }
}

/// 持仓支持的资产类别（不含期权，保持简洁）
private enum HoldingAssetTypes: String, CaseIterable, Identifiable {
    case stock, bond, fund, currency, crypto, other
    var id: String { rawValue }
    var displayName: String {
        AssetType(rawValue: rawValue)?.displayName ?? rawValue
    }
    var rawValueAsAssetType: AssetType { AssetType(rawValue: rawValue) ?? .stock }
}

// MARK: - JSON 持仓解析

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
}
