import SwiftUI
import TectonicIcons
import CoreKit

/// 资讯列表（快讯）：Robinhood News Card 风格
/// 12pt 圆角卡片 + 标题 + 来源/时间 + hover 反馈
struct NewsListView: View {
    @EnvironmentObject var app: AppState
    let category: NewsFeedCategory
    var sourceID: String? = nil

    @State private var items: [NewsItem] = []
    @State private var isLoading = false
    @State private var lastError: String?
    @State private var refreshTick = 0

    private var sourceFeed: NewsFeed? {
        guard let sourceID else { return nil }
        return app.store.newsFeeds.first { $0.id == sourceID }
    }

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

    var body: some View {
        plainList
            .background(DS.bgApp)
            .task(id: "\(category.rawValue)-\(sourceID ?? "")-\(refreshTick)") {
                await load()
            }
            .onChange(of: sourceID) { _, _ in
                app.selectedNews = nil
                refreshTick += 1
            }
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await app.store.fetchNews(category: category, sourceID: sourceID)
        lastError = nil
        if items.isEmpty, app.store.newsFeeds.isEmpty {
            try? app.store.importBuiltinFeedsIfNeeded()
            items = await app.store.fetchNews(category: category, sourceID: sourceID)
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

            // hover 箭头（右侧）
            if hovering {
                TectonicIconView(icon: .chevronRight, size: 14, color: DS.textSecondary)
                    .padding(.top, 16)
            }
        }
        .padding(DS.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusCard)
                .fill(hovering ? DS.bgHover : DS.bgApp)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusCard)
                .stroke(DS.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
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

// MARK: - 新闻详情页（全宽 push，Robinhood 风格）

struct NewsDetailView: View {
    @EnvironmentObject var app: AppState
    let item: NewsItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                // 标题
                Text(item.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                // 元信息
                HStack(spacing: 10) {
                    Text(item.source)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.accent)
                    Text(item.publishedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textTertiary)
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
                    Spacer()
                    if let url = URL(string: item.url) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                TectonicIconView(icon: .externalLink, size: 12, color: DS.accent)
                                Text(L10n.l("news.openInBrowser"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DS.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                DSDivider()

                // 摘要正文
                Text(item.summary.isEmpty ? item.title : item.summary)
                    .font(.system(size: 15))
                    .foregroundStyle(item.summary.isEmpty ? DS.textSecondary : DS.textPrimary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.space5)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.bgApp)
    }
}

extension NewsTag {
    var displayName: String {
        switch (impact, stance) {
        case (.positive, _): "利好"
        case (.negative, _): "利空"
        case (_, .bullish): "看多"
        case (_, .bearish): "看空"
        default: "中性"
        }
    }
}
