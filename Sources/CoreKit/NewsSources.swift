import Foundation

// MARK: - 资讯分类

public enum NewsFeedCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case flash       // 快讯（实时新闻）
    case research    // 研报（机构深度分析）
    case earnings    // 财报（季度财报）
    case calendar    // 日历（财报日历/重要数据）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flash: "快讯"
        case .research: "研报"
        case .earnings: "财报"
        case .calendar: "日历"
        }
    }

    public var icon: String {
        switch self {
        case .flash: "bolt"
        case .research: "doc.text.magnifyingglass"
        case .earnings: "chart.bar.doc.horizontal"
        case .calendar: "calendar"
        }
    }
}

// MARK: - 订阅源类型

public enum NewsFeedKind: String, Codable, Sendable, CaseIterable {
    case jin10Flash          // 金十快讯
    case eastMoneyFlash      // 东财 7x24 快讯
    case eastMoneyResearch   // 东财研报
    case eastMoneyEarnings   // 东财财报日历
    case rss                 // 通用 RSS
}

// MARK: - 订阅源

public struct NewsFeed: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var category: NewsFeedCategory
    public var kind: NewsFeedKind
    public var url: String       // RSS 为链接；API 类为标识
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String, category: NewsFeedCategory,
                kind: NewsFeedKind, url: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.category = category
        self.kind = kind
        self.url = url
        self.enabled = enabled
    }
}

// MARK: - 预置订阅源

public enum NewsFeedCatalog {
    public static let all: [NewsFeed] = [
        // 快讯
        NewsFeed(name: "金十数据·快讯", category: .flash, kind: .jin10Flash, url: "jin10"),
        NewsFeed(name: "东方财富·7x24", category: .flash, kind: .eastMoneyFlash, url: "eastmoney"),
        // 研报
        NewsFeed(name: "东方财富·机构研报", category: .research, kind: .eastMoneyResearch, url: "eastmoney"),
        // 财报
        NewsFeed(name: "东方财富·业绩报表", category: .earnings, kind: .eastMoneyEarnings, url: "eastmoney"),
        // 日历（财报日历按公告日展示）
        NewsFeed(name: "东方财富·财报日历", category: .calendar, kind: .eastMoneyEarnings, url: "eastmoney-calendar"),
        // RSS（可选，默认关闭英文源）
        NewsFeed(name: "CNBC Top News", category: .flash, kind: .rss,
                 url: "https://www.cnbc.com/id/100003114/device/rss/rss.html", enabled: false),
        NewsFeed(name: "Reuters Business", category: .flash, kind: .rss,
                 url: "https://www.reutersagency.com/feed/?best-topics=business-finance&post_type=best", enabled: false),
    ]

    public static let importedFlagKey = "news_feeds_imported"
}

// MARK: - 数据源错误

public enum NewsSourceError: Error, LocalizedError, Sendable {
    case parseFailed(String)
    case notSupported(String)

    public var errorDescription: String? {
        switch self {
        case .parseFailed(let m): "资讯解析失败: \(m)"
        case .notSupported(let m): m
        }
    }
}

// MARK: - 源注册表

/// 按 kind 路由到对应数据源实现
public enum NewsSourceRegistry {

    public static func fetch(feed: NewsFeed, limit: Int = 30) async throws -> [NewsItem] {
        switch feed.kind {
        case .jin10Flash:
            return try await Jin10Source().fetch(limit: limit)
        case .eastMoneyFlash:
            return try await EastMoneyFlashSource().fetch(limit: limit)
        case .eastMoneyResearch:
            return try await EastMoneyResearchSource().fetch(limit: limit)
        case .eastMoneyEarnings:
            return try await EastMoneyEarningsSource().fetch(limit: limit)
        case .rss:
            guard let url = URL(string: feed.url) else {
                throw NewsSourceError.notSupported("无效的 RSS 地址")
            }
            return try await RSSParser.parse(url: url, sourceName: feed.name, limit: limit)
        }
    }
}
