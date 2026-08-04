import Foundation

/// 东方财富搜索源：中文名/代码/拼音搜索，覆盖 A股/港股/美股/日股/韩股/基金，免费无 Key。
/// 接口: https://searchapi.eastmoney.com/api/suggest/get?input=茅台&type=14
/// 返回带中文名（如 600519 → 贵州茅台，AAPL → 苹果），解决中文搜索问题。
public struct EastMoneySearchSource: MarketDataSource, Sendable {
    public var name: String { "东方财富搜索" }
    // 仅用于搜索；行情不从这里出
    public var supportedMarkets: Set<Market> { [.cn, .us, .hk, .jp, .kr, .tw, .fund] }
    public var searchOnly: Bool { true }

    public func fetchQuote(for symbol: Symbol) async throws -> Quote {
        throw DataSourceError.notSupported("东方财富搜索源不提供行情")
    }

    public func search(query: String, market: Market?) async throws -> [Symbol] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let urlStr = "https://searchapi.eastmoney.com/api/suggest/get?input=\(encoded)&type=14"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let resp = try await HTTP.getJSON(url, as: EastMoneySearchResponse.self)
        var result: [Symbol] = []
        for item in resp.quotationCodeTable?.data ?? [] {
            guard let m = marketFromClassify(item.classify ?? "") else { continue }
            if let market, m != market { continue }
            result.append(Symbol(market: m, code: item.code ?? "", name: item.name ?? item.code ?? ""))
            if result.count >= 10 { break }
        }
        return result
    }

    public func fetchKLine(for symbol: Symbol, period: KLinePeriod, limit: Int) async throws -> [KLineBar] {
        throw DataSourceError.notSupported("东方财富搜索源不提供K线")
    }

    /// Classify → Market 映射
    private func marketFromClassify(_ classify: String) -> Market? {
        switch classify {
        case "AStock": .cn
        case "UsStock": .us
        case "HK": .hk
        case "JPX": .jp
        case "KRX": .kr
        case "TWSE", "TW": .tw
        case "OTCFUND", "Fund": .fund
        default: nil
        }
    }
}

struct EastMoneySearchResponse: Decodable {
    struct Table: Decodable {
        struct Item: Decodable {
            let code: String?
            let name: String?
            let classify: String?

            enum CodingKeys: String, CodingKey {
                case code = "Code"
                case name = "Name"
                case classify = "Classify"
            }
        }
        let data: [Item]?

        enum CodingKeys: String, CodingKey {
            case data = "Data"
        }
    }
    let quotationCodeTable: Table?

    enum CodingKeys: String, CodingKey {
        case quotationCodeTable = "QuotationCodeTable"
    }
}
