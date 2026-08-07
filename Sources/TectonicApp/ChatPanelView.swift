import SwiftUI
import TectonicIcons
import CoreKit

/// 底部悬浮 AI 问询对话框（玻璃质感 + Robinhood 设计语言一致）
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
        panel
            .animation(.easeInOut(duration: 0.22), value: app.chatPanel?.id)
            .onAppear {
                // 自动发送初始问题（详情页底部对话框唤起）
                if !didSendInitial, let q = context.initialQuestion, !q.isEmpty {
                    didSendInitial = true
                    send(q)
                }
            }
    }

    // MARK: 面板主体（玻璃质感，固定高度）

    private var panel: some View {
        VStack(spacing: 0) {
            header
            DSDivider()
            messagesList
            DSDivider()
            inputArea
        }
        .frame(width: 500, height: 340)
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
    }

    // MARK: 头部（AI 标识 + 标题 + 模型 + 操作）

    private var header: some View {
        HStack(spacing: 10) {
            // AI 标识（品牌色方块 + sparkles）
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.tradeButton)
                .frame(width: 28, height: 28)
                .overlay(TectonicIconView(icon: .sparkles, size: 13, color: .white))
            VStack(alignment: .leading, spacing: 2) {
                Text(context.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(ai.model)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                    if ai.webSearchEnabled {
                        HStack(spacing: 3) {
                            TectonicIconView(icon: .globe, size: 10, color: DS.accent)
                            Text(L10n.l("chat.webSearchOn"))
                                .font(.system(size: 10))
                                .foregroundStyle(DS.accent)
                        }
                    }
                }
            }
            Spacer()
            // 清空对话
            Button {
                messages = []
                searchedSources = []
            } label: {
                TectonicIconView(icon: .trash, size: 15, color: DS.textSecondary)
            }
            .buttonStyle(.plain)
            .help(L10n.l("chat.clear"))
            // 关闭
            Button {
                app.chatPanel = nil
            } label: {
                TectonicIconView(icon: .x, size: 15, color: DS.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: 消息列表

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        // 空状态（欢迎提示）
                        VStack(spacing: 10) {
                            TectonicIconView(icon: .sparkles, size: 32, color: DS.textTertiary)
                            Text(context.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(DS.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        .padding(.top, 44)
                    }
                    ForEach(messages) { msg in
                        chatBubble(msg)
                    }
                    if isThinking {
                        thinkingIndicator
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id ?? UUID(), anchor: .bottom) }
            }
        }
    }

    /// 消息气泡（助手带头像）
    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == "assistant" {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DS.tradeButton)
                    .frame(width: 22, height: 22)
                    .overlay(TectonicIconView(icon: .sparkles, size: 10, color: .white))
            }
            VStack(alignment: .leading, spacing: 3) {
                if msg.role == "assistant" {
                    Text("Tectonic AI")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.textTertiary)
                }
                Text(msg.content)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(msg.role == "user"
                                  ? DS.accent.opacity(0.13)
                                  : DS.bgHover)
                    )
                    .frame(maxWidth: 320, alignment: msg.role == "user" ? .trailing : .leading)
            }
            if msg.role == "user" {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == "user" ? .trailing : .leading)
    }

    // MARK: 思考指示

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(DS.tradeButton)
                .frame(width: 22, height: 22)
                .overlay(TectonicIconView(icon: .sparkles, size: 10, color: .white))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.l("common.thinking"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.textSecondary)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(DS.textTertiary)
                            .frame(width: 5, height: 5)
                            .opacity(isThinking ? (i == 0 ? 1 : 0.3) : 0.3)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: 输入区

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // 快捷问题（贴输入框上方，DS 风格 chips）
                ForEach(context.quickQuestions, id: \.0) { q in
                    Button {
                        send(q.1)
                    } label: {
                        Text(q.0)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: DS.radiusMedium).fill(DS.bgHover))
                    }
                    .buttonStyle(.plain)
                    .disabled(isThinking)
                }
                Spacer()
                // 联网搜索状态（默认开启）
                if ai.webSearchEnabled {
                    HStack(spacing: 3) {
                        TectonicIconView(icon: .globe, size: 10, color: DS.accent)
                        Text(L10n.l("chat.webSearchOn"))
                            .font(.system(size: 10))
                            .foregroundStyle(DS.accent)
                    }
                    .help(L10n.l("chat.webSearchHint"))
                }
                if !searchedSources.isEmpty {
                    Text("\(searchedSources.count) 源")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(DS.textTertiary)
                }
            }
            HStack(spacing: 8) {
                TextField(context.subtitle, text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.bgHover)
                    )
                    .focused($inputFocused)
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    TectonicIconView(icon: .send, size: 18, color: input.isEmpty || isThinking ? DS.textTertiary : DS.accent)
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            }
        }
        .padding(12)
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
        // 固定适中思考深度 + 默认联网
        let effort = "medium"
        let webEnabled = true
        let feeds = app.store.newsFeeds
        let searchProvider = app.settings.searchProvider
        let searchKey = app.settings.searchAPIKey
        let skillHint = StockAnalysisSkills.skillHint(for: text)

        Task {
            defer { isThinking = false }
            // 联网检索（默认开启）
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
