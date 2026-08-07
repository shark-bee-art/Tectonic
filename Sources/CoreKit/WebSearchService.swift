import Foundation

// MARK: - 联网搜索服务（AI 问询的联网能力）
// 主通道：用户自备搜索 API Key（Brave/Serper/Tavily，官网申请，同大模型提供商模式）
// 兜底：内置 RSS 资讯源关键词检索 + Wikipedia

public struct WebSearchResult: Sendable {
    public var title: String
    public var summary: String
    public var source: String
    public var date: Date?
}

public enum WebSearchService {

    /// 联网搜索主入口：配置了 API Key 走搜索服务商；否则回退 RSS 检索
    public static func search(query: String, feeds: [NewsFeed],
                              provider: SearchProvider, apiKey: String) async -> [WebSearchResult] {
        if !apiKey.isEmpty {
            if let results = await searchAPI(query: query, provider: provider, apiKey: apiKey),
               !results.isEmpty {
                return results
            }
        }
        return await searchRSS(query: query, feeds: feeds)
    }

    /// 搜索服务商 API（Brave / Serper / Tavily）
    static func searchAPI(query: String, provider: SearchProvider, apiKey: String) async -> [WebSearchResult]? {
        switch provider {
        case .brave:
            return await braveSearch(query: query, apiKey: apiKey)
        case .serper:
            return await serperSearch(query: query, apiKey: apiKey)
        case .tavily:
            return await tavilySearch(query: query, apiKey: apiKey)
        }
    }

    /// Brave Search API：GET /res/v1/web/search?q=，Header X-Subscription-Token
    static func braveSearch(query: String, apiKey: String) async -> [WebSearchResult]? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=8") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let web = json["web"] as? [String: Any],
                  let results = web["results"] as? [[String: Any]] else { return nil }
            return results.prefix(8).map { item in
                WebSearchResult(title: item["title"] as? String ?? "",
                                summary: item["description"] as? String ?? "",
                                source: item["url"] as? String ?? "Brave",
                                date: nil)
            }
        } catch {
            return nil
        }
    }

    /// Serper (Google) API：POST https://google.serper.dev/search，Header X-API-KEY
    static func serperSearch(query: String, apiKey: String) async -> [WebSearchResult]? {
        guard let url = URL(string: "https://google.serper.dev/search") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["q": query, "gl": "cn", "hl": "zh-cn", "num": 8])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let organic = json["organic"] as? [[String: Any]] else { return nil }
            return organic.prefix(8).map { item in
                WebSearchResult(title: item["title"] as? String ?? "",
                                summary: item["snippet"] as? String ?? "",
                                source: item["link"] as? String ?? "Google",
                                date: nil)
            }
        } catch {
            return nil
        }
    }

    /// Tavily API：POST https://api.tavily.com/search
    static func tavilySearch(query: String, apiKey: String) async -> [WebSearchResult]? {
        guard let url = URL(string: "https://api.tavily.com/search") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["api_key": apiKey, "query": query, "max_results": 8, "include_answer": false])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else { return nil }
            return results.prefix(8).map { item in
                WebSearchResult(title: item["title"] as? String ?? "",
                                summary: item["content"] as? String ?? "",
                                source: item["url"] as? String ?? "Tavily",
                                date: nil)
            }
        } catch {
            return nil
        }
    }

    /// 兜底：内置 RSS 资讯源关键词检索
    static func searchRSS(query: String, feeds: [NewsFeed], limit: Int = 6) async -> [WebSearchResult] {
        let keywords = keywords(from: query)
        guard !keywords.isEmpty else { return [] }

        let categories: [NewsFeedCategory] = [.flash, .calendar]
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
