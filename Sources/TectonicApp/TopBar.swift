import SwiftUI
import CoreKit

// MARK: - 自绘顶部栏（TradingView 淡雅：品牌区 / 内容列搜索 / 详情列操作按钮）

struct TopBar: View {
    @EnvironmentObject var app: AppState
    var sidebarWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // 1. 侧边栏顶部：品牌区（宽度与侧边栏一致，保证搜索框对齐内容列）
            brandArea
                .frame(width: sidebarWidth)
                .frame(height: 44)
                .background(DS.bgPanel)

            DSDivider()

            // 2. 内容列顶部：搜索框（居中于内容列）
            searchArea
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(DS.bgApp)

            DSDivider()

            // 3. 详情列顶部：操作按钮（统一右侧）
            actionArea
                .frame(width: 240)
                .frame(height: 44)
                .background(DS.bgApp)
        }
    }

    // MARK: 品牌区

    private var brandArea: some View {
        HStack(spacing: 8) {
            // hiddenTitleBar 下为红绿灯留安全区
            Spacer().frame(width: 70)
            // 品牌标识：accent 圆角方块 + 白色趋势线
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [DS.accent, DS.accent.opacity(0.75)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 22, height: 22)
                .overlay(
                    TectonicIconView(icon: .chartLine, size: 13, color: .white)
                )
            Text("Tectonic")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 12)
    }

    // MARK: 搜索区

    private var searchArea: some View {
        HStack(spacing: 8) {
            Spacer()
            DSInputField(text: $app.searchText,
                         placeholder: L10n.l("sidebar.search"),
                         icon: .search)
                .frame(width: 280)
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // MARK: 操作按钮区

    private var actionArea: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            // 刷新
            if app.isRefreshing {
                TectonicIconView(icon: .refresh, size: 16, color: DS.accent)
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
            // AI 问询（当前上下文存在时可用）
            if app.chatPanel == nil {
                DSIconButton(icon: .sparkles, help: L10n.l("chat.open")) {
                    openAI()
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func openAI() {
        // 无当前详情上下文时打开通用问询
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
