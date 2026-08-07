import SwiftUI
import CoreKit

// MARK: - Tectonic v2 设计系统（TradingView 淡雅强化）
// 色板 / 间距 / 圆角 / 组件库。深色同谱系反色通过 TectonicTheme 提供。

/// 设计令牌（浅色默认体系；随主题切换）
enum DS {
    // MARK: 色板（浅色 TradingView 谱系）

    static var bgApp: Color { themeColor(\.background, fallback: Color(hex: "#F8F9FA") ?? .gray.opacity(0.06)) }
    static var bgPanel: Color { themeColor(\.background, fallback: .white) }
    static var bgHover: Color { themeColor(\.hover, fallback: Color(hex: "#F0F3FA") ?? .gray.opacity(0.08)) }
    static var bgSelected: Color { themeColor(\.selection, fallback: Color(hex: "#E8F0FE") ?? .blue.opacity(0.10)) }
    static var textPrimary: Color { themeColor(\.text, fallback: Color(hex: "#131722") ?? .primary) }
    static var textSecondary: Color { themeColor(\.secondary, fallback: Color(hex: "#787B86") ?? .secondary) }
    static var textTertiary: Color { themeColor(\.tertiary, fallback: Color(hex: "#B2B5BE") ?? Color.gray.opacity(0.4)) }
    static var accent: Color { themeColor(\.accent, fallback: Color(hex: "#2962FF") ?? .blue) }
    static var accentHover: Color { Color(hex: "#1E53E5") ?? accent }
    static var border: Color { themeColor(\.border, fallback: Color(hex: "#E0E3EB") ?? .gray.opacity(0.2)) }
    /// 强分隔/输入框描边：跟随主题 border（深浅主题自适应）
    static var borderStrong: Color { themeColor(\.border, fallback: Color(hex: "#D1D4DC") ?? border) }
    /// 涨（红，中国习惯）
    static var up: Color { Color(hex: "#F23645") ?? .red }
    /// 跌（绿）
    static var down: Color { Color(hex: "#089981") ?? .green }
    /// 中性
    static var neutral: Color { Color(hex: "#787B86") ?? .gray }

    static func directionColor(_ change: Double) -> Color { change >= 0 ? up : down }

    /// 从当前主题取色板字段
    private static func themeColor(_ keyPath: KeyPath<TectonicTheme, String>, fallback: Color) -> Color {
        let hex = TectonicThemeCatalog.theme(id: UserDefaults.standard.string(forKey: "theme_id") ?? TectonicThemeCatalog.defaultID)[keyPath: keyPath]
        return Color(hex: hex) ?? fallback
    }

    // MARK: 间距

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24

    // MARK: 圆角

    static let radiusSmall: CGFloat = 4
    static let radiusMedium: CGFloat = 6
    static let radiusCard: CGFloat = 8
    static let radiusCapsule: CGFloat = 999

    // MARK: 行高/字号

    static let listTitleSize: CGFloat = 13.5
    static let listBodySize: CGFloat = 13
    static let metaSize: CGFloat = 11
    static let captionSize: CGFloat = 12
    static let buttonSize: CGFloat = 13
}

// MARK: - 基础组件

/// 自绘侧边栏项：图标 + 名称 + 选中指示条（TradingView 风格）
struct SidebarItemRow: View {
    let icon: TectonicIcon
    let title: String
    let isSelected: Bool
    let isExpanded: Bool?          // 非 nil = 可展开分类（显示 chevron）
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // 选中指示条
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? DS.accent : .clear)
                    .frame(width: 3, height: 16)
                TectonicIconView(icon: icon, size: 18,
                                 color: isSelected ? DS.accent : (hovering ? DS.textPrimary : DS.textSecondary))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.accent : DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let expanded = isExpanded {
                    TectonicIconView(icon: .chevronDown, size: 14, color: DS.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .animation(.easeOut(duration: 0.15), value: expanded)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(isSelected ? DS.bgSelected : (hovering ? DS.bgHover : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 自绘主按钮
struct DSButton: View {
    let title: String
    let icon: TectonicIcon?
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, icon: TectonicIcon? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    TectonicIconView(icon: icon, size: 14,
                                     color: prominent ? .white : (hovering ? DS.accent : DS.textPrimary))
                }
                Text(title)
                    .font(.system(size: DS.buttonSize, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(prominent ? (hovering ? DS.accentHover : DS.accent) : (hovering ? DS.bgHover : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(prominent ? .clear : DS.borderStrong, lineWidth: 1)
            )
            .foregroundStyle(prominent ? .white : DS.textPrimary)
            .scaleEffect(hovering ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 自绘图标按钮
struct DSIconButton: View {
    let icon: TectonicIcon
    var size: CGFloat = 16
    var color: Color? = nil
    var help: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TectonicIconView(icon: icon, size: size, color: color ?? (hovering ? DS.accent : DS.textSecondary))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(hovering ? DS.bgHover : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
    }
}

/// 自绘输入框（聚焦描边 + 光晕）
struct DSInputField: View {
    @Binding var text: String
    var placeholder: String = ""
    var icon: TectonicIcon? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                TectonicIconView(icon: icon, size: 14, color: focused ? DS.accent : DS.textTertiary)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    TectonicIconView(icon: .x, size: 12, color: DS.textTertiary)
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.bgPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(focused ? DS.accent : DS.borderStrong, lineWidth: 1)
                )
                .shadow(color: focused ? DS.accent.opacity(0.10) : .clear, radius: 4)
        )
    }
}

/// 自绘卡片容器
struct DSCard<Content: View>: View {
    var padding: CGFloat = DS.space4
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusCard)
                    .fill(DS.bgPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusCard)
                            .stroke(DS.border, lineWidth: 1)
                    )
            )
    }
}

/// 自绘胶囊标签（AI 判断 / 日历国家等）
struct DSChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }
}

/// 自绘分割线（1px 主题色）
struct DSDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.border)
            .frame(height: 1)
    }
}

/// 空状态/加载占位
struct DSPlaceholder: View {
    let icon: TectonicIcon
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            TectonicIconView(icon: icon, size: 40, color: DS.textTertiary)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                DSButton(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 行情行（自选/行情列表）
struct DSQuoteRow: View {
    let name: String
    let subtitle: String
    let price: String?
    let change: Double?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: DS.listTitleSize, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: DS.metaSize))
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let price {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(.system(size: DS.listTitleSize, weight: .medium).monospacedDigit())
                            .foregroundStyle(DS.textPrimary)
                        if let change {
                            Text(String(format: "%+.2f%%", change))
                                .font(.system(size: DS.metaSize).monospacedDigit())
                                .foregroundStyle(DS.directionColor(change))
                        }
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(isSelected ? DS.bgSelected : (hovering ? DS.bgHover : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
