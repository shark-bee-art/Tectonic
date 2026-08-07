import SwiftUI
import CoreKit

// MARK: - 顶部栏（Robinhood Nav Bar：品牌 + 顶部 tab + 搜索 + 操作按钮，单行）

struct TopBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            // 品牌区（红绿灯安全区 + logo）
            brandArea
                .frame(width: 190)
                .frame(height: 52)

            DSDivider()

            // 顶部 tab 栏（自选/行情/资讯分类）
            TopTabBar()
                .frame(maxWidth: .infinity)
                .frame(height: 52)

            DSDivider()

            // 搜索 + 操作按钮
            actionArea
                .frame(width: 420)
                .frame(height: 52)
        }
        .background(DS.bgApp)
    }

    // MARK: 品牌区

    private var brandArea: some View {
        HStack(spacing: 8) {
            // hiddenTitleBar 下为红绿灯留安全区
            Spacer().frame(width: 70)
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

    // MARK: 搜索 + 操作区

    private var actionArea: some View {
        HStack(spacing: 6) {
            DSSearchField(text: $app.searchText,
                          placeholder: L10n.l("sidebar.search"))
                .frame(width: 220)

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
