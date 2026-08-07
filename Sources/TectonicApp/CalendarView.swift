import SwiftUI
import CoreKit

/// 宏观经济日历：各国统计局发布数据（CPI / GDP / PMI 等），按天分组
/// TradingView 淡雅：卡片化 + 新色板 + Tabler 图标
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
        .background(DS.bgPanel)
        .task {
            await app.store.fetchCalendarEvents()
        }
    }

    // MARK: 空/加载状态

    private var emptyState: some View {
        Group {
            if app.store.calendarLoading {
                DSPlaceholder(icon: .clock, title: L10n.l("common.loading"))
            } else if let err = app.store.calendarError {
                DSPlaceholder(icon: .wifiOff,
                              title: "加载失败：\(err)",
                              actionTitle: L10n.l("common.refresh"),
                              action: { Task { await app.store.fetchCalendarEvents() } })
            } else {
                DSPlaceholder(icon: .calendar,
                              title: L10n.l("sidebar.calendar"),
                              subtitle: L10n.l("calendar.loadingHint"))
            }
        }
    }

    // MARK: 事件列表（按天分组）

    private var eventList: some View {
        let grouped = Dictionary(grouping: app.store.calendarEvents, by: { $0.dayKey })
        let days = grouped.keys.sorted()
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(days, id: \.self) { day in
                    daySection(day: day, events: grouped[day] ?? [])
                }
            }
            .padding(16)
        }
    }

    private func daySection(day: String, events: [EconomicEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 天标题
            HStack(spacing: 8) {
                if isToday(day) {
                    DSChip(text: L10n.l("news.today"), color: DS.accent)
                }
                Text(dayTitle(day))
                    .font(.system(size: DS.sectionHeaderSize, weight: .semibold))
                    .foregroundStyle(DS.textPrimary)
                Spacer()
                Text("\(events.count) 项")
                    .font(.system(size: DS.tickerSize))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.bottom, 2)

            DSCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                        EconomicEventRow(event: event)
                        if idx < events.count - 1 {
                            DSDivider().padding(.leading, 90)
                        }
                    }
                }
            }
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
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(DS.textSecondary)
                .frame(width: 46, alignment: .leading)
            // 地区
            Text(countryShort(event.country))
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 34)
                .padding(.vertical, 3)
                .background(Capsule().fill(countryColor(event.country).opacity(0.12)))
                .foregroundStyle(countryColor(event.country))
            // 事件名
            Text(event.title)
                .font(.system(size: 13))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 重要性
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < event.importance ? importanceColor(event.importance) : DS.border)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 30)
            // 实际 / 预测 / 前值
            valueCell(L10n.l("calendar.actual"), event.actual, bold: true)
            valueCell(L10n.l("calendar.forecast"), event.forecast, bold: false)
            valueCell(L10n.l("calendar.previous"), event.previous, bold: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func valueCell(_ label: String, _ value: String?, bold: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(DS.textTertiary)
            Text(value ?? "—")
                .font(.system(size: 13).monospacedDigit())
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(value == nil ? DS.textTertiary : DS.textPrimary)
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
        case "US": DS.accent
        case "CN": DS.up
        case "EU": .indigo
        case "JP": .pink
        case "UK": .purple
        case "DE": .orange
        case "AU": .teal
        case "CA": DS.down
        default: DS.neutral
        }
    }

    private func importanceColor(_ level: Int) -> Color {
        switch level {
        case 3: DS.up
        case 2: .orange
        default: DS.neutral
        }
    }
}
