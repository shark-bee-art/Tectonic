import Foundation

/// 天天基金源：基金净值 + 净值历史（K线）+ 搜索，免费无 Key。
/// 净值: https://api.fund.eastmoney.com/f10/lsjz?fundCode=110022&pageIndex=1&pageSize=320 （需 Referer）
/// 搜索: https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=1&key=易方达
public struct FundSource: MarketDataSource, Sendable {
    public var name: String { "天天基金" }
    public var supportedMarkets: Set<Market> { [.fund] }

    /// 拉取最近 N 条净值（最新在前；接口每页固定 20 行，需翻页）
    private func fetchNavList(code: String, limit: Int) async throws -> [[String: Any]] {
        var all: [[String: Any]] = []
        var page = 1
        while all.count < limit && page <= 30 {
            let urlStr = "https://api.fund.eastmoney.com/f10/lsjz?fundCode=\(code)&pageIndex=\(page)&pageSize=20"
            guard let url = URL(string: urlStr) else {
                throw DataSourceError.invalidURL(urlStr)
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("http://fundf10.eastmoney.com/", forHTTPHeaderField: "Referer")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DataSourceError.httpError(http.statusCode)
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["Data"] as? [String: Any],
                  let list = dataDict["LSJZList"] as? [[String: Any]] else {
                throw DataSourceError.parseFailed("天天基金净值解析失败")
            }
            if list.isEmpty { break }
            all.append(contentsOf: list)
            page += 1
        }
        return Array(all.prefix(limit))
    }

    // MARK: 行情（最新净值）

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        let list = try await fetchNavList(code: symbol.code, limit: 3)
        guard let latest = list.first,
              let price = Double(latest["DWJZ"] as? String ?? ""), price > 0 else {
            throw DataSourceError.parseFailed("天天基金无净值: \(symbol.code)")
        }
        let changePercent = Double(latest["JZZZL"] as? String ?? "") ?? 0
        let prevClose = changePercent > -99 ? price / (1 + changePercent / 100) : price
        let name = "\(symbol.code)"   // 名称需额外查询；先显示代码
        return Quote(
            symbol: Symbol(market: .fund, code: symbol.code, name: name),
            price: price,
            change: price - prevClose,
            changePercent: changePercent,
            open: prevClose,
            high: max(price, prevClose),
            low: min(price, prevClose),
            prevClose: prevClose,
            volume: 0,
            timestamp: Date()
        )
    }

    // MARK: 搜索

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlStr = "https://fundsuggest.eastmoney.com/FundSearch/api/FundSearchAPI.ashx?m=1&key=\(encoded)"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let data = try await HTTP.get(url)
        // 返回 GBK 编码 JSON
        guard let text = String(data: data, encoding: .gb18030) ?? String(data: data, encoding: .utf8),
              let jsonData = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            throw DataSourceError.parseFailed("天天基金搜索失败")
        }
        var result: [Symbol] = []
        for item in arr {
            guard let code = item["CODE"] as? String,
                  let name = item["NAME"] as? String else { continue }
            result.append(Symbol(market: .fund, code: code, name: name))
            if result.count >= 10 { break }
        }
        return result
    }

    // MARK: K线（净值历史，日线）

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        guard period == .day else {
            throw DataSourceError.notSupported("天天基金仅支持净值日线")
        }
        let list = try await fetchNavList(code: symbol.code, limit: min(limit, 320))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var bars: [KLineBar] = []
        for item in list.reversed() {
            guard let dateStr = item["FSRQ"] as? String,
                  let date = formatter.date(from: dateStr),
                  let nav = Double(item["DWJZ"] as? String ?? "") else { continue }
            let change = Double(item["JZZZL"] as? String ?? "") ?? 0
            let prev = change > -99 ? nav / (1 + change / 100) : nav
            bars.append(KLineBar(symbolId: symbol.id, period: .day, time: date,
                                 open: prev, high: max(prev, nav), low: min(prev, nav),
                                 close: nav, volume: 0))
        }
        return bars
    }
}
