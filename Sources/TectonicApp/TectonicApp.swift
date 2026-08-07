import SwiftUI
import CoreKit

@main
struct TectonicApp: App {
    @StateObject private var appState: AppState

    init() {
        let db = try! AppDatabase.makeDefault()
        _appState = StateObject(wrappedValue: AppState(db: db))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 640)
                // 主题：强调色 + 明暗外观跟随所选主题（设置「通用」里切换）
                .tint(Color(hex: appState.theme.accent) ?? .accentColor)
                .preferredColorScheme(appState.theme.isDark ? .dark : .light)
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button("刷新行情") {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.aiSettings)
                .frame(width: 640, height: 620)
                // 设置窗口同样跟随主题
                .tint(Color(hex: appState.theme.accent) ?? .accentColor)
                .preferredColorScheme(appState.theme.isDark ? .dark : .light)
        }
    }
}
