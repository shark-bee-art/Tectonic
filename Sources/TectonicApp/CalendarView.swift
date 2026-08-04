import SwiftUI
import CoreKit

/// 宏观经济日历：各国统计局发布数据（CPI / GDP / PMI 等），按天分组
struct CalendarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if app.store.calendarEvents.isEmpty {
                emptyState
            } else {
                eventList
            }
        }
        .navigationTitle(L10n.l("sidebar.calendar"))
        .task {
            await app.store.fetchCalendarEvents()
        }
    }

    // MARK: 空/加载状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            if app.store.calendarLoading {
                ProgressView(L10n.l("common.loading"))
            } else if let err = app.store.calendarError {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("加载失败：\(err)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button(L10n.l("common.refresh")) {
                    Task { await app.store.fetchCalendarEvents() }
                }
            } else {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(L10n.l("sidebar.calendar"))
                    .font(.title3)
                Text("加载各国经济数据…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 事件列表（按天分组）

    private var eventList: some View {
        let grouped = Dictionary(grouping: app.store.calendarEvents, by: { $0.dayKey })
        let days = grouped.keys.sorted()
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(days, id: \.self) { day in
                    daySection(day: day, events: grouped[day] ?? [])
                }
            }
            .padding(16)
        }
    }

    private func daySection(day: String, events: [EconomicEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 天标题：8月4日 星期二
            HStack(spacing: 8) {
                if isToday(day) {
                    Text("今天")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
                Text(dayTitle(day))
                    .font(.headline)
                Spacer()
                Text("\(events.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                    EconomicEventRow(event: event)
                    if idx < events.count - 1 {
                        Divider().padding(.leading, 90)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.05)))
        }
    }

    private func isToday(_ day: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date()) == day
    }

    private func dayTitle(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: day) else { return day }
        let out = DateFormatter()
        out.locale = Locale(identifier: L10n.currentLanguage == "ja" ? "ja_JP" : (L10n.currentLanguage == "en" ? "en_US" : "zh_CN"))
        out.dateFormat = "M月d日 EEEE"
        return out.string(from: d)
    }
}

/// 单条经济数据事件行
struct EconomicEventRow: View {
    let event: EconomicEvent

    var body: some View {
        HStack(spacing: 10) {
            // 时间
            Text(event.datetime.formatted(.dateTime.hour().minute()))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            // 地区
            Text(countryShort(event.country))
                .font(.caption2.weight(.semibold))
                .frame(width: 34)
                .padding(.vertical, 3)
                .background(Capsule().fill(countryColor(event.country).opacity(0.15)))
                .foregroundStyle(countryColor(event.country))
            // 事件名
            Text(event.title)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 重要性
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < event.importance ? importanceColor(event.importance) : Color.secondary.opacity(0.15))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 30)
            // 实际 / 预测 / 前值
            valueCell("实际", event.actual, bold: true)
            valueCell("预测", event.forecast, bold: false)
            valueCell("前值", event.previous, bold: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func valueCell(_ label: String, _ value: String?, bold: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value ?? "—")
                .font(.callout.monospacedDigit())
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(value == nil ? Color.secondary.opacity(0.5) : Color.primary)
        }
        .frame(width: 72, alignment: .trailing)
    }

    /// 国家/地区短名（中英）
    private func countryShort(_ c: String) -> String {
        if c.contains("美国") || c.contains("United States") || c.contains("USA") { return "US" }
        if c.contains("中国") || c.contains("China") { return "CN" }
        if c.contains("欧元区") || c.contains("Eurozone") || c.contains("欧元") { return "EU" }
        if c.contains("日本") || c.contains("Japan") { return "JP" }
        if c.contains("英国") || c.contains("United Kingdom") || c.contains("UK") { return "UK" }
        if c.contains("德国") || c.contains("Germany") { return "DE" }
        if c.contains("澳大利亚") || c.contains("Australia") { return "AU" }
        if c.contains("加拿大") || c.contains("Canada") { return "CA" }
        return String(c.prefix(2)).uppercased()
    }

    private func countryColor(_ c: String) -> Color {
        switch countryShort(c) {
        case "US": .blue
        case "CN": .red
        case "EU": .indigo
        case "JP": .pink
        case "UK": .purple
        case "DE": .orange
        case "AU": .teal
        case "CA": .green
        default: .gray
        }
    }

    private func importanceColor(_ level: Int) -> Color {
        switch level {
        case 3: .red
        case 2: .orange
        default: .gray
        }
    }
}
