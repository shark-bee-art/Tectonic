import Foundation

/// 台湾证交所（TWSE）源：台股实时行情，免费无 Key（官方接口）。
/// 行情: https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=tse_2330.tw&json=1&delay=0
/// 字段: n=名称 c=代码 z=最新价 y=昨收 o=今开 h=最高 l=最低 tv=成交量(千股) tlong=时间戳(ms)
public struct TwseSource: MarketDataSource, Sendable {
    public var name: String { "台湾证交所" }
    public var supportedMarkets: Set<Market> { [.tw] }

    public init() {}

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        let code = symbol.code
            .replacingOccurrences(of: ".TW", with: "")
            .replacingOccurrences(of: ".tw", with: "")
        let urlStr = "https://mis.twse.com.tw/stock/api/getStockInfo.jsp?ex_ch=tse_\(code).tw&json=1&delay=0"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DataSourceError.httpError(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msgArray = json["msgArray"] as? [[String: Any]],
              let m = msgArray.first else {
            throw DataSourceError.parseFailed("TWSE 无数据: \(code)")
        }
        guard let price = Double(m["z"] as? String ?? ""), price > 0 else {
            throw DataSourceError.parseFailed("TWSE 无最新价: \(code)")
        }
        let prevClose = Double(m["y"] as? String ?? "") ?? price
        let name = m["n"] as? String ?? symbol.code
        let rawVolume = Double(m["tv"] as? String ?? "") ?? 0
        let ts = (m["tlong"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        return Quote(
            symbol: Symbol(market: .tw, code: code, name: name),
            price: price,
            change: price - prevClose,
            changePercent: prevClose > 0 ? (price - prevClose) / prevClose * 100 : 0,
            open: Double(m["o"] as? String ?? "") ?? price,
            high: Double(m["h"] as? String ?? "") ?? price,
            low: Double(m["l"] as? String ?? "") ?? price,
            prevClose: prevClose,
            volume: rawVolume * 1000,   // tv 单位千股
            timestamp: ts
        )
    }

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        // TWSE 无搜索接口；代码精确匹配
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".TW", with: "")
            .replacingOccurrences(of: ".tw", with: "")
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return [] }
        return [Symbol(market: .tw, code: trimmed, name: trimmed)]
    }

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        guard period == .day else {
            throw DataSourceError.notSupported("TWSE 仅支持日K（月线聚合可后续补充）")
        }
        let code = symbol.code
            .replacingOccurrences(of: ".TW", with: "")
            .replacingOccurrences(of: ".tw", with: "")
        // 每月约 20 个交易日；按需拉取最近 N 个月
        let months = max(min((limit / 20) + 2, 24), 2)
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"

        var bars: [KLineBar] = []
        let now = Date()
        for offset in 0..<months {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: now) else { continue }
            let comps = calendar.dateComponents([.year, .month], from: monthStart)
            let dateStr = String(format: "%04d%02d01", comps.year ?? 0, comps.month ?? 0)
            let urlStr = "https://www.twse.com.tw/exchangeReport/STOCK_DAY?response=json&date=\(dateStr)&stockNo=\(code)"
            guard let url = URL(string: urlStr) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                             forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["data"] as? [[Any]] else { continue }
            for row in rows where row.count >= 6 {
                guard let dateStr2 = row[0] as? String else { continue }
                // 民国纪年 "115/08/03" → 2026-08-03
                let parts = dateStr2.split(separator: "/")
                guard parts.count == 3,
                      let rocYear = Int(parts[0]),
                      let month = Int(parts[1]),
                      let day = Int(parts[2]) else { continue }
                let date = calendar.date(from: DateComponents(year: rocYear + 1911, month: month, day: day))
                // TWSE 数值带千分位逗号（"2,390.00"），先去除
                let clean = { (v: Any?) -> Double? in
                    guard let s = v as? String else { return nil }
                    return Double(s.replacingOccurrences(of: ",", with: ""))
                }
                guard let date,
                      let open = clean(row[3]),
                      let high = clean(row[4]),
                      let low = clean(row[5]),
                      let close = clean(row[6]) else { continue }
                let volume = clean(row[1]) ?? 0
                bars.append(KLineBar(symbolId: symbol.id, period: .day, time: date,
                                     open: open, high: high, low: low, close: close,
                                     volume: volume))
            }
        }
        let sorted = bars.sorted { $0.time < $1.time }
        return Array(sorted.suffix(limit))
    }
}
