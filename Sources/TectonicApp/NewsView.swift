import SwiftUI
import CoreKit

/// 资讯分类列表：快讯/研报/财报/日历 通用
struct NewsListView: View {
    @EnvironmentObject var app: AppState
    let category: NewsFeedCategory

    @State private var items: [NewsItem] = []
    @State private var selectedNews: NewsItem?
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var refreshTick = 0

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具条（分类 + 刷新 + 最后刷新时间）
            HStack {
                Label(category.displayName, systemImage: category.icon)
                    .font(.headline)
                Spacer()
                if let last = items.first?.publishedAt {
                    Text("更新于 \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    refreshTick += 1
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: $selectedNews) {
                ForEach(items) { item in
                    NewsRow(item: item)
                        .tag(item)
                }
            }
            .overlay {
                if isLoading && items.isEmpty {
                    ProgressView("加载中…")
                } else if let lastError, items.isEmpty {
                    VStack(spacing: 8) {
                        Text(lastError)
                            .foregroundStyle(.secondary)
                        Button("重试") { refreshTick += 1 }
                    }
                } else if items.isEmpty {
                    Text("暂无内容\n请在设置 → 资讯源中启用订阅源")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let item = selectedNews {
                NewsReaderBar(item: item)
                    .frame(height: 300)
            }
        }
        .task(id: "\(category.rawValue)-\(refreshTick)") {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await app.store.fetchNews(category: category)
        lastError = nil
        // 订阅源未导入时先导入再拉一次
        if items.isEmpty, app.store.newsFeeds.isEmpty {
            try? app.store.importBuiltinFeedsIfNeeded()
            items = await app.store.fetchNews(category: category)
        }
    }
}

// MARK: - 新闻行

struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let tag = item.aiTag {
                    TagChip(text: tag.impact == .positive ? "利好" : (tag.impact == .negative ? "利空" : "中性"),
                            color: tag.impact == .positive ? .red : (tag.impact == .negative ? .green : .gray))
                    TagChip(text: tag.stance == .bullish ? "看多" : (tag.stance == .bearish ? "看空" : "中性"),
                            color: tag.stance == .bullish ? .red : (tag.stance == .bearish ? .green : .gray))
                }
                Text(item.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.publishedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .font(.body.weight(.medium))
                .lineLimit(3)
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TagChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

// MARK: - 阅读页（底部条）：正文 + AI 对话 + 打标

struct NewsReaderBar: View {
    @EnvironmentObject var app: AppState
    let item: NewsItem

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isThinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let tag = item.aiTag {
                    Text("AI 判断：\(tag.impact == .positive ? "利好" : (tag.impact == .negative ? "利空" : "中性")) / \(tag.stance == .bullish ? "看多" : (tag.stance == .bearish ? "看空" : "中性"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("在浏览器打开") {
                    if let url = URL(string: item.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            Divider()
            HStack(alignment: .top, spacing: 12) {
                // 摘要区
                ScrollView {
                    Text(item.content ?? item.summary)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                Divider()
                // AI 对话区
                VStack(alignment: .leading, spacing: 6) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if messages.isEmpty {
                                    Text("就本条新闻提问，例如：\n「这条新闻对哪只股票影响最大？」\n「接下来可能怎么走？」")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                                    MessageBubble(message: msg)
                                }
                                if isThinking {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("思考中…").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack(spacing: 6) {
                        TextField("询问本条新闻…", text: $input)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { send() }
                        Button("发送") { send() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                    }
                }
                .frame(width: 380)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        input = ""
        let ai = app.aiSettings
        let system = """
        你是一个财经新闻分析助手。以下是用户正在阅读的新闻：

        标题：\(item.title)
        \(item.content.map { "正文：\n\($0)" } ?? "摘要：\(item.summary)")
        来源：\(item.source)，发布于 \(item.publishedAt.formatted())

        用户会就这条新闻提问。回答使用简体中文，结合新闻内容与财经常识，
        明确指出不确定性和风险，不要给出确定性的投资建议。
        """
        messages.append(.user(text))
        isThinking = true
        Task {
            defer { isThinking = false }
            do {
                let reply = try await ModelGateway().ask(
                    text, system: system,
                    provider: ai.provider, model: ai.model,
                    apiKey: ai.apiKey(for: ai.provider))
                messages.append(.assistant(reply))
            } catch {
                messages.append(.assistant("⚠️ 调用失败：\(error.localizedDescription)"))
            }
        }
    }
}
