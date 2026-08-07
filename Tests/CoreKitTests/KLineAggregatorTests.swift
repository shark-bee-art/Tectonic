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
}
