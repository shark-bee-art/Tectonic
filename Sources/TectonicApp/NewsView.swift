import SwiftUI
import CoreKit

/// 资讯分类列表：快讯/研报/财报/日历 通用；日历按日期分组
/// sourceID 非 nil 时只显示该订阅源（侧边栏子菜单独立查看）
/// TradingView 淡雅强化：时间列居左 + 来源标签居右 + hover 箭头/背景反馈
struct NewsListView: View {
    @EnvironmentObject var app: AppState
    let category: NewsFeedCategory
    var sourceID: String? = nil

    @State private var items: [NewsItem] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var refreshTick = 0

    /// 当前源（sourceID 非 nil 时）
    private var sourceFeed: NewsFeed? {
        guard let sourceID else { return nil }
        return app.store.newsFeeds.first { $0.id == sourceID }
    }

    /// 标题：单源显示源名，否则显示分类名
    private var titleText: String {
        sourceFeed?.name ?? category.displayName
    }

    /// 搜索结果（顶部搜索框过滤标题/摘要）
    private var filteredItems: [NewsItem] {
        let q = app.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.summary.localizedCaseInsensitiveContains(q)
                || $0.source.localizedCaseInsensitiveContains(q)
        }
    }

    /// 按日期分组（日历/财报用）
    private var grouped: [(Date, [NewsItem])] {
        let cal = Calendar.current
        var buckets: [Date: [NewsItem]] = [:]
        for item in filteredItems {
            let day = cal.startOfDay(for: item.publishedAt)
            buckets[day, default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { ($0, buckets[$0]!.sorted { $0.publishedAt > $1.publishedAt }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具条
            HStack(spacing: 8) {
                TectonicIconView(icon: categoryIcon, size: 16, color: DS.textPrimary)
                Text(titleText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let last = items.first?.publishedAt {
                    Text("更新于 \(last.formatted(.relative(presentation: .named)))")
                        .font(.system(size: DS.metaSize))
                        .foregroundStyle(DS.textTertiary)
                }
                DSIconButton(icon: .refresh, help: L10n.l("common.refresh")) {
                    refreshTick += 1
                }
                .disabled(isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            DSDivider()

            if category == .calendar || category == .earnings {
                groupedList
            } else {
                plainList
            }
        }
        .background(DS.bgPanel)
        .task(id: "\(category.rawValue)-\(sourceID ?? "")-\(refreshTick)") {
            await load()
        }
        .onChange(of: category) { _, _ in
            app.selectedNews = nil
        }
        .onChange(of: sourceID) { _, _ in
            app.selectedNews = nil
            refreshTick += 1
        }
    }

    // MARK: 列表（按日期分组）

    private var groupedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(grouped, id: \.0) { day, dayItems in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if Calendar.current.isDateInToday(day) {
                                DSChip(text: L10n.l("news.today"), color: DS.accent)
                            }
                            Text(dayHeader(day))
                                .font(.system(size: DS.listTitleSize, weight: .semibold))
                                .foregroundStyle(DS.textPrimary)
                            Spacer()
                            Text("\(dayItems.count) 项")
                                .font(.system(size: DS.metaSize))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.horizontal, 10)

                        ForEach(dayItems) { item in
                            NewsRow(item: item)
                                .onTapGesture { app.selectedNews = item }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .overlay { overlayState }
    }

    // MARK: 列表（平铺）

    private var plainList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredItems) { item in
                    NewsRow(item: item)
                        .onTapGesture { app.selectedNews = item }
                }
            }
            .padding(.vertical, 6)
        }
        .overlay { overlayState }
    }

    @ViewBuilder
    private var overlayState: some View {
        if isLoading && filteredItems.isEmpty {
            DSPlaceholder(icon: .refresh, title: L10n.l("common.loading"))
        } else if let lastError, filteredItems.isEmpty {
            DSPlaceholder(icon: .alertTriangle,
                          title: lastError,
                          actionTitle: L10n.l("common.refresh"),
                          action: { refreshTick += 1 })
        } else if filteredItems.isEmpty && !items.isEmpty {
            // 有数据但搜索无结果
            DSPlaceholder(icon: .searchOff,
                          title: L10n.l("news.searchEmpty"),
                          subtitle: "\"\(app.searchText)\"")
        } else if filteredItems.isEmpty {
            DSPlaceholder(icon: .news,
                          title: L10n.l("news.empty"),
                          subtitle: L10n.l("news.emptyHint"))
        }
    }

    private var categoryIcon: TectonicIcon {
        switch category {
        case .flash: .bolt
        case .research: .fileText
        case .earnings: .chartBar
        case .calendar: .calendar
        }
    }

    private func dayHeader(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return L10n.l("news.today") }
        if cal.isDateInTomorrow(day) { return L10n.l("news.tomorrow") }
        if cal.isDateInYesterday(day) { return L10n.l("news.yesterday") }
        return day.formatted(.dateTime.month().day().weekday(.wide))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await app.store.fetchNews(category: category, sourceID: sourceID)
        lastError = nil
        // 订阅源未导入时先导入再拉一次
        if items.isEmpty, app.store.newsFeeds.isEmpty {
            try? app.store.importBuiltinFeedsIfNeeded()
            items = await app.store.fetchNews(category: category, sourceID: sourceID)
        }
    }
}

// MARK: - 新闻行（TradingView 新闻流：时间列左 + 来源右 + hover 箭头）

struct NewsRow: View {
    let item: NewsItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            // hover 箭头（非 hover 占位保持列对齐）
            TectonicIconView(icon: .chevronRight, size: 9, color: DS.accent)
                .opacity(hovering ? 1 : 0)
                .frame(width: 10)

            // 时间列（固定宽）
            Text(item.publishedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: DS.metaSize, weight: .medium))
                .foregroundStyle(hovering ? DS.accent : DS.textTertiary)
                .frame(width: 62, alignment: .leading)

            // 标题 + 摘要
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: DS.listTitleSize, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    if let tag = item.aiTag {
                        impactChip(tag)
                    }
                }
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.system(size: DS.listBodySize))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 来源标签（右对齐）
            Text(item.source)
                .font(.system(size: DS.metaSize, weight: .medium))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(hovering ? DS.bgHover : .clear)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private func impactChip(_ tag: NewsTag) -> some View {
        let (text, color): (String, Color) = switch (tag.impact, tag.stance) {
        case (.positive, _): (L10n.l("news.tagBullish"), DS.up)
        case (.negative, _): (L10n.l("news.tagBearish"), DS.down)
        case (_, .bullish): (L10n.l("news.tagLong"), DS.up)
        case (_, .bearish): (L10n.l("news.tagShort"), DS.down)
        default: (L10n.l("news.tagNeutral"), DS.neutral)
        }
        DSChip(text: text, color: color)
    }
}

// MARK: - 资讯详情页（detail 列）：正文 + 右上 AI 问询（右侧面板）

struct NewsDetailView: View {
    @EnvironmentObject var app: AppState
    let item: NewsItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 元信息行
                HStack(spacing: 10) {
                    TectonicIconView(icon: .news, size: 13, color: DS.textTertiary)
                    Text(item.source)
                        .font(.system(size: DS.captionSize))
                        .foregroundStyle(DS.textSecondary)
                    Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: DS.captionSize))
                        .foregroundStyle(DS.textTertiary)
                    Spacer()
                    if let tag = item.aiTag {
                        let (text, color): (String, Color) = switch (tag.impact, tag.stance) {
                        case (.positive, _): (L10n.l("news.tagBullish"), DS.up)
                        case (.negative, _): (L10n.l("news.tagBearish"), DS.down)
                        case (_, .bullish): (L10n.l("news.tagLong"), DS.up)
                        case (_, .bearish): (L10n.l("news.tagShort"), DS.down)
                        default: (L10n.l("news.tagNeutral"), DS.neutral)
                        }
                        DSChip(text: text, color: color)
                    }
                    DSIconButton(icon: .externalLink, help: L10n.l("news.openInBrowser")) {
                        if let url = URL(string: item.url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                // 标题
                Text(item.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .textSelection(.enabled)

                DSDivider()

                // 正文
                Text(item.content ?? item.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)
            }
            .padding(20)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.bgApp)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openChat()
                } label: {
                    HStack(spacing: 4) {
                        TectonicIconView(icon: .sparkles, size: 14, color: DS.accent)
                        Text(L10n.l("news.aiChat"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: DS.radiusMedium).fill(DS.bgHover))
                }
                .buttonStyle(.plain)
                .help(L10n.l("news.aiChat"))
            }
        }
    }

    /// 打开右侧 AI 问询面板（正文作为上下文 + 可选联网资讯）
    private func openChat() {
        let item = self.item
        let title = item.title
        app.chatPanel = ChatPanelContext(
            title: String(title.prefix(30)),
            subtitle: L10n.l("placeholder.news"),
            systemBuilder: { webContext in
                var sys = """
                你是一个财经资讯分析助手。以下是用户正在阅读的资讯：

                标题：\(title)
                \(item.content.map { "正文：\n\($0)" } ?? "摘要：\(item.summary)")
                来源：\(item.source)，发布于 \(item.publishedAt.formatted())

                用户会就这条资讯提问。\(app.settings.languageInstruction)
                结合资讯内容与财经常识，明确指出不确定性和风险，不要给出确定性的投资建议。
                """
                if !webContext.isEmpty {
                    sys += "\n\n以下是检索到的相关资讯（联网，请优先参考）：\n\(webContext)"
                }
                return sys
            },
            quickQuestions: [
                (L10n.l("news.quickImpact"), "这条消息对哪只股票或市场影响最大？"),
                (L10n.l("news.quickOutlook"), "接下来行情可能怎么走？"),
                (L10n.l("news.quickRisk"), "有哪些风险点值得注意？"),
            ]
        )
    }
}
