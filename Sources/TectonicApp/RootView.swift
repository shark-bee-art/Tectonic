import SwiftUI
import AppKit

/// 窗口根视图：主界面 + 右侧 AI 问询面板 + ⌘K 命令面板
/// 面板打开时整体窗口向右膨出 430pt（原界面布局完全不变），关闭时缩回
struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var window: NSWindow?
    @State private var panelExpanded = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // 主界面：始终保持原有尺寸与布局
                ContentView()
                    .frame(minWidth: 1000, minHeight: 640)

                // 右侧问询面板（膨出区）
                if let context = app.chatPanel {
                    ChatPanelView(context: context)
                        .id(context.id)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: app.chatPanel?.id)
            .background(WindowAccessor { window in
                self.window = window
                let expanded = app.chatPanel != nil
                guard expanded != panelExpanded else { return }
                panelExpanded = expanded
                if let window {
                    var frame = window.frame
                    frame.size.width += expanded ? 430 : -430
                    window.setFrame(frame, display: true, animate: true)
                }
            })

            // ⌘K 命令面板（覆盖层，居中）
            if app.showCommandPalette {
                CommandPaletteView()
                    .environmentObject(app)
                    .zIndex(30)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: app.showCommandPalette)
        // ⌘K 快捷键
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteToggle)) { _ in
            app.showCommandPalette.toggle()
        }
        // ⌘K：命令面板 / ESC：关闭
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

/// 获取 NSWindow 引用（用于窗口膨出/缩回）
struct WindowAccessor: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window) }
    }
}
