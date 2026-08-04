import Foundation

/// 轻量 RSS/Atom 解析器（XMLParser 实现，无第三方依赖）
public enum RSSParser {

    /// 解析 RSS 源，返回新闻列表
    public static func parse(url: URL, sourceName: String, limit: Int = 30) async throws -> [NewsItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsSourceError.parseFailed("RSS HTTP \(http.statusCode)")
        }
        let parser = RSSParserDelegate(sourceName: sourceName, limit: limit)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw NewsSourceError.parseFailed("RSS XML 解析失败: \(xmlParser.parserError?.localizedDescription ?? "未知错误")")
        }
        return parser.items
    }
}

/// XMLParser 委托：提取 RSS 2.0 / Atom 的标题、链接、摘要、发布时间
private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    let sourceName: String
    let limit: Int
    var items: [NewsItem] = []

    // 当前元素栈
    private var elementStack: [String] = []
    private var currentItem: RSSItemBuilder?
    private var currentElementText = ""
    private var isInItem = false
    private var isInChannel = false

    struct RSSItemBuilder {
        var title = ""
        var link = ""
        var description = ""
        var pubDate = ""
        var guid = ""
    }

    init(sourceName: String, limit: Int) {
        self.sourceName = sourceName
        self.limit = limit
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        elementStack.append(elementName)
        currentElementText = ""

        if elementName == "item" || elementName == "entry" {
            isInItem = true
            currentItem = RSSItemBuilder()
        }
        // Atom 的 link 是属性形式
        if elementName == "link", isInItem, let href = attributeDict["href"] {
            currentItem?.link = href
        }
        if elementName == "channel" { isInChannel = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentElementText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentElementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isInItem {
            switch elementName {
            case "title": currentItem?.title = text
            case "link": if currentItem?.link.isEmpty == true { currentItem?.link = text }
            case "description", "summary", "content": currentItem?.description = text
            case "pubDate", "published", "updated": currentItem?.pubDate = text
            case "guid", "id": currentItem?.guid = text
            default: break
            }
        }
        if elementName == "item" || elementName == "entry" {
            if var item = currentItem {
                if item.title.isEmpty { item.title = item.description.prefix(80).description }
                let date = parseDate(item.pubDate) ?? Date()
                let id = item.guid.isEmpty ? item.link : item.guid
                items.append(NewsItem(
                    id: id, title: item.title,
                    summary: cleanHTML(item.description),
                    url: item.link, source: sourceName,
                    publishedAt: date,
                    content: cleanHTML(item.description),
                    tags: []
                ))
            }
            currentItem = nil
            isInItem = false
        }
        if elementName == "channel" { isInChannel = false }
        if !elementStack.isEmpty { elementStack.removeLast() }
    }

    /// 解析常见日期格式（RSS RFC822 / ISO8601）
    private func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let d = formatter.date(from: trimmed) { return d }
        }
        return nil
    }

    /// 去除 HTML 标签
    private func cleanHTML(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
