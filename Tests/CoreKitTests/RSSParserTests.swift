import XCTest
@testable import CoreKit

final class RSSParserTests: XCTestCase {

    /// RSS 2.0 解析
    func testParseRSS20() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
        <title>测试源</title>
        <link>https://example.com</link>
        <description>测试</description>
        <item>
        <title>第一条新闻</title>
        <link>https://example.com/1</link>
        <description>摘要内容 &amp; 更多</description>
        <pubDate>Mon, 03 Aug 2026 10:00:00 GMT</pubDate>
        <guid>abc-123</guid>
        </item>
        <item>
        <title>第二条新闻</title>
        <link>https://example.com/2</link>
        <description>第二条摘要</description>
        <pubDate>Tue, 04 Aug 2026 10:00:00 GMT</pubDate>
        </item>
        </channel>
        </rss>
        """
        let items = try await RSSParser.parse(data: Data(xml.utf8), sourceName: "测试源", limit: 10)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "第一条新闻")
        XCTAssertEqual(items[0].source, "测试源")
        XCTAssertEqual(items[0].summary, "摘要内容 & 更多")
        XCTAssertEqual(items[0].url, "https://example.com/1")
        XCTAssertEqual(items[0].id, "abc-123")
        // 时间解析（RFC822）
        XCTAssertNotNil(items[0].publishedAt)
        // 去 HTML 实体
        XCTAssertFalse(items[0].summary.contains("&amp;"))
    }

    /// Atom 解析
    func testParseAtom() async throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Atom源</title>
        <entry>
        <title>Atom 文章</title>
        <link href="https://example.com/atom/1"/>
        <summary>Atom 摘要</summary>
        <published>2026-08-04T08:30:00Z</published>
        <id>tag:example,2026:1</id>
        </entry>
        </feed>
        """
        let items = try await RSSParser.parse(data: Data(xml.utf8), sourceName: "Atom源", limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Atom 文章")
        XCTAssertEqual(items[0].url, "https://example.com/atom/1")
        XCTAssertEqual(items[0].id, "tag:example,2026:1")
    }

    /// 空源 / 非法 XML
    func testParseInvalidXML() async throws {
        // 未闭合标签 → 真正的解析错误
        do {
            _ = try await RSSParser.parse(data: Data("<rss><channel><item><title>未闭合".utf8), sourceName: "坏源", limit: 5)
            XCTFail("应抛出解析错误")
        } catch {
            // 期望抛错
        }
        // 合法 XML 但无 item → 返回空数组（不抛错）
        let empty = try await RSSParser.parse(data: Data("<rss><channel><title>无内容</title></channel></rss>".utf8), sourceName: "空源", limit: 5)
        XCTAssertEqual(empty.count, 0)
    }

    /// 网络：真实 RSS 源解析（日经中文）
    func testFetchLiveNikkei() async throws {
        let items = try await RSSParser.parse(
            url: URL(string: "https://cn.nikkei.com/rss.html")!,
            sourceName: "日经中文网", limit: 5)
        print("🔥 日经中文 RSS 返回 \(items.count) 条")
        XCTAssertGreaterThan(items.count, 0)
        print("🔥 首条: \(items.first?.title ?? "")")
    }
}
