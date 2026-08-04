import SwiftUI
import CoreKit

/// 右侧滑出式 AI 问询面板（主流聊天 UI：轻盈毛玻璃 + 头像气泡 + 底部输入区）
struct ChatPanelContext: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    /// 构建 system prompt：参数为联网检索到的资讯（空串表示未联网/无结果）
    let systemBuilder: @MainActor (String) -> String
    let quickQuestions: [(String, String)]
}

struct ChatPanelView: View {
    @EnvironmentObject var app: AppState
    let context: ChatPanelContext

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isThinking = false
    @State private var searchedSources: [String] = []
    @FocusState private var inputFocused: Bool

    private var ai: AISettings { app.aiSettings }
    private var reasoningLabel: String {
        switch ai.reasoningEffort {
        case "low": L10n.l("chat.effort.low")
        case "high": L10n.l("chat.effort.high")
        default: L10n.l("chat.effort.medium")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 透明点击区（点击面板外关闭）
            Color.black.opacity(0.05)
                .contentShape(Rectangle())
                .onTapGesture { app.chatPanel = nil }
            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.22), value: app.chatPanel?.id)
    }

    // MARK: 面板主体

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesList
            Divider()
            inputArea
        }
        .frame(width: 430)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .shadow(color: .black.opacity(0.2), radius: 24, x: -4, y: 0)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // AI 标识（sparkles 渐变头像）
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [.accentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(context.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(ai.model)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if ai.webSearchEnabled {
                        Label(L10n.l("chat.webSearchOn"), systemImage: "globe")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    Text(reasoningLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // 清空对话
            Button {
                messages = []
                searchedSources = []
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.l("chat.clear"))
            // 关闭
            Button {
                app.chatPanel = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
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
                            Image(systemName: "sparkles")
                                .font(.system(size: 34))
                                .foregroundStyle(.tertiary)
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
                    .overlay(Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
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
                                  ? Color.accentColor.opacity(0.13)
                                  : Color.secondary.opacity(0.08))
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
                .overlay(Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.l("common.thinking"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
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
                // 联网搜索快捷开关
                Button {
                    ai.webSearchEnabled.toggle()
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(ai.webSearchEnabled ? Color.white : Color.secondary)
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(ai.webSearchEnabled ? Color.blue : Color.secondary.opacity(0.12))
                        )
                }
                .buttonStyle(.borderless)
                .help(L10n.l("chat.webSearch"))
                // 思考深度快捷开关（点击循环 低→中→高）
                Button {
                    switch ai.reasoningEffort {
                    case "low": ai.reasoningEffort = "medium"
                    case "medium": ai.reasoningEffort = "high"
                    default: ai.reasoningEffort = "low"
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dial.medium")
                            .font(.system(size: 12))
                        Text(reasoningLabel)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.borderless)
                .help("\(L10n.l("chat.thinkDepth")): \(reasoningLabel)")
            }
            HStack(spacing: 8) {
                TextField(context.subtitle, text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.10)))
                    .focused($inputFocused)
                    .onSubmit { send() }
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(input.isEmpty || isThinking ? Color.secondary.opacity(0.4) : Color.accentColor)
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
        let effort = ai.reasoningEffort
        let webEnabled = ai.webSearchEnabled
        let feeds = app.store.newsFeeds

        Task {
            defer { isThinking = false }
            // 联网检索（可选）
            var webContext = ""
            if webEnabled {
                let results = await WebSearchService.search(query: text, feeds: feeds)
                if !results.isEmpty {
                    webContext = results.map {
                        "· [\($0.source)\($0.date.map { " \($0.formatted(.dateTime.month().day()))" } ?? "")] \($0.title)：\(String($0.summary.prefix(180)))"
                    }.joined(separator: "\n")
                    searchedSources = results.map { "\($0.source) · \($0.title.prefix(30))" }
                }
            }
            let system = context.systemBuilder(webContext)
            do {
                let reply = try await ModelGateway().ask(text, system: system,
                                                         provider: provider, model: model, apiKey: key,
                                                         reasoningEffort: effort)
                messages.append(.assistant(reply))
            } catch {
                messages.append(.assistant("⚠️ \(error.localizedDescription)"))
            }
        }
    }
}
