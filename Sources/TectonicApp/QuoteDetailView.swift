import SwiftUI
import CoreKit

/// 标的详情：行情概览 + 技术面数据 + AI 问询对话
struct QuoteDetailView: View {
    @EnvironmentObject var app: AppState
    let symbol: Symbol

    @State private var quote: Quote?
    @State private var technical: TechnicalSummary?
    @State private var isLoadingTech = false
    @State private var techError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                technicalSection
                aiChatSection
            }
            .padding(20)
        }
        .navigationTitle(symbol.name)
        .navigationSubtitle("\(symbol.code) · \(symbol.market.displayName)")
        .task(id: symbol.id) {
            quote = await app.store.quote(for: symbol)
        }
        .task(id: "\(symbol.id)-tech") {
            await loadTechnical()
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

    // MARK: 技术面数据

    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("技术面")
                    .font(.headline)
                Spacer()
                if let t = technical {
                    Text(t.period)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isLoadingTech {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let techError {
                Text(techError)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let t = technical {
                VStack(alignment: .leading, spacing: 14) {
                    // 关键价位
                    HStack(spacing: 12) {
                        levelCard(title: "支撑位", value: t.support, current: t.currentPrice, isBelow: true)
                        levelCard(title: "阻力位", value: t.resistance, current: t.currentPrice, isBelow: false)
                        levelCard(title: "52周低", value: t.low52w, current: t.currentPrice, isBelow: true)
                        levelCard(title: "52周高", value: t.high52w, current: t.currentPrice, isBelow: false)
                    }

                    Divider()

                    // 均线
                    VStack(alignment: .leading, spacing: 8) {
                        Text("均线")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            maRow("MA20", value: t.sma20, current: t.currentPrice)
                            maRow("MA50", value: t.sma50, current: t.currentPrice)
                            maRow("MA200", value: t.sma200, current: t.currentPrice)
                        }
                    }

                    Divider()

                    // 动量与量能
                    HStack(spacing: 24) {
                        metricItem("年初至今", value: t.ytdChangePercent.map { fmtPercent($0) } ?? "—",
                                   color: (t.ytdChangePercent ?? 0) >= 0 ? Color.red : Color.green)
                        if t.avgVolume20 > 0 {
                            metricItem("20日均量", value: "\(shortNum(t.avgVolume20))", color: nil)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    /// 价位卡片：值 + 距现价 %
    private func levelCard(title: String, value: Double?, current: Double, isBelow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let value {
                Text(fmt(value))
                    .font(.title3.weight(.semibold).monospacedDigit())
                let diff = (value - current) / current * 100
                Text("\(fmtSigned(diff))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isBelow ? Color.green : Color.red)
            } else {
                Text("—")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    /// 均线行：值 + 现价相对位置（高于/低于）
    private func maRow(_ name: String, value: Double?, current: Double) -> some View {
        GridRow {
            Text(name)
                .foregroundStyle(.secondary)
            if let value {
                Text(fmt(value))
                    .monospacedDigit()
                let above = current >= value
                Text(above ? "现价在上方" : "现价在下方")
                    .font(.caption)
                    .foregroundStyle(above ? Color.red : Color.green)
                Text("\(fmtPercent((current - value) / value * 100))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("数据不足")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func metricItem(_ title: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color ?? Color.primary)
        }
    }

    private func loadTechnical() async {
        isLoadingTech = true
        defer { isLoadingTech = false }
        do {
            technical = try await app.store.technicalSummary(for: symbol)
            techError = nil
        } catch {
            technical = nil
            techError = "技术面计算失败: \(error.localizedDescription)"
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
    private func shortNum(_ v: Double) -> String {
        if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return String(format: "%.0f", v)
    }
}
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

