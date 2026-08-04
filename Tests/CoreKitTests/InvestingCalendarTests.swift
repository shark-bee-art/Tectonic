import XCTest
@testable import CoreKit

final class InvestingCalendarTests: XCTestCase {

    /// 网络测试：investing 宏观日历真实拉取（limit 20 与 CLI 一致）
    func testFetchLive() async throws {
        let source = InvestingCalendarSource()
        do {
            let items = try await source.fetch(limit: 20)
            print("🔥 investing 返回 \(items.count) 条")
            for item in items.prefix(3) {
                print("🔥 [\(item.source)] \(item.publishedAt) | \(item.title)")
            }
            XCTAssertGreaterThan(items.count, 0)
        } catch {
            print("🔥 investing 失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 走完整 fetchNews 路径（TaskGroup 并发）
    @MainActor
    func testFetchNewsCalendar() async throws {
        let db = try AppDatabase.makeDefault()
        let store = Store(db: db)
        try store.importBuiltinFeedsIfNeeded()
        let items = await store.fetchNews(category: .calendar)
        print("🔥 fetchNews(.calendar) 返回 \(items.count) 条")
        let macro = items.filter { $0.source == "宏观日历" }
        print("🔥 其中宏观日历 \(macro.count) 条")
        for item in macro.prefix(3) {
            print("🔥 [\(item.source)] \(item.publishedAt) | \(item.title.prefix(50))")
        }
        XCTAssertGreaterThan(macro.count, 0)
    }

    /// 离线：用保存的 HTML 验证 parseRows
    func testParseRowsOffline() throws {
        // 从项目外读取保存的响应（若存在）
        let path = "/tmp/inv.json"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        guard let json = try? JSONSerialization.jsonObject(with: raw.data(using: .utf8)!) as? [String: Any],
              let html = json["data"] as? String else {
            XCTFail("无法解析 inv.json")
            return
        }
        let items = InvestingCalendarSource.parseRows(html, limit: 10)
        print("🔥 离线解析 \(items.count) 条")
        for item in items.prefix(3) {
            print("🔥 [\(item.source)] \(item.publishedAt) | \(item.title) | \(item.summary)")
        }
        XCTAssertGreaterThan(items.count, 0)
    }
}

final class OdailyTests: XCTestCase {
    /// 直接调 Odaily 源看真实错误
    func testFetchLive() async throws {
        do {
            let items = try await OdailySource().fetch(limit: 5)
            print("🔥 Odaily 直接调返回 \(items.count) 条")
            XCTAssertGreaterThan(items.count, 0)
        } catch {
            print("🔥 Odaily 直接调失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 与东财/金十并发（复现 fetchNews 场景）
    func testConcurrentWithEastMoney() async throws {
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    let n = try await OdailySource().fetch(limit: 20).count
                    return "🔥 Odaily 并发返回 \(n) 条"
                } catch {
                    return "🔥 Odaily 并发失败: \(error.localizedDescription)"
                }
            }
            group.addTask {
                do {
                    let n = try await EastMoneyFlashSource().fetch(limit: 20).count
                    return "🔥 东财并发返回 \(n) 条"
                } catch {
                    return "🔥 东财并发失败: \(error.localizedDescription)"
                }
            }
            for await r in group { print(r) }
        }
    }
}
