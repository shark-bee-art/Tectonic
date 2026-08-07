import SwiftUI
import AppKit

/// 窗口根视图：主界面 + 底部悬浮 AI 对话框 + ⌘K 命令面板
struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            // 主界面
            ContentView()
                .frame(minWidth: 1000, minHeight: 640)

            // 底部悬浮 AI 对话框（不挤压主界面布局）
            if let context = app.chatPanel {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ChatPanelView(context: context)
                            .id(context.id)
                            .padding(.bottom, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Spacer()
                    }
                }
                .zIndex(20)
                .allowsHitTesting(true)
            }

            // ⌘K 命令面板（覆盖层，居中）
            if app.showCommandPalette {
                CommandPaletteView()
                    .environmentObject(app)
                    .zIndex(30)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: app.chatPanel?.id)
        .animation(.easeOut(duration: 0.15), value: app.showCommandPalette)
        // ⌘K 快捷键
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteToggle)) { _ in
            app.showCommandPalette.toggle()
        }
        // ESC：关闭命令面板 / AI 对话框
        .background(
            KeyEventHandlingView { key in
                if key == 53 { // ESC
                    if app.showCommandPalette { app.showCommandPalette = false; return true }
                    if app.chatPanel != nil { app.chatPanel = nil; return true }
                }
                return false
            }
        )
        // 窗口内容区背景跟随主题（DS token）
        .background(DS.bgApp)
    }
}

/// 命令面板 ⌘K 通知（TectonicApp commands 里发送）
extension Notification.Name {
    static let commandPaletteToggle = Notification.Name("commandPaletteToggle")
}

/// 键盘事件拦截（ESC 关闭面板）
struct KeyEventHandlingView: NSViewRepresentable {
    let onKey: (UInt16) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let v = KeyView()
        v.onKey = onKey
        return v
    }
    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onKey = onKey
    }
}

final class KeyView: NSView {
    var onKey: (UInt16) -> Bool = { _ in false }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey(event.keyCode) { return }
        super.keyDown(with: event)
    }
}
