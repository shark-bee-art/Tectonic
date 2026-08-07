import SwiftUI
import CoreKit

/// 标的详情：行情 Hero + 技术面卡片 + 基本面卡片 + AI 问询（右侧面板）
/// TradingView 淡雅：数据卡片化、等宽数字、红涨绿跌
struct QuoteDetailView: View {
    @EnvironmentObject var app: AppState
    let symbol: Symbol

    @State private var quote: Quote?
    @State private var technical: TechnicalSummary?
    @State private var isLoadingTech = false
    @State private var techError: String?
    @State private var fundamental: FundamentalData?
    @State private var isLoadingFund = false
    @State private var fundError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                technicalSection
                fundamentalSection
            }
            .padding(16)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.bgApp)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openChat()
                } label: {
                    HStack(spacing: 4) {
                        TectonicIconView(icon: .sparkles, size: 14, color: DS.accent)
                        Text(L10n.l("detail.aiChat"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: DS.radiusMedium).fill(DS.bgHover))
                }
                .buttonStyle(.plain)
                .help(L10n.l("detail.aiChat"))
            }
        }
        .task(id: symbol.id) {
            quote = await app.store.quote(for: symbol)
        }
        .task(id: "\(symbol.id)-fund") {
            await loadFundamental()
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

    // MARK: 行情 Hero

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let quote {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(fmt(quote.price))
                            .font(.system(size: 40, weight: .semibold).monospacedDigit())
                            .foregroundStyle(DS.directionColor(quote.change))
                        Text("\(fmtSigned(quote.change)) (\(fmtPercent(quote.changePercent)))")
                            .font(.system(size: 16, weight: .medium).monospacedDigit())
                            .foregroundStyle(DS.directionColor(quote.change))
                    }
                    Text("今开 \(fmt(quote.open))  最高 \(fmt(quote.high))  最低 \(fmt(quote.low))  昨收 \(fmt(quote.prevClose))")
                        .font(.system(size: DS.captionSize))
                        .foregroundStyle(DS.textSecondary)
                }
            } else {
                ProgressView()
            }
            Spacer()
            WatchlistToggle(symbol: symbol)
            Text(symbol.currency)
                .font(.system(size: DS.captionSize))
                .foregroundStyle(DS.textSecondary)
        }
    }

    // MARK: 基本面数据（SEC EDGAR，仅美股）

    private var fundamentalSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TectonicIconView(icon: .chartBar, size: 15, color: DS.textPrimary)
                    Text(L10n.l("detail.fundamental"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    if let fd = fundamental, let year = fd.revenueYear {
                        Text(L10n.l("detail.fundFiscalYear") + " " + year)
                            .font(.system(size: DS.metaSize))
                            .foregroundStyle(DS.textTertiary)
                    }
                }

                if isLoadingFund {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let fundError {
                    Text(fundError)
                        .font(.system(size: DS.captionSize))
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let fd = fundamental {
                    VStack(alignment: .leading, spacing: 14) {
                        // 盈利能力
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel(L10n.l("detail.fundProfitability"))
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                GridRow {
                                    fundItem(L10n.l("detail.fundRevenue"), value: fd.revenue.map { fmtAmount($0) })
                                    fundItem(L10n.l("detail.fundNetIncome"), value: fd.netIncome.map { fmtAmount($0) })
                                    fundItem(L10n.l("detail.fundOperatingIncome"), value: fd.operatingIncome.map { fmtAmount($0) })
                                    fundItem(L10n.l("detail.fundGrossProfit"), value: fd.grossProfit.map { fmtAmount($0) })
                                }
                            }
                        }

                        DSDivider()

                        // 每股与估值
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel(L10n.l("detail.fundValuation"))
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                GridRow {
                                    fundItem(L10n.l("detail.fundEPS"), value: fd.eps.map { String(format: "%.2f", $0) })
                                    fundItem("ROE", value: fd.roe.map { String(format: "%.1f%%", $0) })
                                    fundItem("PE", value: quote.flatMap { fd.pe(price: $0.price) }.map { String(format: "%.1f", $0) })
                                    fundItem("PB", value: quote.flatMap { fd.pb(price: $0.price) }.map { String(format: "%.1f", $0) })
                                }
                            }
                        }

                        DSDivider()

                        // 资产负债
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel(L10n.l("detail.fundBalance"))
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                GridRow {
                                    fundItem(L10n.l("detail.fundAssets"), value: fd.assets.map { fmtAmount($0) })
                                    fundItem(L10n.l("detail.fundLiabilities"), value: fd.liabilities.map { fmtAmount($0) })
                                    fundItem(L10n.l("detail.fundEquity"), value: fd.equity.map { fmtAmount($0) })
                                    fundItem(L10n.l("detail.fundDebtRatio"), value: fd.debtRatio.map { String(format: "%.1f%%", $0) })
                                }
                                GridRow {
                                    fundItem(L10n.l("detail.fundShares"), value: fd.sharesOutstanding.map { fmtAmount($0) })
                                }
                            }
                        }

                        HStack(spacing: 4) {
                            Text("SEC EDGAR")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.textTertiary)
                            if let fd = fundamental, let bd = fd.balanceDate {
                                Text("· " + L10n.l("detail.fundBalanceDate") + " " + bd)
                                    .font(.system(size: 10))
                                    .foregroundStyle(DS.textTertiary)
                            }
                        }
                    }
                } else {
                    Text(L10n.l("detail.fundUnsupported"))
                        .font(.system(size: DS.captionSize))
                        .foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DS.metaSize, weight: .medium))
            .foregroundStyle(DS.textSecondary)
    }

    private func fundItem(_ title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: DS.metaSize))
                .foregroundStyle(DS.textSecondary)
            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(DS.textPrimary)
            } else {
                Text("—")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 金额简写：≥1T → T、≥1B → B、≥1M → M
    private func fmtAmount(_ v: Double) -> String {
        if v >= 1_000_000_000_000 { return String(format: "%.2fT", v / 1_000_000_000_000) }
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        return String(format: "%.0f", v)
    }

    private func loadFundamental() async {
        guard symbol.market == .us else { return }
        guard fundamental == nil else { return }
        isLoadingFund = true
        defer { isLoadingFund = false }
        do {
            fundamental = try await EDGARSource.shared.fundamental(for: symbol)
            fundError = nil
        } catch {
            fundamental = nil
            fundError = "基本面加载失败: \(error.localizedDescription)"
        }
    }

    // MARK: 技术面数据

    private var technicalSection: some View {
        DSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TectonicIconView(icon: .chartLine, size: 15, color: DS.textPrimary)
                    Text(L10n.l("detail.technical"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.textPrimary)
                    Spacer()
                    if let t = technical {
                        Text(t.period)
                            .font(.system(size: DS.metaSize))
                            .foregroundStyle(DS.textTertiary)
                    }
                }

                if isLoadingTech {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let techError {
                    Text(techError)
                        .font(.system(size: DS.captionSize))
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let t = technical {
                    VStack(alignment: .leading, spacing: 14) {
                        // 关键价位
                        HStack(spacing: 12) {
                            levelCard(title: L10n.l("detail.support"), value: t.support, current: t.currentPrice, isBelow: true)
                            levelCard(title: L10n.l("detail.resistance"), value: t.resistance, current: t.currentPrice, isBelow: false)
                            levelCard(title: L10n.l("detail.low52w"), value: t.low52w, current: t.currentPrice, isBelow: true)
                            levelCard(title: L10n.l("detail.high52w"), value: t.high52w, current: t.currentPrice, isBelow: false)
                        }

                        DSDivider()

                        // 均线
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel(L10n.l("detail.movingAverages"))
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                                maRow("MA20", value: t.sma20, current: t.currentPrice)
                                maRow("MA50", value: t.sma50, current: t.currentPrice)
                                maRow("MA200", value: t.sma200, current: t.currentPrice)
                            }
                        }

                        DSDivider()

                        // 动量与量能
                        HStack(spacing: 24) {
                            metricItem(L10n.l("detail.ytd"), value: t.ytdChangePercent.map { fmtPercent($0) } ?? "—",
                                       color: (t.ytdChangePercent ?? 0) >= 0 ? DS.up : DS.down)
                            if let pos = t.rangePosition52w {
                                metricItem(L10n.l("detail.range52w"), value: String(format: "%.0f%%", pos), color: nil)
                            }
                            if t.avgVolume20 > 0 {
                                metricItem(L10n.l("detail.avgVolume20"), value: "\(shortNum(t.avgVolume20))", color: nil)
                            }
                            Spacer()
                        }

                        DSDivider()

                        // 动量指标（RSI/MACD/KDJ/BOLL）
                        VStack(alignment: .leading, spacing: 8) {
                            sectionLabel(L10n.l("detail.momentum"))
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                                if let rsi = t.rsi14 {
                                    GridRow {
                                        Text("RSI(14)").font(.system(size: DS.captionSize)).foregroundStyle(DS.textSecondary)
                                        Text(String(format: "%.1f", rsi)).font(.system(size: DS.captionSize).monospacedDigit()).foregroundStyle(DS.textPrimary)
                                        Text(rsi >= 70 ? L10n.l("detail.overbought") : (rsi <= 30 ? L10n.l("detail.oversold") : L10n.l("detail.neutral")))
                                            .font(.system(size: DS.metaSize))
                                            .foregroundStyle(rsi >= 70 ? DS.up : (rsi <= 30 ? DS.down : DS.textSecondary))
                                    }
                                }
                                if let dif = t.macdDIF, let dea = t.macdDEA, let hist = t.macdHistogram {
                                    GridRow {
                                        Text("MACD").font(.system(size: DS.captionSize)).foregroundStyle(DS.textSecondary)
                                        Text("DIF \(fmt(dif))  DEA \(fmt(dea))  柱 \(fmt(hist))")
                                            .font(.system(size: DS.captionSize).monospacedDigit()).foregroundStyle(DS.textPrimary)
                                        Text(dif >= dea ? L10n.l("detail.bullish") : L10n.l("detail.bearish"))
                                            .font(.system(size: DS.metaSize))
                                            .foregroundStyle(dif >= dea ? DS.up : DS.down)
                                    }
                                }
                                if let bu = t.bollUpper, let bm = t.bollMid, let bl = t.bollLower {
                                    GridRow {
                                        Text(L10n.l("detail.bollinger")).font(.system(size: DS.captionSize)).foregroundStyle(DS.textSecondary)
                                        Text("上 \(fmt(bu))  中 \(fmt(bm))  下 \(fmt(bl))")
                                            .font(.system(size: DS.captionSize).monospacedDigit()).foregroundStyle(DS.textPrimary)
                                        Text(t.currentPrice > bu ? L10n.l("detail.breakUpper") : (t.currentPrice < bl ? L10n.l("detail.breakLower") : L10n.l("detail.inBand")))
                                            .font(.system(size: DS.metaSize))
                                            .foregroundStyle(t.currentPrice > bu ? DS.up : (t.currentPrice < bl ? DS.down : DS.textSecondary))
                                    }
                                }
                                if let k = t.kdjK, let d = t.kdjD, let j = t.kdjJ {
                                    GridRow {
                                        Text("KDJ").font(.system(size: DS.captionSize)).foregroundStyle(DS.textSecondary)
                                        Text("K \(String(format: "%.1f", k))  D \(String(format: "%.1f", d))  J \(String(format: "%.1f", j))")
                                            .font(.system(size: DS.captionSize).monospacedDigit()).foregroundStyle(DS.textPrimary)
                                        Text(k >= 80 ? L10n.l("detail.overbought") : (k <= 20 ? L10n.l("detail.oversold") : L10n.l("detail.neutral")))
                                            .font(.system(size: DS.metaSize))
                                            .foregroundStyle(k >= 80 ? DS.up : (k <= 20 ? DS.down : DS.textSecondary))
                                    }
                                }
                            }
                        }

                        // 市场情绪（恐惧贪婪指数，仅加密标的）
                        if symbol.market == .crypto {
                            DSDivider()
                            HStack(spacing: 8) {
                                TectonicIconView(icon: .activity, size: 14, color: DS.textSecondary)
                                Text(L10n.l("detail.sentiment"))
                                    .font(.system(size: DS.metaSize, weight: .medium))
                                    .foregroundStyle(DS.textSecondary)
                                Spacer()
                                if app.store.fearGreedLoading {
                                    ProgressView().controlSize(.small)
                                } else if let fg = app.store.fearGreed {
                                    Text("\(fg.value)")
                                        .font(.system(.body, design: .rounded).weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(fg.value >= 55 ? DS.up : (fg.value <= 44 ? DS.down : DS.textSecondary))
                                    Text("\(fg.level)（\(fg.classification)）")
                                        .font(.system(size: DS.metaSize))
                                        .foregroundStyle(DS.textSecondary)
                                } else {
                                    Text("—")
                                        .foregroundStyle(DS.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 价位卡片：值 + 距现价 %
    private func levelCard(title: String, value: Double?, current: Double, isBelow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: DS.metaSize))
                .foregroundStyle(DS.textSecondary)
            if let value {
                Text(fmt(value))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DS.textPrimary)
                let diff = (value - current) / current * 100
                Text("\(fmtSigned(diff))%")
                    .font(.system(size: DS.metaSize).monospacedDigit())
                    .foregroundStyle(isBelow ? DS.down : DS.up)
            } else {
                Text("—")
                    .font(.system(size: 17).monospacedDigit())
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.radiusMedium).fill(DS.bgHover))
    }

    /// 均线行：值 + 现价相对位置（高于/低于）
    private func maRow(_ name: String, value: Double?, current: Double) -> some View {
        GridRow {
            Text(name)
                .font(.system(size: DS.captionSize))
                .foregroundStyle(DS.textSecondary)
            if let value {
                Text(fmt(value))
                    .font(.system(size: DS.captionSize).monospacedDigit())
                    .foregroundStyle(DS.textPrimary)
                let above = current >= value
                Text(above ? L10n.l("detail.aboveMA") : L10n.l("detail.belowMA"))
                    .font(.system(size: DS.metaSize))
                    .foregroundStyle(above ? DS.up : DS.down)
                Text("\(fmtPercent((current - value) / value * 100))")
                    .font(.system(size: DS.metaSize).monospacedDigit())
                    .foregroundStyle(DS.textSecondary)
            } else {
                Text(L10n.l("detail.noData"))
                    .font(.system(size: DS.metaSize))
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    private func metricItem(_ title: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: DS.metaSize))
                .foregroundStyle(DS.textSecondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(color ?? DS.textPrimary)
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
            TectonicIconView(icon: inList ? .starFilled : .star,
                             size: 18,
                             color: inList ? DS.accent : DS.textSecondary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(inList ? DS.bgSelected : .clear)
                )
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: inList)
        .help(inList ? L10n.l("detail.removeWatchlist") : L10n.l("detail.addWatchlist"))
    }
}
