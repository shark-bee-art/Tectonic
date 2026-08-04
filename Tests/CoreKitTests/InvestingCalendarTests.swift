import XCTest
@testable import CoreKit

final class InvestingCalendarTests: XCTestCase {

    /// 解析真实 investing 响应（本地缓存文件，避免网络波动）
    func testParseRealResponse() throws {
        // 从 JSON 提取 data 字段（与源内逻辑一致）
        let path = "/tmp/inv2.html"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = json["data"] as? String else {
            throw XCTSkip("缺少 /tmp/inv2.html 测试文件")
        }
        let events = InvestingCalendarSource.parseEvents(html: html)
        XCTAssertGreaterThan(events.count, 50, "应解析出大量事件")
        // 事件字段
        let first = events[0]
        XCTAssertFalse(first.title.isEmpty)
        XCTAssertFalse(first.country.isEmpty)
        XCTAssertTrue(first.importance >= 1 && first.importance <= 3)
        // 至少有一个知名指标（CPI/GDP/PMI 之一）
        let titles = events.map { $0.title }
        let known = titles.filter { $0.contains("CPI") || $0.contains("GDP") || $0.contains("PMI") || $0.contains("失业") || $0.contains("利率") }
        XCTAssertGreaterThan(known.count, 3, "应有 CPI/GDP/PMI 等指标，实际: \(known.prefix(8))")
    }

    /// 时间解析（东八区）
    func testDatetimeParsing() {
        let d = InvestingCalendarSource.parseDatetime("2026/08/04 02:30:00")
        XCTAssertNotNil(d)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: d!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 4)
    }

    /// 按天分组
    func testDayGrouping() {
        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let day2 = day1.addingTimeInterval(86400)
        let e1 = EconomicEvent(id: "1", datetime: day1, country: "美国", title: "CPI", importance: 3, actual: nil, forecast: nil, previous: nil)
        let e2 = EconomicEvent(id: "2", datetime: day2, country: "中国", title: "PMI", importance: 2, actual: nil, forecast: nil, previous: nil)
        let events = [e1, e2]
        let grouped = Dictionary(grouping: events, by: { $0.dayKey })
        XCTAssertEqual(grouped.count, 2)
    }

    /// 值清理
    func testCleanValue() {
        XCTAssertNil(InvestingCalendarSource.cleanValue("—"))
        XCTAssertNil(InvestingCalendarSource.cleanValue("  "))
        XCTAssertEqual(InvestingCalendarSource.cleanValue("2.5%"), "2.5%")
    }
}
