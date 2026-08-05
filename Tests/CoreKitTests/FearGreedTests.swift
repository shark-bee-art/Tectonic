import XCTest
@testable import CoreKit

final class FearGreedTests: XCTestCase {
    func testLevelClassificationBoundaries() {
        let now = Date()
        // 0-24 极端恐惧 / 25-44 恐惧 / 45-54 中性 / 55-74 贪婪 / 75-100 极端贪婪
        XCTAssertEqual(FearGreedIndex(value: 0, classification: "Extreme Fear", timestamp: now).level, "极端恐惧")
        XCTAssertEqual(FearGreedIndex(value: 24, classification: "Extreme Fear", timestamp: now).level, "极端恐惧")
        XCTAssertEqual(FearGreedIndex(value: 25, classification: "Fear", timestamp: now).level, "恐惧")
        XCTAssertEqual(FearGreedIndex(value: 44, classification: "Fear", timestamp: now).level, "恐惧")
        XCTAssertEqual(FearGreedIndex(value: 45, classification: "Neutral", timestamp: now).level, "中性")
        XCTAssertEqual(FearGreedIndex(value: 54, classification: "Neutral", timestamp: now).level, "中性")
        XCTAssertEqual(FearGreedIndex(value: 55, classification: "Greed", timestamp: now).level, "贪婪")
        XCTAssertEqual(FearGreedIndex(value: 74, classification: "Greed", timestamp: now).level, "贪婪")
        XCTAssertEqual(FearGreedIndex(value: 75, classification: "Extreme Greed", timestamp: now).level, "极端贪婪")
        XCTAssertEqual(FearGreedIndex(value: 100, classification: "Extreme Greed", timestamp: now).level, "极端贪婪")
    }

    func testLevelClassificationEdgeAboveRange() {
        // 防御：超出 100 归入极端贪婪（switch default）
        let now = Date()
        XCTAssertEqual(FearGreedIndex(value: 101, classification: "Extreme Greed", timestamp: now).level, "极端贪婪")
    }
}
