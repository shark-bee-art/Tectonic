import Foundation

// MARK: - 宏观经济日历（investing.com 经济日历 API 爬虫源）
// 各国统计局数据：CPI / GDP / PMI / 失业率 / 利率决议 等，按天分类
// 免费、无需 Key；对频繁请求敏感 → 调用方需缓存（Store 30 分钟）

public struct EconomicEvent: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let datetime: Date
    public let country: String
    public let title: String
    public let importance: Int        // 1 低 / 2 中 / 3 高
    public let actual: String?
    public let forecast: String?
    public let previous: String?

    public init(id: String, datetime: Date, country: String, title: String,
                importance: Int, actual: String?, forecast: String?, previous: String?) {
        self.id = id
        self.datetime = datetime
        self.country = country
        self.title = title
        self.importance = importance
        self.actual = actual
        self.forecast = forecast
        self.previous = previous
    }

    /// 按天分组的 key（本地日期）
    public var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: datetime)
    }
}

public enum InvestingCalendarSource {

    /// 关注的地区（investing country id）：美国/中国/欧元区/日本/英国/德国/澳大利亚/加拿大
    public static let countryIDs = ["5", "37", "72", "35", "25", "22", "6", "32"]

    /// 拉取经济日历事件
    public static func fetch(from: Date, to: Date) async throws -> [EconomicEvent] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateFrom = fmt.string(from: from)
        let dateTo = fmt.string(from: to)

        let url = URL(string: "https://cn.investing.com/economic-calendar/Service/getCalendarFilteredData")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cn.investing.com/economic-calendar/", forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        var body = countryIDs.map { "country%5B%5D=\($0)" }.joined(separator: "&")
        body += "&dateFrom=\(dateFrom)&dateTo=\(dateTo)&timeZone=8&timeFrame=day&limit_from=0"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CalendarSourceError("HTTP \(http.statusCode)")
        }
        // 响应为 JSON：{ "data": "<转义 HTML>", ... }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = json["data"] as? String else {
            throw CalendarSourceError("响应解析失败")
        }
        return parseEvents(html: html)
    }

    public struct CalendarSourceError: LocalizedError {
        public let message: String
        init(_ m: String) { message = m }
        public var errorDescription: String? { message }
    }

    // MARK: - HTML 解析

    static func parseEvents(html: String) -> [EconomicEvent] {
        let rowPattern = #"<tr id="eventRowId_(\d+)"[^>]*data-event-datetime="([^"]+)"[^>]*>(.*?)</tr>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else { return [] }

        var events: [EconomicEvent] = []
        let ns = html as NSString
        for m in rowRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard m.numberOfRanges >= 4 else { continue }
            let eventID = ns.substring(with: m.range(at: 1))
            let datetimeStr = ns.substring(with: m.range(at: 2))
            let row = ns.substring(with: m.range(at: 3))

            guard let date = parseDatetime(datetimeStr) else { continue }
            let title: String = extractText(row, pattern: #"class="[^"]*left[^"]*event[^"]*"[^>]*>\s*<a[^>]*>(.*?)</a>"#)
                ?? extractText(row, pattern: #"class="[^"]*left[^"]*event[^"]*"[^>]*>(.*?)</td>"#)
                ?? ""
            guard !title.isEmpty else { continue }
            let country = extractAttribute(row, pattern: #"class="[^"]*flagCur[^"]*"[^>]*>\s*<span[^>]*title="([^"]+)""#) ?? ""
            let importance = detectImportance(row)
            // 实际/预测/前值列：investing 用 class（无 data-test 属性）
            let actual: String? = extractText(row, pattern: #"<td[^>]*class="[^"]*bold[^"]*act[^"]*"[^>]*>(.*?)</td>"#)
            let forecast: String? = extractText(row, pattern: #"<td[^>]*class="[^"]*fore[^"]*"[^>]*>(.*?)</td>"#)
            let previous: String? = extractText(row, pattern: #"<td[^>]*class="[^"]*prev[^"]*"[^>]*>(.*?)</td>"#)

            events.append(EconomicEvent(id: eventID, datetime: date, country: country, title: title,
                                        importance: importance,
                                        actual: cleanValue(actual),
                                        forecast: cleanValue(forecast),
                                        previous: cleanValue(previous)))
        }
        return events.sorted { $0.datetime < $1.datetime }
    }

    /// 解析 investing 时间（2026/08/04 02:30:00，东八区）
    static func parseDatetime(_ s: String) -> Date? {
        let cleaned = s.trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: cleaned)
    }

    /// 重要性：计数 BullishIcon 前颜色（red=3/orange=2/gray=1，Half 半星）
    static func detectImportance(_ row: String) -> Int {
        let red = countOccurrences(row, #"redFullBullishIcon|redHalfBullishIcon"#)
        let orange = countOccurrences(row, #"orangeFullBullishIcon|orangeHalfBullishIcon"#)
        let gray = countOccurrences(row, #"grayFullBullishIcon|grayHalfBullishIcon"#)
        if red > 0 { return 3 }
        if orange > 0 { return 2 }
        if gray > 0 { return 1 }
        return 1
    }

    static func countOccurrences(_ s: String, _ pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }

    /// 提取第一个匹配的文本（去标签/HTML 实体）
    static func extractText(_ s: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)),
              m.numberOfRanges >= 2 else { return nil }
        let raw = (s as NSString).substring(with: m.range(at: 1))
        return decodeEntities(stripTags(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractAttribute(_ s: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)),
              m.numberOfRanges >= 2 else { return nil }
        return decodeEntities((s as NSString).substring(with: m.range(at: 1)))
    }

    /// 提取实际/预测/前值列（data-test 属性优先）
    static func extractColumn(_ s: String, pattern: String) -> String? {
        extractText(s, pattern: pattern)
    }

    static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let entities: [String: String] = ["&amp;": "&", "&nbsp;": " ", "&quot;": "\"", "&#39;": "'",
                                          "&lt;": "<", "&gt;": ">", "&ndash;": "-", "&mdash;": "—"]
        for (k, v) in entities { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }

    /// 值清理：空 / "—" / "-" → nil
    static func cleanValue(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "—", t != "-", t != "---" else { return nil }
        return t
    }
}
