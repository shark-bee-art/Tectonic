import SwiftUI
import CoreKit

/// 交易记录（活动账本）：记录/编辑/删除各类交易活动（买卖/分红/利息/存取款/转账/费用/税/拆股等）
struct TransactionsView: View {
    @EnvironmentObject var app: AppState
    @State private var editing: Activity?
    @State private var showEditor = false
    @State private var selected: Activity?

    var body: some View {
        VStack(spacing: 0) {
            if app.store.activities.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text(L10n.l("tx.empty"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button {
                        editing = nil
                        showEditor = true
                    } label: {
                        Label(L10n.l("tx.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selected) {
                    ForEach(app.store.activities) { activity in
                        ActivityRow(activity: activity,
                                    accountName: accountName(activity.accountID),
                                    assets: app.store.assets)
                            .tag(activity)
                            .contextMenu {
                                Button(L10n.l("common.edit")) {
                                    editing = activity
                                    showEditor = true
                                }
                                Button(L10n.l("common.delete"), role: .destructive) {
                                    try? app.store.deleteActivity(activity)
                                }
                            }
                    }
                }
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 8) {
                        if let tx = selected {
                            ActivitySummaryBar(activity: tx, accountName: accountName(tx.accountID))
                        }
                        // 底部添加交易入口（右上角工具栏不占位）
                        HStack {
                            Button {
                                editing = nil
                                showEditor = true
                            } label: {
                                Label(L10n.l("tx.add"), systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .help(L10n.l("tx.add"))
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            ActivityEditor(activity: editing) { _ in
                showEditor = false
            }
            .environmentObject(app)
        }
    }

    private func accountName(_ id: String) -> String {
        app.store.accounts.first { $0.id == id }?.name ?? id
    }
}

// MARK: - 活动行

struct ActivityRow: View {
    let activity: Activity
    let accountName: String
    let assets: [String: Asset]

    private var asset: Asset? {
        activity.assetID.flatMap { assets[$0] }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 日期
            VStack(alignment: .leading) {
                Text(activity.date.formatted(.dateTime.month().day()))
                    .font(.body.weight(.medium))
                Text(activity.date.formatted(.dateTime.year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
            // 资产/名称
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(activityTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let opt = activity.option {
                        Text(opt.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundStyle(.purple)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // 类型标签
            Text(activity.type.displayName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(typeColor.opacity(0.15)))
                .foregroundStyle(typeColor)
            // 金额
            VStack(alignment: .trailing, spacing: 2) {
                Text(detailText)
                    .font(.callout.monospacedDigit())
                Text(cashFlowText)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(cashFlowColor)
            }
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var activityTitle: String {
        if let asset, !asset.name.isEmpty { return asset.name }
        if !activity.notes.isEmpty { return activity.notes }
        return asset?.code ?? activity.type.displayName
    }

    private var subtitle: String {
        switch activity.type {
        case .buy, .sell, .split:
            return (asset?.code ?? activity.assetID ?? "") + " · " + (asset?.market.displayName ?? "")
        case .dividend, .interest, .credit, .adjustment:
            return (asset?.code ?? activity.assetID ?? "") + " · " + accountName
        default:
            return accountName
        }
    }

    private var detailText: String {
        switch activity.type {
        case .buy, .sell:
            return String(format: "%.4f × %.4f", activity.quantity, activity.unitPrice)
        default:
            return ""
        }
    }

    private var cashFlowText: String {
        String(format: "%@%.2f", activity.netCashFlow >= 0 ? "+" : "", activity.netCashFlow)
    }

    private var typeColor: Color {
        switch activity.type {
        case .buy: .red
        case .sell: .green
        case .dividend, .interest, .credit: .orange
        case .deposit, .transferIn: .blue
        case .withdrawal, .transferOut, .fee, .tax: .gray
        case .split: .purple
        case .adjustment, .unknown: .secondary
        }
    }

    private var cashFlowColor: Color {
        switch activity.type {
        case .buy, .deposit, .withdrawal, .transferIn, .transferOut, .fee, .tax:
            return activity.netCashFlow >= 0 ? Color.red : Color.green
        default:
            return activity.netCashFlow >= 0 ? Color.red : Color.green
        }
    }
}

// MARK: - 选中活动详情条

struct ActivitySummaryBar: View {
    let activity: Activity
    let accountName: String

    var body: some View {
        HStack(spacing: 16) {
            Text(activity.type.displayName)
                .font(.headline)
            if let assetID = activity.assetID {
                Text(assetID)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(accountName)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if activity.quantity > 0 || activity.unitPrice > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.4f × %.4f", activity.quantity, activity.unitPrice))
                        .font(.callout.monospacedDigit())
                    if activity.fee > 0 {
                        Text("\(L10n.l("tx.fee")) \(activity.fee, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if activity.amount != 0 {
                Text(String(format: "%+.2f", activity.amount))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(activity.amount >= 0 ? Color.red : Color.green)
            }
        }
        .padding(12)
        .background(.bar)
    }
}

// MARK: - 活动编辑器

struct ActivityEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let activity: Activity?
    let onSave: (Activity) -> Void

    @State private var date: Date
    @State private var type: ActivityType
    @State private var accountID: String
    @State private var assetType: AssetType
    @State private var name: String
    @State private var code: String
    @State private var market: Market
    @State private var quantity: String
    @State private var price: String
    @State private var fee: String
    @State private var notes: String
    // 期权字段
    @State private var callPut: String
    @State private var strike: String
    @State private var expiry: Date
    @State private var hasOption: Bool

    init(activity: Activity?, onSave: @escaping (Activity) -> Void) {
        self.activity = activity
        self.onSave = onSave
        _date = State(initialValue: activity?.date ?? Date())
        _type = State(initialValue: activity?.type ?? .buy)
        _accountID = State(initialValue: activity?.accountID ?? "")
        _assetType = State(initialValue: .stock)
        _name = State(initialValue: "")
        _code = State(initialValue: "")
        _market = State(initialValue: .us)
        _quantity = State(initialValue: activity.map { String($0.quantity) } ?? "")
        _price = State(initialValue: activity.map { String($0.unitPrice) } ?? "")
        _fee = State(initialValue: activity.map { String($0.fee) } ?? "0")
        _notes = State(initialValue: activity?.notes ?? "")
        _callPut = State(initialValue: activity?.option?.callPut ?? "call")
        _strike = State(initialValue: activity?.option.map { String($0.strikePrice) } ?? "")
        _expiry = State(initialValue: activity?.option?.expiryDate ?? Date().addingTimeInterval(30 * 86400))
        _hasOption = State(initialValue: activity?.option != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(activity == nil ? L10n.l("tx.add") : L10n.l("tx.edit"))
                .font(.title2.weight(.semibold))

            Form {
                Section {
                    Picker(L10n.l("tx.type"), selection: $type) {
                        ForEach(ActivityType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    DatePicker(L10n.l("tx.date"), selection: $date, displayedComponents: .date)
                    Picker(L10n.l("activity.account"), selection: $accountID) {
                        ForEach(app.store.accounts.filter(\.isActive)) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                }

                // 证券类字段（买卖/拆股/分红等需要标的）
                if type.requiresAsset {
                    Section {
                        Picker(L10n.l("tx.assetType"), selection: $assetType) {
                            ForEach(AssetType.allCases) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .onChange(of: assetType) { _, newType in
                            if market == .us || market == .crypto || market == .fund {
                                market = newType.defaultMarket
                            }
                        }
                        TextField(L10n.l("tx.name"), text: $name)
                        TextField(L10n.l("tx.code"), text: $code)
                        Picker(L10n.l("sidebar.markets"), selection: $market) {
                            ForEach(Market.allCases) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                    }
                }

                // 数量/价格/金额字段（按类型显示）
                Section {
                    switch type {
                    case .buy, .sell:
                        TextField(L10n.l("tx.quantity"), text: $quantity)
                        TextField(L10n.l("tx.price"), text: $price)
                        TextField(L10n.l("tx.fee"), text: $fee)
                    case .split:
                        TextField(L10n.l("activity.buy") + " ratio", text: $quantity)
                            .help("2:1 拆股填 2")
                    case .dividend, .interest, .credit, .adjustment:
                        TextField(L10n.l("activity.amount"), text: $quantity)
                            .help("收益金额")
                    case .deposit, .withdrawal, .transferIn, .transferOut, .fee, .tax:
                        TextField(L10n.l("activity.amount"), text: $quantity)
                        TextField(L10n.l("tx.fee"), text: $fee)
                    case .unknown:
                        TextField(L10n.l("activity.amount"), text: $quantity)
                    }
                    TextField(L10n.l("tx.notes"), text: $notes)
                }

                // 期权字段
                if type == .buy || type == .sell {
                    Section(L10n.l("asset.option")) {
                        Toggle(L10n.l("asset.option"), isOn: $hasOption)
                        if hasOption {
                            Picker(L10n.l("option.callPut"), selection: $callPut) {
                                Text(L10n.l("option.call")).tag("call")
                                Text(L10n.l("option.put")).tag("put")
                            }
                            .pickerStyle(.segmented)
                            TextField(L10n.l("option.strike"), text: $strike)
                            DatePicker(L10n.l("option.expiry"), selection: $expiry, displayedComponents: .date)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L10n.l("common.cancel")) { dismiss() }
                Button(activity == nil ? L10n.l("common.add") : L10n.l("common.save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!validInput)
            }
        }
        .padding(20)
        .frame(width: 440, height: 620)
        .onAppear {
            if let a = activity {
                name = a.assetID.flatMap { id in
                    app.store.assets[id]?.name ?? ""
                } ?? ""
                code = a.assetID.flatMap { id in
                    app.store.assets[id]?.code ?? ""
                } ?? ""
                market = a.assetID.flatMap { id in
                    app.store.assets[id]?.market ?? .us
                } ?? .us
                assetType = a.assetID.flatMap { id in
                    app.store.assets[id]?.assetType ?? .stock
                } ?? .stock
                if let asset = a.assetID.flatMap({ app.store.assets[$0] }) {
                    name = asset.name
                    code = asset.code
                    market = asset.market
                    assetType = asset.assetType
                }
            }
            if accountID.isEmpty {
                accountID = app.store.defaultAccount().id
            }
        }
    }

    private var validInput: Bool {
        switch type {
        case .buy, .sell:
            return !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Double(quantity) != nil && Double(price) != nil
        case .split, .dividend, .interest, .credit, .adjustment, .deposit, .withdrawal,
             .transferIn, .transferOut, .fee, .tax, .unknown:
            return Double(quantity) != nil
        }
    }

    private func save() {
        let option: OptionSpec? = hasOption
            ? OptionSpec(callPut: callPut,
                         strikePrice: Double(strike) ?? 0,
                         expiryDate: expiry,
                         multiplier: 100)
            : nil
        let qty = Double(quantity) ?? 0
        let px = Double(price) ?? 0

        let assetID: String?
        if type.requiresAsset {
            let symbol = Symbol(market: market,
                                code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                currency: accountCurrency)
            let asset = Asset(market: market, code: symbol.code, name: symbol.name,
                              currency: accountCurrency, assetType: assetType)
            try? app.store.upsertAsset(asset)
            assetID = asset.id
        } else {
            assetID = nil
        }

        let amount: Double
        switch type {
        case .buy, .sell:
            amount = qty * px
        default:
            amount = qty
        }

        let newActivity = Activity(
            id: activity?.id ?? UUID().uuidString,
            accountID: accountID,
            assetID: assetID,
            type: type,
            date: date,
            quantity: (type == .buy || type == .sell) ? qty : (type == .split ? qty : 0),
            unitPrice: (type == .buy || type == .sell) ? px : 0,
            amount: amount,
            fee: Double(fee) ?? 0,
            currency: accountCurrency,
            notes: notes,
            option: (type == .buy || type == .sell) ? option : nil
        )
        try? app.store.upsertActivity(newActivity)
        onSave(newActivity)
        dismiss()
    }

    private var accountCurrency: String {
        app.store.accounts.first { $0.id == accountID }?.currency ?? "USD"
    }
}
