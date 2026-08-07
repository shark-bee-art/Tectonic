import Foundation

/// CoinGecko 加密源：主流币行情 + 搜索 + 日K OHLC，免费无 Key。
/// 价格: https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true
/// 搜索: https://api.coingecko.com/api/v3/search?query=btc
/// K线:  https://api.coingecko.com/api/v3/coins/bitcoin/ohlc?vs_currency=usd&days=365
public struct CoinGeckoSource: MarketDataSource, Sendable {
    public var name: String { "CoinGecko" }
    public var supportedMarkets: Set<Market> { [.crypto] }

    /// 常见交易对 → CoinGecko id 映射（BTCUSDT → bitcoin）
    private static let coinIDs: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana", "XRP": "ripple",
        "DOGE": "dogecoin", "ADA": "cardano", "BNB": "binancecoin",
        "USDT": "tether", "USDC": "usd-coin", "LTC": "litecoin",
        "DOT": "polkadot", "AVAX": "avalanche-2", "LINK": "chainlink",
        "MATIC": "matic-network", "POL": "polygon-ecosystem-token",
        "SHIB": "shiba-inu", "TRX": "tron", "ATOM": "cosmos",
        "ETC": "ethereum-classic", "UNI": "uniswap", "APT": "aptos",
        "ARB": "arbitrum", "OP": "optimism", "NEAR": "near",
        "FIL": "filecoin", "SUI": "sui", "INJ": "injective-protocol",
        "SEI": "sei-network", "TIA": "celestia", "ORDI": "ordinals",
        "WLD": "worldcoin-wld", "PEPE": "pepe", "FLOKI": "floki",
        "BONK": "bonk", "AAVE": "aave", "MKR": "maker",
        "GRT": "the-graph", "STX": "blockstack", "IMX": "immutable-x",
        "SAND": "the-sandbox", "MANA": "decentraland", "AXS": "axie-infinity",
        "GALA": "gala", "CRV": "curve-dao-token", "LDO": "lido-dao",
        "RNDR": "render-token", "FET": "fetch-ai", "AGIX": "singularitynet",
        "OCEAN": "ocean-protocol", "KAS": "kaspa", "QNT": "quant-network",
    ]

    /// BTCUSDT → btc → bitcoin
    public static func coinID(forCode code: String) -> String? {
        let upper = code.uppercased()
        var base = upper
        for suffix in ["USDT", "USDC", "USD", "BUSD", "FDUSD"] {
            if upper.hasSuffix(suffix), upper.count > suffix.count {
                base = String(upper.dropLast(suffix.count))
                break
            }
        }
        return coinIDs[base] ?? coinIDs[upper]
    }

    // MARK: 行情

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        guard let id = Self.coinID(forCode: symbol.code) else {
            throw DataSourceError.notSupported("CoinGecko 未知币种: \(symbol.code)")
        }
        let urlStr = "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd&include_24hr_change=true"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let json = try await HTTP.getJSON(url, as: [String: [String: Double]].self)
        guard let entry = json[id],
              let price = entry["usd"], price > 0 else {
            throw DataSourceError.parseFailed("CoinGecko 无价格: \(symbol.code)")
        }
        let changePercent = entry["usd_24h_change"] ?? 0
        let prevClose = changePercent >= -99 ? price / (1 + changePercent / 100) : price
        return Quote(
            symbol: symbol,
            price: price,
            change: price - prevClose,
            changePercent: changePercent,
            open: prevClose,
            high: price,
            low: price,
            prevClose: prevClose,
            volume: 0,
            timestamp: Date()
        )
    }

    // MARK: 搜索

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let urlStr = "https://api.coingecko.com/api/v3/search?query=\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let resp = try await HTTP.getJSON(url, as: CoinGeckoSearchResponse.self)
        var result: [Symbol] = []
        // 按市值排名过滤：只保留主流币，避免垃圾 token 混入搜索
        for coin in resp.coins ?? [] {
            let rank = coin.marketCapRank ?? Int.max
            guard rank <= 200 else { continue }
            let code = (coin.symbol ?? "").uppercased() + "USDT"
            result.append(Symbol(market: .crypto, code: code, name: coin.name ?? code))
            if result.count >= 5 { break }
        }
        return result
    }

    // MARK: K线（OHLC 只有日线；周/月由日线本地聚合）

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        guard let id = Self.coinID(forCode: symbol.code) else {
            throw DataSourceError.notSupported("CoinGecko 未知币种: \(symbol.code)")
        }
        guard period != .m5 else {
            throw DataSourceError.notSupported("CoinGecko 不支持分时")
        }
        let days: Int
        switch period {
        case .day: days = min(limit, 365)
        case .week: days = min(limit * 7, 730)
        case .month: days = min(limit * 30, 3650)
        case .year: days = min(limit * 365, 3650)
        case .m5: days = 1
        }
        let urlStr = "https://api.coingecko.com/api/v3/coins/\(id)/ohlc?vs_currency=usd&days=\(days)"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let rows = try await HTTP.getJSON(url, as: [[Double]].self)
        var bars: [KLineBar] = []
        for row in rows where row.count >= 5 {
            bars.append(KLineBar(symbolId: symbol.id, period: .day,
                                 time: Date(timeIntervalSince1970: row[0] / 1000),
                                 open: row[1], high: row[2], low: row[3], close: row[4],
                                 volume: 0))
        }
        switch period {
        case .day:
            return Array(bars.suffix(limit))
        case .week:
            return aggregate(bars, by: .weekOfYear).suffix(limit)
        case .month:
            return aggregate(bars, by: .month).suffix(limit)
        case .year:
            return aggregate(bars, by: .year).suffix(limit)
        case .m5:
            return []
        }
    }

    /// 日线聚合为周/月线
    private func aggregate(_ daily: [KLineBar], by unit: Calendar.Component) -> [KLineBar] {
        let cal = Calendar(identifier: .gregorian)
        var result: [KLineBar] = []
        var currentKey: Date?
        var group: [KLineBar] = []
        func flush() {
            guard let first = group.first, let last = group.last else { return }
            let period: KLinePeriod = unit == .weekOfYear ? .week : .month
            result.append(KLineBar(symbolId: first.symbolId, period: period,
                                   time: first.time,
                                   open: first.open,
                                   high: group.map(\.high).max() ?? first.high,
                                   low: group.map(\.low).min() ?? first.low,
                                   close: last.close,
                                   volume: group.reduce(0) { $0 + $1.volume }))
            group = []
        }
        for bar in daily {
            let key = cal.dateInterval(of: unit, for: bar.time)?.start ?? bar.time
            if let current = currentKey, current != key {
                flush()
            }
            currentKey = key
            group.append(bar)
        }
        flush()
        return result
    }
}

struct CoinGeckoSearchResponse: Decodable {
    struct Coin: Decodable {
        let id: String
        let symbol: String?
        let name: String?
        let marketCapRank: Int?
    }
    let coins: [Coin]?
}
