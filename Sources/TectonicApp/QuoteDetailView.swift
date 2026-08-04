import SwiftUI
import CoreKit

/// 标的详情：行情概览 + K线（苹果股市风格）+ AI 问询对话
struct QuoteDetailView: View {
    @EnvironmentObject var app: AppState
    let symbol: Symbol

    @State private var quote: Quote?
    @State private var bars: [KLineBar] = []
    @State private var range: ChartRange = .threeMonth
    @State private var isLoadingKline = false
    @State private var klineError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                klineSection
                aiChatSection
            }
            .padding(20)
        }
        .navigationTitle(symbol.name)
        .navigationSubtitle("\(symbol.code) · \(symbol.market.displayName)")
        .task(id: symbol.id) {
            quote = await app.store.quote(for: symbol)
        }
        .task(id: "\(symbol.id)-\(range.rawValue)") {
            await loadKline()
        }
    }

    // MARK: 头部行情

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let quote {
                Text("\(fmt(quote.price))")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(quote.change >= 0 ? Color.red : Color.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(fmtSigned(quote.change)) (\(fmtPercent(quote.changePercent)))")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(quote.change >= 0 ? Color.red : Color.green)
                    Text("今开 \(fmt(quote.open))  最高 \(fmt(quote.high))  最低 \(fmt(quote.low))  昨收 \(fmt(quote.prevClose))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
            Spacer()
            WatchlistToggle(symbol: symbol)
            Text(symbol.currency)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: K线（苹果股市风格）

    private var klineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("K线")
                    .font(.headline)
                Spacer()
                Picker("时间范围", selection: $range) {
                    ForEach(ChartRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            // 当前范围最近一根 OHLC 信息（苹果股市顶部信息条）
            if let last = bars.last {
                let up = last.close >= last.open
                HStack(spacing: 16) {
                    infoItem("开", fmt(last.open))
                    infoItem("高", fmt(last.high))
                    infoItem("低", fmt(last.low))
                    infoItem("收", fmt(last.close), color: up ? Color.red : Color.green)
                    Text("\(fmtSigned(last.close - last.open)) (\(fmtPercent((last.close - last.open) / last.open * 100)))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(up ? Color.red : Color.green)
                    Spacer()
                    Text(periodLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
            if isLoadingKline {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if let klineError {
                Text(klineError)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else if bars.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                KLineChart(bars: bars)
                    .frame(height: 300)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func infoItem(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(color ?? Color.primary)
        }
    }

    /// 当前范围使用的周期描述
    private var periodLabel: String {
        let (period, _) = range.target
        return period == .m5 ? "分时" : "\(period.displayName) · \(bars.count) 根"
    }

    private func loadKline() async {
        isLoadingKline = true
        defer { isLoadingKline = false }
        let (period, limit) = range.target
        do {
            bars = try await app.store.kline(for: symbol, period: period, limit: limit)
            klineError = nil
        } catch {
            bars = []
            klineError = "K线加载失败: \(error.localizedDescription)"
        }
    }

    // MARK: AI 对话

    private var aiChatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 分析")
                .font(.headline)
            SymbolChatView(symbol: symbol)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
    }
    private func fmtSigned(_ v: Double) -> String {
        String(format: "%+.2f", v)
    }
    private func fmtPercent(_ v: Double) -> String {
        String(format: "%+.2f%%", v)
    }
}

// MARK: - 自选开关（工具栏）

struct WatchlistToggle: View {
    @EnvironmentObject var app: AppState
    let symbol: Symbol

    var body: some View {
        let inList = app.store.isInWatchlist(symbol)
        Button {
            do {
                if inList {
                    try app.store.removeFromWatchlist(symbol)
                } else {
                    try app.store.addToWatchlist(symbol)
                }
            } catch {
                print("自选操作失败: \(error)")
            }
        } label: {
            Label(inList ? "移出自选" : "添加自选",
                  systemImage: inList ? "star.fill" : "star")
        }
        .help(inList ? "移出自选" : "添加自选")
    }
}

// MARK: - 标的 AI 对话

struct SymbolChatView: View {
    @EnvironmentObject var app: AppState
    let symbol: Symbol

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isThinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            Text("针对 \(symbol.name)（\(symbol.code)）提问，例如：\n「最近走势如何？技术面怎么看？」\n「根据近期新闻，有什么风险点？」")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            MessageBubble(message: msg)
                        }
                        if isThinking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("思考中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 220)
            }

            HStack(spacing: 8) {
                TextField("询问关于 \(symbol.name) 的问题…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send() }
                Button("发送") {
                    send()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        input = ""
        let ai = app.aiSettings
        let provider = ai.provider
        let model = ai.model
        let key = ai.apiKey(for: provider)

        // 上下文：标的 + 行情 + 用户问题
        let quoteText: String
        if let q = app.store.quotes[symbol.id] {
            quoteText = String(format: "现价 %.4f，涨跌 %+.2f%%（昨收 %.4f）",
                               q.price, q.changePercent, q.prevClose)
        } else {
            quoteText = "暂无实时行情数据"
        }
        let system = """
        你是专业的财经分析助手，分析标的是 \(symbol.name)（\(symbol.code)，\(symbol.market.displayName)）。
        当前行情：\(quoteText)。
        回答使用简体中文，基于公开信息分析，明确指出不确定性和风险，不要给出确定性的投资建议。
        """
        messages.append(.user(text))
        isThinking = true
        Task {
            defer { isThinking = false }
            do {
                let reply = try await ModelGateway().ask(
                    text, system: system,
                    provider: provider, model: model, apiKey: key)
                messages.append(.assistant(reply))
            } catch {
                messages.append(.assistant("⚠️ 调用失败：\(error.localizedDescription)"))
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 40)
            }
            Text(message.content)
                .font(.callout)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(message.role == "user"
                              ? Color.accentColor.opacity(0.15)
                              : Color.primary.opacity(0.06))
                )
                .textSelection(.enabled)
            if message.role == "assistant" {
                Spacer(minLength: 40)
            }
        }
    }
}
