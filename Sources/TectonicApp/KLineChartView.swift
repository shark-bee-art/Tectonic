import SwiftUI
import TectonicIcons
import CoreKit

/// K 线图：自绘蜡烛图 + 成交量柱 + 均线（MA5/20）+ 周期切换（日/周/月/年）
/// 红涨绿跌（中国习惯：close >= open 涨=红 up、跌=绿 down）
struct KLineChartView: View {
    let bars: [KLineBar]
    var height: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            if bars.count >= 2 {
                chartArea
            } else {
                DSPlaceholder(icon: .chartLine, title: L10n.l("detail.klineEmpty"))
                    .frame(height: height)
            }
        }
    }

    // MARK: 图表主体（蜡烛 + 均线 + 成交量）

    private var chartArea: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let chartH = height * 0.72
            let volH = height * 0.2
            let gap: CGFloat = 8

            // 价格范围（含 padding）
            let allPrices = bars.flatMap { [$0.high, $0.low] }
            let minP = (allPrices.min() ?? 0) * 0.998
            let maxP = (allPrices.max() ?? 1) * 1.002
            let priceSpan = max(maxP - minP, 0.0001)

            // 成交量范围
            let maxVol = (bars.map(\.volume).max() ?? 1) * 1.05

            // 均线
            let ma5 = movingAverage(bars, period: 5)
            let ma20 = movingAverage(bars, period: 20)

            ZStack(alignment: .topLeading) {
                // 网格线（4 条横向）
                ForEach(0..<4, id: \.self) { i in
                    let y = chartH * CGFloat(i) / 3
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(DS.border.opacity(0.5), lineWidth: 0.5)
                }

                // 蜡烛 + 成交量
                Canvas { context, size in
                    let slot = w / CGFloat(bars.count)
                    let bodyW = max(slot * 0.55, 1.5)

                    for (i, bar) in bars.enumerated() {
                        let x = slot * CGFloat(i) + slot / 2
                        let up = bar.close >= bar.open
                        let color = up ? DS.up : DS.down

                        // 影线
                        let highY = yPrice(bar.high, min: minP, span: priceSpan, h: chartH)
                        let lowY = yPrice(bar.low, min: minP, span: priceSpan, h: chartH)
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: highY))
                        line.addLine(to: CGPoint(x: x, y: lowY))
                        context.stroke(line, with: .color(color), lineWidth: 1)

                        // 实体
                        let openY = yPrice(bar.open, min: minP, span: priceSpan, h: chartH)
                        let closeY = yPrice(bar.close, min: minP, span: priceSpan, h: chartH)
                        let top = min(openY, closeY)
                        let bodyH = max(abs(openY - closeY), 1)
                        let rect = CGRect(x: x - bodyW / 2, y: top, width: bodyW, height: bodyH)
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.5), with: .color(color))
                        // 成交量（底部区）
                        let volX = slot * CGFloat(i) + slot / 2
                        let volRect = CGRect(
                            x: volX - bodyW / 2,
                            y: chartH + gap + volH * (1 - bar.volume / maxVol),
                            width: bodyW,
                            height: volH * (bar.volume / maxVol)
                        )
                        context.fill(Path(volRect), with: .color(color.opacity(0.55)))
                    }

                    // 均线 MA5 / MA20
                    drawMA(context, size: size, values: ma5, slot: slot, span: priceSpan, min: minP, h: chartH, color: DS.accent)
                    drawMA(context, size: size, values: ma20, slot: slot, span: priceSpan, min: minP, h: chartH, color: .orange)
                }

                // 右侧价格刻度（最高/最低）
                VStack {
                    Text(fmtPrice(maxP))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(DS.textTertiary)
                    Spacer()
                    Text(fmtPrice(minP))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(DS.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 2)
                .frame(height: chartH)
            }
        }
        .frame(height: height)
    }

    // MARK: 工具

    private func yPrice(_ v: Double, min: Double, span: Double, h: CGFloat) -> CGFloat {
        h - CGFloat((v - min) / span) * h
    }

    private func movingAverage(_ bars: [KLineBar], period: Int) -> [Double?] {
        var result: [Double?] = []
        for i in 0..<bars.count {
            guard i >= period - 1 else { result.append(nil); continue }
            let sum = (i - period + 1...i).reduce(0.0) { $0 + bars[$1].close }
            result.append(sum / Double(period))
        }
        return result
    }

    private func drawMA(_ context: GraphicsContext, size: CGSize, values: [Double?],
                        slot: CGFloat, span: Double, min: Double, h: CGFloat, color: Color) {
        var path = Path()
        var started = false
        for (i, v) in values.enumerated() {
            guard let v else { started = false; continue }
            let x = slot * CGFloat(i) + slot / 2
            let y = yPrice(v, min: min, span: span, h: h)
            if started {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.move(to: CGPoint(x: x, y: y))
                started = true
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    private func fmtPrice(_ v: Double) -> String {
        if v >= 1000 { return String(format: "%.0f", v) }
        if v >= 100 { return String(format: "%.1f", v) }
        if v >= 1 { return String(format: "%.2f", v) }
        return String(format: "%.4f", v)
    }
}

// MARK: - K 线周期切换条

struct KLinePeriodPicker: View {
    @Binding var period: KLinePeriod
    let periods: [KLinePeriod] = [.day, .week, .month, .year]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(periods, id: \.self) { p in
                Button {
                    period = p
                } label: {
                    Text(p.displayName)
                        .font(.system(size: 12, weight: period == p ? .semibold : .regular))
                        .foregroundStyle(period == p ? DS.textPrimary : DS.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusMedium)
                                .fill(period == p ? DS.bgSelected : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
