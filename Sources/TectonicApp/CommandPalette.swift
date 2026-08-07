import SwiftUI
import CoreKit

// MARK: - ⌘K 命令面板（TradingView 淡雅：输入即搜，上下键选择，回车执行）

/// 命令面板条目
struct CommandItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: TectonicIcon
    let action: () -> Void
}

struct CommandPaletteView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [CommandItem] = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 输入行
            HStack(spacing: 8) {
                TectonicIconView(icon: .search, size: 16, color: DS.textTertiary)
                TextField(L10n.l("cmd.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($fieldFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        TectonicIconView(icon: .x, size: 12, color: DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text("⌘K")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.bgHover))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            DSDivider()

            // 结果列表
            if results.isEmpty && !query.isEmpty {
                VStack(spacing: 8) {
                    TectonicIconView(icon: .searchOff, size: 28, color: DS.textTertiary)
                    Text(L10n.l("cmd.noResult"))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(results) { item in
                            CommandRow(item: item) {
                                item.action()
                                dismiss()
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
            }

            // 底部提示
            HStack(spacing: 12) {
                hintKey(L10n.l("cmd.enter"), text: L10n.l("cmd.execute"))
                hintKey("↑↓", text: L10n.l("cmd.navigate"))
                Spacer()
                hintKey("ESC", text: L10n.l("cmd.close"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 520)
        .background(DS.bgPanel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 6)
        .onAppear {
            fieldFocused = true
            rebuild()
        }
        .onChange(of: query) { _, _ in rebuild() }
    }

    private func hintKey(_ key: String, text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.bgHover))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(DS.textTertiary)
        }
    }

    // MARK: 搜索构建

    private func rebuild() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items: [CommandItem] = []
        let match: (String) -> Bool = { s in
            q.isEmpty || s.lowercased().contains(q)
        }

        // 1. 自选标的
        for item in app.store.watchlist where match(item.symbol.name) || match(item.symbol.code) {
            items.append(CommandItem(
                title: item.symbol.name,
                subtitle: "\(item.symbol.code) · \(item.symbol.market.displayName)",
                icon: .star
            ) {
                app.selectedTab = .watchlist
                app.selectedSymbol = item.symbol
            })
        }

        // 2. 导航
        if match(L10n.l("sidebar.watchlist")) {
            items.append(CommandItem(title: L10n.l("sidebar.watchlist"), subtitle: L10n.l("cmd.nav"), icon: .star) {
                app.selectedTab = .watchlist
            })
        }
        if match(L10n.l("sidebar.markets")) {
            items.append(CommandItem(title: L10n.l("sidebar.markets"), subtitle: L10n.l("cmd.nav"), icon: .chartLine) {
                app.selectedTab = .markets
            })
        }
        for category in NewsFeedCategory.allCases {
            if match(category.displayName) {
                items.append(CommandItem(title: category.displayName, subtitle: L10n.l("cmd.nav"), icon: .news) {
                    app.selectedTab = allItem(for: category)
                })
            }
        }

        // 3. 操作
        if match(L10n.l("cmd.refresh")) || q == "refresh" {
            items.append(CommandItem(title: L10n.l("cmd.refresh"), subtitle: "⌘R", icon: .refresh) {
                Task { await app.refreshAll() }
            })
        }
        if match(L10n.l("cmd.add")) || q == "add" {
            items.append(CommandItem(title: L10n.l("cmd.add"), subtitle: "⌘N", icon: .plus) {
                // 打开添加面板：通过 AppState 通知 ContentView
                app.openAddSymbol = true
            })
        }

        results = items
    }

    private func allItem(for category: NewsFeedCategory) -> AppState.SidebarItem {
        switch category {
        case .flash: .newsFlash
        case .research: .newsResearch
        case .earnings: .newsEarnings
        case .calendar: .newsCalendar
        }
    }
}

/// 命令行
struct CommandRow: View {
    let item: CommandItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                TectonicIconView(icon: item.icon, size: 15, color: hovering ? DS.accent : DS.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                TectonicIconView(icon: .chevronRight, size: 12, color: DS.textTertiary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(hovering ? DS.bgHover : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
