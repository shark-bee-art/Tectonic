import Foundation

// MARK: - 交易记录导入解析（支持主流券商交易/流水导出：嘉信/盈透/富途/老虎等）

public struct ParsedTrade: Sendable, Identifiable {
    public var id: String { "\(date?.timeIntervalSince1970 ?? 0)-\(symbol)-\(direction)-\(quantity)-\(price)" }
    public var date: Date?
    public var symbol: String
    public var name: String
    public var direction: String     // "buy" / "sell"
    public var quantity: Double
    public var price: Double
    public var fee: Double
    public var market: Market
    public var assetType: AssetType

    public init(date: Date? = nil, symbol: String, name: String, direction: String,
                quantity: Double, price: Double, fee: Double = 0,
                market: Market = .us, assetType: AssetType = .stock) {
        self.date = date
        self.symbol = symbol
        self.name = name
        self.direction = direction
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.market = market
        self.assetType = assetType
    }
}

public enum TradeCSVParser {

    /// 解析券商交易 CSV → 交易列表（自动识别嘉信 Action / IBKR / 富途等表头）
    public static func parse(_ text: String) -> [ParsedTrade] {
        let result = RobustCSV.parse(text)
        let headers = result.headers
        let rows = result.rows
        guard !headers.isEmpty else { return [] }

        // 列识别
        let actionIdx = headers.firstIndex(where: { ["action", "operation", "方向", "交易类型", "type", "买卖"].contains($0) })
        let dateIdx = headers.firstIndex(where: { ["date", "日期", "trade date", "time", "settlement date", "transaction date"].contains($0) })
        let symbolIdx = headers.firstIndex(where: { ["symbol", "ticker", "code", "代码", "证券代码", "instrument", "contract"].contains($0) })
        let nameIdx = headers.firstIndex(where: { ["description", "name", "名称", "证券名称", "asset description"].contains($0) })
        let qtyIdx = headers.firstIndex(where: { ["quantity", "qty", "shares", "数量", "成交数量", "amount"].contains($0) })
        let priceIdx = headers.firstIndex(where: { ["price", "成交价", "价格", "fill price", "avg price"].contains($0) })
        let feeIdx = headers.firstIndex(where: { ["fees", "fee", "commission", "手续费", "佣金", "费用"].contains($0) })
        let amountIdx = headers.firstIndex(where: { ["amount", "金额", "total", "net amount", "proceeds"].contains($0) })

        // 必须至少有代码列 + (数量或金额)
        guard let symIdx = symbolIdx else { return [] }
        let hasQty = qtyIdx != nil
        let hasAmount = amountIdx != nil
        guard hasQty || hasAmount else { return [] }

        var trades: [ParsedTrade] = []
        for row in rows {
            guard symIdx < row.count else { continue }
            let symbolRaw = row[symIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !symbolRaw.isEmpty else { continue }

            // 方向：Action 列 / 金额正负推断
            var direction: String?
            if let ai = actionIdx, ai < row.count {
                direction = inferDirection(row[ai])
            }
            if direction == nil, let ami = amountIdx, ami < row.count,
               let amt = RobustCSV.cleanNumber(row[ami]) {
                direction = amt >= 0 ? "buy" : "sell"
            }
            guard let dir = direction else { continue }

            // 数量与价格（卖出常为负数，取绝对值）
            var quantity: Double? = qtyIdx.flatMap { $0 < row.count ? RobustCSV.cleanNumber(row[$0]) : nil }
                .map { abs($0) }
            var price: Double? = priceIdx.flatMap { $0 < row.count ? RobustCSV.cleanNumber(row[$0]) : nil }
                .map { abs($0) }
            // 数量缺失时从金额/价格推算（期权等）
            if quantity == nil || quantity == 0, let ami = amountIdx, ami < row.count,
               let amt = RobustCSV.cleanNumber(row[ami]) {
                if let p = price, p > 0 {
                    quantity = abs(amt) / p
                }
            }
            // 金额缺失时从数量×价格算
            if let q = quantity, price == nil, let ami = amountIdx, ami < row.count,
               let amt = RobustCSV.cleanNumber(row[ami]), q > 0 {
                price = abs(amt) / q
            }
            guard let q = quantity, q > 0, let p = price, p > 0 else { continue }

            let fee = feeIdx.flatMap { $0 < row.count ? (RobustCSV.cleanNumber(row[$0]) ?? 0) : nil } ?? 0
            let date = dateIdx.flatMap { $0 < row.count ? parseDate(row[$0]) : nil }
            let name = nameIdx.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil } ?? symbolRaw
            let market = RobustCSV.inferMarket(symbolRaw)
            let assetType: AssetType = market == .crypto ? .crypto : (market == .fund ? .fund : .stock)

            trades.append(ParsedTrade(date: date, symbol: symbolRaw, name: name,
                                      direction: dir, quantity: q, price: p, fee: fee,
                                      market: market, assetType: assetType))
        }
        return trades
    }

    /// 方向识别（嘉信 Action：Buy/Buy to Open/Sell/Bought/Sold 等）
    static func inferDirection(_ s: String) -> String? {
        let up = s.uppercased()
        if up.contains("BUY") || up.contains("BOUGHT") || up.contains("买入") || up.contains("买") { return "buy" }
        if up.contains("SELL") || up.contains("SOLD") || up.contains("卖出") || up.contains("卖") { return "sell" }
        return nil
    }

    /// 多格式日期解析（嘉信 MM/dd/yyyy、ISO、中文等）
    public static func parseDate(_ s: String) -> Date? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "yyyy/MM/dd", "yyyy-MM-dd HH:mm:ss",
                       "MM/dd/yyyy HH:mm", "yyyy年M月d日", "dd-MM-yyyy", "yyyyMMdd"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats {
            f.dateFormat = fmt
            if let d = f.date(from: cleaned) { return d }
        }
        return nil
    }
}
