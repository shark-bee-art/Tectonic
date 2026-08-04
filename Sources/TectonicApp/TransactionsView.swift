import SwiftUI
import CoreKit

/// 交易记录：记录/编辑/删除（股票、债券、基金、货币、加密货币、期权等）+ 文件导入（模型辅助）
struct TransactionsView: View {
    @EnvironmentObject var app: AppState
    @State private var editing: Trade?
    @State private var showEditor = false
    @State private var selected: Trade?
    @State private var showImporter = false
    @State private var previewTrades: [ParsedTrade] = []
    @State private var showPreview = false
    @State private var pendingURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            if app.store.trades.isEmpty {
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
                    ForEach(app.store.trades) { tx in
                        TradeRow(tx: tx)
                            .tag(tx)
                            .contextMenu {
                                Button(L10n.l("common.edit")) {
                                    editing = tx
                                    showEditor = true
                                }
                                Button(L10n.l("common.delete"), role: .destructive) {
                                    try? app.store.deleteTrade(tx)
                                }
                            }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let tx = selected {
                        TradeSummaryBar(tx: tx)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = nil
                    showEditor = true
                } label: {
                    Label(L10n.l("tx.add"), systemImage: "plus")
                }
                .help(L10n.l("tx.add"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Label(L10n.l("common.import"), systemImage: "square.and.arrow.down")
                }
                .help(L10n.l("holdings.importFile"))
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .json, .data, .plainText]) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showPreview) {
            TradeImportPreviewSheet(trades: previewTrades, sourceURL: pendingURL) { trades in
                if !trades.isEmpty {
                    for t in trades {
                        try? app.store.upsertTrade(t)
                    }
                    showPreview = false
                } else {
                    showPreview = false
                }
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showEditor) {
            TradeEditor(tx: editing) { saved in
                showEditor = false
            }
            .environmentObject(app)
        }
    }

    /// 导入券商交易文件：规则解析 → 预览；空则提示
    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            pendingURL = url
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            if url.pathExtension.lowercased() == "json" {
                previewTrades = parseJSONTrades(text)
            } else {
                previewTrades = TradeCSVParser.parse(text)
            }
            if previewTrades.isEmpty {
                return
            }
            showPreview = true
        case .failure:
            break
        }
    }

    /// JSON 交易解析（{symbol, direction, quantity, price, fee, date} 数组）
    private func parseJSONTrades(_ text: String) -> [ParsedTrade] {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var trades: [ParsedTrade] = []
        for item in arr {
            guard let symbol = (item["symbol"] as? String) ?? (item["ticker"] as? String),
                  let qty = (item["quantity"] as? Double) ?? RobustCSV.cleanNumber((item["quantity"] as? String) ?? ""),
                  let price = (item["price"] as? Double) ?? RobustCSV.cleanNumber((item["price"] as? String) ?? "") else { continue }
            let dir = (item["direction"] as? String) == "sell" ? "sell" : "buy"
            let date = (item["date"] as? String).flatMap { TradeCSVParser.parseDate($0) }
            trades.append(ParsedTrade(date: date, symbol: symbol,
                                      name: (item["name"] as? String) ?? symbol,
                                      direction: dir, quantity: qty, price: price,
                                      fee: (item["fee"] as? Double) ?? 0,
                                      market: Market(rawValue: (item["market"] as? String) ?? "") ?? RobustCSV.inferMarket(symbol),
                                      assetType: AssetType(rawValue: (item["assetType"] as? String) ?? "") ?? .stock))
        }
        return trades
    }
}

/// 交易行
struct TradeRow: View {
    let tx: Trade

    var body: some View {
        HStack(spacing: 12) {
            // 日期
            VStack(alignment: .leading) {
                Text(tx.date.formatted(.dateTime.month().day()))
                    .font(.body.weight(.medium))
                Text(tx.date.formatted(.dateTime.year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44)
            // 资产
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tx.name.isEmpty ? tx.code : tx.name)
                        .font(.body.weight(.medium))
                    if let opt = tx.option {
                        Text(opt.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundStyle(.purple)
                    }
                    Text(tx.assetType.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(tx.code) · \(tx.market.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // 方向
            Text(tx.direction == "buy" ? L10n.l("tx.buy") : L10n.l("tx.sell"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill((tx.direction == "buy" ? Color.red : Color.green).opacity(0.15)))
                .foregroundStyle(tx.direction == "buy" ? Color.red : Color.green)
            // 数量与价格
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tx.quantity, specifier: "%.2f") × \(tx.price, specifier: "%.4f")")
                    .font(.callout.monospacedDigit())
                Text(String(format: "%@ %@", tx.netAmount >= 0 ? "+" : "", String(format: "%.2f", tx.netAmount)))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tx.netAmount >= 0 ? Color.red : Color.green)
            }
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

/// 选中交易的详情条
struct TradeSummaryBar: View {
    let tx: Trade

    var body: some View {
        HStack(spacing: 16) {
            Text("\(tx.name)（\(tx.code)）")
                .font(.headline)
            if let opt = tx.option {
                Text(opt.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(tx.quantity, specifier: "%.2f") × \(tx.price, specifier: "%.4f")")
                    .font(.callout.monospacedDigit())
                if tx.fee > 0 {
                    Text("\(L10n.l("tx.fee")) \(tx.fee, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(String(format: "%+.2f", tx.netAmount))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(tx.netAmount >= 0 ? Color.red : Color.green)
        }
        .padding(12)
        .background(.bar)
    }
}

/// 交易导入预览确认（规则解析结果 + AI 兜底）
struct TradeImportPreviewSheet: View {
    @EnvironmentObject var app: AppState
    @State var trades: [ParsedTrade]
    let sourceURL: URL?
    let onConfirm: ([Trade]) -> Void

    @State private var isAIParsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.l("tx.title"))
                .font(.headline)
            Text("\(trades.count) \(L10n.l("tx.title"))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Table(Array(trades.prefix(15).enumerated()).map { TradeRowModel(index: $0.offset, trade: $0.element) }) {
                TableColumn(L10n.l("tx.date")) { m in
                    Text(m.trade.date?.formatted(.dateTime.month().day()) ?? "—")
                }
                TableColumn(L10n.l("tx.code")) { m in
                    Text(m.trade.symbol).font(.callout.monospaced())
                }
                TableColumn(L10n.l("tx.name")) { m in
                    Text(m.trade.name)
                }
                TableColumn(L10n.l("tx.direction")) { m in
                    Text(m.trade.direction == "buy" ? L10n.l("tx.buy") : L10n.l("tx.sell"))
                        .foregroundStyle(m.trade.direction == "buy" ? Color.red : Color.green)
                }
                TableColumn(L10n.l("tx.quantity")) { m in
                    Text(m.trade.quantity, format: .number.precision(.fractionLength(2)))
                }
                TableColumn(L10n.l("tx.price")) { m in
                    Text(m.trade.price, format: .number.precision(.fractionLength(4)))
                }
                TableColumn(L10n.l("tx.fee")) { m in
                    Text(m.trade.fee, format: .number.precision(.fractionLength(2)))
                }
            }
            .frame(height: 280)

            HStack {
                if isAIParsing {
                    ProgressView(L10n.l("holdings.aiParsing"))
                } else {
                    Button {
                        Task {
                            isAIParsing = true
                            let provider = app.aiSettings.provider
                            let model = app.aiSettings.model
                            let key = app.aiSettings.apiKey(for: provider)
                            if let url = sourceURL {
                                let ai = TradeAIParser()
                                let aiTrades = await ai.parse(url: url, provider: provider, model: model, apiKey: key)
                                if !aiTrades.isEmpty {
                                    trades = aiTrades
                                }
                            }
                            isAIParsing = false
                        }
                    } label: {
                        Label("AI 识别（兜底）", systemImage: "brain")
                    }
                }
                Spacer()
                Button(L10n.l("common.cancel")) { onConfirm([]) }
                Button(L10n.l("common.import")) {
                    onConfirm(trades.map { $0.toTrade() })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trades.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 820, height: 460)
    }

    struct TradeRowModel: Identifiable {
        let id = UUID()
        let index: Int
        let trade: ParsedTrade
    }
}

extension ParsedTrade {
    func toTrade() -> Trade {
        Trade(date: date ?? Date(),
              assetType: assetType,
              name: name, code: symbol,
              market: market,
              direction: direction,
              quantity: quantity, price: price, fee: fee)
    }
}

// MARK: - 交易 AI 解析兜底

struct TradeAIParser {
    func parse(url: URL, provider: ModelProvider, model: String, apiKey: String?) async -> [ParsedTrade] {
        guard url.startAccessingSecurityScopedResource() else { return [] }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        guard let key = apiKey else { return [] }

        let prompt = """
        识别以下券商交易记录文件，输出严格的 JSON 数组（不要任何其他文字）：
        [{"date": "yyyy-MM-dd", "symbol": "代码", "name": "名称", "direction": "buy|sell", "quantity": 数量, "price": 价格, "fee": 手续费, "market": "us|hk|cn|crypto|fund|jp|kr|tw"}]

        文件内容：
        \(String(text.prefix(8000)))

        规则：
        - 只识别证券买卖交易（Buy/Sell/买入/卖出），忽略分红、转账、存款等
        - 卖出方向填 sell，数量为正
        - 无法识别的行跳过
        """
        do {
            let reply = try await ModelGateway().ask(prompt, system: "你是一个精确的交易记录解析器。只输出 JSON。",
                                                     provider: provider, model: model, apiKey: key)
            return parseTradesJSON(reply)
        } catch {
            return []
        }
    }

    private func parseTradesJSON(_ text: String) -> [ParsedTrade] {
        var cleaned = text
        if let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var trades: [ParsedTrade] = []
        for item in arr {
            guard let symbol = item["symbol"] as? String,
                  let qty = (item["quantity"] as? Double) ?? Double("\(item["quantity"] ?? "")"),
                  let price = (item["price"] as? Double) ?? Double("\(item["price"] ?? "")"),
                  qty > 0, price > 0 else { continue }
            let dir = (item["direction"] as? String) == "sell" ? "sell" : "buy"
            let date = (item["date"] as? String).flatMap { TradeCSVParser.parseDate($0) }
            trades.append(ParsedTrade(date: date, symbol: symbol,
                                      name: (item["name"] as? String) ?? symbol,
                                      direction: dir, quantity: qty, price: price,
                                      fee: (item["fee"] as? Double) ?? 0,
                                      market: Market(rawValue: (item["market"] as? String) ?? "") ?? RobustCSV.inferMarket(symbol),
                                      assetType: .stock))
        }
        return trades
    }
}

/// 添加/编辑交易表单
struct TradeEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let tx: Trade?
    let onSave: (Trade) -> Void

    @State private var date: Date
    @State private var assetType: AssetType
    @State private var name: String
    @State private var code: String
    @State private var market: Market
    @State private var direction: String
    @State private var quantity: String
    @State private var price: String
    @State private var fee: String
    @State private var notes: String
    // 期权字段
    @State private var callPut: String
    @State private var strike: String
    @State private var expiry: Date
    @State private var hasOption: Bool

    init(tx: Trade?, onSave: @escaping (Trade) -> Void) {
        self.tx = tx
        self.onSave = onSave
        _date = State(initialValue: tx?.date ?? Date())
        _assetType = State(initialValue: tx?.assetType ?? .stock)
        _name = State(initialValue: tx?.name ?? "")
        _code = State(initialValue: tx?.code ?? "")
        _market = State(initialValue: tx?.market ?? .us)
        _direction = State(initialValue: tx?.direction ?? "buy")
        _quantity = State(initialValue: tx.map { String($0.quantity) } ?? "")
        _price = State(initialValue: tx.map { String($0.price) } ?? "")
        _fee = State(initialValue: tx.map { String($0.fee) } ?? "0")
        _notes = State(initialValue: tx?.notes ?? "")
        _callPut = State(initialValue: tx?.option?.callPut ?? "call")
        _strike = State(initialValue: tx?.option.map { String($0.strikePrice) } ?? "")
        _expiry = State(initialValue: tx?.option?.expiryDate ?? Date().addingTimeInterval(30 * 86400))
        _hasOption = State(initialValue: tx?.option != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tx == nil ? L10n.l("tx.add") : L10n.l("tx.edit"))
                .font(.title2.weight(.semibold))

            Form {
                Section {
                    DatePicker(L10n.l("tx.date"), selection: $date, displayedComponents: .date)
                    Picker(L10n.l("tx.assetType"), selection: $assetType) {
                        ForEach(AssetType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .onChange(of: assetType) { _, newType in
                        // 类型变化时同步默认市场
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
                    Picker(L10n.l("tx.direction"), selection: $direction) {
                        Text(L10n.l("tx.buy")).tag("buy")
                        Text(L10n.l("tx.sell")).tag("sell")
                    }
                    .pickerStyle(.segmented)
                    TextField(L10n.l("tx.quantity"), text: $quantity)
                    TextField(L10n.l("tx.price"), text: $price)
                    TextField(L10n.l("tx.fee"), text: $fee)
                    TextField(L10n.l("tx.notes"), text: $notes)
                }

                // 期权字段
                if assetType == .option {
                    Section(L10n.l("asset.option")) {
                        Toggle("期权", isOn: $hasOption)
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
                Button(tx == nil ? L10n.l("common.add") : L10n.l("common.save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || Double(quantity) == nil || Double(price) == nil)
            }
        }
        .padding(20)
        .frame(width: 420, height: 560)
    }

    private func save() {
        let option: OptionSpec? = assetType == .option && hasOption
            ? OptionSpec(callPut: callPut,
                         strikePrice: Double(strike) ?? 0,
                         expiryDate: expiry,
                         multiplier: 100)
            : nil
        let newTx = Trade(
            id: tx?.id ?? UUID().uuidString,
            date: date,
            assetType: assetType,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            market: market,
            direction: direction,
            quantity: Double(quantity) ?? 0,
            price: Double(price) ?? 0,
            fee: Double(fee) ?? 0,
            notes: notes,
            option: option
        )
        try? app.store.upsertTrade(newTx)
        onSave(newTx)
        dismiss()
    }
}
