import SwiftUI
import CoreKit

/// 主界面：自绘三栏（TradingView 淡雅）
/// 顶部栏（品牌区/搜索/操作） + 侧边栏 + 内容列 + 详情列
/// 弃用 NavigationSplitView 系统渲染：自绘分割线、自绘选中态、可拖拽分栏
struct ContentView: View {
    @EnvironmentObject var app: AppState
    /// 侧边栏宽度（拖拽实时更新 + UserDefaults 持久化）
    @State private var sidebarWidth: CGFloat = 220
    @State private var draggingSidebar = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(sidebarWidth: sidebarWidth)
            DSDivider()
            HStack(spacing: 0) {
                // 侧边栏
                SidebarView(width: sidebarWidth,
                            onWidthChange: { newWidth in
                                sidebarWidth = newWidth
                                UserDefaults.standard.set(newWidth, forKey: "sidebar_width")
                            },
                            onDrag: { draggingSidebar = $0 })
                    .frame(width: sidebarWidth)

                DSDivider()

                // 内容列
                contentColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                DSDivider()

                // 详情列
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DS.bgApp)
        .onAppear {
            app.onAppear()
            sidebarWidth = CGFloat(UserDefaults.standard.double(forKey: "sidebar_width").isZero
                                    ? 220 : UserDefaults.standard.double(forKey: "sidebar_width"))
        }
    }

    // MARK: 内容列

    private var contentColumn: some View {
        Group {
            switch app.selectedTab {
            case .watchlist:
                WatchlistView()
            case .markets:
                MarketsView()
            case .newsFlash:
                NewsListView(category: .flash)
            case .newsResearch:
                NewsListView(category: .research)
            case .newsEarnings:
                NewsListView(category: .earnings)
            case .newsCalendar:
                CalendarView()
            case .newsFeed(let id):
                NewsListView(category: app.store.newsFeeds.first { $0.id == id }?.category ?? .flash, sourceID: id)
            }
        }
        .background(DS.bgPanel)
        .transition(.opacity.combined(with: .identity))
        .animation(.easeOut(duration: 0.15), value: app.selectedTab)
    }

    // MARK: 详情列

    private var detailColumn: some View {
        Group {
            switch app.selectedTab {
            case .watchlist, .markets:
                if let symbol = app.selectedSymbol {
                    QuoteDetailView(symbol: symbol)
                        .id(symbol.id)
                } else {
                    DSPlaceholder(icon: .chartLine,
                                  title: L10n.l("placeholder.select"),
                                  subtitle: L10n.l("placeholder.selectHint"))
                }
            case .newsFlash, .newsResearch, .newsEarnings, .newsCalendar, .newsFeed:
                if let item = app.selectedNews {
                    NewsDetailView(item: item)
                        .id(item.id)
                } else {
                    DSPlaceholder(icon: .news,
                                  title: L10n.l("placeholder.news"),
                                  subtitle: L10n.l("placeholder.newsHint"))
                }
            }
        }
        .background(DS.bgApp)
    }
}

// MARK: - 自绘侧边栏（弃 List(.sidebar) 系统渲染）

struct SidebarView: View {
    @EnvironmentObject var app: AppState
    let width: CGFloat
    var onWidthChange: (CGFloat) -> Void = { _ in }
    var onDrag: (Bool) -> Void = { _ in }

    /// 展开中的资讯分类（nil = 全收）
    @State private var expandedCategory: NewsFeedCategory?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    // 导航区
                    SidebarItemRow(icon: .star, title: L10n.l("sidebar.watchlist"),
                                   isSelected: app.selectedTab == .watchlist, isExpanded: nil) {
                        select(.watchlist)
                    }
                    SidebarItemRow(icon: .chartLine, title: L10n.l("sidebar.markets"),
                                   isSelected: app.selectedTab == .markets, isExpanded: nil) {
                        select(.markets)
                    }

                    // 资讯区（四分类，可展开）
                    ForEach(NewsFeedCategory.allCases) { category in
                        let expanded = expandedCategory == category
                        SidebarItemRow(icon: categoryIcon(category),
                                       title: category.displayName,
                                       isSelected: isCategoryActive(category),
                                       isExpanded: expanded) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                expandedCategory = expanded ? nil : category
                                // 展开时默认进入「全部」
                                if expandedCategory == category {
                                    select(allItem(for: category))
                                }
                            }
                        }
                        if expanded {
                            VStack(spacing: 1) {
                                // 全部
                                sourceRow(title: L10n.l("sidebar.all") + category.displayName,
                                          icon: .layoutGrid,
                                          selected: app.selectedTab == allItem(for: category)) {
                                    select(allItem(for: category))
                                }
                                ForEach(feeds(for: category)) { feed in
                                    sourceRow(title: feed.name,
                                              icon: .point,
                                              selected: app.selectedTab == .newsFeed(sourceID: feed.id)) {
                                        select(.newsFeed(sourceID: feed.id))
                                    }
                                }
                            }
                            .padding(.leading, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(6)
            }
            .scrollContentBackground(.hidden)
            .background(DS.bgPanel)

            // 底部：拖拽手柄区域
            Rectangle()
                .fill(Color.clear)
                .frame(height: 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            onDrag(true)
                            let newWidth = min(max(width + value.translation.width, 170), 320)
                            onWidthChange(newWidth)
                        }
                        .onEnded { _ in onDrag(false) }
                )
                .help("拖拽调整侧边栏宽度")
        }
    }

    private func select(_ item: AppState.SidebarItem) {
        app.selectedTab = item
        // 切换分类时清空详情选择
        app.selectedSymbol = nil
        app.selectedNews = nil
    }

    private func feeds(for category: NewsFeedCategory) -> [NewsFeed] {
        app.store.newsFeeds.filter { $0.category == category && $0.enabled }
    }

    private func allItem(for category: NewsFeedCategory) -> AppState.SidebarItem {
        switch category {
        case .flash: .newsFlash
        case .research: .newsResearch
        case .earnings: .newsEarnings
        case .calendar: .newsCalendar
        }
    }

    private func isCategoryActive(_ category: NewsFeedCategory) -> Bool {
        switch category {
        case .flash: app.selectedTab == .newsFlash || matchesFeed(category, .flash)
        case .research: app.selectedTab == .newsResearch || matchesFeed(category, .research)
        case .earnings: app.selectedTab == .newsEarnings || matchesFeed(category, .earnings)
        case .calendar: app.selectedTab == .newsCalendar || matchesFeed(category, .calendar)
        }
    }

    private func matchesFeed(_ category: NewsFeedCategory, _ c: NewsFeedCategory) -> Bool {
        guard case .newsFeed(let id) = app.selectedTab else { return false }
        return app.store.newsFeeds.first { $0.id == id }?.category == c
    }

    private func categoryIcon(_ category: NewsFeedCategory) -> TectonicIcon {
        switch category {
        case .flash: .bolt
        case .research: .fileText
        case .earnings: .chartBar
        case .calendar: .calendar
        }
    }

    private func sourceRow(title: String, icon: TectonicIcon, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                TectonicIconView(icon: icon, size: 14, color: selected ? DS.accent : DS.textTertiary)
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.accent : DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
