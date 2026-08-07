import Foundation

/// Binance 加密源：USDT 交易对行情 + K线，免费无 Key。
/// 行情: https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT
/// K线: https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1d&limit=320
public struct BinanceSource: MarketDataSource, Sendable {
    public var name: String { "Binance" }
    public var supportedMarkets: Set<Market> { [.crypto] }

    private func symbol(_ code: String) -> String {
        code.uppercased()
    }

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        let sym = binanceSymbol(symbol.code)
        let urlStr = "https://api.binance.com/api/v3/ticker/24hr?symbol=\(sym)"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let t = try await HTTP.getJSON(url, as: BinanceTicker.self)
        guard let price = Double(t.lastPrice ?? ""), price > 0 else {
            throw DataSourceError.parseFailed("Binance 无价格: \(sym)")
        }
        let changePercent = Double(t.priceChangePercent ?? "") ?? 0
        let prevClose = changePercent > -99 ? price / (1 + changePercent / 100) : price
        return Quote(
            symbol: symbol,
            price: price,
            change: price - prevClose,
            changePercent: changePercent,
            open: Double(t.openPrice ?? "") ?? price,
            high: Double(t.highPrice ?? "") ?? price,
            low: Double(t.lowPrice ?? "") ?? price,
            prevClose: prevClose,
            volume: Double(t.volume ?? "") ?? 0,
            timestamp: Date()
        )
    }

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        // 只接受已含稳定币后缀的交易对（不自动拼接，避免垃圾结果）
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasSuffix("USDT") || trimmed.hasSuffix("USDC") || trimmed.hasSuffix("FDUSD") {
            return [Symbol(market: .crypto, code: trimmed, name: trimmed)]
        }
        return []
    }

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        let sym = binanceSymbol(symbol.code)
        let interval: String
        switch period {
        case .day: interval = "1d"
        case .week: interval = "1w"
        case .month: interval = "1M"
        case .year: interval = "1M" // 年K由注册表聚合
        case .m5: interval = "5m"
        }
        let urlStr = "https://api.binance.com/api/v3/klines?symbol=\(sym)&interval=\(interval)&limit=\(min(limit, 1000))"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let rows = try await HTTP.getJSON(url, as: [BinanceKline].self)
        var bars: [KLineBar] = []
        for row in rows {
            guard let open = Double(row.open),
                  let high = Double(row.high),
                  let low = Double(row.low),
                  let close = Double(row.close),
                  let volume = Double(row.volume) else { continue }
            bars.append(KLineBar(symbolId: symbol.id, period: period,
                                 time: Date(timeIntervalSince1970: row.openTime / 1000),
                                 open: open, high: high, low: low, close: close,
                                 volume: volume))
        }
        return bars
    }

    private func binanceSymbol(_ code: String) -> String {
        // 用户可能输入 btc → BTCUSDT
        let upper = code.uppercased()
        if upper.hasSuffix("USDT") || upper.hasSuffix("USDC") || upper.hasSuffix("FDUSD") {
            return upper
        }
        return upper + "USDT"
    }
}

struct BinanceTicker: Decodable {
    let lastPrice: String?
    let priceChangePercent: String?
    let openPrice: String?
    let highPrice: String?
    let lowPrice: String?
    let volume: String?
}

/// Binance K线行（非固定类型数组，手动 Decodable）
struct BinanceKline: Decodable {
    let openTime: Double
    let open: String
    let high: String
    let low: String
    let close: String
    let volume: String

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        openTime = try container.decode(Double.self)
        open = try container.decode(String.self)
        high = try container.decode(String.self)
        low = try container.decode(String.self)
        close = try container.decode(String.self)
        volume = try container.decode(String.self)
    }
}
