import SwiftUI
import TectonicIcons
import CoreKit
import UniformTypeIdentifiers

/// 设置：通用 + 市场 + AI + 资讯源
/// 自绘顶部横向 tab（图标 + 文字横排，弃系统 TabView 保证自定义图标渲染）
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedTab = "general"

    private let tabs: [(id: String, icon: TectonicIcon, title: String)] = [
        ("general", .settings, L10n.l("settings.generalTab")),
        ("market", .chartBar, L10n.l("settings.marketTab")),
        ("ai", .sparkles, L10n.l("settings.aiTab")),
        ("news", .news, L10n.l("settings.newsTab")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 顶部横向 tab（居中排列，间距大，字体大）
            HStack(spacing: 28) {
                ForEach(tabs, id: \.id) { tab in
                    settingsNavRow(icon: tab.icon, title: tab.title, selected: selectedTab == tab.id) {
                        selectedTab = tab.id
                    }
                }
            }
            .frame(maxWidth: .infinity)  // 居中
            .padding(.vertical, 12)
            .background(DS.bgSurface)

            DSDivider()

            // 内容区
            Group {
                switch selectedTab {
                case "general": GeneralSettingsTab()
                case "market": MarketSettingsTab()
                case "ai": AISettingsTab()
                default: NewsSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.bgPanel)
    }

    private func settingsNavRow(icon: TectonicIcon, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                TectonicIconView(icon: icon, size: 18,
                                 color: selected ? DS.textPrimary : DS.textSecondary)
                Text(title)
                    .font(.system(size: 16, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(selected ? DS.bgSelected : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 通用设置：界面语言 + 行情刷新频率

struct GeneralSettingsTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section(L10n.l("settings.appearance")) {
                ForEach(TectonicThemeCatalog.themes) { theme in
                    themeRow(theme)
                }
                Text(L10n.l("settings.appearanceHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.l("settings.language")) {
                Picker(L10n.l("settings.language"), selection: Binding(
                    get: { app.settings.preferredLanguage },
                    set: { app.settings.preferredLanguage = $0 }
                )) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                }
                .pickerStyle(.menu)
                Text(L10n.l("settings.languageHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.l("settings.refreshInterval")) {
                Picker(L10n.l("settings.refreshInterval"), selection: Binding(
                    get: { app.settings.refreshIntervalMinutes },
                    set: { app.settings.refreshIntervalMinutes = $0 }
                )) {
                    Text("5 \(L10n.l("settings.minutes"))").tag(5)
                    Text("10 \(L10n.l("settings.minutes"))").tag(10)
                    Text("30 \(L10n.l("settings.minutes"))").tag(30)
                    Text("1 \(L10n.l("settings.hour"))").tag(60)
                }
                .pickerStyle(.menu)
                Text(L10n.l("settings.refreshIntervalHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    /// 主题行（色块预览 + 名称/描述 + 选中圆点；点击即切换，即时生效）
    private func themeRow(_ theme: TectonicTheme) -> some View {
        let selected = app.settings.themeID == theme.id
        return Button {
            app.settings.themeID = theme.id
        } label: {
            HStack(spacing: 10) {
                // 色块预览（accent / time / background / text）
                HStack(spacing: 3) {
                    Circle().fill(Color(hex: theme.accent) ?? .accentColor).frame(width: 10, height: 10)
                    Circle().fill(Color(hex: theme.time) ?? .secondary).frame(width: 10, height: 10)
                    Circle()
                        .fill(Color(hex: theme.background) ?? .gray)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(hex: theme.border) ?? .gray.opacity(0.4), lineWidth: 1))
                    Circle().fill(Color(hex: theme.text) ?? .primary).frame(width: 10, height: 10)
                }
                .frame(width: 52, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.l("theme.name." + theme.id))
                        .foregroundStyle(.primary)
                    Text(L10n.l("theme.desc." + theme.id))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TectonicIconView(icon: selected ? .circleCheck : .circle, size: 15,
                                 color: selected ? DS.accent : DS.textTertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 资讯源设置：订阅源启停 + 添加自定义 RSS

struct NewsSettingsTab: View {
    @EnvironmentObject var app: AppState

    @State private var newName = ""
    @State private var newURL = ""
    @State private var newCategory: NewsFeedCategory = .flash
    @State private var addMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                ForEach(NewsFeedCategory.allCases) { category in
                    Section(category.displayName) {
                        let feeds = app.store.newsFeeds.filter { $0.category == category }
                        if feeds.isEmpty {
                            Text("无订阅源（可在下方添加）")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(feeds, id: \.id) { feed in
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { feed.enabled },
                                    set: { try? app.store.setFeedEnabled(feed, enabled: $0) }
                                ))
                                .labelsHidden()
                                Text(feed.name)
                                Spacer()
                                Text(feed.kind == .rss ? "RSS" : feed.kind.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button {
                                    try? app.store.removeFeed(feed)
                                } label: {
                                    TectonicIconView(icon: .circleX, size: 14, color: DS.textSecondary)
                                }
                                .buttonStyle(.borderless)
                                .help("删除订阅源")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // 添加自定义 RSS
            VStack(alignment: .leading, spacing: 8) {
                Text("添加自定义 RSS 订阅源")
                    .font(.headline)
                if let msg = addMessage {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(msg.hasPrefix("已添加") ? Color.green : Color.red)
                }
                HStack(spacing: 8) {
                    TextField("名称（如：日经中文网）", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    TextField("RSS 地址（https://…）", text: $newURL)
                        .textFieldStyle(.roundedBorder)
                    Picker("分类", selection: $newCategory) {
                        ForEach(NewsFeedCategory.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .frame(width: 100)
                    Button("添加") { addFeed() }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("支持任意 RSS 2.0 / Atom 订阅源；添加后会立即验证可解析")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)

            Button("恢复预置订阅源（\(NewsFeedCatalog.all.count) 个）") {
                _ = try? app.store.importMissingBuiltinFeeds()
                addMessage = nil
            }
        }
        .padding(12)
    }

    private func addFeed() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty, let u = URL(string: url), u.scheme != nil else {
            addMessage = "名称或地址无效"
            return
        }
        // 先验证 RSS 可解析
        Task {
            do {
                let items = try await RSSParser.parse(url: u, sourceName: name, limit: 1)
                guard !items.isEmpty else {
                    addMessage = "该地址不是有效的 RSS 源（无内容）"
                    return
                }
                try app.store.addRSSFeed(name: name, url: url, category: newCategory)
                newName = ""
                newURL = ""
                addMessage = "已添加 \(name)（验证通过，抓到 \(items.count) 条）"
            } catch {
                addMessage = "解析失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 市场设置：开关 + 排序

struct MarketSettingsTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section {
                    Text("选择要显示的市场（按固定顺序展示）")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("显示开关") {
                    ForEach(Market.allCases) { market in
                        Toggle(isOn: Binding(
                            get: { app.settings.isEnabled(market) },
                            set: { app.settings.setEnabled(market, enabled: $0) }
                        )) {
                            HStack {
                                TectonicIconView(icon: marketIcon(market), size: 15, color: DS.textSecondary)
                                    .frame(width: 18)
                                Text(market.displayName)
                                Spacer()
                                Text(market.tradingHours)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            Button("恢复内置标的（\(BuiltinSymbols.all.count) 个）") {
                try? app.store.importBuiltinSymbols()
            }
            .help("重新导入预置的常见标的（幂等，已存在的跳过）")
        }
        .padding(12)
    }

    private func marketIcon(_ m: Market) -> TectonicIcon {
        switch m {
        case .us: .buildingBank
        case .crypto: .currencyBitcoin
        case .hk: .buildingSkyscraper
        case .cn: .building
        case .fund: .chartDonut
        case .kr: .buildingCommunity
        case .jp: .sun
        case .tw: .mountain
        }
    }
}

// MARK: - AI 设置：供应商（分组行列表）+ 模型（下拉）+ Key（本地存储）

/// 搜索服务商下拉文案
private func providerLabel(_ p: SearchProvider) -> String {
    "\(p.displayName)（\(p.freeTier)）"
}

struct AISettingsTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var ai: AISettings
    @State private var availableModels: [String] = []
    @State private var modelSelection: String?
    @State private var showCustomModelField = false

    var body: some View {
        Form {
            Section("供应商") {
                // 按分组：本地 / 国际云端 / 国内云端
                ForEach(providerGroups(), id: \.self) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.textSecondary)
                            .padding(.top, 4)
                        ForEach(ModelProvider.allCases.filter { $0.group == group }) { p in
                            ProviderRow(provider: p)
                                .environmentObject(app)
                        }
                    }
                }
            }

            Section(L10n.l("settings.model")) {
                Picker("模型", selection: $modelSelection) {
                    ForEach(availableModels, id: \.self) { m in
                        Text(m).tag(Optional(m))
                    }
                    if !availableModels.isEmpty {
                        Divider()
                    }
                    Text(L10n.l("settings.customModel")).tag(Optional("__custom__"))
                }
                .pickerStyle(.menu)

                if showCustomModelField {
                    TextField(L10n.l("settings.modelCustomField"), text: $ai.model)
                }

                Text(availableModels.isEmpty
                     ? L10n.l("common.loading")
                     : "\(L10n.l("settings.modelUpdated")) · \(availableModels.count)")
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }

            Section(L10n.l("chat.webSearch")) {
                Picker("搜索服务商", selection: Binding(
                    get: { app.settings.searchProvider },
                    set: { app.settings.searchProvider = $0 }
                )) {
                    ForEach(SearchProvider.allCases) { p in
                        Text(providerLabel(p)).tag(p)
                    }
                }
                .pickerStyle(.menu)
                SecureField("API Key（官网申请）", text: Binding(
                    get: { app.settings.searchAPIKey },
                    set: { app.settings.searchAPIKey = $0 }
                ))
                HStack {
                    Text(app.settings.searchAPIKey.isEmpty
                         ? "未配置 → 自动回退内置资讯源检索"
                         : "已配置 → 问询前联网检索")
                        .font(.caption)
                        .foregroundStyle(DS.textSecondary)
                    Spacer()
                    Button("去官网申请") {
                        if let url = URL(string: app.settings.searchProvider.signupURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }

            Section("API Key（仅本地存储）") {
                APIKeyRow(provider: ai.provider)
                    .environmentObject(ai)
                if let url = keyApplicationURL(for: ai.provider) {
                    Link(destination: url) {
                        Label { Text("申请 \(ai.provider.displayName) API Key") } icon: { TectonicIconView(icon: .externalLink, size: 12, color: DS.accent) }
                    }
                }
            }

            Section("数据源（可选）") {
                ForEach(optionalDataSources) { ds in
                    HStack {
                        Text(ds.name)
                        Spacer()
                        Link("申请 Key", destination: ds.url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)  // 与其他设置页一致
        .onAppear {
            loadModels()
            syncModelSelection()
        }
        .onChange(of: ai.provider) { _, _ in
            loadModels()
            syncModelSelection()
        }
        .onChange(of: modelSelection) { _, v in
            if v == "__custom__" {
                showCustomModelField = true
            } else if let v, !v.isEmpty {
                showCustomModelField = false
                ai.model = v
            }
        }
    }

    /// 加载模型目录：本地缓存/静态清单立即填充，过期则后台刷新
    private func loadModels() {
        availableModels = ModelCatalog.available(provider: ai.provider)
        guard ModelCatalog.isStale(provider: ai.provider) else { return }
        let provider = ai.provider
        let key = ai.apiKey(for: provider)
        Task {
            if let fresh = await ModelCatalog.refresh(provider: provider, apiKey: key) {
                availableModels = fresh
                syncModelSelection()
            }
        }
    }

    /// 同步 Picker 选择态：当前模型在目录 → 选中该项；否则 → 自定义并显示输入框
    private func syncModelSelection() {
        if availableModels.contains(ai.model) {
            modelSelection = ai.model
            showCustomModelField = false
        } else {
            modelSelection = "__custom__"
            showCustomModelField = true
        }
    }

    private func providerGroups() -> [String] {
        var groups: [String] = []
        for p in ModelProvider.allCases where !groups.contains(p.group) {
            groups.append(p.group)
        }
        return groups
    }

    private func keyApplicationURL(for p: ModelProvider) -> URL? {
        switch p {
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")
        case .kimi: URL(string: "https://platform.moonshot.cn/console/api-keys")
        case .tongyi: URL(string: "https://dashscope.console.aliyun.com/apiKey")
        case .zhipu: URL(string: "https://open.bigmodel.cn/usercenter/apikeys")
        case .wenxin: URL(string: "https://console.bce.baidu.com/qianfan/ais/console/applicationConsole/application")
        case .doubao: URL(string: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey")
        case .ollama: nil
        }
    }

    struct OptionalDataSource: Identifiable {
        let id: String
        let name: String
        let url: URL
    }

    private var optionalDataSources: [OptionalDataSource] {
        [
            OptionalDataSource(id: "finnhub", name: "Finnhub（美股/财报/新闻）",
                               url: URL(string: "https://finnhub.io/register")!),
            OptionalDataSource(id: "twelve", name: "Twelve Data（全球行情）",
                               url: URL(string: "https://twelvedata.com/pricing")!),
            OptionalDataSource(id: "alpha", name: "Alpha Vantage（美股/外汇）",
                               url: URL(string: "https://www.alphavantage.co/support/#api-key")!),
        ]
    }
}

struct ProviderRow: View {
    @EnvironmentObject var ai: AISettings
    let provider: ModelProvider

    var body: some View {
        Button {
            ai.provider = provider
        } label: {
            HStack {
                TectonicIconView(icon: ai.provider == provider ? .circleCheck : .circle, size: 15,
                                 color: ai.provider == provider ? DS.accent : DS.textTertiary)
                Text(provider.displayName)
                Spacer()
                if !(ai.apiKey(for: provider) ?? "").isEmpty {
                    Text("已配置 Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct APIKeyRow: View {
    @EnvironmentObject var ai: AISettings
    let provider: ModelProvider
    @State private var key: String = ""

    var body: some View {
        SecureField("API Key", text: $key)
            .onAppear { key = ai.apiKey(for: provider) ?? "" }
            .onChange(of: key) { _, v in
                ai.setAPIKey(v, for: provider)
            }
    }
}