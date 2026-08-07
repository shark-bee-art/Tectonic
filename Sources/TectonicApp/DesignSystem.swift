import SwiftUI
import CoreKit

// MARK: - Tectonic 设计系统 v3（Robinhood 视觉语言）
// 来源：Meliwat/awesome-ios-design-md → finance/robinhood（MIT 参考）
// 纯白画布 / 纯黑文字 / 品牌绿 #00C805 + 橙红 #FF5000（涨跌绑定方向）/ 全等宽数字 / 极简扁平
// ⚠️ 涨跌映射按中国习惯反转：涨=红(#FF5000 橙红) 跌=绿(#00C805) —— RH 原版是绿涨红跌

/// 设计令牌（Robinhood 谱系；深浅色自动跟随主题）
enum DS {
    // MARK: 色板（RH 浅色主体系）

    /// 画布（纯白）
    static var bgApp: Color { themeColor(\.background, fallback: Color(hex: "#FFFFFF") ?? .white) }
    /// 表面灰（section 背景、hover）
    static var bgPanel: Color { themeColor(\.sidebar, fallback: Color(hex: "#FFFFFF") ?? .white) }
    /// 表面灰 2（输入框填充、按压态）
    static var bgSurface: Color { themeColor(\.hover, fallback: Color(hex: "#F7F7F7") ?? .gray.opacity(0.1)) }
    /// 行 hover（RH Surface Gray）
    static var bgHover: Color { themeColor(\.hover, fallback: Color(hex: "#F7F7F7") ?? .gray.opacity(0.08)) }
    /// 行选中（RH watchlist row press）
    static var bgSelected: Color { themeColor(\.selection, fallback: Color(hex: "#EFEFEF") ?? .gray.opacity(0.15)) }
    /// 主文字（纯黑，非软化灰——RH 品牌特征）
    static var textPrimary: Color { themeColor(\.text, fallback: Color(hex: "#000000") ?? .primary) }
    /// 次要文字
    static var textSecondary: Color { themeColor(\.secondary, fallback: Color(hex: "#5C6166") ?? .secondary) }
    /// 三级文字（占位符）
    static var textTertiary: Color { themeColor(\.tertiary, fallback: Color(hex: "#9B9EA3") ?? .gray) }
    /// 弱文字（骨架）
    static var textMuted: Color { Color(hex: "#C2C5CA") ?? textTertiary }
    /// 强调（选中指示/链接）—— RH 风格用黑色做选中，品牌绿保留语义
    static var accent: Color { themeColor(\.accent, fallback: Color(hex: "#000000") ?? .black) }
    /// 主按钮（Trade 按钮 = 黑色白字，非绿色——RH 铁律）
    static var tradeButton: Color { Color(hex: "#000000") ?? .black }
    static var tradeButtonPressed: Color { Color(hex: "#1A1A1A") ?? .black.opacity(0.9) }
    /// 分割线
    static var border: Color { themeColor(\.border, fallback: Color(hex: "#E6E6E6") ?? .gray.opacity(0.2)) }
    /// 输入框描边
    static var borderStrong: Color { themeColor(\.border, fallback: Color(hex: "#E6E6E6") ?? border) }

    // MARK: 涨跌语义（⚠️ 中国习惯：红涨绿跌）

    /// 涨（橙红 #FF5000——RH Red 实为橙，友好感）
    static var up: Color { Color(hex: "#FF5000") ?? .red }
    /// 跌（品牌绿 #00C805）
    static var down: Color { Color(hex: "#00C805") ?? .green }
    /// 涨跌按压
    static var upPressed: Color { Color(hex: "#E04700") ?? up }
    static var downPressed: Color { Color(hex: "#00A904") ?? down }
    /// 涨背景 tint（红 tint）
    static var upBg: Color { Color(hex: "#FFEDE5") ?? up.opacity(0.12) }
    /// 跌背景 tint（绿 tint）
    static var downBg: Color { Color(hex: "#E6F9E0") ?? down.opacity(0.12) }
    /// 中性
    static var neutral: Color { textSecondary }
    /// 硬错误（真红 #E62232，区别于涨跌橙/绿）
    static var errorRed: Color { Color(hex: "#E62232") ?? .red }

    /// 涨跌方向色（change >= 0 → up）
    static func directionColor(_ change: Double) -> Color { change >= 0 ? up : down }

    /// 从当前主题取色板字段
    private static func themeColor(_ keyPath: KeyPath<TectonicTheme, String>, fallback: Color) -> Color {
        let hex = TectonicThemeCatalog.theme(id: UserDefaults.standard.string(forKey: "theme_id") ?? TectonicThemeCatalog.defaultID)[keyPath: keyPath]
        return Color(hex: hex) ?? fallback
    }

    // MARK: 间距（RH：基准 4pt，水平 margin 16pt，section gap 32pt）

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    // MARK: 圆角（RH：4/8/12/16/24/circle）

    static let radiusSmall: CGFloat = 4
    static let radiusMedium: CGFloat = 8    // 主按钮/卡片
    static let radiusCard: CGFloat = 12    // 搜索框/新闻卡片/行按压
    static let radiusLarge: CGFloat = 16
    static let radiusCapsule: CGFloat = 999

    // MARK: 字号（RH Capsule Sans 谱系，SF 替代）

    static let heroSize: CGFloat = 40      // Portfolio Hero
    static let screenTitleSize: CGFloat = 22
    static let sectionHeaderSize: CGFloat = 18
    static let positionTitleSize: CGFloat = 16
    static let positionValueSize: CGFloat = 17
    static let tickerSize: CGFloat = 13    // 带 +0.3pt tracking
    static let bodySize: CGFloat = 15
    static let bodySmallSize: CGFloat = 13
    static let buttonSize: CGFloat = 16
    static let captionSize: CGFloat = 11   // All-Caps 标签
    static let tabSize: CGFloat = 10
}

// MARK: - 数字格式化（tabular 是 RH 铁律）

extension Text {
    /// 价格/百分比用等宽数字
    static func num(_ s: String, size: CGFloat, weight: Font.Weight = .regular) -> Text {
        Text(s).font(.system(size: size, weight: weight).monospacedDigit())
    }
}

// MARK: - 基础组件（Robinhood 规范）

/// All-Caps 小节标签（BUYING POWER / TODAY'S RETURN 风格）
struct DSCapsLabel: View {
    let text: String
    var color: Color = DS.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: DS.captionSize, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(color)
    }
}

/// Hero 大数字（40pt Display 粗体 + tabular）
struct DSHeroValue: View {
    let value: String
    var color: Color = DS.textPrimary
    var size: CGFloat = DS.heroSize

    var body: some View {
        Text(value)
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
            .kerning(-0.5)
    }
}

/// Position Row（RH 核心行组件：56pt 高，左侧 32pt 圆角图标 + 名称/代码，右侧价值/涨跌）
struct PositionRow: View {
    let name: String
    let ticker: String          // 代码（tracking +0.3）
    let icon: TectonicIcon      // 左侧 32×32 图标
    let value: String?          // 右侧价值（tabular）
    let change: Double?         // 涨跌（绑定方向色）
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space3) {
                // 左侧 32×32 圆角徽章（RH logo/ticker badge）
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(iconBadgeColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                        TectonicIconView(icon: icon, size: 16,
                                         color: iconBadgeColor.isLight ? .black : .white)
                    )

                // 中间：名称 + 代码
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: DS.positionTitleSize, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(ticker)
                        .font(.system(size: DS.tickerSize, weight: .medium))
                        .kerning(0.3)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // 右侧：价值 + 涨跌
                if let value {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(value)
                            .font(.system(size: DS.positionValueSize, weight: .medium).monospacedDigit())
                            .foregroundStyle(DS.textPrimary)
                        if let change {
                            Text(String(format: "%+.2f%%", change))
                                .font(.system(size: DS.tickerSize, weight: .medium).monospacedDigit())
                                .foregroundStyle(DS.directionColor(change))
                        }
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, DS.space4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DS.radiusCard)
                    .fill(isSelected ? DS.bgSelected : (hovering ? DS.bgHover : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var iconBadgeColor: Color {
        if let change {
            return DS.directionColor(change).opacity(0.12)
        }
        return DS.bgSurface
    }
}

/// 主按钮（RH Trade 按钮：黑色底白字，8pt 圆角，48pt 高）
struct DSTradeButton: View {
    let title: String
    let action: () -> Void
    var disabled: Bool = false
    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: DS.buttonSize, weight: .semibold))
                .foregroundStyle(disabled ? DS.textMuted : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(disabled ? DS.bgSurface : (pressing ? DS.tradeButtonPressed : DS.tradeButton))
                )
                .scaleEffect(pressing ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { _ in }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
    }
}

/// 次级描边按钮（Set Alert / Add to List）
struct DSOutlineButton: View {
    let title: String
    var icon: TectonicIcon? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    TectonicIconView(icon: icon, size: 14, color: hovering ? DS.textPrimary : DS.textSecondary)
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(hovering ? DS.textPrimary : DS.textSecondary)
            }
            .padding(.horizontal, DS.space5)
            .padding(.vertical, DS.space3)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(hovering ? DS.bgSurface : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .stroke(DS.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 图标按钮（RH 无描边，hover 灰底）
struct DSIconButton: View {
    let icon: TectonicIcon
    var size: CGFloat = 16
    var color: Color? = nil
    var help: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TectonicIconView(icon: icon, size: size, color: color ?? (hovering ? DS.textPrimary : DS.textSecondary))
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

/// 搜索框（RH：Surface Gray 底，12pt 圆角，44pt 高）
struct DSSearchField: View {
    @Binding var text: String
    var placeholder: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TectonicIconView(icon: .search, size: 16,
                             color: focused ? DS.textPrimary : DS.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
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
        .padding(.horizontal, DS.space3)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusCard)
                .fill(focused ? DS.bgPanel : DS.bgSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusCard)
                        .stroke(focused ? DS.textPrimary : .clear, lineWidth: 1)
                )
        )
    }
}

/// 通用输入框（表单用）
struct DSInputField: View {
    @Binding var text: String
    var placeholder: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, DS.space3)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusCard)
                    .fill(DS.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusCard)
                            .stroke(focused ? DS.textPrimary : DS.border, lineWidth: 1)
                    )
            )
            .focused($focused)
    }
}

/// 卡片容器（RH News Card：12pt 圆角，1pt border）
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

/// 涨跌胶囊（RH Day Change：无底色纯文字 or tint 背景）
struct DSChangeChip: View {
    let change: Double
    var withBackground: Bool = false

    var body: some View {
        let color = DS.directionColor(change)
        Text(String(format: "%+.2f%%", change))
            .font(.system(size: DS.tickerSize, weight: .medium).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, withBackground ? 8 : 0)
            .padding(.vertical, withBackground ? 3 : 0)
            .background(withBackground ? Capsule().fill(color.opacity(0.12)) : nil)
    }
}

/// AI 标签胶囊
struct DSChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: DS.captionSize, weight: .semibold))
            .kerning(0.3)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }
}

/// 自绘分割线（RH hairline 0.5-1pt）
struct DSDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.border)
            .frame(height: 1)
    }
}

/// 空状态/加载占位（RH：图标 + 标题 + 说明，居中）
struct DSPlaceholder: View {
    let icon: TectonicIcon
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.space3) {
            TectonicIconView(icon: icon, size: 40, color: DS.textTertiary)
            Text(title)
                .font(.system(size: DS.bodySize))
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: DS.bodySmallSize))
                    .foregroundStyle(DS.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                DSOutlineButton(title: actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 行情行（自选/行情列表——复用 PositionRow 形态）
struct DSQuoteRow: View {
    let name: String
    let subtitle: String
    let price: String?
    let change: Double?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PositionRow(name: name,
                    ticker: subtitle,
                    icon: .chartLine,
                    value: price,
                    change: change,
                    isSelected: isSelected,
                    action: action)
    }
}

// MARK: - Color 亮度工具

extension Color {
    /// 粗略判断颜色是否为浅色（用于徽章图标反色）
    var isLight: Bool {
        guard let comps = NSColor(self).usingColorSpace(.sRGB) else { return true }
        let lum = 0.299 * comps.redComponent + 0.587 * comps.greenComponent + 0.114 * comps.blueComponent
        return lum > 0.6
    }
}

// MARK: - 侧边栏项（RH 风格：无指示条，选中=黑字+灰底）

struct SidebarItemRow: View {
    let icon: TectonicIcon
    let title: String
    let isSelected: Bool
    let isExpanded: Bool?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                TectonicIconView(icon: icon, size: 18,
                                 color: isSelected ? DS.textPrimary : (hovering ? DS.textPrimary : DS.textSecondary))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let expanded = isExpanded {
                    TectonicIconView(icon: .chevronDown, size: 14, color: DS.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .animation(.easeOut(duration: 0.15), value: expanded)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DS.radiusCard)
                    .fill(isSelected ? DS.bgSelected : (hovering ? DS.bgHover : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
