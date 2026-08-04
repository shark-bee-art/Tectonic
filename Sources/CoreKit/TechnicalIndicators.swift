import Foundation

/// 技术面摘要：基于日K计算的关键指标
public struct TechnicalSummary: Codable, Sendable {
    public var currentPrice: Double
    public var support: Double?          // 支撑位（现价下方最近的极值聚类）
    public var resistance: Double?       // 阻力位（现价上方最近的极值聚类）
    public var sma20: Double?            // 20 日均线
    public var sma50: Double?            // 50 日均线
    public var sma200: Double?           // 200 日均线
    public var ytdChangePercent: Double? // 年初至今涨跌幅 %
    public var high52w: Double?          // 52 周最高
    public var low52w: Double?           // 52 周最低
    public var avgVolume20: Double       // 20 日均量
    public var barCount: Int             // 参与计算的 K线数
    public var period: String            // 数据周期描述（如「日K · 251 根」）

    public init(currentPrice: Double, support: Double? = nil, resistance: Double? = nil,
                sma20: Double? = nil, sma50: Double? = nil, sma200: Double? = nil,
                ytdChangePercent: Double? = nil, high52w: Double? = nil, low52w: Double? = nil,
                avgVolume20: Double = 0, barCount: Int = 0, period: String = "") {
        self.currentPrice = currentPrice
        self.support = support
        self.resistance = resistance
        self.sma20 = sma20
        self.sma50 = sma50
        self.sma200 = sma200
        self.ytdChangePercent = ytdChangePercent
        self.high52w = high52w
        self.low52w = low52w
        self.avgVolume20 = avgVolume20
        self.barCount = barCount
        self.period = period
    }
}

/// 技术指标计算（纯函数，可单测）
public enum TechnicalAnalyzer {

    /// 基于日K（建议 ≥260 根，覆盖 200 日均线 + 52 周 + YTD）计算技术面摘要
    public static func analyze(bars: [KLineBar]) -> TechnicalSummary {
        guard let last = bars.last else {
            return TechnicalSummary(currentPrice: 0)
        }
        let price = last.close
        let sorted = bars.sorted { $0.time < $1.time }

        let sma20 = sma(sorted, period: 20)
        let sma50 = sma(sorted, period: 50)
        let sma200 = sma(sorted, period: 200)
        let ytd = ytdChange(sorted, currentPrice: price)
        let high52w = sorted.suffix(260).map(\.high).max()
        let low52w = sorted.suffix(260).map(\.low).min()
        let avgVol = sorted.suffix(20).map(\.volume).reduce(0, +) / Double(max(sorted.suffix(20).count, 1))

        let (support, resistance) = supportResistance(sorted, currentPrice: price)

        return TechnicalSummary(
            currentPrice: price,
            support: support,
            resistance: resistance,
            sma20: sma20,
            sma50: sma50,
            sma200: sma200,
            ytdChangePercent: ytd,
            high52w: high52w,
            low52w: low52w,
            avgVolume20: avgVol,
            barCount: sorted.count,
            period: "日K · \(sorted.count) 根"
        )
    }

    // MARK: - 均线

    /// 简单移动平均（最近 n 根收盘）
    public static func sma(_ bars: [KLineBar], period: Int) -> Double? {
        let window = bars.suffix(period)
        guard window.count == period else { return nil }
        return window.map(\.close).reduce(0, +) / Double(period)
    }

    // MARK: - 年初至今

    /// YTD 涨跌幅：本年度第一个交易日收盘 → 最新收盘
    public static func ytdChange(_ bars: [KLineBar], currentPrice: Double) -> Double? {
        let cal = Calendar(identifier: .gregorian)
        let currentYear = cal.component(.year, from: Date())
        guard let firstOfYear = bars.first(where: { cal.component(.year, from: $0.time) == currentYear }) else {
            return nil
        }
        let base = firstOfYear.open
        guard base > 0 else { return nil }
        return (currentPrice - base) / base * 100
    }

    // MARK: - 支撑/阻力（极值聚类）

    /// 支撑/阻力：基于局部极值（fractal）聚类。
    /// - 局部极值：某根 K 线在 ±2 根窗口内最高（阻力候选）/最低（支撑候选）
    /// - 聚类：按价格排序，相邻极值差距 < 1.5% 合并取均值
    /// - 支撑 = 现价下方最近的聚类；阻力 = 现价上方最近的聚类
    public static func supportResistance(_ bars: [KLineBar], currentPrice: Double,
                                         lookback: Int = 60) -> (Double?, Double?) {
        let window = Array(bars.suffix(lookback))
        guard window.count >= 5 else { return (nil, nil) }

        var highs: [Double] = []
        var lows: [Double] = []
        for i in 2..<(window.count - 2) {
            let center = window[i]
            let prev2 = window[i-2], prev1 = window[i-1], next1 = window[i+1], next2 = window[i+2]
            if center.high >= prev2.high && center.high >= prev1.high
                && center.high >= next1.high && center.high >= next2.high {
                highs.append(center.high)
            }
            if center.low <= prev2.low && center.low <= prev1.low
                && center.low <= next1.low && center.low <= next2.low {
                lows.append(center.low)
            }
        }

        let resistance = nearestCluster(highs, currentPrice: currentPrice, below: false)
        let support = nearestCluster(lows, currentPrice: currentPrice, below: true)
        return (support, resistance)
    }

    /// 聚类并取现价附近最近的一个
    private static func nearestCluster(_ values: [Double], currentPrice: Double, below: Bool) -> Double? {
        guard !values.isEmpty else { return nil }
        // 按价格聚类（容差 1.5%）
        let sorted = values.sorted()
        var clusters: [Double] = []
        for v in sorted {
            if let last = clusters.last, abs(v - last) / last < 0.015 {
                clusters[clusters.count - 1] = (last + v) / 2
            } else {
                clusters.append(v)
            }
        }
        if below {
            // 现价下方最近的聚类
            return clusters.filter { $0 < currentPrice }.last
        } else {
            // 现价上方最近的聚类
            return clusters.filter { $0 > currentPrice }.first
        }
    }
}
