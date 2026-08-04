import SwiftUI
import CoreKit
import Observation

/// 应用状态：Store + 设置 + 导航
@MainActor
final class AppState: ObservableObject {
    let store: Store
    let settings: AppSettings
    let aiSettings: AISettings

    // 导航
    @Published var selectedSymbol: Symbol?
    @Published var selectedTab: SidebarItem = .watchlist

    @Published var isRefreshing = false

    enum SidebarItem: String, Hashable {
        case watchlist = "自选"
        case markets = "行情"
        case news = "资讯"
        case holdings = "持仓"
    }

    init(db: AppDatabase) {
        self.store = Store(db: db)
        self.settings = AppSettings()
        self.aiSettings = AISettings()
    }

    /// 刷新自选行情
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await store.refreshQuotes()
    }

    /// 首次启动自动刷一次
    func onAppear() {
        Task { await refreshAll() }
    }
}

// MARK: - 便捷访问（供 SwiftUI 视图）

extension AppState {
    /// 当前启用的市场（按用户排序）
    var activeMarkets: [Market] {
        settings.marketOrder.filter { settings.isEnabled($0) }
    }
}
