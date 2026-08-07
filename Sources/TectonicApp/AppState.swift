import SwiftUI
import CoreKit
import Observation
import Combine

/// 应用状态：Store + 设置 + 导航
@MainActor
final class AppState: ObservableObject {
    let store: Store
    let settings: AppSettings

    /// 当前主题（跟随 settings.themeID；切换后 tint/配色即时生效）
    var theme: TectonicTheme {
        TectonicThemeCatalog.theme(id: settings.themeID)
    }
    let aiSettings: AISettings

    private var cancellables: Set<AnyCancellable> = []

    // 导航
    @Published var selectedSymbol: Symbol?
    @Published var selectedNews: NewsItem?
    @Published var selectedTab: SidebarItem = .watchlist

    @Published var isRefreshing = false
    /// 右侧 AI 问询面板（nil = 关闭）
    @Published var chatPanel: ChatPanelContext?

    enum SidebarItem: Hashable {
        case watchlist
        case markets
        case newsFlash
        case newsResearch
        case newsEarnings
        case newsCalendar
        /// 独立查看某个资讯源（sourceID = NewsFeed.id）
        case newsFeed(sourceID: String)
        case holdings
        case transactions

        /// 侧边栏显示名
        var title: String {
            switch self {
            case .watchlist: "自选"
            case .markets: "行情"
            case .newsFlash: "快讯"
            case .newsResearch: "研报"
            case .newsEarnings: "财报"
            case .newsCalendar: "日历"
            case .newsFeed: "订阅源"
            case .holdings: "持仓"
            case .transactions: "交易记录"
            }
        }
    }

    init(db: AppDatabase) {
        self.store = Store(db: db)
        self.settings = AppSettings()
        self.aiSettings = AISettings()
        // 转发 Store 内部 @Published 变化（自选/行情/资讯源等），保证 UI 实时同步
        store.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        // 转发设置变化（语言/刷新频率切换后 UI 与定时器即时生效）
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.startAutoRefresh()
            }
            .store(in: &cancellables)
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

    /// 按设置频率启动/重建自动刷新定时器（5/10/30/60 分钟；手动刷新随时可用）
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let minutes = max(settings.refreshIntervalMinutes, 5)
        let timer = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
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
