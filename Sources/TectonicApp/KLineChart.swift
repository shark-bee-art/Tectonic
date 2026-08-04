import SwiftUI
import CoreKit

/// 苹果股市 App 风格 K线图（Canvas 绘制）
/// - 极简淡网格 + 右侧价格刻度
/// - 收盘线下方渐变填充
/// - 蜡烛：影线 + 圆角实体（国内习惯：红涨绿跌）
/// - 鼠标 hover 十字线 + 信息气泡
struct KLineChart: View {
    let bars: [KLineBar]

    @State private var hoverIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !bars.isEmpty, size.width > 10, size.height > 10 else { return }
                drawChart(context: &context, size: size)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard !bars.isEmpty, geo.size.width > 0 else { return }
                    let step = geo.size.width / CGFloat(bars.count)
                    let idx = min(max(Int(location.x / step), 0), bars.count - 1)
                    hoverIndex = idx
                case .ended:
                    hoverIndex = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let idx = hoverIndex, idx >= 0, idx < bars.count {
                    HoverBubble(bar: bars[idx])
                        .padding(8)
                }
            }
        }
    }

    private func drawChart(context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let priceTopPadding: CGFloat = 8    // 顶部留白（放 OHLC 信息条在外部）

        // 价格区间（高低 + 8% 留白）
        let minP = bars.map(\.low).min() ?? 0
        let maxP = bars.map(\.high).max() ?? 1
        let pad = (maxP - minP) * 0.08
        let lo = minP - pad
        let hi = maxP + pad
        guard hi > lo else { return }

        let step = w / CGFloat(bars.count)
        func xf(_ i: Int) -> CGFloat { CGFloat(i) * step + step / 2 }
        func yf(_ p: Double) -> CGFloat { h - CGFloat((p - lo) / (hi - lo)) * (h - priceTopPadding) + priceTopPadding / 2 }

        // 1. 收盘线下方渐变填充（淡，随最后收盘方向着色）
        let lastUp = (bars.last?.close ?? 0) >= (bars.first?.open ?? 0)
        let fillColor: Color = lastUp ? .red : .green
        var fillPath = Path()
        for (i, bar) in bars.enumerated() {
            let pt = CGPoint(x: xf(i), y: yf(bar.close))
            if i == 0 { fillPath.move(to: pt) } else { fillPath.addLine(to: pt) }
        }
        if let lastX = bars.indices.last.map({ xf($0) }) {
            fillPath.addLine(to: CGPoint(x: lastX, y: h))
            fillPath.addLine(to: CGPoint(x: xf(0), y: h))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .linearGradient(
                Gradient(colors: [fillColor.opacity(0.18), fillColor.opacity(0.0)]),
                startPoint: CGPoint(x: 0, y: priceTopPadding / 2),
                endPoint: CGPoint(x: 0, y: h)))
        }

        // 2. 淡网格线（3 条横线）
        for i in 0...3 {
            let y = priceTopPadding / 2 + (h - priceTopPadding) * CGFloat(i) / 3
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: w, y: y))
            context.stroke(line, with: .color(.primary.opacity(0.05)), lineWidth: 1)
        }

        // 3. 蜡烛（影线 + 实体）
        for (i, bar) in bars.enumerated() {
            let up = bar.close >= bar.open
            let color: Color = up ? .red : .green
            let x = xf(i)
            // 影线
            var wick = Path()
            wick.move(to: CGPoint(x: x, y: yf(bar.high)))
            wick.addLine(to: CGPoint(x: x, y: yf(bar.low)))
            context.stroke(wick, with: .color(color.opacity(0.9)), lineWidth: 1)
            // 实体
            let bodyTop = yf(max(bar.open, bar.close))
            let bodyBottom = yf(min(bar.open, bar.close))
            let bodyH = max(bodyBottom - bodyTop, 1.5)
            let bodyW = max(step * 0.62, 1.5)
            let rect = CGRect(x: x - bodyW / 2, y: bodyTop, width: bodyW, height: bodyH)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
        }

        // 4. 右侧价格刻度（3 个）
        for i in 0...3 {
            let p = hi - (hi - lo) * Double(i) / 3
            let y = priceTopPadding / 2 + (h - priceTopPadding) * CGFloat(i) / 3 - 7
            var text = context.resolve(Text(fmt(p))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary))
            context.draw(text, at: CGPoint(x: w - 6, y: y), anchor: .trailing)
        }

        // 5. 首尾日期
        if let first = bars.first, let last = bars.last {
            var firstText = context.resolve(Text(shortDate(first.time))
                .font(.caption2).foregroundStyle(.secondary))
            var lastText = context.resolve(Text(shortDate(last.time))
                .font(.caption2).foregroundStyle(.secondary))
            context.draw(firstText, at: CGPoint(x: 2, y: h - 8), anchor: .leading)
            context.draw(lastText, at: CGPoint(x: w - 2, y: h - 8), anchor: .trailing)
        }

        // 6. 十字线
        if let idx = hoverIndex, idx >= 0, idx < bars.count {
            let x = xf(idx)
            var vLine = Path()
            vLine.move(to: CGPoint(x: x, y: priceTopPadding / 2))
            vLine.addLine(to: CGPoint(x: x, y: h))
            context.stroke(vLine, with: .color(.primary.opacity(0.2)), lineWidth: 1)
            // 当前 K 线中点标记
            let bar = bars[idx]
            let cy = yf(bar.close)
            var dot = Path(ellipseIn: CGRect(x: x - 3, y: cy - 3, width: 6, height: 6))
            context.fill(dot, with: .color(bar.close >= bar.open ? .red : .green))
        }
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
    }

    private func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Hover 信息气泡：日期 + 开/高/低/收 + 涨跌
struct HoverBubble: View {
    let bar: KLineBar

    var body: some View {
        let up = bar.close >= bar.open
        VStack(alignment: .leading, spacing: 3) {
            Text(bar.time.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow { Text("开").gridColumnAlignment(.trailing); Text(fmt(bar.open)).gridColumnAlignment(.trailing) }
                GridRow { Text("高"); Text(fmt(bar.high)) }
                GridRow { Text("低"); Text(fmt(bar.low)) }
                GridRow { Text("收"); Text(fmt(bar.close)).foregroundStyle(up ? Color.red : Color.green) }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.primary)
            Text("\(fmt(bar.close - bar.open)) (\(fmtPct((bar.close - bar.open) / bar.open * 100)))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(up ? Color.red : Color.green)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        )
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
    }
    private func fmtPct(_ v: Double) -> String {
        String(format: "%+.2f%%", v)
    }
}

// MARK: - 苹果风格时间范围

/// 时间范围选择（苹果股市 App 风格）：自动决定 K线周期与数量
enum ChartRange: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case oneMonth = "1M"
    case threeMonth = "3M"
    case sixMonth = "6M"
    case oneYear = "1Y"
    case fiveYear = "5Y"

    var id: String { rawValue }

    /// 映射到 (周期, 数量)
    var target: (KLinePeriod, Int) {
        switch self {
        case .oneDay: (.m5, 240)          // 分时
        case .oneMonth: (.day, 30)
        case .threeMonth: (.day, 65)
        case .sixMonth: (.day, 130)
        case .oneYear: (.day, 250)
        case .fiveYear: (.week, 260)
        }
    }
}
