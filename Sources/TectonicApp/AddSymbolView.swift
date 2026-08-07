import SwiftUI
import CoreKit

/// 添加标的：搜索 → 结果列表 → 添加自选（TradingView 淡雅组件）
struct AddSymbolButton: View {
    @EnvironmentObject var app: AppState
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            TectonicIconView(icon: .plus, size: 16, color: DS.textSecondary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(DS.bgHover)
                )
        }
        .buttonStyle(.plain)
        .help("添加标的 (⌘N)")
        .keyboardShortcut("n", modifiers: .command)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AddSymbolPopover()
                .environmentObject(app)
                .frame(width: 440)
        }
        // 命令面板「添加标的」触发
        .onChange(of: app.openAddSymbol) { _, v in
            if v {
                isPresented = true
                app.openAddSymbol = false
            }
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
            HStack(spacing: 8) {
                TectonicIconView(icon: .plus, size: 16, color: DS.accent)
                Text(L10n.l("add.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
            }

            if let msg = addedMessage {
                HStack(spacing: 6) {
                    TectonicIconView(icon: .circleCheck, size: 14, color: DS.down)
                    Text(msg)
                        .font(.system(size: DS.captionSize))
                        .foregroundStyle(DS.down)
                }
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                Picker("市场", selection: $selectedMarket) {
                    Text("全部").tag(Market?.none)
                    ForEach(Market.allCases) { m in
                        Text(m.displayName).tag(Market?.some(m))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
                DSInputField(text: $query, placeholder: L10n.l("add.searchHint"))
                    .onSubmit { search() }
                DSButton(L10n.l("add.search"), icon: .search, prominent: true) { search() }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if results.isEmpty && !query.isEmpty {
                Text(L10n.l("add.noResult"))
                    .font(.system(size: DS.captionSize))
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(results, id: \.id) { symbol in
                            symbolRow(symbol)
                        }
                    }
                }
                .frame(minHeight: 90, maxHeight: 260)
            } else {
                Text(L10n.l("add.hint"))
                    .font(.system(size: DS.captionSize))
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            HStack {
                DSInputField(text: $groupName, placeholder: L10n.l("add.groupHint"))
                    .frame(width: 200)
                Spacer()
                DSButton(L10n.l("add.done"), icon: .check, prominent: true) { dismiss() }
            }
        }
        .padding(16)
    }

    private func symbolRow(_ symbol: Symbol) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol.name)
                    .font(.system(size: DS.listTitleSize, weight: .medium))
                    .foregroundStyle(DS.textPrimary)
                Text("\(symbol.market.displayName) \(symbol.code)")
                    .font(.system(size: DS.metaSize))
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer()
            if app.store.isInWatchlist(symbol) || lastAdded == symbol.id {
                HStack(spacing: 4) {
                    TectonicIconView(icon: .circleCheck, size: 14, color: DS.down)
                    Text(L10n.l("add.added"))
                        .font(.system(size: DS.captionSize, weight: .medium))
                        .foregroundStyle(DS.down)
                }
            } else {
                DSButton(L10n.l("add.add"), icon: .plus, prominent: true) {
                    add(symbol)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
