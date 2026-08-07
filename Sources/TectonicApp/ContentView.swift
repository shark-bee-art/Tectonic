import SwiftUI
import CoreKit

/// 主界面：单栏 + 导航栈（Robinhood 结构，无三栏）
/// 顶部 tab 栏（自选/行情/快讯/研报/财报/日历）→ 全宽列表 → 点击 push 全宽详情页（带返回）
struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            DSDivider()
            // 主区域：详情优先（导航栈 push），否则当前 tab 列表
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.bgApp)
        .onAppear { app.onAppear() }
    }

    // MARK: 主区域（导航栈：详情 > 列表）

    @ViewBuilder
    private var mainArea: some View {
        if let symbol = app.selectedSymbol, isSymbolTab {
            DetailNavContainer(title: symbol.name) {
                QuoteDetailView(symbol: symbol)
                    .id(symbol.id)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let item = app.selectedNews, isNewsTab {
            DetailNavContainer(title: item.title) {
                NewsDetailView(item: item)
                    .id(item.id)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            tabContent
                .transition(.opacity)
        }
    }

    private var isSymbolTab: Bool {
        switch app.selectedTab {
        case .watchlist, .markets: true
        default: false
        }
    }

    private var isNewsTab: Bool {
        switch app.selectedTab {
        case .newsFlash, .newsResearch, .newsEarnings, .newsCalendar, .newsFeed: true
        default: false
        }
    }

    // MARK: 当前 tab 内容（全宽列表）

    @ViewBuilder
    private var tabContent: some View {
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
}

// MARK: - 顶部 tab 栏（Robinhood 底部 tab 的桌面化：顶部分段 tab）

struct TopTabBar: View {
    @EnvironmentObject var app: AppState
    /// 展开中的资讯分类（nil = 收起来源子菜单）
    @State private var expandedCategory: NewsFeedCategory?

    var body: some View {
        HStack(spacing: 4) {
            // 主 tab
            tabButton(icon: .star, title: L10n.l("sidebar.watchlist"),
                      selected: app.selectedTab == .watchlist) {
                select(.watchlist)
            }
            tabButton(icon: .chartLine, title: L10n.l("sidebar.markets"),
                      selected: app.selectedTab == .markets) {
                select(.markets)
            }

            // 资讯分类 tab（带来源子菜单）
            ForEach(NewsFeedCategory.allCases) { category in
                let expanded = expandedCategory == category
                Menu {
                    // 全部
                    Button {
                        select(allItem(for: category))
                    } label: {
                        Label(L10n.l("sidebar.all") + category.displayName,
                              systemImage: "square.grid.2x2")
                    }
                    if !feeds(for: category).isEmpty {
                        Divider()
                        ForEach(feeds(for: category)) { feed in
                            Button {
                                select(.newsFeed(sourceID: feed.id))
                            } label: {
                                Label(feed.name, systemImage: "dot.radiowaves.left.and.right")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        TectonicIconView(icon: categoryIcon(category), size: 14,
                                         color: isCategoryActive(category) ? DS.textPrimary : DS.textSecondary)
                        Text(category.displayName)
                            .font(.system(size: 13, weight: isCategoryActive(category) ? .semibold : .regular))
                            .foregroundStyle(isCategoryActive(category) ? DS.textPrimary : DS.textSecondary)
                        TectonicIconView(icon: .chevronDown, size: 10, color: DS.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusCard)
                            .fill(isCategoryActive(category) ? DS.bgSelected : .clear)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Spacer()
        }
        .padding(.horizontal, DS.space4)
        .padding(.vertical, 6)
        .background(DS.bgApp)
    }

    private func tabButton(icon: TectonicIcon, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                TectonicIconView(icon: icon, size: 14, color: selected ? DS.textPrimary : DS.textSecondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
            }
            .padding(.horizontal, 12)
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
        case .flash: app.selectedTab == .newsFlash || matchesFeed(.flash)
        case .research: app.selectedTab == .newsResearch || matchesFeed(.research)
        case .earnings: app.selectedTab == .newsEarnings || matchesFeed(.earnings)
        case .calendar: app.selectedTab == .newsCalendar || matchesFeed(.calendar)
        }
    }

    private func matchesFeed(_ c: NewsFeedCategory) -> Bool {
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
}

// MARK: - 详情页导航容器（返回按钮 + 标题，Robinhood push 风格）

struct DetailNavContainer<Content: View>: View {
    @EnvironmentObject var app: AppState
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // 返回栏
            HStack(spacing: 8) {
                Button {
                    app.selectedSymbol = nil
                    app.selectedNews = nil
                } label: {
                    HStack(spacing: 4) {
                        TectonicIconView(icon: .chevronLeft, size: 14, color: DS.textPrimary)
                        Text(L10n.l("nav.back"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .fill(DS.bgSurface)
                    )
                }
                .buttonStyle(.plain)
                .help(L10n.l("nav.back"))

                Text(title)
                    .font(.system(size: DS.screenTitleSize, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, DS.space4)
            .padding(.vertical, DS.space2)
            .background(DS.bgApp)

            DSDivider()

            content
        }
        .background(DS.bgApp)
    }
}
