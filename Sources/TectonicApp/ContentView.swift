import SwiftUI
import CoreKit

/// 主界面：NavigationSplitView（Tide 形态）
/// 侧边栏：自选/行情/资讯/持仓 + 市场分组
/// 内容区：行情列表 / 详情 / AI 对话
struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } content: {
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
                // 独立查看某个订阅源（category 取该源所属分类）
                NewsListView(category: app.store.newsFeeds.first { $0.id == id }?.category ?? .flash, sourceID: id)
            }
        } detail: {
            switch app.selectedTab {
            case .watchlist, .markets:
                if let symbol = app.selectedSymbol {
                    QuoteDetailView(symbol: symbol)
                        .id(symbol.id)
                } else {
                    PlaceholderView()
                }
            case .newsFlash, .newsResearch, .newsEarnings, .newsCalendar, .newsFeed:
                if let item = app.selectedNews {
                    NewsDetailView(item: item)
                        .id(item.id)
                } else {
                    PlaceholderView()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if app.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 24)
                } else {
                    Button {
                        Task { await app.refreshAll() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .help("刷新行情 (⌘R)")
                }
                // 添加标的按钮（全局：自选/行情页使用）
                AddSymbolButton()
            }
        }
        // 标题栏/工具栏区域跟随主题
        .toolbarBackground(Color(hex: app.theme.background) ?? Color.clear, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .background(Color(hex: app.theme.background) ?? Color.clear)
        .onAppear {
            app.onAppear()
        }
    }
}

// MARK: - 侧边栏

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List(selection: $app.selectedTab) {
            Section(L10n.l("sidebar.navigation")) {
                Label(L10n.l("sidebar.watchlist"), systemImage: "star.fill")
                    .tag(AppState.SidebarItem.watchlist)
                Label(L10n.l("sidebar.markets"), systemImage: "chart.line.uptrend.xyaxis")
                    .tag(AppState.SidebarItem.markets)
            }
            Section(L10n.l("sidebar.news")) {
                DisclosureGroup {
                    // 全部快讯（查看该分类全部源）
                    Label(L10n.l("sidebar.all") + L10n.l("sidebar.flash"), systemImage: "square.grid.2x2")
                        .tag(AppState.SidebarItem.newsFlash)
                    ForEach(feeds(for: .flash)) { feed in
                        sourceRow(feed)
                    }
                } label: {
                    Label(L10n.l("sidebar.flash"), systemImage: "bolt.fill")
                }

                DisclosureGroup {
                    Label(L10n.l("sidebar.all") + L10n.l("sidebar.research"), systemImage: "square.grid.2x2")
                        .tag(AppState.SidebarItem.newsResearch)
                    ForEach(feeds(for: .research)) { feed in
                        sourceRow(feed)
                    }
                } label: {
                    Label(L10n.l("sidebar.research"), systemImage: "doc.text.magnifyingglass")
                }

                DisclosureGroup {
                    Label(L10n.l("sidebar.all") + L10n.l("sidebar.earnings"), systemImage: "square.grid.2x2")
                        .tag(AppState.SidebarItem.newsEarnings)
                    ForEach(feeds(for: .earnings)) { feed in
                        sourceRow(feed)
                    }
                } label: {
                    Label(L10n.l("sidebar.earnings"), systemImage: "chart.bar.doc.horizontal")
                }

                DisclosureGroup {
                    Label(L10n.l("sidebar.all") + L10n.l("sidebar.calendar"), systemImage: "square.grid.2x2")
                        .tag(AppState.SidebarItem.newsCalendar)
                    ForEach(feeds(for: .calendar)) { feed in
                        sourceRow(feed)
                    }
                } label: {
                    Label(L10n.l("sidebar.calendar"), systemImage: "calendar")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(hex: app.theme.sidebar) ?? Color.clear)
    }

    /// 某分类下启用的订阅源
    private func feeds(for category: NewsFeedCategory) -> [NewsFeed] {
        app.store.newsFeeds.filter { $0.category == category && $0.enabled }
    }

    /// 订阅源行（点击 = 独立查看该源）
    private func sourceRow(_ feed: NewsFeed) -> some View {
        Label(feed.name, systemImage: "dot.radiowaves.left.and.right")
            .lineLimit(1)
            .tag(AppState.SidebarItem.newsFeed(sourceID: feed.id))
    }
}

// MARK: - 占位

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("选择左侧的标的查看详情")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
