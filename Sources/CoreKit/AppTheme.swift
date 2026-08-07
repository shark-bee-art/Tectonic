import Foundation

// MARK: - Tectonic 主题（参考 Hermes 内置皮肤风格谱系，20 种预置）

/// 主题色板（hex 字符串，CoreKit 不依赖 SwiftUI；Color 转换在 App 层）
public struct TectonicTheme: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// 是否深色外观（决定 preferredColorScheme）
    public var isDark: Bool

    // 色板
    public var background: String    // 主背景（内容区）
    public var sidebar: String       // 侧边栏背景
    public var text: String          // 主文字
    public var secondary: String     // 次要文字
    public var tertiary: String      // 弱文字
    public var accent: String        // 强调色（选中/按钮/链接）
    public var time: String          // 辅助时间/元信息
    public var hover: String         // 行悬停背景
    public var selection: String     // 行选中背景
    public var border: String        // 分割线/边框

    public init(
        id: String, isDark: Bool,
        background: String, sidebar: String, text: String,
        secondary: String, tertiary: String, accent: String,
        time: String, hover: String, selection: String, border: String
    ) {
        self.id = id
        self.isDark = isDark
        self.background = background
        self.sidebar = sidebar
        self.text = text
        self.secondary = secondary
        self.tertiary = tertiary
        self.accent = accent
        self.time = time
        self.hover = hover
        self.selection = selection
        self.border = border
    }
}

// MARK: - 预置主题目录（20 种：12 浅色 + 8 深色）

public enum TectonicThemeCatalog {
    /// 默认主题（TradingView 淡雅风）
    public static let defaultID = "alabaster"

    public static let themes: [TectonicTheme] = [
        // ══════════ 浅色（12）══════════

        // 1. Robinhood 淡雅（默认）：纯白画布 + 纯黑文字 + 品牌绿/橙红涨跌 —— v3 重写默认
        TectonicTheme(
            id: "alabaster", isDark: false,
            background: "#FFFFFF", sidebar: "#FFFFFF", text: "#000000",
            secondary: "#5C6166", tertiary: "#9B9EA3", accent: "#000000",
            time: "#5C6166", hover: "#F7F7F7", selection: "#EFEFEF", border: "#E6E6E6"
        ),
        // 2. 纸张：奶油纸 + 深棕墨 + 焦糖 —— typewriter
        TectonicTheme(
            id: "typewriter", isDark: false,
            background: "#F6F0E2", sidebar: "#EDE4CC", text: "#3A3226",
            secondary: "#7C6F58", tertiary: "#A99C82", accent: "#8A6D3B",
            time: "#5C4B30", hover: "#EFE5CD", selection: "#E6D8B6", border: "#E0D5BA"
        ),
        // 3. 樱花：粉白 + 玫瑰粉 —— sakura
        TectonicTheme(
            id: "sakura", isDark: false,
            background: "#FDF7F8", sidebar: "#F8EDF0", text: "#483238",
            secondary: "#8C6F78", tertiary: "#B39CA4", accent: "#D96A8C",
            time: "#9E526E", hover: "#FBE9EE", selection: "#F8DBE5", border: "#EFDDE2"
        ),
        // 4. 柔和：暖灰 + 紫罗兰 —— catppuccin
        TectonicTheme(
            id: "catppuccin", isDark: false,
            background: "#EFF1F5", sidebar: "#E5E8EF", text: "#4C4F69",
            secondary: "#7C7F93", tertiary: "#A5ADCB", accent: "#7287FD",
            time: "#5C5F77", hover: "#E1E5F2", selection: "#DADFF0", border: "#D8DCE8"
        ),
        // 5. 羊皮纸：暖米 + 深棕 + 赭黄 —— warm-parchment
        TectonicTheme(
            id: "warm-parchment", isDark: false,
            background: "#F7F1E4", sidebar: "#EFE6D0", text: "#3D3526",
            secondary: "#82745A", tertiary: "#ABA089", accent: "#A07C2E",
            time: "#6B5A33", hover: "#F0E7D0", selection: "#E8DAB8", border: "#E2D8BE"
        ),
        // 6. 骨白：冷米白 + 石板灰 + 靛蓝 —— bone-white
        TectonicTheme(
            id: "bone-white", isDark: false,
            background: "#F6F6F2", sidebar: "#ECECE6", text: "#26262B",
            secondary: "#6E6E76", tertiary: "#9E9EA6", accent: "#4A5A8A",
            time: "#3A4458", hover: "#E8EAF0", selection: "#DADEF0", border: "#E0E0D8"
        ),
        // 7. 亚麻鼠尾草：灰绿 + 橄榄 —— linen-sage
        TectonicTheme(
            id: "linen-sage", isDark: false,
            background: "#F2F3EC", sidebar: "#E7EAE0", text: "#2E3329",
            secondary: "#6C7262", tertiary: "#9CA292", accent: "#5E7A3E",
            time: "#4A5A3A", hover: "#E5EBDD", selection: "#D8E2CC", border: "#DDE0D4"
        ),
        // 8. 灰玫瑰：灰粉 + 干玫瑰 —— dusty-rose
        TectonicTheme(
            id: "dusty-rose", isDark: false,
            background: "#F8F4F3", sidebar: "#F0E8E6", text: "#3A3130",
            secondary: "#7E6F6C", tertiary: "#A99E9C", accent: "#A25E6A",
            time: "#6E5058", hover: "#F1E4E2", selection: "#E8D4D2", border: "#E6DAD8"
        ),
        // 9. 蜜桃：暖桃 + 珊瑚 —— peach-fuzz
        TectonicTheme(
            id: "peach-fuzz", isDark: false,
            background: "#FBF3EE", sidebar: "#F5E9E0", text: "#3D322C",
            secondary: "#837068", tertiary: "#ADA099", accent: "#D97A4A",
            time: "#8A5E42", hover: "#F6E5DA", selection: "#F0D8C8", border: "#EDDED2"
        ),
        // 10. 海沫丝：薄荷白 + 海绿 —— seafoam-silk
        TectonicTheme(
            id: "seafoam-silk", isDark: false,
            background: "#F0F6F3", sidebar: "#E4EFEA", text: "#24352E",
            secondary: "#5F756C", tertiary: "#8FA69C", accent: "#2E8B74",
            time: "#3E6B5A", hover: "#DEEBE4", selection: "#D0E2D8", border: "#D8E4DE"
        ),
        // 11. 正午：明亮蓝白 + 天空蓝 —— high-noon
        TectonicTheme(
            id: "high-noon", isDark: false,
            background: "#F8FAFD", sidebar: "#EDF2F8", text: "#1E2A3A",
            secondary: "#5F6E82", tertiary: "#93A2B5", accent: "#2E7FE0",
            time: "#2A4A70", hover: "#E4EEFA", selection: "#D6E6F8", border: "#DDE5EE"
        ),
        // 12. 薰衣草：淡紫白 + 紫罗兰 —— lavender-dream
        TectonicTheme(
            id: "lavender-dream", isDark: false,
            background: "#F7F5FB", sidebar: "#EFEBF7", text: "#322E42",
            secondary: "#736C88", tertiary: "#A39DB8", accent: "#7B5EA7",
            time: "#5A4E78", hover: "#ECE6F6", selection: "#E0D6F0", border: "#E2DCEA"
        ),

        // ══════════ 深色（8）══════════

        // 13. 黑曜石：纯黑 + 银灰 + 冷银蓝 —— obsidian
        TectonicTheme(
            id: "obsidian", isDark: true,
            background: "#0F0F0F", sidebar: "#171717", text: "#D0D0D0",
            secondary: "#8A8A8A", tertiary: "#565656", accent: "#7A8AB8",
            time: "#A8B0C8", hover: "#222228", selection: "#2A2A34", border: "#2C2C2C"
        ),
        // 14. 深海：深蓝黑 + 海蓝 —— deep-ocean
        TectonicTheme(
            id: "deep-ocean", isDark: true,
            background: "#0D1524", sidebar: "#0A101C", text: "#D8E2F0",
            secondary: "#8095B0", tertiary: "#51627C", accent: "#4FA3E8",
            time: "#9FB8D8", hover: "#16233C", selection: "#1C2E4C", border: "#1E2F48"
        ),
        // 15. 霓虹：深紫黑 + 霓虹粉 —— neonwave
        TectonicTheme(
            id: "neonwave", isDark: true,
            background: "#150A26", sidebar: "#0F061C", text: "#E9E0F6",
            secondary: "#9B87BA", tertiary: "#5F4E7C", accent: "#F72585",
            time: "#BBA8DE", hover: "#251540", selection: "#301B4E", border: "#2C1B48"
        ),
        // 16. 石墨：中性深灰 + 钢蓝 —— graphite
        TectonicTheme(
            id: "graphite", isDark: true,
            background: "#16181D", sidebar: "#1D2026", text: "#D2D4DA",
            secondary: "#8A8E98", tertiary: "#565A64", accent: "#7E93B8",
            time: "#A2A8B4", hover: "#242830", selection: "#2C313C", border: "#2A2E36"
        ),
        // 17. 午夜工作室：深蓝黑 + 冷白 —— midnight-studio
        TectonicTheme(
            id: "midnight-studio", isDark: true,
            background: "#10141E", sidebar: "#161C28", text: "#DCE2EE",
            secondary: "#8E98AC", tertiary: "#5A6478", accent: "#5FA8E8",
            time: "#A6B2C6", hover: "#1B2332", selection: "#222C40", border: "#232B3A"
        ),
        // 18. 锻造大师：深绿黑 + 铜绿 —— forge-master
        TectonicTheme(
            id: "forge-master", isDark: true,
            background: "#0E1412", sidebar: "#151D1A", text: "#D8E2DC",
            secondary: "#87988F", tertiary: "#55645C", accent: "#4FA87E",
            time: "#A2B8AC", hover: "#1A2620", selection: "#21332A", border: "#24302A"
        ),
        // 19. 红色警报：深红黑 + 警报红 —— red-alert
        TectonicTheme(
            id: "red-alert", isDark: true,
            background: "#160F10", sidebar: "#1E1517", text: "#E2D6D8",
            secondary: "#9A868A", tertiary: "#635458", accent: "#E05050",
            time: "#B49CA0", hover: "#271A1D", selection: "#322024", border: "#2C1E22"
        ),
        // 20. 虚空日落：深紫红 + 夕阳橙 —— void-sunset
        TectonicTheme(
            id: "void-sunset", isDark: true,
            background: "#171020", sidebar: "#1E1528", text: "#E4DAEA",
            secondary: "#9C8AAE", tertiary: "#645472", accent: "#E07A5A",
            time: "#B8A2C8", hover: "#271C34", selection: "#322442", border: "#2C2038"
        ),
    ]

    /// 按 ID 取主题（未知 ID 回退默认）
    public static func theme(id: String) -> TectonicTheme {
        themes.first { $0.id == id } ?? themes.first { $0.id == defaultID } ?? themes[0]
    }
}
