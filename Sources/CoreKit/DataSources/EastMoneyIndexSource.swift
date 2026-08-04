import Foundation

/// 东方财富指数源：全球指数行情（日经225/台湾加权/恒生等），免费无 Key。
/// 接口: https://push2.eastmoney.com/api/qt/stock/get?secid=100.N225&fields=f57,f58,f43,f60,f170
/// 字段: f43=最新价×100  f60=昨收×100  f170=涨跌幅×100  f58=名称
public struct EastMoneyIndexSource: MarketDataSource, Sendable {
    public var name: String { "东方财富指数" }
    public var supportedMarkets: Set<Market> { [.jp, .tw, .hk] }

    /// code → 东财 secid
    private static let secids: [String: String] = [
        "N225": "100.N225",    // 日经225
        "TWII": "100.TWII",    // 台湾加权
        "HSI": "100.HSI",      // 恒生
        "DJI": "100.DJIA",     // 道琼斯
        "IXIC": "100.NDX",     // 纳斯达克100
        "SPX": "100.SPX",      // 标普500
    ]

    public init() {}

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        guard let secid = Self.secids[symbol.code.uppercased()] else {
            throw DataSourceError.notSupported("东财指数不支持: \(symbol.code)")
        }
        let urlStr = "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=f57,f58,f43,f60,f170"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataSourceError.httpError(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = json["data"] as? [String: Any],
              let rawPrice = item["f43"] as? Int else {
            throw DataSourceError.parseFailed("东财指数无数据: \(symbol.code)")
        }
        let price = Double(rawPrice) / 100
        guard price > 0 else {
            throw DataSourceError.parseFailed("东财指数价格异常: \(symbol.code)")
        }
        let prevClose = Double(item["f60"] as? Int ?? 0) / 100
        let changePercent = Double(item["f170"] as? Int ?? 0) / 100
        let name = item["f58"] as? String ?? symbol.code
        return Quote(
            symbol: Symbol(market: symbol.market, code: symbol.code, name: name),
            price: price,
            change: prevClose > 0 ? price - prevClose : 0,
            changePercent: prevClose > 0 ? changePercent : 0,
            open: prevClose,
            high: max(price, prevClose),
            low: min(price, prevClose),
            prevClose: prevClose,
            volume: 0,
            timestamp: Date()
        )
    }

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        // 指数代码精确匹配
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let market, market == .jp || market == .tw || market == .hk,
           Self.secids[trimmed] != nil {
            return [Symbol(market: market, code: trimmed, name: trimmed)]
        }
        return []
    }

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        // 东财指数K线接口（push2his）留待后续；技术面指标对指数暂不提供
        throw DataSourceError.notSupported("东财指数暂不提供K线")
    }
}
