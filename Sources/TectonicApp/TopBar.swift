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
                    .frame(width: 410)
            }
            .frame(height: 52)
        }
        .background(DS.bgApp)
    }

    // MARK: 四 tab（自选 / 行情 / 快讯 / 日历）

    private var tabArea: some View {
        HStack(spacing: 16) {
            tabButton(icon: .star, title: L10n.l("sidebar.watchlist"),
                      selected: app.selectedTab == .watchlist) {
                select(.watchlist)
            }
            tabButton(icon: .chartLine, title: L10n.l("sidebar.markets"),
                      selected: app.selectedTab == .markets) {
                select(.markets)
            }
            // 快讯（bolt 图标 + 来源菜单）
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
                HStack(spacing: 6) {
                    TectonicIconView(icon: .bolt, size: 17,
                                     color: app.selectedTab.isNewsTab ? DS.textPrimary : DS.textSecondary)
                    Text(app.selectedTab.isNewsTab ? currentNewsTitle : L10n.l("sidebar.flash"))
                        .font(.system(size: 17, weight: app.selectedTab.isNewsTab ? .semibold : .regular))
                        .foregroundStyle(app.selectedTab.isNewsTab ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1)
                    TectonicIconView(icon: .chevronDown, size: 11, color: DS.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
                TectonicIconView(icon: icon, size: 17, color: selected ? DS.textPrimary : DS.textSecondary)
                Text(title)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
                .frame(width: 300)
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
    @State private var addedIDs: Set<String> = []
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TectonicIconView(icon: .search, size: 14,
                             color: focused ? DS.textPrimary : DS.textTertiary)
            TextField(L10n.l("add.searchHint"), text: $app.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { search() }
                .onChange(of: focused) { _, newValue in
                    app.isSearchFocused = newValue
                    if !newValue {
                        app.searchResults = []
                    }
                }
                .onChange(of: app.searchQuery) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 1 {
                        search()
                    } else {
                        app.searchResults = []
                    }
                }
            if !app.searchQuery.isEmpty {
                Button {
                    app.searchQuery = ""
                    app.searchResults = []
                } label: {
                    TectonicIconView(icon: .x, size: 12, color: DS.textTertiary)
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 300, height: 36)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusCard)
                .fill(focused ? DS.bgPanel : DS.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusCard)
                        .stroke(focused ? DS.textPrimary : DS.border, lineWidth: 1)
                )
        )
    }

    private func search() {
        let q = app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        Task {
            let found = await app.store.search(query: q, market: nil)
            app.searchResults = found.isEmpty ? (exactSymbol(q).map { [$0] } ?? []) : found
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
}

// MARK: - 全局搜索下拉（浮在 ContentView 最上层，不被任何内容遮挡）

struct SearchResultsOverlay: View {
    @EnvironmentObject var app: AppState
    @State private var addedIDs: Set<String> = []

    var body: some View {
        // 对齐右上（搜索框位置：右侧 410 区域内的左上 ≈ 窗口宽 - 430）
        VStack(spacing: 0) {
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if app.isSearchFocused && !app.searchResults.isEmpty {
                VStack(spacing: 1) {
                    ForEach(app.searchResults.prefix(6)) { symbol in
                        searchResultRow(symbol)
                    }
                }
                .padding(4)
                .frame(width: 300)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusCard)
                        .fill(DS.bgPanel)
                        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusCard)
                                .stroke(DS.border, lineWidth: 1)
                        )
                )
                .padding(.trailing, 44)   // 对齐搜索框右缘（窗口右缘 → 10 padding + 刷新按钮 ~28 + 间距 6）
                .padding(.top, 50)        // 顶部栏 52 高 + 间距
                .transition(.opacity)
                .zIndex(100)
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

    private func add(_ symbol: Symbol) {
        do {
            let added = try app.store.addToWatchlist(symbol)
            if added {
                addedIDs.insert(symbol.id)
                // 添加成功：清空输入与结果，收起下拉，恢复原样
                app.searchQuery = ""
                app.searchResults = []
                app.isSearchFocused = false
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
