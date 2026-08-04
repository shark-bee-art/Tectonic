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
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 640)
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
        }
    }
}
