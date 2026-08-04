import Foundation

// MARK: - 数据源错误

public enum DataSourceError: Error, Sendable, LocalizedError {
    case invalidURL(String)
    case httpError(Int)
    case parseFailed(String)
    case notSupported(String)
    case emptyData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let u): "无效的 URL: \(u)"
        case .httpError(let code): "HTTP 错误: \(code)"
        case .parseFailed(let m): "解析失败: \(m)"
        case .notSupported(let m): "不支持: \(m)"
        case .emptyData(let m): "无数据: \(m)"
        }
    }
}

// MARK: - 数据源协议

/// 一个行情数据源适配器。每个市场通常有多个源，按注册表路由 + 兜底切换。
public protocol MarketDataSource: Sendable {
    var name: String { get }
    var supportedMarkets: Set<Market> { get }
    /// 仅用于搜索（不提供行情/K线），行情路由会跳过此类源
    var searchOnly: Bool { get }

    /// 拉取单个标的行情
    func fetchQuote(for symbol: Symbol) async throws -> Quote

    /// 批量拉取行情（腾讯等支持批量接口的源可覆盖，默认逐个拉）
    func fetchQuotes(for symbols: [Symbol]) async throws -> [Quote]

    /// 搜索标的
    func search(query: String, market: Market?) async throws -> [Symbol]

    /// K线
    func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar]
}

public extension MarketDataSource {
    var searchOnly: Bool { false }

    func fetchQuotes(for symbols: [Symbol]) async throws -> [Quote] {
        var result: [Quote] = []
        for s in symbols {
            if let q = try? await fetchQuote(for: s) {
                result.append(q)
            }
        }
        return result
    }
}

// MARK: - 网络基础

public enum HTTP {
    /// 带浏览器 UA 的 GET，返回 Data
    public static func get(_ url: URL, timeout: TimeInterval = 20) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataSourceError.httpError(http.statusCode)
        }
        return data
    }

    /// 带 UA 的 GET，按编码解码为 String
    public static func getString(_ url: URL, encoding: String.Encoding = .utf8,
                                 timeout: TimeInterval = 20) async throws -> String {
        let data = try await get(url, timeout: timeout)
        guard let s = String(data: data, encoding: encoding) else {
            throw DataSourceError.parseFailed("无法按 \(encoding) 解码响应")
        }
        return s
    }

    public static func getJSON<T: Decodable>(_ url: URL, as type: T.Type,
                                             timeout: TimeInterval = 20) async throws -> T {
        let data = try await get(url, timeout: timeout)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw DataSourceError.parseFailed("JSON 解码失败: \(error)")
        }
    }
}

// MARK: - 数据源注册表

/// 聚合所有数据源，按市场路由；支持多源兜底。
public final class MarketDataSourceRegistry: Sendable {
    public static let shared = MarketDataSourceRegistry()
    private let sources: [any MarketDataSource]

    private init() {
        sources = [
            EastMoneySearchSource(),
            TencentSource(),
            TwseSource(),
            YahooSource(),
            CoinGeckoSource(),
            BinanceSource(),
            FundSource(),
        ]
    }

    /// 某市场的所有可用源（按优先级顺序：数组中先注册的优先）；排除 searchOnly 源
    public func sources(for market: Market) -> [any MarketDataSource] {
        sources.filter { !$0.searchOnly && $0.supportedMarkets.contains(market) }
    }

    /// 所有参与搜索的源（含 searchOnly）
    public var searchSources: [any MarketDataSource] {
        sources
    }

    /// 带兜底的行情拉取：优先源失败时自动切换到下一个
    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        let candidates = sources(for: symbol.market)
        guard !candidates.isEmpty else {
            throw DataSourceError.notSupported("市场 \(symbol.market.displayName) 无数据源")
        }
        var lastError: Error?
        for source in candidates {
            do {
                return try await source.fetchQuote(for: symbol)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? DataSourceError.emptyData("所有数据源均失败")
    }

    public func fetchQuotes(for symbols: [Symbol]) async throws -> [Quote] {
        // 按市场分组，用各市场首选源批量拉
        var result: [Quote] = []
        for market in Market.allCases {
            let group = symbols.filter { $0.market == market }
            guard !group.isEmpty else { continue }
            let candidates = sources(for: market)
            if let first = candidates.first {
                if let quotes = try? await first.fetchQuotes(for: group) {
                    result.append(contentsOf: quotes)
                    continue
                }
            }
            // 兜底：逐个拉
            for s in group {
                if let q = try? await fetchQuote(for: s) {
                    result.append(q)
                }
            }
        }
        return result
    }

    public func search(query: String, market: Market? = nil) async throws -> [Symbol] {
        var found: [Symbol] = []
        for source in searchSources {
            if let market, !source.supportedMarkets.contains(market) { continue }
            if let r = try? await source.search(query: query, market: market) {
                found.append(contentsOf: r)
            }
        }
        return found
    }

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int = 320) async throws -> [KLineBar] {
        let candidates = sources(for: symbol.market)
        var lastError: Error?
        for source in candidates {
            do {
                let bars = try await source.fetchKLine(for: symbol, period: period, limit: limit)
                if !bars.isEmpty { return bars }
            } catch {
                lastError = error
            }
        }
        // 明确不支持优先抛出；限流类错误（Yahoo 403 等）转成友好提示
        if let e = lastError as? DataSourceError, case .notSupported = e {
            throw e
        }
        if let e = lastError as? DataSourceError, case .httpError = e {
            throw DataSourceError.notSupported("\(symbol.market.displayName) \(period.displayName) 数据源被限流，请稍后重试")
        }
        throw lastError ?? DataSourceError.emptyData("K线数据为空")
    }
}
