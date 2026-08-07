import SwiftUI
import CoreKit

// MARK: - 顶部栏（Robinhood Nav Bar：大标题 22pt 左对齐 + 搜索框 + 操作按钮）

struct TopBar: View {
    @EnvironmentObject var app: AppState
    var sidebarWidth: CGFloat

    /// 当前内容列标题（RH 大标题）
    private var screenTitle: String {
        switch app.selectedTab {
        case .watchlist: L10n.l("sidebar.watchlist")
        case .markets: L10n.l("sidebar.markets")
        case .newsFlash: L10n.l("sidebar.flash")
        case .newsResearch: L10n.l("sidebar.research")
        case .newsEarnings: L10n.l("sidebar.earnings")
        case .newsCalendar: L10n.l("sidebar.calendar")
        case .newsFeed(let id):
            app.store.newsFeeds.first { $0.id == id }?.name ?? L10n.l("sidebar.news")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 1. 侧边栏顶部：品牌区
            brandArea
                .frame(width: sidebarWidth)
                .frame(height: 52)
                .background(DS.bgPanel)

            DSDivider()

            // 2. 内容列顶部：大标题（RH Screen Title 22pt 左对齐）+ 搜索框
            VStack(alignment: .leading, spacing: 6) {
                Text(screenTitle)
                    .font(.system(size: DS.screenTitleSize, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(DS.textPrimary)
                DSSearchField(text: $app.searchText,
                              placeholder: L10n.l("sidebar.search"))
            }
            .padding(.horizontal, DS.space4)
            .padding(.vertical, DS.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.bgApp)

            DSDivider()

            // 3. 详情列顶部：操作按钮（右侧）
            actionArea
                .frame(width: 240)
                .frame(height: 52)
                .background(DS.bgApp)
        }
    }

    // MARK: 品牌区

    private var brandArea: some View {
        HStack(spacing: 8) {
            // hiddenTitleBar 下为红绿灯留安全区
            Spacer().frame(width: 70)
            // 品牌标识：黑色圆角方块 + 白色趋势线（RH 简洁风）
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.tradeButton)
                .frame(width: 24, height: 24)
                .overlay(
                    TectonicIconView(icon: .chartLine, size: 13, color: .white)
                )
            Text("Tectonic")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 12)
    }

    // MARK: 操作按钮区

    private var actionArea: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
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
            // 添加标的
            AddSymbolButton()
            // AI 问询
            if app.chatPanel == nil {
                DSIconButton(icon: .sparkles, help: L10n.l("chat.open")) {
                    openAI()
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func openAI() {
        app.chatPanel = ChatPanelContext(
            title: "Tectonic AI",
            subtitle: L10n.l("placeholder.detail"),
            systemBuilder: { webContext in
                var sys = "你是专业的财经分析助手。基于公开信息分析，明确指出不确定性和风险，不要给出确定性的投资建议。"
                sys += app.settings.languageInstruction
                if !webContext.isEmpty {
                    sys += "\n\n以下是检索到的相关资讯（联网，请优先参考）：\n\(webContext)"
                }
                return sys
            },
            quickQuestions: []
        )
    }
}

// MARK: - 侧边栏搜索词（AppState 扩展）

extension AppState {
    /// 顶部搜索框文案
    static let searchPlaceholder = "搜索"
}
