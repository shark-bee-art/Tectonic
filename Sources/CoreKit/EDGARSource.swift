import Foundation

// MARK: - 基本面数据模型（SEC EDGAR 来源）

/// 标的的基本面数据（SEC EDGAR XBRL，仅美股）。
/// 利润表指标取「最近财年」（duration，end-start≈365天）；资产负债表/股本取「最新报告期」（instant）。
public struct FundamentalData: Codable, Sendable, Identifiable {
    public var id: String { symbol.id }
    public let symbol: Symbol

    // 利润表（最近财年）
    public let revenue: Double?          // 营收
    public let netIncome: Double?        // 净利润
    public let operatingIncome: Double?  // 营业利润
    public let grossProfit: Double?      // 毛利
    public let eps: Double?              // 基本每股收益
    public let revenueYear: String?      // 财年截止日，如 "2025-09-27"

    // 资产负债表（最新报告期）
    public let assets: Double?           // 总资产
    public let liabilities: Double?      // 总负债
    public let equity: Double?           // 股东权益
    public let sharesOutstanding: Double? // 流通股数
    public let balanceDate: String?      // 资产负债表日

    public let fetchedAt: Date

    public init(symbol: Symbol, revenue: Double?, netIncome: Double?, operatingIncome: Double?,
                grossProfit: Double?, eps: Double?, revenueYear: String?, assets: Double?,
                liabilities: Double?, equity: Double?, sharesOutstanding: Double?,
                balanceDate: String?, fetchedAt: Date = Date()) {
        self.symbol = symbol
        self.revenue = revenue
        self.netIncome = netIncome
        self.operatingIncome = operatingIncome
        self.grossProfit = grossProfit
        self.eps = eps
        self.revenueYear = revenueYear
        self.assets = assets
        self.liabilities = liabilities
        self.equity = equity
        self.sharesOutstanding = sharesOutstanding
        self.balanceDate = balanceDate
        self.fetchedAt = fetchedAt
    }

    // MARK: 派生指标

    /// 净资产收益率 ROE = 净利 / 股东权益
    public var roe: Double? {
        guard let ni = netIncome, let eq = equity, eq != 0 else { return nil }
        return ni / eq * 100
    }

    /// 资产负债率 = 负债 / 总资产
    public var debtRatio: Double? {
        guard let l = liabilities, let a = assets, a != 0 else { return nil }
        return l / a * 100
    }

    /// 市盈率 PE = 现价 / EPS
    public func pe(price: Double) -> Double? {
        guard let e = eps, e > 0, price > 0 else { return nil }
        return price / e
    }

    /// 市净率 PB = 市值 / 净资产 = 现价×流通股 / 股东权益
    public func pb(price: Double) -> Double? {
        guard let s = sharesOutstanding, let eq = equity, eq != 0, price > 0 else { return nil }
        return price * s / eq
    }
}

// MARK: - SEC EDGAR 数据源（官方，S级合规：声明 UA + 10 req/s）

/// SEC EDGAR XBRL 基本面数据源。
/// - 合规：UA 必须为「公司名 邮箱」格式，否则 Undeclared Automated Tool 拒绝；限速 10 req/s（actor 串行天然满足）。
/// - 数据：company_tickers.json（ticker→CIK 映射）+ companyfacts（单公司全量 XBRL 指标）。
public actor EDGARSource {
    public static let shared = EDGARSource()

    private let userAgent = "Tectonic research@example.com"
    private let tickersURL = URL(string: "https://www.sec.gov/files/company_tickers.json")!
    private let factsBase = "https://data.sec.gov/api/xbrl/companyfacts/"

    /// 内存缓存：ticker → CIK
    private var cikMap: [String: Int]?
    /// 内存缓存：ticker → companyfacts 原始 JSON（同一会话内不重复拉）
    private var factsCache: [String: [String: Any]] = [:]

    public init() {}

    // MARK: 公开接口

    /// 拉取美股标的基本面数据。非美股抛 notSupported。
    public func fundamental(for symbol: Symbol) async throws -> FundamentalData {
        guard symbol.market == .us else {
            throw DataSourceError.notSupported("SEC EDGAR 仅支持美股")
        }
        let ticker = Self.normalizeTicker(symbol.code)
        let cik = try await cik(for: ticker)
        let facts = try await companyFacts(cik: cik, ticker: ticker)
        return try Self.parse(facts, symbol: symbol)
    }

    // MARK: 内部

    /// ticker 归一化：大写、去点（BRK.B → BRK-B? EDGAR 映射表用 BRK-B）、去空格
    static func normalizeTicker(_ raw: String) -> String {
        let upper = raw.uppercased().trimmingCharacters(in: .whitespaces)
        // EDGAR company_tickers.json 中 BRK.B 记为 BRK-B（点转横线）
        return upper.replacingOccurrences(of: ".", with: "-")
    }

    private func cik(for ticker: String) async throws -> Int {
        if let map = cikMap, let cik = map[ticker] {
            return cik
        }
        let data = try await HTTP.get(tickersURL, timeout: 30)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DataSourceError.parseFailed("company_tickers.json 顶层非字典")
        }
        var map: [String: Int] = [:]
        map.reserveCapacity(json.count)
        for (_, v) in json {
            guard let entry = v as? [String: Any],
                  let t = entry["ticker"] as? String,
                  let cik = entry["cik_str"] as? Int else { continue }
            map[t.uppercased()] = cik
        }
        self.cikMap = map
        guard let cik = map[ticker] else {
            throw DataSourceError.emptyData("SEC EDGAR 无 ticker \(ticker) 的 CIK 映射")
        }
        return cik
    }

    private func companyFacts(cik: Int, ticker: String) async throws -> [String: Any] {
        if let cached = factsCache[ticker] {
            return cached
        }
        let padded = String(format: "%010d", cik)
        let url = URL(string: factsBase + "CIK\(padded).json")!
        let data = try await HTTP.get(url, timeout: 60)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DataSourceError.parseFailed("companyfacts 顶层非字典")
        }
        factsCache[ticker] = json
        return json
    }

    // MARK: 解析

    static func parse(_ facts: [String: Any], symbol: Symbol) throws -> FundamentalData {
        guard let top = facts["facts"] as? [String: Any],
              let gaap = top["us-gaap"] as? [String: Any] else {
            throw DataSourceError.parseFailed("companyfacts 缺 facts.us-gaap")
        }

        // duration 指标（利润表）：最近财年（end-start ∈ [330,400] 天）
        let revenue = latestAnnual(gaap, tag: "RevenueFromContractWithCustomerExcludingAssessedTax")
        let netIncome = latestAnnual(gaap, tag: "NetIncomeLoss")
        let operatingIncome = latestAnnual(gaap, tag: "OperatingIncomeLoss")
        let grossProfit = latestAnnual(gaap, tag: "GrossProfit")
        let eps = latestAnnual(gaap, tag: "EarningsPerShareBasic")

        // instant 指标（资产负债表/股本）：最新报告期
        let assets = latestInstant(gaap, tag: "Assets")
        let liabilities = latestInstant(gaap, tag: "Liabilities")
        let equity = latestInstant(gaap, tag: "StockholdersEquity")
        let shares = latestInstant(gaap, tag: "CommonStockSharesOutstanding")

        return FundamentalData(
            symbol: symbol,
            revenue: revenue?.value,
            netIncome: netIncome?.value,
            operatingIncome: operatingIncome?.value,
            grossProfit: grossProfit?.value,
            eps: eps?.value,
            revenueYear: revenue?.date,
            assets: assets?.value,
            liabilities: liabilities?.value,
            equity: equity?.value,
            sharesOutstanding: shares?.value,
            balanceDate: assets?.date
        )
    }

    /// 提取某标签的「最近财年」duration 值（单位取第一个非空 unit）。
    static func latestAnnual(_ gaap: [String: Any], tag: String) -> (value: Double, date: String)? {
        guard let concept = gaap[tag] as? [String: Any],
              let units = concept["units"] as? [String: Any] else { return nil }
        var best: (Double, String, Int)?  // (val, end, endDaysFrom2000)
        for (_, arrAny) in units {
            guard let arr = arrAny as? [[String: Any]] else { continue }
            for entry in arr {
                guard let start = entry["start"] as? String,
                      let end = entry["end"] as? String,
                      let val = entry["val"] as? Double else { continue }
                let days = daysBetween(start, end)
                guard days >= 330, days <= 400 else { continue }
                let key = daysFrom2000(end)
                if best == nil || key > best!.2 {
                    best = (val, end, key)
                }
            }
        }
        guard let b = best else { return nil }
        return (b.0, b.1)
    }

    /// 提取某标签的「最新报告期」instant 值（无 start，取最近 end）。
    static func latestInstant(_ gaap: [String: Any], tag: String) -> (value: Double, date: String)? {
        guard let concept = gaap[tag] as? [String: Any],
              let units = concept["units"] as? [String: Any] else { return nil }
        var best: (Double, String, Int)?
        for (_, arrAny) in units {
            guard let arr = arrAny as? [[String: Any]] else { continue }
            for entry in arr {
                guard let end = entry["end"] as? String,
                      let val = entry["val"] as? Double else { continue }
                let key = daysFrom2000(end)
                if best == nil || key > best!.2 {
                    best = (val, end, key)
                }
            }
        }
        guard let b = best else { return nil }
        return (b.0, b.1)
    }

    static func daysBetween(_ start: String, _ end: String) -> Int {
        daysFrom2000(end) - daysFrom2000(start)
    }

    /// "YYYY-MM-DD" → 距 2000-01-01 天数（纯整数比较，避免 DateFormatter 开销）
    static func daysFrom2000(_ s: String) -> Int {
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return 0 }
        var days = (y - 2000) * 365 + (y - 2000) / 4  // 近似闰年
        // 用固定月天数表（忽略闰年 2 月误差，仅用于排序/差窗，330~400 容差足够）
        let md = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        for i in 1..<m { days += md[i] }
        return days + d
    }
}
