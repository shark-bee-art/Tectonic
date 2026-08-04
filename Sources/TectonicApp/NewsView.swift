import SwiftUI
import CoreKit

/// 资讯分类列表：快讯/研报/财报/日历 通用；日历按日期分组
struct NewsListView: View {
    @EnvironmentObject var app: AppState
    let category: NewsFeedCategory

    @State private var items: [NewsItem] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var refreshTick = 0

    /// 按日期分组（日历/财报用）
    private var grouped: [(Date, [NewsItem])] {
        let cal = Calendar.current
        var buckets: [Date: [NewsItem]] = [:]
        for item in items {
            let day = cal.startOfDay(for: item.publishedAt)
            buckets[day, default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { ($0, buckets[$0]!.sorted { $0.publishedAt > $1.publishedAt }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具条
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

            List(selection: $app.selectedNews) {
                if category == .calendar || category == .earnings {
                    // 按日期分组展示
                    ForEach(grouped, id: \.0) { day, dayItems in
                        Section(header: Text(dayHeader(day))) {
                            ForEach(dayItems) { item in
                                NewsRow(item: item)
                                    .tag(item)
                            }
                        }
                    }
                } else {
                    ForEach(items) { item in
                        NewsRow(item: item)
                            .tag(item)
                    }
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
        .task(id: "\(category.rawValue)-\(refreshTick)") {
            await load()
        }
        .onChange(of: category) { _, _ in
            app.selectedNews = nil
        }
    }

    private func dayHeader(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "今天" }
        if cal.isDateInTomorrow(day) { return "明天" }
        if cal.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month().day().weekday(.wide))
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

// MARK: - 资讯详情页（detail 列）：正文在上，模型对话框固定底部

struct NewsDetailView: View {
    @EnvironmentObject var app: AppState
    let item: NewsItem

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isThinking = false

    var body: some View {
        VStack(spacing: 0) {
            // 正文区（可滚动）
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(item.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let tag = item.aiTag {
                            Text("AI 判断：\(tag.impact == .positive ? "利好" : (tag.impact == .negative ? "利空" : "中性")) / \(tag.stance == .bullish ? "看多" : (tag.stance == .bearish ? "看空" : "中性"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            if let url = URL(string: item.url) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("浏览器打开", systemImage: "safari")
                        }
                        .controlSize(.small)
                    }
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    Divider()
                    Text(item.content ?? item.summary)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // AI 对话区（固定底部）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("AI 问询", systemImage: "brain")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // 快捷问题（并排）
                    ForEach([("影响分析", "这条消息对哪只股票或市场影响最大？"), ("后续走势", "接下来行情可能怎么走？"), ("风险点", "有哪些风险点值得注意？")], id: \.0) { q in
                        Button(q.0) {
                            send(q.1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isThinking)
                    }
                    if isThinking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if messages.isEmpty {
                                Text("就本条资讯提问：\n「这条消息对哪只股票影响最大？」\n「接下来行情可能怎么走？」")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                                MessageBubble(message: msg)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 120)
                HStack(spacing: 6) {
                    TextField("询问本条资讯…", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }
                    Button("发送") { send() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }
            }
            .padding(12)
            .background(.bar)
        }
    }

    private func send(_ preset: String? = nil) {
        let text: String
        if let preset {
            text = preset
        } else {
            text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isThinking else { return }
        }
        input = ""
        guard !isThinking else { return }
        let ai = app.aiSettings
        let system = """
        你是一个财经资讯分析助手。以下是用户正在阅读的资讯：

        标题：\(item.title)
        \(item.content.map { "正文：\n\($0)" } ?? "摘要：\(item.summary)")
        来源：\(item.source)，发布于 \(item.publishedAt.formatted())

        用户会就这条资讯提问。\(app.settings.languageInstruction)
        结合资讯内容与财经常识，明确指出不确定性和风险，不要给出确定性的投资建议。
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
