import Foundation

// MARK: - 健壮 CSV 解析（参考成熟开源 Portfolio 工具的导入设计）

public enum CSVField: String, CaseIterable, Identifiable, Sendable {
    case symbol, name, quantity, costBasis, market, assetType
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .symbol: "代码 (symbol)"
        case .name: "名称 (name)"
        case .quantity: "数量 (quantity)"
        case .costBasis: "成本价 (cost)"
        case .market: "市场 (market)"
        case .assetType: "资产类别 (type)"
        }
    }
}

public struct CSVParseResult: Sendable {
    public let headers: [String]
    public let rows: [[String]]
    /// 自动识别的字段 → 列索引
    public var mapping: [CSVField: Int]
    /// 未识别列
    public var unmappedColumns: [String]
}

public enum RobustCSV {

    /// 解析 CSV 文本（RFC 4180：引号包裹、逗号内转义、\r\n 换行），自动嗅探分隔符
    public static func parse(_ text: String) -> CSVParseResult {
        let delimiter = sniffDelimiter(text)
        let raw = parseRows(text, delimiter: delimiter)
        guard var headers = raw.first else { return CSVParseResult(headers: [], rows: [], mapping: [:], unmappedColumns: []) }
        headers = headers.map { cleanHeader($0) }
        var rows = Array(raw.dropFirst())
        // 跳过完全空的行
        rows = rows.filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        // 列数不足的行补空
        let width = headers.count
        rows = rows.map { row in
            var r = row
            while r.count < width { r.append("") }
            return Array(r.prefix(width))
        }
        let mapping = mapHeaders(headers)
        let unmapped = headers.enumerated()
            .filter { (idx, _) in !mapping.values.contains(idx) }
            .map(\.element)
        return CSVParseResult(headers: headers, rows: rows, mapping: mapping, unmappedColumns: unmapped)
    }

    /// 嗅探分隔符：优先 tab，其次 ; ，默认 ,
    static func sniffDelimiter(_ text: String) -> Character {
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let counts = [",": firstLine.filter { $0 == "," }.count,
                      ";": firstLine.filter { $0 == ";" }.count,
                      "\t": firstLine.filter { $0 == "\t" }.count]
        if let tab = counts["\t"], tab > 0 { return "\t" }
        if let sem = counts[";"], sem > counts[","] ?? 0 { return ";" }
        return ","
    }

    /// RFC 4180 解析：支持引号、引号内逗号/换行/转义引号
    static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.append(c)
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case delimiter:
                    row.append(field)
                    field = ""
                case "\r":
                    if i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                case "\n":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    /// 清理表头（去引号/空白/小写）
    static func cleanHeader(_ h: String) -> String {
        h.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// 表头同义词大表 → 自动字段映射
    public static func mapHeaders(_ headers: [String]) -> [CSVField: Int] {
        let synonyms: [CSVField: [String]] = [
            .symbol: ["symbol", "ticker", "code", "证券代码", "代码", "股票代码", "标的代码", "ticker symbol", "symbol/name", "证券"],
            .name: ["name", "名称", "股票名称", "证券名称", "简称", "公司名称", "asset name"],
            .quantity: ["quantity", "qty", "shares", "数量", "持仓数量", "持股数量", "持仓", "余额", "amount", "position", "持仓量", "股数", "份数", "balance"],
            .costBasis: ["cost", "cost basis", "cost_basis", "costbasis", "average cost", "avg cost", "avgcost", "price", "成本价", "持仓成本", "成本", "平均成本", "成本价格", "买入成本", "成本均价", "持仓成本价", "单位成本", "average price"],
            .market: ["market", "exchange", "市场", "交易所", "地区", "marketplace"],
            .assetType: ["asset type", "type", "类型", "资产类别", "资产类型", "asset class", "security type"],
        ]
        var mapping: [CSVField: Int] = [:]
        for (field, keys) in synonyms {
            // 精确匹配优先
            if let idx = headers.firstIndex(where: { keys.contains($0) }) {
                mapping[field] = idx
            } else {
                // 模糊匹配：包含关系
                for (idx, h) in headers.enumerated() where mapping.values.contains(idx) == false {
                    let hc = h.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
                    if keys.contains(where: { $0.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "") == hc }) {
                        mapping[field] = idx
                        break
                    }
                }
            }
        }
        return mapping
    }

    /// 金额/数字清理：去货币符号、千分位逗号、百分号、空格
    public static func cleanNumber(_ s: String) -> Double? {
        var cleaned = s
            .replacingOccurrences(of: "HK$", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\"", with: "")
        if cleaned.hasSuffix("万") {
            cleaned = cleaned.replacingOccurrences(of: "万", with: "")
            return Double(cleaned).map { $0 * 10_000 }
        }
        return Double(cleaned)
    }

    /// 从行数据提取结构化持仓（自动映射）
    public static func extractHoldings(_ result: CSVParseResult, broker: String) -> [Holding] {
        var holdings: [Holding] = []
        guard let symIdx = result.mapping[.symbol] else { return [] }
        let qtyIdx = result.mapping[.quantity]
        let costIdx = result.mapping[.costBasis]
        let nameIdx = result.mapping[.name]
        let marketIdx = result.mapping[.market]
        let typeIdx = result.mapping[.assetType]

        for row in result.rows {
            guard symIdx < row.count else { continue }
            let codeRaw = row[symIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !codeRaw.isEmpty else { continue }

            // 数量：优先显式列；缺失时尝试从名称列数字推断（如 "AAPL 10"）失败则跳过
            var qty: Double? = nil
            if let qi = qtyIdx, qi < row.count { qty = cleanNumber(row[qi]) }
            var cost: Double? = nil
            if let ci = costIdx, ci < row.count { cost = cleanNumber(row[ci]) }

            // 成本缺失时用名称列兜底（部分券商只有 "名称 数量@价格"）
            if qty == nil || cost == nil {
                if let ni = nameIdx, ni < row.count {
                    let tokens = row[ni].split(whereSeparator: { $0 == "@" || $0 == " " || $0 == "x" || $0 == "×" })
                    if tokens.count >= 2, qty == nil { qty = cleanNumber(String(tokens[tokens.count - 2])) }
                    if tokens.count >= 1, cost == nil { cost = cleanNumber(String(tokens[tokens.count - 1])) }
                }
            }
            guard let q = qty, q > 0, let c = cost else { continue }

            let name = nameIdx.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? codeRaw
            let market: Market
            if let mi = marketIdx, mi < row.count {
                market = inferMarketFromString(row[mi]) ?? inferMarket(codeRaw)
            } else {
                market = inferMarket(codeRaw)
            }
            let assetType: AssetType
            if let ti = typeIdx, ti < row.count {
                assetType = inferAssetType(row[ti]) ?? .stock
            } else {
                assetType = market == .crypto ? .crypto : (market == .fund ? .fund : .stock)
            }
            holdings.append(Holding(symbol: Symbol(market: market, code: codeRaw, name: name),
                                    quantity: q, costBasis: c, broker: broker, assetType: assetType))
        }
        return holdings
    }

    static func inferMarketFromString(_ s: String) -> Market? {
        let up = s.uppercased()
        if up.contains("US") || up.contains("NASDAQ") || up.contains("NYSE") { return .us }
        if up.contains("HK") { return .hk }
        if up.contains("CN") || up.contains("SH") || up.contains("SZ") || up.contains("SS") { return .cn }
        if up.contains("JP") || up.contains("TOKYO") || up.contains("TSE") { return .jp }
        if up.contains("KR") || up.contains("KOSPI") { return .kr }
        if up.contains("TW") || up.contains("TAIWAN") { return .tw }
        return nil
    }

    static func inferAssetType(_ s: String) -> AssetType? {
        let up = s.uppercased()
        if up.contains("OPTION") || up.contains("期权") { return .option }
        if up.contains("BOND") || up.contains("债券") { return .bond }
        if up.contains("FUND") || up.contains("基金") || up.contains("ETF") { return .fund }
        if up.contains("CRYPTO") || up.contains("加密") || up.contains("COIN") || up.contains("TOKEN") { return .crypto }
        if up.contains("CURRENCY") || up.contains("货币") || up.contains("CASH") { return .currency }
        if up.contains("STOCK") || up.contains("股票") || up.contains("EQUITY") { return .stock }
        return nil
    }

    /// 从代码推断市场
    public static func inferMarket(_ code: String) -> Market {
        let up = code.uppercased()
        if up.hasSuffix(".HK") { return .hk }
        if up.hasSuffix(".T") || up.hasSuffix(".TSE") { return .jp }
        if up.hasSuffix(".KS") || up.hasSuffix(".KQ") { return .kr }
        if up.hasSuffix(".TW") { return .tw }
        if up.hasSuffix(".SS") || up.hasSuffix(".SZ") { return .cn }
        if up.hasSuffix("USDT") || up.hasSuffix("USDC") || up.hasSuffix("BTC") || up.hasSuffix("ETH") { return .crypto }
        if up.allSatisfy(\.isNumber), up.count == 6 {
            return up.hasPrefix("0") || up.hasPrefix("1") ? .fund : .cn
        }
        return .us
    }
}
