import SwiftUI
import TectonicIcons
import CoreKit

/// 资讯列表：快讯/研报/财报/聚合 通用
/// category = nil → 聚合模式（快讯+研报+财报 合并，顶部子分类切换条）
/// Robinhood News Card：12pt 圆角卡片 + 标题 + 来源/时间 + hover 反馈
struct NewsListView: View {
    @EnvironmentObject var app: AppState
    /// nil = 聚合（新闻 tab）；非 nil = 单分类
    let category: NewsFeedCategory?
    var sourceID: String? = nil

    @State private var items: [NewsItem] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var refreshTick = 0
    /// 聚合模式下选中的子分类（nil = 全部）
    @State private var subCategory: NewsFeedCategory? = nil

    private var sourceFeed: NewsFeed? {
        guard let sourceID else { return nil }
        return app.store.newsFeeds.first { $0.id == sourceID }
    }

    private var titleText: String {
        sourceFeed?.name ?? category?.displayName ?? L10n.l("sidebar.news")
    }

    /// 搜索结果（顶部搜索框过滤标题/摘要；聚合模式下子分类过滤）
    private var filteredItems: [NewsItem] {
        var list = items
        // 聚合模式下子分类过滤：匹配该分类下订阅源的来源名
        if let sub = subCategory {
            let sourceNames = Set(app.store.newsFeeds
                .filter { $0.category == sub && $0.enabled }
                .map { $0.name })
            list = list.filter { sourceNames.contains($0.source) }
        }
        let q = app.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.summary.localizedCaseInsensitiveContains(q)
                || $0.source.localizedCaseInsensitiveContains(q)
        }
    }

    /// 按日期分组（日历用；聚合/财报平铺）
    private var grouped: [(Date, [NewsItem])] {
        let cal = Calendar.current
        var buckets: [Date: [NewsItem]] = [:]
        for item in filteredItems {
            let day = cal.startOfDay(for: item.publishedAt)
            buckets[day, default: []].append(item)
        }
        return buckets.keys.sorted(by: >).map { ($0, buckets[$0]!.sorted { $0.publishedAt > $1.publishedAt }) }
    }

    /// 聚合模式下可切换的子分类（快讯/研报/财报）
    private var subCategories: [NewsFeedCategory] {
        [.flash, .research, .earnings]
    }

    var body: some View {
        VStack(spacing: 0) {
            // 聚合模式：子分类切换条
            if category == nil, sourceID == nil {
                subCategoryBar
            }

            if category == .calendar {
                groupedList
            } else {
                plainList
            }
        }
        .background(DS.bgApp)
        .task(id: "\(category?.rawValue ?? "all")-\(sourceID ?? "")-\(refreshTick)") {
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

    // MARK: 子分类切换条

    private var subCategoryBar: some View {
        HStack(spacing: 6) {
            subTab(title: L10n.l("sidebar.all") + L10n.l("sidebar.news"), selected: subCategory == nil) {
                subCategory = nil
            }
            ForEach(subCategories, id: \.self) { cat in
                subTab(title: cat.displayName, selected: subCategory == cat) {
                    subCategory = cat
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.space4)
        .padding(.vertical, 6)
    }

    private func subTab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(selected ? DS.bgSelected : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 列表（按日期分组）

    private var groupedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space8) {
                ForEach(grouped, id: \.0) { day, dayItems in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if Calendar.current.isDateInToday(day) {
                                DSChip(text: L10n.l("news.today"), color: DS.up)
                            }
                            Text(dayHeader(day))
                                .font(.system(size: DS.sectionHeaderSize, weight: .semibold))
                                .foregroundStyle(DS.textPrimary)
                            Spacer()
                            Text("\(dayItems.count) 项")
                                .font(.system(size: DS.bodySmallSize))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.horizontal, DS.space4)

                        ForEach(dayItems) { item in
                            NewsCard(item: item)
                                .onTapGesture { app.selectedNews = item }
                        }
                    }
                }
            }
            .padding(.vertical, DS.space4)
        }
        .overlay { overlayState }
    }

    // MARK: 列表（平铺）

    private var plainList: some View {
        ScrollView {
            LazyVStack(spacing: DS.space2) {
                ForEach(filteredItems) { item in
                    NewsCard(item: item)
                        .onTapGesture { app.selectedNews = item }
                }
            }
            .padding(.horizontal, DS.space4)
            .padding(.vertical, DS.space4)
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
            DSPlaceholder(icon: .searchOff,
                          title: L10n.l("news.searchEmpty"),
                          subtitle: "\"\(app.searchText)\"")
        } else if filteredItems.isEmpty {
            DSPlaceholder(icon: .news,
                          title: L10n.l("news.empty"),
                          subtitle: L10n.l("news.emptyHint"))
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
        if let category {
            items = await app.store.fetchNews(category: category, sourceID: sourceID)
        } else {
            // 聚合：拉取三个子分类合并，按时间排序
            let cats: [NewsFeedCategory] = [.flash, .research, .earnings]
            var all: [NewsItem] = []
            for cat in cats {
                let part = await app.store.fetchNews(category: cat, sourceID: sourceID)
                all.append(contentsOf: part)
            }
            items = all.sorted { $0.publishedAt > $1.publishedAt }
        }
        lastError = nil
        if items.isEmpty, app.store.newsFeeds.isEmpty {
            try? app.store.importBuiltinFeedsIfNeeded()
            if let category {
                items = await app.store.fetchNews(category: category, sourceID: sourceID)
            }
        }
    }
}
// MARK: - 新闻卡片（RH News Card：12pt 圆角 + 1pt 边框 + 标题/来源/时间）

struct NewsCard: View {
    let item: NewsItem
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.space3) {
            // 左侧：分类图标方块（RH thumbnail 位）
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.bgSurface)
                .frame(width: 48, height: 48)
                .overlay(
                    TectonicIconView(icon: .news, size: 18, color: DS.textSecondary)
                )

            // 中间：标题 + 摘要
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.system(size: DS.bodySmallSize))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
                // 元信息：AI 标签 + 来源 + 时间
                HStack(spacing: 8) {
                    if let tag = item.aiTag {
                        impactChip(tag)
                    }
                    Text(item.source)
                        .font(.system(size: DS.tickerSize, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    Text(item.publishedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: DS.tickerSize, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                }
            }

            // 右侧 hover 箭头
            TectonicIconView(icon: .chevronRight, size: 12, color: DS.textTertiary)
                .opacity(hovering ? 1 : 0)
                .padding(.top, 4)
        }
        .padding(DS.space3)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusCard)
                .fill(isSelected ? DS.bgSelected : (hovering ? DS.bgHover : DS.bgPanel))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusCard)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var isSelected: Bool {
        // 由外部选中态驱动——简化：hover 表达即可
        false
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
            VStack(alignment: .leading, spacing: DS.space4) {
                // 元信息行
                HStack(spacing: 10) {
                    TectonicIconView(icon: .news, size: 13, color: DS.textTertiary)
                    Text(item.source)
                        .font(.system(size: DS.bodySmallSize))
                        .foregroundStyle(DS.textSecondary)
                    Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: DS.bodySmallSize))
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

                // 标题（RH Screen Title）
                Text(item.title)
                    .font(.system(size: DS.screenTitleSize, weight: .bold))
                    .kerning(-0.2)
                    .foregroundStyle(DS.textPrimary)
                    .textSelection(.enabled)

                DSDivider()

                // 正文
                Text(item.content ?? item.summary)
                    .font(.system(size: DS.bodySize))
                    .foregroundStyle(DS.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(5)
            }
            .padding(DS.space6)
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
                        TectonicIconView(icon: .sparkles, size: 14, color: DS.up)
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
