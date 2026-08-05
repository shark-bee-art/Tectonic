import SwiftUI
import CoreKit

/// 标的详情：行情概览 + 技术面数据 + AI 问询（右侧面板）
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
            }
            .padding(20)
        }
        .navigationTitle(symbol.name)
        .navigationSubtitle("\(symbol.code) · \(symbol.market.displayName)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openChat()
                } label: {
                    Label(L10n.l("detail.aiChat"), systemImage: "brain")
                }
                .help(L10n.l("detail.aiChat"))
            }
        }
        .task(id: symbol.id) {
            quote = await app.store.quote(for: symbol)
        }
        .task(id: "\(symbol.id)-tech") {
            await loadTechnical()
            if symbol.market == .crypto {
                await app.store.fetchFearGreed()
            }
        }
    }

    /// 打开右侧 AI 问询面板（系统提示含行情 + 可选联网资讯）
    private func openChat() {
        let symbol = self.symbol
        let name = symbol.name
        let code = symbol.code
        let marketName = symbol.market.displayName
        app.chatPanel = ChatPanelContext(
            title: "\(name)（\(code)）",
            subtitle: L10n.l("placeholder.detail"),
            systemBuilder: { webContext in
                let quoteText: String
                if let q = app.store.quotes[symbol.id] {
                    quoteText = String(format: "现价 %.4f，涨跌 %+.2f%%（昨收 %.4f）", q.price, q.changePercent, q.prevClose)
                } else {
                    quoteText = "暂无实时行情数据"
                }
                var sys = """
                你是专业的财经分析助手，分析标的是 \(name)（\(code)，\(marketName)）。
                当前行情：\(quoteText)。
                \(app.settings.languageInstruction) 基于公开信息分析，明确指出不确定性和风险，不要给出确定性的投资建议。
                """
                if !webContext.isEmpty {
                    sys += "\n\n以下是检索到的相关资讯（联网，请优先参考）：\n\(webContext)"
                }
                return sys
            },
            quickQuestions: [
                (L10n.l("detail.quickTrend"), "最近走势如何？技术面怎么看？"),
                (L10n.l("detail.quickFundamental"), "基本面情况怎么样？关键财务指标如何？"),
                (L10n.l("detail.quickNews"), "近期有哪些重要新闻？有什么风险点？"),
            ]
        )
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
                        if let pos = t.rangePosition52w {
                            metricItem("52周区间位置", value: String(format: "%.0f%%", pos), color: nil)
                        }
                        if t.avgVolume20 > 0 {
                            metricItem("20日均量", value: "\(shortNum(t.avgVolume20))", color: nil)
                        }
                        Spacer()
                    }

                    Divider()

                    // 动量指标（RSI/MACD/KDJ/BOLL）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("动量指标")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                            if let rsi = t.rsi14 {
                                GridRow {
                                    Text("RSI(14)").foregroundStyle(.secondary)
                                    Text(String(format: "%.1f", rsi)).monospacedDigit()
                                    Text(rsi >= 70 ? "超买" : (rsi <= 30 ? "超卖" : "中性"))
                                        .font(.caption)
                                        .foregroundStyle(rsi >= 70 ? Color.red : (rsi <= 30 ? Color.green : Color.secondary))
                                }
                            }
                            if let dif = t.macdDIF, let dea = t.macdDEA, let hist = t.macdHistogram {
                                GridRow {
                                    Text("MACD").foregroundStyle(.secondary)
                                    Text("DIF \(fmt(dif))  DEA \(fmt(dea))  柱 \(fmt(hist))").monospacedDigit()
                                    Text(dif >= dea ? "多头" : "空头")
                                        .font(.caption)
                                        .foregroundStyle(dif >= dea ? Color.red : Color.green)
                                }
                            }
                            if let bu = t.bollUpper, let bm = t.bollMid, let bl = t.bollLower {
                                GridRow {
                                    Text("布林带").foregroundStyle(.secondary)
                                    Text("上 \(fmt(bu))  中 \(fmt(bm))  下 \(fmt(bl))").monospacedDigit()
                                    Text(t.currentPrice > bu ? "突破上轨" : (t.currentPrice < bl ? "跌破下轨" : "通道内"))
                                        .font(.caption)
                                        .foregroundStyle(t.currentPrice > bu ? Color.red : (t.currentPrice < bl ? Color.green : Color.secondary))
                                }
                            }
                            if let k = t.kdjK, let d = t.kdjD, let j = t.kdjJ {
                                GridRow {
                                    Text("KDJ").foregroundStyle(.secondary)
                                    Text("K \(String(format: "%.1f", k))  D \(String(format: "%.1f", d))  J \(String(format: "%.1f", j))").monospacedDigit()
                                    Text(k >= 80 ? "超买" : (k <= 20 ? "超卖" : "中性"))
                                        .font(.caption)
                                        .foregroundStyle(k >= 80 ? Color.red : (k <= 20 ? Color.green : Color.secondary))
                                }
                            }
                        }
                    }

                    // 市场情绪（恐惧贪婪指数，仅加密标的）
                    if symbol.market == .crypto {
                        Divider()
                        HStack(spacing: 8) {
                            Text("市场情绪")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if app.store.fearGreedLoading {
                                ProgressView().controlSize(.small)
                            } else if let fg = app.store.fearGreed {
                                Text("\(fg.value)")
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(fg.value >= 55 ? Color.red : (fg.value <= 44 ? Color.green : Color.secondary))
                                Text("\(fg.level)（\(fg.classification)）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            Label(inList ? L10n.l("detail.removeWatchlist") : L10n.l("detail.addWatchlist"),
                  systemImage: inList ? "star.fill" : "star")
                .foregroundStyle(inList ? Color.yellow : Color.accentColor)
        }
        .buttonStyle(.bordered)
        .symbolEffect(.bounce, value: inList)
        .help(inList ? L10n.l("detail.removeWatchlist") : L10n.l("detail.addWatchlist"))
    }
}
