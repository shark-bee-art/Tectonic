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
            case .holdings:
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
            Section("导航") {
                Label("自选", systemImage: "star.fill")
                    .tag(AppState.SidebarItem.watchlist)
                Label("行情", systemImage: "chart.line.uptrend.xyaxis")
                    .tag(AppState.SidebarItem.markets)
            }
            Section("资讯") {
                Label("快讯", systemImage: "bolt.fill")
                    .tag(AppState.SidebarItem.newsFlash)
                Label("研报", systemImage: "doc.text.magnifyingglass")
                    .tag(AppState.SidebarItem.newsResearch)
                Label("财报", systemImage: "chart.bar.doc.horizontal")
                    .tag(AppState.SidebarItem.newsEarnings)
                Label("日历", systemImage: "calendar")
                    .tag(AppState.SidebarItem.newsCalendar)
            }
            Section("资产") {
                Label("持仓", systemImage: "briefcase")
                    .tag(AppState.SidebarItem.holdings)
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
