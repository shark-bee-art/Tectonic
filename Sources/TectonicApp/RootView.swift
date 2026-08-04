import SwiftUI
import AppKit

/// 窗口根视图：主界面 + 右侧 AI 问询面板
/// 面板打开时整体窗口向右膨出 430pt（原界面布局完全不变），关闭时缩回
struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var window: NSWindow?
    @State private var panelExpanded = false

    var body: some View {
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
