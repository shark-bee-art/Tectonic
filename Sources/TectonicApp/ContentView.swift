import SwiftUI
import TectonicIcons
import CoreKit

/// 主界面：单栏 + 导航栈
/// 顶部（应用图标 + 四 tab + 搜索） → 全宽列表 → 点击 push 全宽详情页（带返回）
struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar()
                DSDivider()
                // 主区域：详情优先（导航栈 push），否则当前 tab 列表
                mainArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(DS.bgApp)

            // 全局搜索下拉（最上层，不被任何内容遮挡）
            SearchResultsOverlay()
        }
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
        app.selectedTab.isNewsTab
    }

    // MARK: 当前 tab 内容（全宽列表）

    @ViewBuilder
    private var tabContent: some View {
        switch app.selectedTab {
        case .watchlist:
            WatchlistView()
        case .markets:
            MarketsView()
        case .flash:
            NewsListView(category: .flash)
        case .newsFeed(let id):
            NewsListView(category: .flash, sourceID: id)
        case .calendar:
            CalendarView()
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
