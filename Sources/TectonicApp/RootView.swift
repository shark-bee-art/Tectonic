import SwiftUI

/// 窗口根视图：主界面 + 右侧 AI 问询面板（浮层，不改变原有布局）
struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            ContentView()
            // 右侧 AI 问询面板：覆盖整个窗口右侧，浮层不挤压布局
            if let context = app.chatPanel {
                ChatPanelView(context: context)
                    .id(context.id)
                    .zIndex(20)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: app.chatPanel?.id)
    }
}
