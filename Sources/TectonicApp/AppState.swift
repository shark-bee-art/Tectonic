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
    @Published var selectedNews: NewsItem?
    @Published var selectedTab: SidebarItem = .watchlist

    @Published var isRefreshing = false

    enum SidebarItem: String, Hashable {
        case watchlist = "自选"
        case markets = "行情"
        case newsFlash = "快讯"
        case newsResearch = "研报"
        case newsEarnings = "财报"
        case newsCalendar = "日历"
        case holdings = "持仓"
    }

    init(db: AppDatabase) {
        self.store = Store(db: db)
        self.settings = AppSettings()
        self.aiSettings = AISettings()
    }

    // 行情自动刷新（60s）
    private var refreshTimer: Timer?

    /// 刷新自选行情
    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await store.refreshQuotes()
    }

    /// 首次启动自动刷一次 + 导入内置标的/订阅源 + 启动定时刷新
    func onAppear() {
        // 首启导入内置标的（幂等）
        do {
            let added = try store.importBuiltinIfNeeded()
            if added > 0 { print("Tectonic: 已导入 \(added) 个内置标的") }
        } catch {
            print("Tectonic: 内置标的导入失败 \(error)")
        }
        // 首启导入预置资讯订阅源（幂等）
        do {
            let added = try store.importBuiltinFeedsIfNeeded()
            if added > 0 { print("Tectonic: 已导入 \(added) 个资讯订阅源") }
        } catch {
            print("Tectonic: 订阅源导入失败 \(error)")
        }
        Task { await refreshAll() }
        startAutoRefresh()
    }

    func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }
}

// MARK: - 便捷访问（供 SwiftUI 视图）

extension AppState {
    /// 当前启用的市场（按用户排序）
    var activeMarkets: [Market] {
        settings.marketOrder.filter { settings.isEnabled($0) }
    }
}
