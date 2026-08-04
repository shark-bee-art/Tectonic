import XCTest
@testable import CoreKit

final class TechnicalIndicatorsTests: XCTestCase {

    // MARK: - 构造数据辅助

    /// 生成 n 根日K：日期从 2025-01-01 起，收盘 = open 附近小幅波动
    private func makeBars(count: Int, closes: [Double]? = nil) -> [KLineBar] {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        var bars: [KLineBar] = []
        for i in 0..<count {
            let time = cal.date(byAdding: .day, value: i, to: start)!
            let close: Double
            if let closes, i < closes.count {
                close = closes[i]
            } else {
                close = Double(i + 100)
            }
            let open = close * 0.99
            bars.append(KLineBar(symbolId: "test", period: .day, time: time,
                                 open: open, high: max(open, close) * 1.01,
                                 low: min(open, close) * 0.99, close: close,
                                 volume: 1_000_000))
        }
        return bars
    }

    // MARK: - SMA

    func testSMA() {
        // 1...10 收盘，5 日均线 = (6+7+8+9+10)/5 = 8
        let bars = makeBars(count: 10, closes: (1...10).map { Double($0) })
        XCTAssertEqual(TechnicalAnalyzer.sma(bars, period: 5) ?? 0, 8.0, accuracy: 0.001)
        // 数据不足返回 nil
        XCTAssertNil(TechnicalAnalyzer.sma(bars, period: 20))
    }

    func testSMAWindowIsMostRecent() {
        // 收盘 1...30，MA5 应基于最后 5 根（26-30）= 28
        let bars = makeBars(count: 30, closes: (1...30).map { Double($0) })
        XCTAssertEqual(TechnicalAnalyzer.sma(bars, period: 5) ?? 0, 28.0, accuracy: 0.001)
    }

    // MARK: - YTD

    func testYTD() {
        // 当年（2026）第一根 open 作为基准；构造跨年数据
        let cal = Calendar(identifier: .gregorian)
        let start2025 = cal.date(from: DateComponents(year: 2025, month: 12, day: 30))!
        let start2026 = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        var bars = [
            KLineBar(symbolId: "t", period: .day, time: start2025,
                     open: 100, high: 101, low: 99, close: 100, volume: 1),
        ]
        for i in 0..<10 {
            let time = cal.date(byAdding: .day, value: i, to: start2026)!
            bars.append(KLineBar(symbolId: "t", period: .day, time: time,
                                 open: 100, high: 101, low: 99, close: Double(100 + i), volume: 1))
        }
        // 2026 第一根 open=100，最新 close=109 → +9%
        let ytd = TechnicalAnalyzer.ytdChange(bars, currentPrice: bars.last!.close)
        XCTAssertEqual(ytd ?? 0, 9.0, accuracy: 0.001)
    }

    // MARK: - 支撑/阻力

    func testSupportResistance() {
        // 构造：价格在 100-120 震荡，现价 110
        // 极值低点 ~100/102，极值高点 ~118/120
        var bars: [KLineBar] = []
        let pattern: [(Double, Double)] = [
            (100, 108), (102, 110), (105, 112), (108, 115), (110, 118),  // 高点 118
            (108, 116), (105, 113), (102, 110), (100, 108), (103, 110),  // 低点 100
            (105, 112), (108, 115), (110, 117), (112, 120), (110, 118),  // 高点 120
            (108, 115), (105, 112), (102, 109), (100, 107), (103, 110),  // 低点 100
        ]
        for (low, high) in pattern {
            let close = (low + high) / 2
            bars.append(KLineBar(symbolId: "t", period: .day, time: Date(),
                                 open: close, high: high, low: low, close: close, volume: 1))
        }
        let (support, resistance) = TechnicalAnalyzer.supportResistance(bars, currentPrice: 110)
        // 支撑应约 100（最近的极值低点聚类），阻力应约 118-120
        XCTAssertNotNil(support)
        XCTAssertNotNil(resistance)
        XCTAssertLessThan(support ?? 0, 110)
        XCTAssertGreaterThan(resistance ?? 0, 110)
        // 支撑接近 100（容差内）
        XCTAssertEqual(support ?? 0, 100, accuracy: 3)
        // 阻力接近 118（容差内）
        XCTAssertEqual(resistance ?? 0, 118, accuracy: 3)
    }

    func testSupportResistanceEmptyData() {
        let (s, r) = TechnicalAnalyzer.supportResistance([], currentPrice: 10)
        XCTAssertNil(s)
        XCTAssertNil(r)
    }

    // MARK: - 完整 analyze

    func testAnalyze() {
        let bars = makeBars(count: 260, closes: (1...260).map { Double($0) * 2 })
        let summary = TechnicalAnalyzer.analyze(bars: bars)
        XCTAssertEqual(summary.currentPrice, 260 * 2, accuracy: 0.001)
        XCTAssertEqual(summary.barCount, 260)
        XCTAssertNotNil(summary.sma20)
        XCTAssertNotNil(summary.sma200)
        // 线性序列 2,4,...,520：MA20 = 最后20根均值 = 501，MA200 = 321
        XCTAssertEqual(summary.sma20 ?? 0, 501, accuracy: 0.001)
        XCTAssertEqual(summary.sma200 ?? 0, 321, accuracy: 0.001)
        XCTAssertNotNil(summary.high52w)
        XCTAssertNotNil(summary.low52w)
        XCTAssertGreaterThan(summary.avgVolume20, 0)
    }

    func testAnalyzeEmpty() {
        let summary = TechnicalAnalyzer.analyze(bars: [])
        XCTAssertEqual(summary.currentPrice, 0)
        XCTAssertNil(summary.sma200)
    }

    // MARK: - RSI

    func testRSIAllUpIs100() {
        // 全涨序列 → RSI 100
        let bars = makeBars(count: 30, closes: (1...30).map { Double($0) })
        XCTAssertEqual(TechnicalAnalyzer.rsi(bars) ?? 0, 100, accuracy: 0.001)
    }

    func testRSIAllDownIsNearZero() {
        // 全跌序列 → RSI ≈ 0（损失平滑后略大于 0，但应 < 10）
        let bars = makeBars(count: 30, closes: (1...30).map { Double(100 - $0) })
        let rsi = TechnicalAnalyzer.rsi(bars) ?? 100
        XCTAssertLessThan(rsi, 10)
    }

    func testRSIAlternating() {
        // 涨跌交替 → RSI ≈ 50
        var closes: [Double] = []
        for i in 0..<60 { closes.append(Double(100 + (i % 2 == 0 ? 1 : -1))) }
        let bars = makeBars(count: 60, closes: closes)
        let rsi = TechnicalAnalyzer.rsi(bars) ?? 0
        XCTAssertEqual(rsi, 50, accuracy: 10)
    }

    func testRSIInsufficientData() {
        let bars = makeBars(count: 10, closes: (1...10).map { Double($0) })
        XCTAssertNil(TechnicalAnalyzer.rsi(bars, period: 14))
    }

    // MARK: - BOLL

    func testBollinger() {
        // 恒定价格 → 标准差 0 → 上=中=下
        let bars = makeBars(count: 30, closes: Array(repeating: 100.0, count: 30))
        let (upper, mid, lower) = TechnicalAnalyzer.bollinger(bars)
        XCTAssertEqual(mid ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(upper ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(lower ?? 0, 100, accuracy: 0.001)
    }

    func testBollingerSpread() {
        // 波动序列 → 上 > 中 > 下
        var closes: [Double] = []
        for i in 0..<30 { closes.append(Double(100 + (i % 2 == 0 ? 10 : -10))) }
        let bars = makeBars(count: 30, closes: closes)
        let (upper, mid, lower) = TechnicalAnalyzer.bollinger(bars)
        XCTAssertNotNil(upper)
        XCTAssertNotNil(mid)
        XCTAssertNotNil(lower)
        XCTAssertGreaterThan(upper ?? 0, mid ?? 0)
        XCTAssertGreaterThan(mid ?? 0, lower ?? 0)
    }

    // MARK: - KDJ

    func testKDJRange() {
        let bars = makeBars(count: 60, closes: (1...60).map { Double($0) })
        let (k, d, _) = TechnicalAnalyzer.kdj(bars)
        XCTAssertNotNil(k)
        XCTAssertNotNil(d)
        // 上涨趋势 → K 应处于高位（> 50）
        XCTAssertGreaterThan(k ?? 0, 50)
        XCTAssertLessThan(k ?? 0, 100)
    }

    // MARK: - 52周区间位置

    func testRangePosition() {
        // 前 130 根 100（低点）、中 60 根 200（高点）、后 70 根 150（现价）
        // → 位置 = (150-100)/(200-100) = 50%
        let closes = (1...260).map { $0 <= 130 ? 100.0 : ($0 <= 190 ? 200.0 : 150.0) }
        let bars = makeBars(count: 260, closes: closes)
        let summary = TechnicalAnalyzer.analyze(bars: bars)
        XCTAssertEqual(summary.rangePosition52w ?? 0, 50, accuracy: 1)
    }
}
