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
        }
        .padding(20)
    }
}

// MARK: - 市场设置：开关 + 排序

struct MarketSettingsTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
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
            Section("优先级（拖拽排序）") {
                ForEach(app.settings.marketOrder) { market in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        Text(market.displayName)
                        Spacer()
                        Text(market.currency)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .draggable(market.rawValue)
                }
                .onInsert(of: [UTType.text], perform: insert)
            }
        }
        .formStyle(.grouped)
    }

    private func insert(at index: Int, _ items: [NSItemProvider]) {
        // 简化：从已启用列表重建顺序（拖拽重排）
        for provider in items {
            _ = provider.loadObject(ofClass: NSString.self) { str, _ in
                guard let raw = str as? String,
                      let market = Market(rawValue: raw) else { return }
                DispatchQueue.main.async {
                    var order = app.settings.marketOrder
                    order.removeAll { $0 == market }
                    order.insert(market, at: min(index, order.count))
                    app.settings.setOrder(order)
                }
            }
        }
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
    @State private var customModel = ""

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
                Picker("模型", selection: $ai.model) {
                    Text("\(ai.provider.presetModel)（默认）")
                        .tag(ai.provider.presetModel)
                    Text("自定义…").tag("__custom__")
                }
                .pickerStyle(.menu)
                .disabled(false)

                if ai.model == "__custom__" {
                    TextField("输入模型名称", text: $customModel)
                        .onChange(of: customModel) { _, v in
                            if !v.isEmpty { ai.model = v }
                        }
                }

                Text("供应商：\(ai.provider.displayName)")
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
            customModel = ai.model
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
