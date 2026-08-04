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
                NewsListView(category: .calendar)
            case .holdings:
                HoldingsView()
            case .transactions:
                TransactionsView()
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
            case .newsFlash, .newsResearch, .newsEarnings, .newsCalendar:
                if let item = app.selectedNews {
                    NewsDetailView(item: item)
                        .id(item.id)
                } else {
                    PlaceholderView()
                }
            case .holdings, .transactions:
                PlaceholderView()
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
                AddSymbolButton()
            }
        }
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
                Label(L10n.l("sidebar.flash"), systemImage: "bolt.fill")
                    .tag(AppState.SidebarItem.newsFlash)
                Label(L10n.l("sidebar.research"), systemImage: "doc.text.magnifyingglass")
                    .tag(AppState.SidebarItem.newsResearch)
                Label(L10n.l("sidebar.earnings"), systemImage: "chart.bar.doc.horizontal")
                    .tag(AppState.SidebarItem.newsEarnings)
                Label(L10n.l("sidebar.calendar"), systemImage: "calendar")
                    .tag(AppState.SidebarItem.newsCalendar)
            }
            Section(L10n.l("sidebar.assets")) {
                Label(L10n.l("sidebar.holdings"), systemImage: "briefcase")
                    .tag(AppState.SidebarItem.holdings)
                Label(L10n.l("sidebar.transactions"), systemImage: "list.bullet.rectangle")
                    .tag(AppState.SidebarItem.transactions)
            }
        }
        .listStyle(.sidebar)
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
