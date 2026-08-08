import XCTest
@testable import CoreKit

final class KLineAggregatorTests: XCTestCase {

    /// 造 3 根日K：1/1、1/2、1/3（同一月）
    private func makeBars() -> [KLineBar] {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1
        let d1 = cal.date(from: comps)!
        let d2 = cal.date(byAdding: .day, value: 1, to: d1)!
        let d3 = cal.date(byAdding: .day, value: 1, to: d2)!
        return [
            KLineBar(symbolId: "test", period: .day, time: d1, open: 10, high: 12, low: 9, close: 11, volume: 100),
            KLineBar(symbolId: "test", period: .day, time: d2, open: 11, high: 15, low: 10, close: 14, volume: 200),
            KLineBar(symbolId: "test", period: .day, time: d3, open: 14, high: 16, low: 13, close: 15, volume: 300),
        ]
    }

    func testAggregateToMonth() {
        let bars = makeBars()
        let month = KLineAggregator.aggregate(bars, to: .month)
        XCTAssertEqual(month.count, 1)
        guard let m = month.first else { return }
        // O=首根开、H=最高、L=最低、C=末根收、V=合计
        XCTAssertEqual(m.open, 10)
        XCTAssertEqual(m.high, 16)
        XCTAssertEqual(m.low, 9)
        XCTAssertEqual(m.close, 15)
        XCTAssertEqual(m.volume, 600)
    }

    func testAggregateToYear() {
        let bars = makeBars()
        let year = KLineAggregator.aggregate(bars, to: .year)
        XCTAssertEqual(year.count, 1)
        guard let y = year.first else { return }
        XCTAssertEqual(y.open, 10)
        XCTAssertEqual(y.high, 16)
        XCTAssertEqual(y.low, 9)
        XCTAssertEqual(y.close, 15)
        XCTAssertEqual(y.volume, 600)
    }

    func testAggregateEmpty() {
        XCTAssertTrue(KLineAggregator.aggregate([], to: .year).isEmpty)
    }

    /// 跨月排序：10 月必须排在 2 月之后（字典序会错排，回归保护）
    func testAggregateMonthOrdering() {
        let cal = Calendar(identifier: .gregorian)
        var c1 = DateComponents(); c1.year = 2026; c1.month = 2; c1.day = 3
        var c2 = DateComponents(); c2.year = 2026; c2.month = 10; c2.day = 20
        var c3 = DateComponents(); c3.year = 2026; c3.month = 1; c3.day = 5
        let bars = [
            KLineBar(symbolId: "t", period: .day, time: cal.date(from: c1)!, open: 1, high: 2, low: 1, close: 1.5, volume: 10),
            KLineBar(symbolId: "t", period: .day, time: cal.date(from: c2)!, open: 2, high: 3, low: 2, close: 2.5, volume: 10),
            KLineBar(symbolId: "t", period: .day, time: cal.date(from: c3)!, open: 0.5, high: 1, low: 0.5, close: 0.8, volume: 10),
        ]
        let months = KLineAggregator.aggregate(bars, to: .month)
        XCTAssertEqual(months.count, 3, "聚合应为 3 桶")
        let monthNums = months.map { cal.component(.month, from: $0.time) }
        XCTAssertEqual(monthNums, [1, 2, 10])  // 时间序而非字典序
    }
}
