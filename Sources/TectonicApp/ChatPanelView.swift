import SwiftUI
import TectonicIcons
import CoreKit

/// 底部悬浮 AI 问询对话框（主流聊天 UI：头像气泡 + 底部输入区）
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

    // MARK: 面板主体（底部悬浮，固定高度可滚动）

    private var panel: some View {
        VStack(spacing: 0) {
            header
            DSDivider()
            messagesList
            DSDivider()
            inputArea
        }
        .frame(width: 500, height: 340)
        .background(DS.bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, y: 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // AI 标识（sparkles 渐变头像）
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [.accentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay(TectonicIconView(icon: .sparkles, size: 14, color: .white))
            VStack(alignment: .leading, spacing: 2) {
                Text(context.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(ai.model)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if ai.webSearchEnabled {
                        HStack(spacing: 3) {
                            TectonicIconView(icon: .globe, size: 11, color: DS.accent)
                            Text(L10n.l("chat.webSearchOn"))
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(DS.accent)
                    }
                }
            }
            Spacer()
            // 清空对话
            Button {
                messages = []
                searchedSources = []
            } label: {
                TectonicIconView(icon: .trash, size: 16, color: DS.textSecondary)
            }
            .buttonStyle(.borderless)
            .help(L10n.l("chat.clear"))
            // 关闭
            Button {
                app.chatPanel = nil
            } label: {
                TectonicIconView(icon: .x, size: 16, color: DS.textSecondary)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if messages.isEmpty {
                        // 空状态（主流聊天 UI：欢迎提示）
                        VStack(spacing: 10) {
                            TectonicIconView(icon: .sparkles, size: 34, color: DS.textTertiary)
                            Text(context.subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        .padding(.top, 50)
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
                .padding(.vertical, 12)
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
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.accentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 24, height: 24)
                    .overlay(TectonicIconView(icon: .sparkles, size: 11, color: .white))
            }
            VStack(alignment: .leading, spacing: 3) {
                if msg.role == "assistant" {
                    Text("Tectonic AI")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(msg.content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [.accentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 24, height: 24)
                .overlay(TectonicIconView(icon: .sparkles, size: 11, color: .white))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.l("common.thinking"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                // 快捷问题（贴输入框上方）
                ForEach(context.quickQuestions, id: \.0) { q in
                    Button {
                        send(q.1)
                    } label: {
                        Text(q.0)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isThinking)
                }
                Spacer()
                // 联网搜索状态（默认开启，无需开关）
                if ai.webSearchEnabled {
                    HStack(spacing: 3) {
                        TectonicIconView(icon: .globe, size: 11, color: DS.accent)
                        Text(L10n.l("chat.webSearchOn"))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(DS.accent)
                    .help(L10n.l("chat.webSearchHint"))
                }
                if !searchedSources.isEmpty {
                    Text("\(searchedSources.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                TextField(context.subtitle, text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.bgHover))
                    .focused($inputFocused)
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    TectonicIconView(icon: .send, size: 24, color: input.isEmpty || isThinking ? DS.textTertiary : DS.accent)
                        .font(.system(size: 26))
                        .foregroundStyle(input.isEmpty || isThinking ? DS.textTertiary : DS.accent)
                }
                .buttonStyle(.borderless)
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
