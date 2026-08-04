import Foundation

// MARK: - 联网搜索服务（AI 问询的联网能力）
// 方案：从内置 RSS 资讯源检索相关新闻（免费/无 key/财经相关）+ Wikipedia 通用知识兜底

public struct WebSearchResult: Sendable {
    public var title: String
    public var summary: String
    public var source: String
    public var date: Date?
}

public enum WebSearchService {

    /// 检索与问题相关的资讯（并发抓取启用源 RSS，标题/摘要关键词匹配）
    public static func search(query: String, feeds: [NewsFeed], limit: Int = 6) async -> [WebSearchResult] {
        let keywords = keywords(from: query)
        guard !keywords.isEmpty else { return [] }

        let categories: [NewsFeedCategory] = [.flash, .research, .earnings, .calendar]
        let enabledFeeds = feeds.filter { $0.enabled && categories.contains($0.category) }

        var results: [WebSearchResult] = []
        let collector = ResultCollector()

        await withTaskGroup(of: Void.self) { group in
            for feed in enabledFeeds.prefix(8) {
                group.addTask {
                    guard let url = URL(string: feed.url) else { return }
                    guard let items = try? await RSSParser.parse(url: url, sourceName: feed.name, limit: 25) else { return }
                    for item in items {
                        let haystack = "\(item.title) \(item.summary)".lowercased()
                        let matched = keywords.filter { haystack.contains($0) }.count
                        guard matched >= 1 else { continue }
                        await collector.append(WebSearchResult(title: item.title, summary: item.summary,
                                                               source: item.source, date: item.publishedAt))
                    }
                }
            }
        }
        results = await collector.all()

        // 排序：关键词命中数优先 + 时间新
        return results
            .sorted { a, b in
                let ka = keywords.filter { "\(a.title) \(a.summary)".lowercased().contains($0) }.count
                let kb = keywords.filter { "\(b.title) \(b.summary)".lowercased().contains($0) }.count
                if ka != kb { return ka > kb }
                return (a.date ?? .distantPast) > (b.date ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Wikipedia 通用知识兜底
    public static func wikipedia(query: String, limit: Int = 3) async -> [WebSearchResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let urlStr = "https://zh.wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encoded)&format=json&srlimit=\(limit)&utf8=1"
        guard let url = URL(string: urlStr) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = json["query"] as? [String: Any],
                  let search = query["search"] as? [[String: Any]] else { return [] }
            return search.compactMap { item in
                guard let title = item["title"] as? String else { return nil }
                let snippet = (item["snippet"] as? String ?? "")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&quot;", with: "\"")
                return WebSearchResult(title: title, summary: String(snippet.prefix(300)), source: "Wikipedia", date: nil)
            }
        } catch {
            return []
        }
    }

    /// 并发安全的收集器
    private actor ResultCollector {
        private var items: [WebSearchResult] = []

        func append(_ item: WebSearchResult) {
            if !items.contains(where: { $0.title == item.title }) {
                items.append(item)
            }
        }

        func all() -> [WebSearchResult] { items }
    }

    /// 从问题提取关键词（去停用词/标点，取有信息量的词）
    public static func keywords(from query: String) -> [String] {
        let stopwords: Set<String> = ["的", "了", "是", "在", "和", "与", "及", "或", "有", "我", "你", "他",
                                      "怎么", "如何", "什么", "为什么", "哪些", "哪个", "最近", "现在", "当前",
                                      "走势", "怎么样", "情况", "a", "an", "the", "is", "are", "was", "for",
                                      "and", "or", "of", "to", "in", "on", "at", "by", "with", "about",
                                      "how", "what", "why", "which", "when", "where"]
        // 英文大写代码（AAPL/BTC 等）与中文词保留
        var words: [String] = []
        let tokens = query.components(separatedBy: CharacterSet(charactersIn: " ，。,.?!？、:：;；()（）\"'“”"))
        for token in tokens {
            let t = token.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !stopwords.contains(t.lowercased()) else { continue }
            // 全大写英文（代码）或长度 >= 2 的词
            if t.count >= 2 || t.uppercased() == t {
                words.append(t.lowercased())
            }
        }
        return Array(words.prefix(6))
    }
}
