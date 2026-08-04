import Foundation

/// 腾讯行情源：A股/港股/美股/日股/韩股实时行情 + K线，免费无 Key。
/// 行情接口: https://qt.gtimg.cn/q=sh600519,sz000001,hk00700,usAAPL,jp7203,kr005930 （GBK 编码，~ 分隔字段）
/// K线接口: https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=sh600519,day,,,320,qfq
public struct TencentSource: MarketDataSource, Sendable {
    public var name: String { "腾讯行情" }
    public var supportedMarkets: Set<Market> { [.cn, .hk, .us, .jp, .kr] }

    // MARK: 代码转换

    private func tencentCode(_ symbol: Symbol) -> String {
        switch symbol.market {
        case .cn:
            // 6/9 开头沪市，其余深市
            if symbol.code.hasPrefix("6") || symbol.code.hasPrefix("9") {
                return "sh\(symbol.code)"
            }
            return "sz\(symbol.code)"
        case .hk:
            let c = symbol.code
                .replacingOccurrences(of: ".HK", with: "")
                .replacingOccurrences(of: ".hk", with: "")
            return "hk\(c)"
        case .us:
            return "us\(symbol.code.uppercased())"
        case .jp:
            let c = symbol.code
                .replacingOccurrences(of: ".T", with: "")
                .replacingOccurrences(of: ".t", with: "")
            return "jp\(c)"
        case .kr:
            let c = symbol.code
                .replacingOccurrences(of: ".KS", with: "")
                .replacingOccurrences(of: ".ks", with: "")
            return "kr\(c)"
        default:
            return symbol.code
        }
    }

    // MARK: 行情

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        let quotes = try await fetchQuotes(for: [symbol])
        guard let q = quotes.first else {
            throw DataSourceError.emptyData("腾讯行情无数据: \(symbol.code)")
        }
        return q
    }

    public func fetchQuotes(for symbols: [Symbol]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        // 腾讯批量接口单次上限约 60 个，分块
        var result: [Quote] = []
        for chunk in symbols.chunked(by: 50) {
            let codes = chunk.map { tencentCode($0) }.joined(separator: ",")
            guard let url = URL(string: "https://qt.gtimg.cn/q=\(codes)") else {
                throw DataSourceError.invalidURL(codes)
            }
            let text = try await HTTP.getString(url, encoding: .gb18030)
            let symbolByCode = Dictionary(uniqueKeysWithValues: chunk.map { (tencentCode($0).lowercased(), $0) })
            for line in text.components(separatedBy: ";") {
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[line.index(line.startIndex, offsetBy: 2)..<eq]).lowercased()
                guard let symbol = symbolByCode[key] else { continue }
                let value = String(line[line.index(eq, offsetBy: 1)...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let f = value.components(separatedBy: "~")
                guard f.count > 34, let price = Double(f[3]), price > 0 else { continue }
                let prevClose = Double(f[4]) ?? price
                let change = price - prevClose
                let changePercent = prevClose > 0 ? change / prevClose * 100 : 0
                let rawVolume = Double(f[6]) ?? 0
                // A股成交量单位是「手」（×100 = 股），国际市场直接是股
                let volume = symbol.market == .cn ? rawVolume * 100 : rawVolume
                let displayName = f.count > 1 && !f[1].isEmpty ? f[1] : symbol.name
                let resolved = symbol.name == symbol.code ? Symbol(market: symbol.market, code: symbol.code, name: displayName) : symbol
                let quote = Quote(
                    symbol: resolved,
                    price: price,
                    change: change,
                    changePercent: changePercent,
                    open: Double(f[5]) ?? price,
                    high: Double(f[33]) ?? price,
                    low: Double(f[34]) ?? price,
                    prevClose: prevClose,
                    volume: volume
                )
                result.append(quote)
            }
        }
        return result
    }

    // MARK: 搜索

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        // 腾讯无公开搜索接口；A股/港股代码即查即得（按代码精确匹配）
        var result: [Symbol] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.isEmpty { return result }
        if let market, market == .cn {
            if trimmed.allSatisfy(\.isNumber), trimmed.count == 6 {
                result.append(Symbol(market: .cn, code: trimmed, name: trimmed))
            }
        } else if market == nil {
            if trimmed.allSatisfy(\.isNumber), trimmed.count == 6 {
                result.append(Symbol(market: .cn, code: trimmed, name: trimmed))
            }
            if trimmed.hasSuffix(".HK") || (trimmed.allSatisfy(\.isNumber) && trimmed.count == 5) {
                let code = trimmed.replacingOccurrences(of: ".HK", with: "")
                result.append(Symbol(market: .hk, code: code, name: code))
            }
        }
        return result
    }

    // MARK: K线

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        let code = tencentCode(symbol)
        let periodParam: String
        switch period {
        case .day: periodParam = "day"
        case .week: periodParam = "week"
        case .month: periodParam = "month"
        case .m5: periodParam = "m5"
        }
        let urlStr = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(code),\(periodParam),,,\(limit),qfq"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let data = try await HTTP.get(url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataDict = json?["data"] as? [String: Any],
              let item = dataDict[code] as? [String: Any] else {
            throw DataSourceError.parseFailed("腾讯K线结构异常")
        }
        // 前复权键: qfqday / qfqweek / qfqmonth / m5（m5 无 qfq 前缀）
        let key = period == .m5 ? "m5" : "qfq\(periodParam)"
        guard let rows = (item[key] as? [[Any]]) ?? (item[periodParam] as? [[Any]]) else {
            throw DataSourceError.parseFailed("腾讯K线无数据")
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = period == .m5 ? "yyyyMMddHHmm" : "yyyy-MM-dd"

        var bars: [KLineBar] = []
        for row in rows {
            guard row.count >= 6,
                  let timeStr = row[0] as? String,
                  let date = dateFormatter.date(from: timeStr),
                  let open = Double("\(row[1])"),
                  let close = Double("\(row[2])"),
                  let high = Double("\(row[3])"),
                  let low = Double("\(row[4])"),
                  let volume = Double("\(row[5])") else { continue }
            bars.append(KLineBar(symbolId: symbol.id, period: period, time: date,
                                 open: open, high: high, low: low, close: close,
                                 volume: volume))
        }
        return bars
    }
}

extension Array {
    /// 按最大长度分块
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension String.Encoding {
    /// GB18030（GBK 超集，腾讯接口用）
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
}
