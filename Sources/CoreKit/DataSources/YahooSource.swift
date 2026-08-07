import Foundation

/// Yahoo Finance 源：全球市场（美股/港股/日股/韩股/台股/A股）行情 + K线 + 搜索，免 Key。
/// 行情/K线接口: https://query1.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d&range=1y&crumb=xxx
/// 搜索接口:     https://query1.finance.yahoo.com/v1/finance/search?q=apple&crumb=xxx
/// 反爬：需先访问 fc.yahoo.com 种 cookie，再取 crumb，请求带 crumb。
public struct YahooSource: MarketDataSource, Sendable {
    public var name: String { "Yahoo Finance" }
    public var supportedMarkets: Set<Market> { [.us, .hk, .cn, .kr, .jp, .tw] }

    // crumb 缓存（5 分钟过期；非隔离静态变量，Swift 6 下标记 unsafe）
    nonisolated(unsafe) private static var cachedCrumb: String?
    nonisolated(unsafe) private static var crumbFetchedAt: Date?
    // 熔断：获取失败后 10 分钟内快速失败，避免每次等网络超时
    nonisolated(unsafe) private static var crumbFailedAt: Date?

    /// 获取 crumb（带 cookie 缓存；URLSession.shared 自动管理 cookie）
    /// 风控期拿不到 crumb 时快速失败（返回 nil），避免长时间等待
    private func crumb() async throws -> String? {
        if let c = Self.cachedCrumb,
           let at = Self.crumbFetchedAt,
           Date().timeIntervalSince(at) < 300 {
            return c
        }
        // 熔断：之前失败过则直接快速失败
        if let f = Self.crumbFailedAt, Date().timeIntervalSince(f) < 600 {
            return nil
        }
        // 1. 访问首页种 cookie（快速失败，不等超时）
        if let fc = URL(string: "https://fc.yahoo.com") {
            var request = URLRequest(url: fc)
            request.timeoutInterval = 5
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                             forHTTPHeaderField: "User-Agent")
            _ = try? await URLSession.shared.data(for: request)
        }
        // 2. 取 crumb（快速失败）
        if let crumbURL = URL(string: "https://query1.finance.yahoo.com/v1/test/getcrumb") {
            var request = URLRequest(url: crumbURL)
            request.timeoutInterval = 6
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                             forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                let c = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let c, !c.isEmpty {
                    Self.cachedCrumb = c
                    Self.crumbFetchedAt = Date()
                    Self.crumbFailedAt = nil
                    return c
                }
            }
        }
        // 获取失败 → 记录熔断时间
        Self.crumbFailedAt = Date()
        return Self.cachedCrumb
    }

    /// 给 URL 追加 crumb 参数；拿不到 crumb 时快速抛错（避免 chart 请求等超时）
    private func crumbedURL(_ base: String) async throws -> URL {
        guard var components = URLComponents(string: base) else {
            throw DataSourceError.invalidURL(base)
        }
        if let c = try? await crumb() {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "crumb", value: c))
            components.queryItems = items
            return components.url ?? URL(string: base)!
        }
        throw DataSourceError.notSupported("Yahoo 风控中（无法获取 crumb），暂不可用")
    }

    // MARK: 代码转换

    public func yahooCode(_ symbol: Symbol) -> String {
        switch symbol.market {
        case .us:
            return symbol.code.uppercased()
        case .hk:
            let c = symbol.code
                .replacingOccurrences(of: ".HK", with: "")
                .replacingOccurrences(of: ".hk", with: "")
            return "\(c).HK"
        case .cn:
            return symbol.code.hasPrefix("6") || symbol.code.hasPrefix("9")
                ? "\(symbol.code).SS" : "\(symbol.code).SZ"
        case .kr:
            return "\(symbol.code).KS"
        case .jp:
            return "\(symbol.code).T"
        case .tw:
            return "\(symbol.code).TW"
        default:
            return symbol.code
        }
    }

    // MARK: 行情（chart 接口 meta 含最新价）

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        let code = yahooCode(symbol)
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(code)?interval=1d&range=5d"
        guard let url = try? await crumbedURL(urlStr) else {
            throw DataSourceError.notSupported("Yahoo 暂不可用")
        }
        let chart = try await HTTP.getJSON(url, as: YahooChartResponse.self)
        guard let result = chart.chart?.result?.first,
              let meta = result.meta,
              let price = meta.regularMarketPrice, price > 0 else {
            throw DataSourceError.parseFailed("Yahoo 行情无数据: \(code)")
        }
        let prevClose = meta.chartPreviousClose ?? price
        let change = price - prevClose
        let changePercent = prevClose > 0 ? change / prevClose * 100 : 0
        return Quote(
            symbol: symbol,
            price: price,
            change: change,
            changePercent: changePercent,
            open: meta.regularMarketOpen ?? price,
            high: meta.regularMarketDayHigh ?? price,
            low: meta.regularMarketDayLow ?? price,
            prevClose: prevClose,
            volume: meta.regularMarketVolume ?? 0,
            timestamp: Date()
        )
    }

    // MARK: 搜索

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let urlStr = "https://query1.finance.yahoo.com/v1/finance/search?q=\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)"
        guard let url = try? await crumbedURL(urlStr) else {
            throw DataSourceError.notSupported("Yahoo 暂不可用")
        }
        let resp = try await HTTP.getJSON(url, as: YahooSearchResponse.self)
        var result: [Symbol] = []
        for q in resp.quotes ?? [] {
            guard let m = marketFromQuote(q) else { continue }
            if let market, m != market { continue }
            result.append(Symbol(market: m, code: q.symbol, name: q.shortname ?? q.longname ?? q.symbol))
            if result.count >= 10 { break }
        }
        return result
    }

    private func marketFromQuote(_ q: YahooSearchResponse.Quote) -> Market? {
        let qt = q.quoteType ?? ""
        let exch = q.exchDisp ?? ""
        if qt == "CRYPTOCURRENCY" { return .crypto }
        if exch.contains("HK") { return .hk }
        if exch.contains("TSE") && q.symbol.hasSuffix(".T") { return .jp }
        if exch.contains("KSC") || exch.contains("Korea") { return .kr }
        if exch.contains("TPE") || exch.contains("Taiwan") { return .tw }
        if exch.contains("SSE") || exch.contains("SHE") || q.symbol.hasSuffix(".SS") || q.symbol.hasSuffix(".SZ") { return .cn }
        return .us
    }

    // MARK: K线

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        let code = yahooCode(symbol)
        let (interval, range): (String, String)
        switch period {
        case .day:  (interval, range) = ("1d", "2y")     // ~500 根日线
        case .week: (interval, range) = ("1wk", "10y")
        case .month:(interval, range) = ("1mo", "max")
        case .year:  (interval, range) = ("1mo", "max") // 年K由注册表聚合
        case .m5:   (interval, range) = ("5m", "1d")
        }
        let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(code)?interval=\(interval)&range=\(range)"
        guard let url = try? await crumbedURL(urlStr) else {
            throw DataSourceError.notSupported("Yahoo 暂不可用")
        }
        let chart = try await HTTP.getJSON(url, as: YahooChartResponse.self)
        guard let result = chart.chart?.result?.first,
              let timestamps = result.timestamp,
              let quoteArr = result.indicators?.quote?.first else {
            throw DataSourceError.parseFailed("Yahoo K线无数据: \(code)")
        }
        var bars: [KLineBar] = []
        for (i, ts) in timestamps.enumerated() {
            guard i < quoteArr.open?.count ?? 0,
                  let open = quoteArr.open?[i],
                  let high = quoteArr.high?[i],
                  let low = quoteArr.low?[i],
                  let close = quoteArr.close?[i],
                  open > 0, close > 0 else { continue }
            let volume = quoteArr.volume?[i] ?? 0
            bars.append(KLineBar(symbolId: symbol.id, period: period,
                                 time: Date(timeIntervalSince1970: ts),
                                 open: open, high: high, low: low, close: close,
                                 volume: volume))
        }
        return Array(bars.suffix(limit))
    }
}

// MARK: - Yahoo JSON 结构

struct YahooChartResponse: Decodable {
    struct Chart: Decodable {
        struct Result: Decodable {
            struct Meta: Decodable {
                let regularMarketPrice: Double?
                let chartPreviousClose: Double?
                let regularMarketOpen: Double?
                let regularMarketDayHigh: Double?
                let regularMarketDayLow: Double?
                let regularMarketVolume: Double?
                let currency: String?
            }
            struct Indicators: Decodable {
                struct Quote: Decodable {
                    let open: [Double?]?
                    let high: [Double?]?
                    let low: [Double?]?
                    let close: [Double?]?
                    let volume: [Double?]?
                }
                let quote: [Quote]?
            }
            let meta: Meta?
            let timestamp: [Double]?
            let indicators: Indicators?
        }
        let result: [Result]?
    }
    let chart: Chart?
}

struct YahooSearchResponse: Decodable {
    struct Quote: Decodable {
        let symbol: String
        let shortname: String?
        let longname: String?
        let quoteType: String?
        let exchDisp: String?
    }
    let quotes: [Quote]?
}
