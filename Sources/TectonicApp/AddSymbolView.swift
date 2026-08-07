import SwiftUI
import CoreKit

/// 添加标的：搜索 → 结果列表 → 添加自选
struct AddSymbolButton: View {
    @EnvironmentObject var app: AppState
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("添加标的", systemImage: "plus")
        }
        .help("添加标的 (⌘N)")
        .keyboardShortcut("n", modifiers: .command)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AddSymbolPopover()
                .environmentObject(app)
                .frame(width: 420)
        }
    }
}

struct AddSymbolPopover: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Symbol] = []
    @State private var isSearching = false
    @State private var selectedMarket: Market? = nil
    @State private var groupName = "默认分组"
    @State private var addedMessage: String?
    @State private var lastAdded: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加标的")
                .font(.headline)

            if let msg = addedMessage {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                Picker("市场", selection: $selectedMarket) {
                    Text("全部").tag(Market?.none)
                    ForEach(Market.allCases) { m in
                        Text(m.displayName).tag(Market?.some(m))
                    }
                }
                .frame(width: 110)
                TextField("代码或名称，如 AAPL / 600519 / BTCUSDT", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("搜索") { search() }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if results.isEmpty && !query.isEmpty {
                Text("无匹配结果（可尝试输入代码精确搜索）")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if !results.isEmpty {
                List(results, id: \.id) { symbol in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(symbol.name)
                            Text("\(symbol.market.displayName) \(symbol.code)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if app.store.isInWatchlist(symbol) {
                            Label("已添加", systemImage: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.green)
                        } else if lastAdded == symbol.id {
                            Label("已添加", systemImage: "checkmark.circle.fill")
                                .font(.callout)
                                .foregroundStyle(.green)
                        } else {
                            Button("添加") {
                                add(symbol)
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 260)
            } else {
                Text("输入代码或名称开始搜索\n支持：AAPL、600519、00700.HK、BTCUSDT、110022、7203.T 等")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            HStack {
                TextField("分组（默认：默认分组）", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Spacer()
                Button("完成") { dismiss() }
            }
        }
        .padding(16)
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        results = []
        lastAdded = nil
        addedMessage = nil
        Task {
            defer { isSearching = false }
            results = await app.store.search(query: q, market: selectedMarket)
            // 兜底：直接按代码构造（精确匹配）
            if results.isEmpty, let symbol = exactSymbol(q) {
                results = [symbol]
            }
        }
    }

    private func exactSymbol(_ q: String) -> Symbol? {
        let up = q.uppercased()
        // A股 6 位数字
        if up.allSatisfy(\.isNumber), up.count == 6 {
            return Symbol(market: .cn, code: up, name: up)
        }
        // 港股 5 位数字或 .HK 后缀
        if up.hasSuffix(".HK") || (up.allSatisfy(\.isNumber) && up.count == 5) {
            let code = up.replacingOccurrences(of: ".HK", with: "")
            return Symbol(market: .hk, code: code, name: code)
        }
        // 加密 USDT 交易对
        if up.hasSuffix("USDT") || up.hasSuffix("USDC") {
            return Symbol(market: .crypto, code: up, name: up)
        }
        // 基金 6 位数字（00/01 开头）
        if up.allSatisfy(\.isNumber), up.count == 6, up.hasPrefix("0") || up.hasPrefix("1") {
            return Symbol(market: .fund, code: up, name: up)
        }
        return nil
    }

    private func add(_ symbol: Symbol) {
        let group = groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "默认分组" : groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let added = try app.store.addToWatchlist(symbol, group: group)
            if added {
                lastAdded = symbol.id
                withAnimation {
                    addedMessage = "已添加 \(symbol.name)（\(symbol.code)）到「\(group)」"
                }
            } else {
                withAnimation {
                    addedMessage = "\(symbol.name) 已在自选中"
                }
            }
            // 消息 2.5 秒后消失
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { addedMessage = nil }
            }
        } catch {
            addedMessage = "添加失败：\(error.localizedDescription)"
        }
    }
}
