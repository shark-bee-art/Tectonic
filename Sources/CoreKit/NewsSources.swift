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

/// 资讯源全部使用 RSS（2.0/Atom）订阅，不依赖任何 API/爬虫
public enum NewsFeedKind: String, Codable, Sendable, CaseIterable {
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

// MARK: - 预置订阅源（全部为真实 RSS，来自 GitHub 主流合集验证）

public enum NewsFeedCatalog {
    public static let all: [NewsFeed] = [
        // 快讯（实时新闻）
        NewsFeed(name: "中新网·财经", category: .flash, kind: .rss,
                 url: "https://www.chinanews.com.cn/rss/finance.xml"),
        NewsFeed(name: "日经中文网", category: .flash, kind: .rss,
                 url: "https://cn.nikkei.com/rss.html"),
        NewsFeed(name: "钛媒体", category: .flash, kind: .rss,
                 url: "https://www.tmtpost.com/rss"),
        NewsFeed(name: "CNBC Top News", category: .flash, kind: .rss,
                 url: "https://www.cnbc.com/id/100003114/device/rss/rss.html"),
        NewsFeed(name: "MarketWatch Top", category: .flash, kind: .rss,
                 url: "https://feeds.marketwatch.com/marketwatch/topstories/"),
        NewsFeed(name: "CoinDesk", category: .flash, kind: .rss,
                 url: "https://www.coindesk.com/arc/outboundfeeds/rss/"),
        NewsFeed(name: "CoinTelegraph", category: .flash, kind: .rss,
                 url: "https://cointelegraph.com/rss"),
        NewsFeed(name: "The Block", category: .flash, kind: .rss,
                 url: "https://www.theblock.co/rss.xml"),
        NewsFeed(name: "Yahoo Finance 美股大盘", category: .flash, kind: .rss,
                 url: "https://feeds.finance.yahoo.com/rss/2.0/headline?s=^GSPC&region=US&lang=en-US"),
        NewsFeed(name: "Yahoo Finance 科技龙头", category: .flash, kind: .rss,
                 url: "https://feeds.finance.yahoo.com/rss/2.0/headline?s=AAPL,MSFT,NVDA,GOOGL,AMZN,TSLA&region=US&lang=en-US"),
        // 研报（机构/深度分析）
        NewsFeed(name: "Fortune", category: .research, kind: .rss,
                 url: "https://fortune.com/feed"),
        NewsFeed(name: "Forbes Business", category: .research, kind: .rss,
                 url: "https://www.forbes.com/business/feed/"),
        NewsFeed(name: "Seeking Alpha", category: .research, kind: .rss,
                 url: "https://seekingalpha.com/market_currents.xml"),
        // 财报（公司财报新闻）
        NewsFeed(name: "CNBC Earnings", category: .earnings, kind: .rss,
                 url: "https://www.cnbc.com/id/15839135/device/rss/rss.html"),
        // 日历（宏观/经济数据新闻）
        NewsFeed(name: "CNBC Economy", category: .calendar, kind: .rss,
                 url: "https://www.cnbc.com/id/20910258/device/rss/rss.html"),
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

/// 按 kind 路由到对应数据源实现（当前仅 RSS）
public enum NewsSourceRegistry {

    public static func fetch(feed: NewsFeed, limit: Int = 30) async throws -> [NewsItem] {
        guard let url = URL(string: feed.url) else {
            throw NewsSourceError.notSupported("无效的 RSS 地址")
        }
        return try await RSSParser.parse(url: url, sourceName: feed.name, limit: limit)
    }
}
