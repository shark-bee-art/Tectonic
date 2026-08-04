import SwiftUI
import CoreKit
import UniformTypeIdentifiers

/// 设置：通用（市场）+ AI（供应商/模型/Key）
/// 遵循用户偏好：分类标题无选择控件、语言/模型用下拉、API Key 仅本地存储
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedTab = "market"

    var body: some View {
        TabView(selection: $selectedTab) {
            MarketSettingsTab()
                .tabItem { Label("市场", systemImage: "chart.bar") }
                .tag("market")
            AISettingsTab()
                .tabItem { Label("AI 模型", systemImage: "brain") }
                .tag("ai")
            NewsSettingsTab()
                .tabItem { Label("资讯源", systemImage: "newspaper") }
                .tag("news")
        }
        .padding(20)
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
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
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
                    Text("选择要显示的市场，拖拽调整优先级（顶部优先）")
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
                                Image(systemName: marketIcon(market))
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

            // 优先级排序：独立 List（Form 内的 List 拖拽不生效）
            VStack(alignment: .leading, spacing: 4) {
                Text("优先级（拖拽行或按钮调整）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                List {
                    ForEach(app.settings.marketOrder) { market in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                            Text(market.displayName)
                            Spacer()
                            Button {
                                app.settings.moveMarketUp(market)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(app.settings.marketOrder.first == market)
                            Button {
                                app.settings.moveMarketDown(market)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(app.settings.marketOrder.last == market)
                            Text(market.currency)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 48)
                        }
                    }
                    .onMove { from, to in
                        app.settings.moveMarket(from: from, to: to)
                    }
                }
                .listStyle(.inset)
                .frame(height: CGFloat(app.settings.marketOrder.count) * 30 + 10)
            }

            Divider()

            Button("恢复内置标的（\(BuiltinSymbols.all.count) 个）") {
                try? app.store.importBuiltinSymbols()
            }
            .help("重新导入预置的常见标的（幂等，已存在的跳过）")
        }
        .padding(12)
    }

    private func marketIcon(_ m: Market) -> String {
        switch m {
        case .us: "building.columns"
        case .crypto: "bitcoinsign"
        case .hk: "building.2"
        case .cn: "building"
        case .fund: "chart.pie"
        case .kr: "building.2.crop.circle"
        case .jp: "sun.max"
        case .tw: "mountain.2"
        }
    }
}

// MARK: - AI 设置：供应商（分组行列表）+ 模型（下拉）+ Key（本地存储）

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
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(ModelProvider.allCases.filter { $0.group == group }) { p in
                            ProviderRow(provider: p)
                                .environmentObject(app)
                        }
                    }
                }
            }

            Section("模型") {
                Picker("模型", selection: $modelSelection) {
                    ForEach(availableModels, id: \.self) { m in
                        Text(m).tag(Optional(m))
                    }
                    if !availableModels.isEmpty {
                        Divider()
                    }
                    Text("自定义模型…").tag(Optional("__custom__"))
                }
                .pickerStyle(.menu)

                if showCustomModelField {
                    TextField("自定义模型名称", text: $ai.model)
                }

                Text(availableModels.isEmpty
                     ? "模型列表加载中…"
                     : "可选 \(availableModels.count) 个模型 · 每周自动更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API Key（仅本地存储）") {
                APIKeyRow(provider: ai.provider)
                    .environmentObject(ai)
                if let url = keyApplicationURL(for: ai.provider) {
                    Link(destination: url) {
                        Label("申请 \(ai.provider.displayName) API Key", systemImage: "arrow.up.right.square")
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
                Image(systemName: ai.provider == provider
                      ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(ai.provider == provider
                                     ? Color.accentColor : Color.secondary)
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
