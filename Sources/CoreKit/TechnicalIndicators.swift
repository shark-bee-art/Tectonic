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
    public var rsi14: Double?            // RSI(14)
    public var macdDIF: Double?          // MACD DIF（快线-慢线）
    public var macdDEA: Double?          // MACD DEA（信号线）
    public var macdHistogram: Double?    // MACD 柱（(DIF-DEA)×2）
    public var bollUpper: Double?        // 布林上轨（MA20+2σ）
    public var bollMid: Double?          // 布林中轨（MA20）
    public var bollLower: Double?        // 布林下轨（MA20-2σ）
    public var kdjK: Double?             // KDJ K
    public var kdjD: Double?             // KDJ D
    public var kdjJ: Double?             // KDJ J
    public var rangePosition52w: Double? // 现价在 52 周区间位置 %（0-100）
    public var barCount: Int             // 参与计算的 K线数
    public var period: String            // 数据周期描述（如「日K · 251 根」）

    public init(currentPrice: Double, support: Double? = nil, resistance: Double? = nil,
                sma20: Double? = nil, sma50: Double? = nil, sma200: Double? = nil,
                ytdChangePercent: Double? = nil, high52w: Double? = nil, low52w: Double? = nil,
                avgVolume20: Double = 0, rsi14: Double? = nil,
                macdDIF: Double? = nil, macdDEA: Double? = nil, macdHistogram: Double? = nil,
                bollUpper: Double? = nil, bollMid: Double? = nil, bollLower: Double? = nil,
                kdjK: Double? = nil, kdjD: Double? = nil, kdjJ: Double? = nil,
                rangePosition52w: Double? = nil,
                barCount: Int = 0, period: String = "") {
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
        self.rsi14 = rsi14
        self.macdDIF = macdDIF
        self.macdDEA = macdDEA
        self.macdHistogram = macdHistogram
        self.bollUpper = bollUpper
        self.bollMid = bollMid
        self.bollLower = bollLower
        self.kdjK = kdjK
        self.kdjD = kdjD
        self.kdjJ = kdjJ
        self.rangePosition52w = rangePosition52w
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

        // 动量指标
        let rsi14 = rsi(sorted, period: 14)
        let (dif, dea, hist) = macd(sorted)
        let (bollU, bollM, bollL) = bollinger(sorted, period: 20, multiplier: 2)
        let (k, d, j) = kdj(sorted)
        let rangePos: Double? = {
            guard let h = high52w, let l = low52w, h > l else { return nil }
            return (price - l) / (h - l) * 100
        }()

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
            rsi14: rsi14,
            macdDIF: dif,
            macdDEA: dea,
            macdHistogram: hist,
            bollUpper: bollU,
            bollMid: bollM,
            bollLower: bollL,
            kdjK: k,
            kdjD: d,
            kdjJ: j,
            rangePosition52w: rangePos,
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

    // MARK: - RSI（Wilder 平滑）

    /// RSI：相对强弱指标，14 周期 Wilder 平滑
    public static func rsi(_ bars: [KLineBar], period: Int = 14) -> Double? {
        let closes = bars.map(\.close)
        guard closes.count > period else { return nil }
        var gains: Double = 0
        var losses: Double = 0
        for i in 1...period {
            let diff = closes[i] - closes[i - 1]
            if diff >= 0 { gains += diff } else { losses -= diff }
        }
        var avgGain = gains / Double(period)
        var avgLoss = losses / Double(period)
        for i in (period + 1)..<closes.count {
            let diff = closes[i] - closes[i - 1]
            avgGain = (avgGain * Double(period - 1) + max(diff, 0)) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + max(-diff, 0)) / Double(period)
        }
        guard avgLoss > 0 else { return 100 }   // 全涨 → RSI 100
        let rs = avgGain / avgLoss
        return 100 - 100 / (1 + rs)
    }

    // MARK: - MACD（12, 26, 9）

    /// MACD：DIF = EMA12 - EMA26；DEA = EMA9(DIF)；柱 = (DIF-DEA)×2
    public static func macd(_ bars: [KLineBar]) -> (Double?, Double?, Double?) {
        let closes = bars.map(\.close)
        guard closes.count > 34 else { return (nil, nil, nil) }
        let ema12 = ema(closes, period: 12)
        let ema26 = ema(closes, period: 26)
        let dif = ema12 - ema26
        // DEA = EMA9 of DIF 序列
        var difSeries: [Double] = []
        // 重算 DIF 序列（从第 26 根起）
        var e12 = closes[0], e26 = closes[0]
        for (i, c) in closes.enumerated() {
            if i > 0 {
                e12 = e12 + 2.0 / 13.0 * (c - e12)
                e26 = e26 + 2.0 / 27.0 * (c - e26)
            }
            if i >= 25 {
                difSeries.append(e12 - e26)
            }
        }
        let dea = difSeries.suffix(9).reduce(0, +) / 9
        let hist = (dif - dea) * 2
        return (dif, dea, hist)
    }

    /// EMA 序列最后一个值
    private static func ema(_ values: [Double], period: Int) -> Double {
        var result = values[0]
        let k = 2.0 / Double(period + 1)
        for v in values.dropFirst() {
            result = result + k * (v - result)
        }
        return result
    }

    // MARK: - 布林带（20, 2σ）

    /// BOLL：中轨 = MA20，上下轨 = MA20 ± 2×标准差
    public static func bollinger(_ bars: [KLineBar], period: Int = 20, multiplier: Double = 2) -> (Double?, Double?, Double?) {
        let window = bars.suffix(period).map(\.close)
        guard window.count == period else { return (nil, nil, nil) }
        let mean = window.reduce(0, +) / Double(period)
        let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(period)
        let sd = variance.squareRoot()
        return (mean + multiplier * sd, mean, mean - multiplier * sd)
    }

    // MARK: - KDJ（9, 3, 3）

    /// KDJ：RSV = (C - L9)/(H9 - L9)×100；K = SMA(RSV,3)；D = SMA(K,3)；J = 3K - 2D
    public static func kdj(_ bars: [KLineBar], period: Int = 9) -> (Double?, Double?, Double?) {
        let n = bars.count
        guard n > period + 3 else { return (nil, nil, nil) }
        var k: Double = 50
        var d: Double = 50
        for i in (period - 1)..<n {
            let window = bars[(i - period + 1)...i]
            let high = window.map(\.high).max() ?? 0
            let low = window.map(\.low).min() ?? 0
            let close = bars[i].close
            let rsv = high > low ? (close - low) / (high - low) * 100 : 50
            k = (2.0 * k + rsv) / 3.0
            d = (2.0 * d + k) / 3.0
        }
        let j = 3 * k - 2 * d
        return (k, d, j)
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
