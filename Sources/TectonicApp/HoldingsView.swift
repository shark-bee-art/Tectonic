import SwiftUI
import CoreKit
import Charts

/// 持仓（自动推导）：持仓页只读展示，成本/盈亏全部从交易记录按 FIFO 推导。
/// 顶部账户选择器（多券商/多账户）+ 摘要 + 组合历史曲线 + 分布饼图 + 持仓列表。
struct HoldingsView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedAccountID: String? = nil
    @State private var showAccountManager = false

    /// 当前账户的估值
    private var valuation: PortfolioValuation {
        app.store.valuation(accountID: selectedAccountID)
    }

    /// 当前账户的历史快照
    private var history: [PortfolioSnapshot] {
        app.store.portfolioHistory(accountID: selectedAccountID)
    }

    private var hasData: Bool {
        !app.store.activities.isEmpty || !valuation.positions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            accountPicker
            if hasData {
                holdingsContent
            } else {
                emptyState
            }
        }
        .sheet(isPresented: $showAccountManager) {
            AccountManagerView()
                .environmentObject(app)
        }
        .onAppear {
            if !app.store.activities.isEmpty {
                Task { await app.store.refreshPortfolioQuotes() }
            }
        }
    }

    // MARK: 账户选择器

    private var accountPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedAccountID) {
                Text(L10n.l("account.all")).tag(String?.none)
                ForEach(app.store.accounts.filter { $0.isActive }) { account in
                    Text(account.name).tag(String?.some(account.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            .pickerStyle(.menu)
            Button {
                showAccountManager = true
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .help(L10n.l("account.add"))
            Spacer()
            if app.store.activities.isEmpty {
                Text(L10n.l("holdings.derived"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(L10n.l("holdings.emptyDerived"))
                .font(.title3)
                .multilineTextAlignment(.center)
            Text(L10n.l("holdings.emptyTxHint"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 持仓内容

    private var holdingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryRow

                if !history.isEmpty {
                    Text(L10n.l("holdings.history"))
                        .font(.headline)
                    historyChart
                }

                if !valuation.positions.isEmpty {
                    Text(L10n.l("holdings.distribution"))
                        .font(.headline)
                    allocationPieChart
                }

                Text(L10n.l("sidebar.holdings"))
                    .font(.headline)
                if valuation.positions.isEmpty {
                    Text(L10n.l("holdings.emptyDerived"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(valuation.positions) { position in
                            PositionRow(position: position)
                            if position.id != valuation.positions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.05)))
                }
            }
            .padding(16)
        }
    }

    // MARK: 摘要

    private var summaryRow: some View {
        HStack(spacing: 24) {
            summaryItem(L10n.l("holdings.totalValue"),
                        String(format: "%.2f", valuation.totalValue),
                        color: nil)
            summaryItem(L10n.l("holdings.cash"),
                        String(format: "%.2f", valuation.cashBalance),
                        color: nil)
            summaryItem(L10n.l("holdings.unrealized"),
                        String(format: "%+.2f", valuation.unrealizedPnL),
                        color: valuation.unrealizedPnL >= 0 ? .red : .green)
            summaryItem(L10n.l("holdings.realized"),
                        String(format: "%+.2f", valuation.realizedPnL),
                        color: valuation.realizedPnL >= 0 ? .red : .green)
            summaryItem(L10n.l("holdings.netContribution"),
                        String(format: "%.2f", valuation.netContribution),
                        color: nil)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func summaryItem(_ label: String, _ value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(color ?? .primary)
        }
    }

    // MARK: 组合历史曲线

    private var historyChart: some View {
        Chart(history) { snap in
            LineMark(x: .value("Date", snap.date),
                     y: .value("Total", snap.totalValue))
                .foregroundStyle(Color(hex: app.theme.accent) ?? .accentColor)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("Date", snap.date),
                     y: .value("Total", snap.totalValue))
                .foregroundStyle(
                    LinearGradient(colors: [(Color(hex: app.theme.accent) ?? .accentColor).opacity(0.25), .clear],
                                   startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 180)
    }

    // MARK: 分布饼图

    private var allocationPieChart: some View {
        let items = valuation.positions
            .filter { $0.marketValue > 0 }
            .sorted { $0.marketValue > $1.marketValue }
        return Chart(items) { p in
            SectorMark(angle: .value("value", p.marketValue),
                       innerRadius: .ratio(0.55),
                       angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value("name", p.asset.name))
        }
        .chartLegend(position: .bottom)
        .frame(height: 200)
    }
}

// MARK: - 持仓行

struct PositionRow: View {
    @EnvironmentObject var app: AppState
    let position: Position

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.asset.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text("\(position.asset.market.displayName) · \(position.asset.code)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.4f", position.quantity))
                    .font(.system(size: 13, design: .monospaced))
                Text(L10n.l("holdings.avgCost") + " " + String(format: "%.2f", position.avgCostPerUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f", position.marketValue))
                    .font(.system(size: 13, design: .monospaced))
                Text(String(format: "%.2f", position.costBasis))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%+.2f", position.unrealizedPnL))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(position.unrealizedPnL >= 0 ? Color.red : Color.green)
                Text(String(format: "%+.2f%%", position.unrealizedPnLPercent))
                    .font(.caption)
                    .foregroundStyle(position.unrealizedPnLPercent >= 0 ? Color.red : Color.green)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 账户管理

struct AccountManagerView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State private var editing: Account?
    @State private var showEditor = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.l("account.manage"))
                    .font(.headline)
                Spacer()
                Button(L10n.l("common.done")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            if app.store.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(L10n.l("account.emptyHint"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.store.accounts) { account in
                    HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(account.name)
                                        .fontWeight(.medium)
                                    if account.isDefault {
                                        Text(L10n.l("account.default"))
                                            .font(.caption2)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill((Color(hex: app.theme.accent) ?? .accentColor).opacity(0.15)))
                                            .foregroundStyle(Color(hex: app.theme.accent) ?? .accentColor)
                                    }
                                }
                                Text("\(account.type.displayName) · \(account.currency)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                editing = account
                                showEditor = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            Button {
                                try? app.store.removeAccount(account)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                        .padding(.vertical, 2)
                    }
            }
            Divider()
            HStack {
                Button {
                    editing = nil
                    showEditor = true
                } label: {
                    Label(L10n.l("account.add"), systemImage: "plus")
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(width: 460, height: 420)
        .sheet(isPresented: $showEditor) {
            AccountEditor(account: editing)
                .environmentObject(app)
        }
    }
}

// MARK: - 账户编辑

struct AccountEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    let account: Account?

    @State private var name = ""
    @State private var type: AccountType = .securities
    @State private var currency = "USD"
    @State private var isDefault = false

    private let currencies = ["USD", "CNY", "HKD", "JPY", "KRW", "TWD", "EUR", "GBP", "SGD"]

    var body: some View {
        VStack(spacing: 16) {
            Text(account == nil ? L10n.l("account.add") : L10n.l("account.edit"))
                .font(.headline)
            Form {
                TextField(L10n.l("account.name"), text: $name)
                Picker(L10n.l("account.type"), selection: $type) {
                    ForEach(AccountType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                Picker(L10n.l("account.currency"), selection: $currency) {
                    ForEach(currencies, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                Toggle(L10n.l("account.default"), isOn: $isDefault)
            }
            .formStyle(.grouped)
            HStack {
                Button(L10n.l("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.l("common.save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 380)
        .onAppear {
            if let account {
                name = account.name
                type = account.type
                currency = account.currency
                isDefault = account.isDefault
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing = account {
            var updated = existing
            updated.name = trimmed
            updated.type = type
            updated.currency = currency
            updated.isDefault = isDefault
            try? app.store.updateAccount(updated)
        } else {
            let new = Account(name: trimmed, type: type, currency: currency, isDefault: isDefault)
            try? app.store.addAccount(new)
        }
        dismiss()
    }
}
