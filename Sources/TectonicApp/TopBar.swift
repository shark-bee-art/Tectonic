import SwiftUI
import TectonicIcons
import CoreKit

// MARK: - 顶部栏（四 tab 居中 + 搜索栏 + 刷新）

struct TopBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // 左侧：红绿灯安全区（hiddenTitleBar 下保留）
                Spacer().frame(width: 70)
                Spacer()
                // 中央：四 tab
                tabArea
                Spacer()
                // 右侧：搜索栏 + 刷新
                actionArea
                    .frame(width: 380)
            }
            .frame(height: 52)
        }
        .background(DS.bgApp)
    }

    // MARK: 四 tab（自选 / 行情 / 快讯 / 日历）

    private var tabArea: some View {
        HStack(spacing: 4) {
            tabButton(icon: .star, title: L10n.l("sidebar.watchlist"),
                      selected: app.selectedTab == .watchlist) {
                select(.watchlist)
            }
            tabButton(icon: .chartLine, title: L10n.l("sidebar.markets"),
                      selected: app.selectedTab == .markets) {
                select(.markets)
            }
            // 快讯（含来源菜单）
            Menu {
                Button {
                    select(.flash)
                } label: {
                    Label(L10n.l("sidebar.flash"), systemImage: "square.grid.2x2")
                }
                if !flashFeeds.isEmpty {
                    Divider()
                    ForEach(flashFeeds) { feed in
                        Button {
                            select(.newsFeed(sourceID: feed.id))
                        } label: {
                            Label(feed.name, systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    TectonicIconView(icon: .bolt, size: 15,
                                     color: app.selectedTab.isNewsTab ? DS.textPrimary : DS.textSecondary)
                    Text(app.selectedTab.isNewsTab ? currentNewsTitle : L10n.l("sidebar.flash"))
                        .font(.system(size: 15, weight: app.selectedTab.isNewsTab ? .semibold : .regular))
                        .foregroundStyle(app.selectedTab.isNewsTab ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1)
                    TectonicIconView(icon: .chevronDown, size: 11, color: DS.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusCard)
                        .fill(app.selectedTab.isNewsTab ? DS.bgSelected : .clear)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            tabButton(icon: .calendar, title: L10n.l("sidebar.calendar"),
                      selected: app.selectedTab == .calendar) {
                select(.calendar)
            }
        }
    }

    private var currentNewsTitle: String {
        switch app.selectedTab {
        case .newsFeed(let id):
            app.store.newsFeeds.first { $0.id == id }?.name ?? L10n.l("sidebar.flash")
        default: L10n.l("sidebar.flash")
        }
    }

    private var flashFeeds: [NewsFeed] {
        app.store.newsFeeds.filter { $0.enabled && $0.category == .flash }
    }

    private func tabButton(icon: TectonicIcon, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                TectonicIconView(icon: icon, size: 15, color: selected ? DS.textPrimary : DS.textSecondary)
                Text(title)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusCard)
                    .fill(selected ? DS.bgSelected : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func select(_ item: AppState.SidebarItem) {
        app.selectedTab = item
        app.selectedSymbol = nil
        app.selectedNews = nil
    }

    // MARK: 搜索栏 + 刷新

    private var actionArea: some View {
        HStack(spacing: 6) {
            // 搜索标的 → 添加到自选
            SymbolSearchField()
                .frame(width: 280)
            // 刷新
            if app.isRefreshing {
                TectonicIconView(icon: .refresh, size: 16, color: DS.textSecondary)
                    .rotationEffect(.degrees(app.isRefreshing ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: app.isRefreshing)
                    .padding(6)
            } else {
                DSIconButton(icon: .refresh, help: "刷新行情 (⌘R)") {
                    Task { await app.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - 搜索栏（输入即搜，结果可直接添加到自选）

struct SymbolSearchField: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var results: [Symbol] = []
    @State private var isSearching = false
    @State private var addedIDs: Set<String> = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 输入框
            HStack(spacing: 6) {
                TectonicIconView(icon: .search, size: 14,
                                 color: focused ? DS.textPrimary : DS.textTertiary)
                TextField(L10n.l("add.searchHint"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit { search() }
                    .onChange(of: query) { _, newValue in
                        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 1 {
                            search()
                        } else {
                            results = []
                        }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        TectonicIconView(icon: .x, size: 12, color: DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清除")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusCard)
                    .fill(focused ? DS.bgPanel : DS.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusCard)
                            .stroke(focused ? DS.textPrimary : DS.border, lineWidth: 1)
                    )
            )

            // 搜索结果下拉（最多 6 条，避免过高）
            if focused && !results.isEmpty {
                VStack(spacing: 1) {
                    ForEach(results.prefix(6)) { symbol in
                        searchResultRow(symbol)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusCard)
                        .fill(DS.bgPanel)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusCard)
                                .stroke(DS.border, lineWidth: 1)
                        )
                )
                .transition(.opacity)
            }
        }
    }

    private func searchResultRow(_ symbol: Symbol) -> some View {
        let inWatchlist = app.store.isInWatchlist(symbol)
        let justAdded = addedIDs.contains(symbol.id)
        return Button {
            add(symbol)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(symbol.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text("\(symbol.market.displayName) \(symbol.code)")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if inWatchlist || justAdded {
                    HStack(spacing: 3) {
                        TectonicIconView(icon: .circleCheck, size: 12, color: DS.down)
                        Text(L10n.l("add.added"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.down)
                    }
                } else {
                    Text(L10n.l("add.add"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        Task {
            defer { isSearching = false }
            results = await app.store.search(query: q, market: nil)
            if results.isEmpty, let symbol = exactSymbol(q) {
                results = [symbol]
            }
        }
    }

    private func exactSymbol(_ q: String) -> Symbol? {
        let up = q.uppercased()
        if up.allSatisfy(\.isNumber), up.count == 6 {
            return Symbol(market: .cn, code: up, name: up)
        }
        if up.hasSuffix(".HK") || (up.allSatisfy(\.isNumber) && up.count == 5) {
            let code = up.replacingOccurrences(of: ".HK", with: "")
            return Symbol(market: .hk, code: code, name: code)
        }
        if up.hasSuffix("USDT") || up.hasSuffix("USDC") {
            return Symbol(market: .crypto, code: up, name: up)
        }
        if up.allSatisfy(\.isNumber), up.count == 6, up.hasPrefix("0") || up.hasPrefix("1") {
            return Symbol(market: .fund, code: up, name: up)
        }
        return nil
    }

    private func add(_ symbol: Symbol) {
        do {
            let added = try app.store.addToWatchlist(symbol)
            if added {
                addedIDs.insert(symbol.id)
                // 添加成功：清空输入与结果，收起下拉，恢复原样
                query = ""
                results = []
                focused = false
                // 反馈 2 秒后移除标记
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    addedIDs.remove(symbol.id)
                }
            }
        } catch {
            print("添加自选失败: \(error)")
        }
    }
}

extension AppState {
    /// 顶部搜索框文案
    static let searchPlaceholder = "搜索"
}
