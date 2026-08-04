import Foundation

// MARK: - 金十数据快讯

/// 金十数据：实时快讯流（flash-api.jin10.com）
public struct Jin10Source: Sendable {
    public init() {}

    public func fetch(limit: Int = 30) async throws -> [NewsItem] {
        let urlStr = "https://flash-api.jin10.com/get_flash_list?max_time=&channel=-8200"
        guard let url = URL(string: urlStr) else {
            throw NewsSourceError.parseFailed("金十 URL 无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("bVBF4FyRTn5NJF5n", forHTTPHeaderField: "x-app-id")
        request.setValue("1.0.0", forHTTPHeaderField: "x-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsSourceError.parseFailed("金十 HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw NewsSourceError.parseFailed("金十响应解析失败")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var result: [NewsItem] = []
        for item in items {
            guard let inner = item["data"] as? [String: Any],
                  let content = inner["content"] as? String,
                  !content.isEmpty else { continue }
            let id = item["id"] as? String ?? UUID().uuidString
            let important = (item["important"] as? Int ?? 0) == 1
            let time = (item["time"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
            let clean = Self.cleanHTML(content)
            let title = (important ? "⚡ " : "") + String(clean.prefix(80))
            result.append(NewsItem(
                id: id, title: title, summary: clean, url: "https://www.jin10.com",
                source: "金十数据", publishedAt: time,
                content: clean, tags: [.us, .cn, .crypto]
            ))
            if result.count >= limit { break }
        }
        return result
    }

    /// 去除 HTML 标签与实体
    static func cleanHTML(_ raw: String) -> String {
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

// MARK: - 东方财富 7x24 快讯

public struct EastMoneyFlashSource: Sendable {
    public init() {}

    public func fetch(limit: Int = 30) async throws -> [NewsItem] {
        let urlStr = "https://np-listapi.eastmoney.com/comm/web/getFastNewsList?client=web&biz=web_724&fastColumn=102&sortEnd=&pageSize=\(min(limit, 50))&req_trace=1"
        guard let url = URL(string: urlStr) else {
            throw NewsSourceError.parseFailed("东财快讯 URL 无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsSourceError.parseFailed("东财快讯 HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = (json["data"] as? [String: Any])?["fastNewsList"] as? [[String: Any]] else {
            throw NewsSourceError.parseFailed("东财快讯响应解析失败")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var result: [NewsItem] = []
        for item in list {
            guard let title = item["title"] as? String, !title.isEmpty else { continue }
            let id = item["code"] as? String ?? item["art_code"] as? String ?? UUID().uuidString
            let summary = (item["digest"] as? String) ?? title
            let timeStr = (item["showTime"] as? String) ?? (item["showtime"] as? String)
            let time = timeStr.flatMap { formatter.date(from: $0) } ?? Date()
            let url = item["url"] as? String ?? "https://finance.eastmoney.com/"
            result.append(NewsItem(
                id: id, title: title, summary: summary, url: url,
                source: "东方财富", publishedAt: time,
                content: summary, tags: [.cn]
            ))
            if result.count >= limit { break }
        }
        return result
    }
}

// MARK: - 东方财富机构研报

public struct EastMoneyResearchSource: Sendable {
    public init() {}

    public func fetch(limit: Int = 30) async throws -> [NewsItem] {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let end = now.formatted(.iso8601.year().month().day())
        let begin = (cal.date(byAdding: .day, value: -7, to: now) ?? now)
            .formatted(.iso8601.year().month().day())
        let urlStr = "https://reportapi.eastmoney.com/report/list?pageSize=\(min(limit, 50))&industry=*&rating=*&ratingChange=*&beginTime=\(begin)&endTime=\(end)&pageNo=1&qType=0&code=*"
        guard let url = URL(string: urlStr) else {
            throw NewsSourceError.parseFailed("东财研报 URL 无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsSourceError.parseFailed("东财研报 HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw NewsSourceError.parseFailed("东财研报响应解析失败")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        var result: [NewsItem] = []
        for item in list {
            guard let title = item["title"] as? String else { continue }
            let id = item["infoCode"] as? String ?? UUID().uuidString
            let stock = (item["stockName"] as? String) ?? ""
            let org = (item["orgSName"] as? String) ?? ""
            let dateStr = item["publishDate"] as? String ?? ""
            let time = formatter.date(from: dateStr) ?? Date()
            let rating = (item["emRatingName"] as? String) ?? ""
            let eps = (item["predictNextTwoYearEps"] as? String) ?? ""
            let pe = (item["predictNextTwoYearPe"] as? String) ?? ""
            var summaryParts: [String] = []
            if !stock.isEmpty { summaryParts.append("标的：\(stock)") }
            if !org.isEmpty { summaryParts.append("机构：\(org)") }
            if !rating.isEmpty { summaryParts.append("评级：\(rating)") }
            if !eps.isEmpty { summaryParts.append("预测EPS：\(eps)") }
            if !pe.isEmpty { summaryParts.append("预测PE：\(pe)") }
            let summary = summaryParts.joined(separator: " · ")
            result.append(NewsItem(
                id: id, title: title, summary: summary,
                url: "https://data.eastmoney.com/report/info/\(id).html",
                source: org.isEmpty ? "机构研报" : org,
                publishedAt: time, content: summary, tags: [.cn]
            ))
            if result.count >= limit { break }
        }
        return result
    }
}

// MARK: - Odaily 星球日报（加密资讯）

/// Odaily：中文加密资讯（web-api.odaily.news/infoFlow/list）
public struct OdailySource: Sendable {
    public init() {}

    public func fetch(limit: Int = 30) async throws -> [NewsItem] {
        let urlStr = "https://web-api.odaily.news/infoFlow/list?page=1&size=\(min(limit, 50))"
        guard let url = URL(string: urlStr) else {
            throw NewsSourceError.parseFailed("Odaily URL 无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsSourceError.parseFailed("Odaily HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw NewsSourceError.parseFailed("Odaily 响应解析失败")
        }
        // publishedTime 是毫秒时间戳
        var result: [NewsItem] = []
        for item in items {
            guard let title = item["title"] as? String, !title.isEmpty else { continue }
            let id = "odaily-\(item["entityId"] as? Int ?? 0)"
            let ts = (item["publishedTime"] as? Double ?? 0) / 1000
            let date = Date(timeIntervalSince1970: ts)
            let summary = (item["summary"] as? String) ?? ""
            let url = item["newsUrl"] as? String ?? "https://www.odaily.news/"
            let isImportant = (item["isImportant"] as? Int ?? 0) == 1
            let type = (item["entityType"] as? String) ?? ""
            result.append(NewsItem(
                id: id, title: (isImportant ? "⚡ " : "") + title,
                summary: summary, url: url,
                source: type == "newsflash" ? "Odaily快讯" : "Odaily",
                publishedAt: date, content: summary, tags: [.crypto]
            ))
            if result.count >= limit { break }
        }
        return result
    }
}

// MARK: - Investing.com 宏观经济日历（CPI/PPI/PMI 等）

/// Investing.com 经济日历：各国宏观数据发布时间与 实际/预测/前值
public struct InvestingCalendarSource: Sendable {
    public init() {}

    public func fetch(limit: Int = 100) async throws -> [NewsItem] {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateFrom = fmt.string(from: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        let dateTo = fmt.string(from: calendar.date(byAdding: .day, value: 7, to: now) ?? now)

        let body = "country%5B%5D=5&country%5B%5D=37&country%5B%5D=72&country%5B%5D=35&country%5B%5D=25&country%5B%5D=22&country%5B%5D=6&country%5B%5D=32&dateFrom=\(dateFrom)&dateTo=\(dateTo)&timeZone=8&timeFrame=day&limit_from=0"
        guard let url = URL(string: "https://cn.investing.com/economic-calendar/Service/getCalendarFilteredData") else {
            throw NewsSourceError.parseFailed("Investing URL 无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://cn.investing.com/economic-calendar/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsSourceError.parseFailed("Investing HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let html = json["data"] as? String else {
            throw NewsSourceError.parseFailed("Investing 响应解析失败")
        }
        return Self.parseRows(html, limit: limit)
    }

    static func parseRows(_ html: String, limit: Int) -> [NewsItem] {
        let pattern = #"<tr id="eventRowId_(\d+)" class="js-event-item "[^>]*data-event-datetime="([^"]+)"[^>]*>(.*?)</tr>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))

        var result: [NewsItem] = []
        for m in matches {
            let eventId = ns.substring(with: m.range(at: 1))
            let datetime = ns.substring(with: m.range(at: 2))
            let row = ns.substring(with: m.range(at: 3))

            let time = Self.extract(row, pattern: #"class="first left time js-time"[^>]*>([^<]*)"#)
            let country = Self.extract(row, pattern: #"class="left flagCur noWrap"[^>]*>.*?<span title="([^"]*)"#)
            let currency = Self.extract(row, pattern: #"class="left flagCur noWrap"[^>]*>.*?<span[^>]*>&nbsp;</span>\s*([A-Z]{3})"#)
            let event = Self.extract(row, pattern: #"class="left event"[^>]*>.*?<a[^>]*>\s*(.*?)\s*</a>"#)
            let actual = Self.extract(row, pattern: #"class="bold act[^"]*"[^>]*>([^<]*)"#)
            let forecast = Self.extract(row, pattern: #"class="fore[^"]*"[^>]*>\s*(?:<span[^>]*>)?([^<]*)"#)
            let previous = Self.extract(row, pattern: #"class="prev[^"]*"[^>]*>\s*<span[^>]*>([^<]*)"#)
            // 重要性：bull 图标数（bull2=中等 3=高）
            let bullCount = (row.components(separatedBy: "grayFullBullishIcon").count - 1)

            let eventName = event.isEmpty ? "经济事件" : event
            let countryName = country.isEmpty ? "" : "（\(country)）"
            var summaryParts: [String] = []
            if !country.isEmpty { summaryParts.append(country) }
            summaryParts.append("实际 \(actual.isEmpty ? "—" : actual)")
            summaryParts.append("预测 \(forecast.isEmpty ? "—" : forecast)")
            summaryParts.append("前值 \(previous.isEmpty ? "—" : previous)")
            let importance = bullCount >= 3 ? "🔴" : (bullCount >= 2 ? "🟠" : "⚪")

            let date = Self.parseDatetime(datetime, time: time)
            let title = "\(importance) \(eventName)\(countryName)"
            result.append(NewsItem(
                id: "investing-\(eventId)",
                title: title,
                summary: summaryParts.joined(separator: " · "),
                url: "https://cn.investing.com/economic-calendar/",
                source: "宏观日历",
                publishedAt: date,
                content: summaryParts.joined(separator: "\n"),
                tags: [.us, .cn, .crypto]
            ))
            if result.count >= limit { break }
        }
        return result
    }

    static func extract(_ text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return "" }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return "" }
        var value = ns.substring(with: m.range(at: 1))
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "&nbsp;", with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析 "2026/08/03 04:00:00" + td 时间
    static func parseDatetime(_ datetime: String, time: String) -> Date {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy/MM/dd HH:mm:ss"
        if let d = fmt.date(from: datetime) { return d }
        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy/MM/dd"
        if let d = dayFmt.date(from: String(datetime.prefix(10))), !time.isEmpty {
            let hm = time.split(separator: ":")
            if hm.count == 2, let h = Int(hm[0]), let mi = Int(hm[1]) {
                return Calendar.current.date(bySettingHour: h, minute: mi, second: 0, of: d) ?? d
            }
        }
        return Date()
    }
}

// MARK: - 东方财富财报日历（业绩报表）

public struct EastMoneyEarningsSource: Sendable {
    public init() {}

    public func fetch(limit: Int = 30) async throws -> [NewsItem] {
        let urlStr = "https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_LICO_FN_CPD&columns=ALL&pageNumber=1&pageSize=\(min(limit, 50))&sortColumns=NOTICE_DATE&sortTypes=-1"
        guard let url = URL(string: urlStr) else {
            throw NewsSourceError.parseFailed("东财财报 URL 无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NewsSourceError.parseFailed("东财财报 HTTP \(http.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = (json["result"] as? [String: Any])?["data"] as? [[String: Any]] else {
            throw NewsSourceError.parseFailed("东财财报响应解析失败")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var result: [NewsItem] = []
        for item in list {
            guard let code = item["SECURITY_CODE"] as? String else { continue }
            let name = (item["SECURITY_NAME_ABBR"] as? String) ?? code
            let notice = (item["NOTICE_DATE"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
            let reportDate = (item["REPORTDATE"] as? String ?? "").prefix(10)
            let eps = (item["BASIC_EPS"] as? Double).map { String(format: "%.3f", $0) } ?? "—"
            let income = (item["TOTAL_OPERATE_INCOME"] as? Double).map { shortNum($0) } ?? "—"
            let yoy = (item["TOTAL_OPERATE_INCOME_YOY"] as? Double).map { String(format: "%+.1f%%", $0) } ?? ""
            let id = "\(code)-\(reportDate)"
            let title = "\(name)（\(code)）\(reportDate) 财报"
            let summary = "EPS \(eps) · 营收 \(income)\(yoy.isEmpty ? "" : "（同比\(yoy)）") · 公告日 \(notice.formatted(date: .abbreviated, time: .omitted))"
            result.append(NewsItem(
                id: id, title: title, summary: summary,
                url: "https://data.eastmoney.com/bbsj/\(code)/\(reportDate).html",
                source: "业绩报表", publishedAt: notice, content: summary, tags: [.cn]
            ))
            if result.count >= limit { break }
        }
        return result
    }

    private func shortNum(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1f亿", v / 1_000_000_000) }
        if v >= 10_000 { return String(format: "%.1f万", v / 10_000) }
        return String(format: "%.0f", v)
    }
}
