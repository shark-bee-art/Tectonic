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
            case .news:
                NewsView()
            case .holdings:
                HoldingsView()
            }
        } detail: {
            if let symbol = app.selectedSymbol {
                QuoteDetailView(symbol: symbol)
            } else {
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
                Label("资讯", systemImage: "newspaper")
                    .tag(AppState.SidebarItem.news)
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
