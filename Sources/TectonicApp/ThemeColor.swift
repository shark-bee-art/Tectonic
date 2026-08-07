import SwiftUI

// MARK: - 主题色工具（hex → Color；CoreKit 只存 hex 字符串，转换在 App 层）

extension Color {
    /// 从 hex 字符串（#RRGGBB）创建颜色；非法输入返回 nil
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }
}
