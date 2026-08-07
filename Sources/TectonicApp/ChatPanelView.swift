import SwiftUI
import TectonicIcons
import CoreKit

/// 底部悬浮 AI 问询对话框
/// 设计语言：主流 AI 聊天产品（ChatGPT/Claude 风格）——
/// 极简头部 / 全宽消息流（AI 靠左带头像、用户靠右）/ 大圆角输入框 + 圆形发送按钮 / 玻璃质感
struct ChatPanelContext: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    /// 构建 system prompt：参数为联网检索到的资讯（空串表示未联网/无结果）
    let systemBuilder: @MainActor (String) -> String
    let quickQuestions: [(String, String)]
    /// 打开时自动发送的初始问题（详情页底部对话框预填）
    var initialQuestion: String? = nil
}

struct ChatPanelView: View {
    @EnvironmentObject var app: AppState
    let context: ChatPanelContext

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isThinking = false
    @State private var searchedSources: [String] = []
    @State private var didSendInitial = false
    @FocusState private var inputFocused: Bool

    private var ai: AISettings { app.aiSettings }

    var body: some View {
        VStack(spacing: 0) {
            header
            DSDivider()
            messageStream
            inputArea
        }
        .frame(width: 620, height: 460)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.22), value: app.chatPanel?.id)
        .onAppear {
            if !didSendInitial, let q = context.initialQuestion, !q.isEmpty {
                didSendInitial = true
                send(q)
            }
        }
    }

    // MARK: 头部（极简：logo + 标题 + 模型，右侧关闭）

    private var header: some View {
        HStack(spacing: 10) {
            // AI logo（品牌色小方块）
            RoundedRectangle(cornerRadius: 7)
                .fill(DS.tradeButton)
                .frame(width: 26, height: 26)
                .overlay(TectonicIconView(icon: .sparkles, size: 12, color: .white))
            VStack(alignment: .leading, spacing: 1) {
                Text(context.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(ai.model)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                    if ai.webSearchEnabled {
                        HStack(spacing: 2) {
                            TectonicIconView(icon: .globe, size: 9, color: DS.accent)
                            Text(L10n.l("chat.webSearchOn"))
                                .font(.system(size: 9.5))
                                .foregroundStyle(DS.accent)
                        }
                    }
                }
            }
            Spacer()
            Button {
                app.chatPanel = nil
            } label: {
                TectonicIconView(icon: .x, size: 14, color: DS.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(DS.bgHover)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.l("nav.back"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 消息流（全宽：AI 靠左带头像，用户靠右）

    private var messageStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { msg in
                        messageRow(msg)
                    }
                    if isThinking {
                        thinkingRow
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id ?? UUID(), anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(DS.tradeButton)
                .frame(width: 40, height: 40)
                .overlay(TectonicIconView(icon: .sparkles, size: 18, color: .white))
            Text(context.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.textPrimary)
            Text(context.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    /// 单条消息（全宽，无卡片气泡）
    private func messageRow(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == "user"
        return HStack(alignment: .top, spacing: 10) {
            if !isUser {
                aiAvatar(size: 22)
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !isUser {
                    Text("Tectonic AI")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                Text(msg.content)
                    .font(.system(size: 13.5))
                    .foregroundStyle(DS.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(isUser ? DS.accent.opacity(0.12) : DS.bgHover.opacity(0.85))
                    )
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
            if isUser {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    // MARK: 思考指示

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            aiAvatar(size: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text("Tectonic AI")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(DS.textTertiary)
                            .frame(width: 5, height: 5)
                            .opacity(isThinking ? (i == 0 ? 1 : 0.3) : 0.3)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: isThinking)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func aiAvatar(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28)
            .fill(DS.tradeButton)
            .frame(width: size, height: size)
            .overlay(TectonicIconView(icon: .sparkles, size: size * 0.45, color: .white))
    }

    // MARK: 输入区（大圆角输入框 + 圆形发送按钮 + 轻量快捷问题）

    private var inputArea: some View {
        VStack(spacing: 8) {
            // 输入行
            HStack(spacing: 8) {
                TextField(L10n.l("chat.askHint"), text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(DS.bgHover.opacity(0.9))
                    )
                    .focused($inputFocused)
                    .onSubmit { send() }

                // 圆形发送按钮
                let canSend = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
                Button {
                    send()
                } label: {
                    Circle()
                        .fill(canSend ? DS.tradeButton : DS.bgHover)
                        .frame(width: 34, height: 34)
                        .overlay(
                            TectonicIconView(icon: .send, size: 14,
                                             color: canSend ? .white : DS.textTertiary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 发送

    private func send(_ preset: String? = nil) {
        let text: String
        if let preset {
            text = preset
        } else {
            text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
        }
        guard !isThinking else { return }
        input = ""
        messages.append(.user(text))
        isThinking = true
        let provider = ai.provider
        let model = ai.model
        let key = ai.apiKey(for: provider)
        let effort = "medium"
        let webEnabled = true
        let feeds = app.store.newsFeeds
        let searchProvider = app.settings.searchProvider
        let searchKey = app.settings.searchAPIKey
        let skillHint = StockAnalysisSkills.skillHint(for: text)

        Task {
            defer { isThinking = false }
            var webContext = ""
            if webEnabled {
                let results = await WebSearchService.search(query: text, feeds: feeds,
                                                            provider: searchProvider, apiKey: searchKey)
                if !results.isEmpty {
                    webContext = results.map {
                        "· [\($0.source)\($0.date.map { " \($0.formatted(.dateTime.month().day()))" } ?? "")] \($0.title)：\(String($0.summary.prefix(180)))"
                    }.joined(separator: "\n")
                    searchedSources = results.map { "\($0.source) · \($0.title.prefix(30))" }
                }
            }
            let system = context.systemBuilder(webContext)
            let finalSystem = "\(system)\n\n\(StockAnalysisSkills.guidance)\n\(skillHint)"
            do {
                let reply = try await ModelGateway().ask(text, system: finalSystem,
                                                         provider: provider, model: model, apiKey: key,
                                                         reasoningEffort: effort)
                messages.append(.assistant(reply))
            } catch {
                messages.append(.assistant("⚠️ \(error.localizedDescription)"))
            }
        }
    }
}
