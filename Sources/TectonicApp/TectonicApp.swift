import SwiftUI
import CoreKit

@main
struct TectonicApp: App {
    @StateObject private var appState: AppState

    init() {
        // 图标系统为矢量自绘（Lucide Shape），无需字体注册
        let db = try! AppDatabase.makeDefault()
        _appState = StateObject(wrappedValue: AppState(db: db))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 640)
                // 主题：强调色 + 明暗外观跟随所选主题（设置「通用」里切换）
                .tint(DS.accent)
                .preferredColorScheme(appState.theme.isDark ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("刷新行情") {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandGroup(replacing: .textEditing) {
                Button("命令面板") {
                    NotificationCenter.default.post(name: .commandPaletteToggle, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.aiSettings)
                .frame(width: 760, height: 620)
                // 设置窗口同样跟随主题
                .tint(DS.accent)
                .preferredColorScheme(appState.theme.isDark ? .dark : .light)
        }
    }
}
