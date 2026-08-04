import SwiftUI
import CoreKit

/// 自选列表：分组显示，点击进入详情
struct WatchlistView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let groups = app.store.groups()
        List(selection: $app.selectedSymbol) {
            ForEach(groups, id: \.self) { group in
                let items = app.store.watchlist.filter { $0.group == group }
                Section(group) {
                    ForEach(items, id: \.symbol.id) { item in
                        QuoteRow(symbol: item.symbol,
                                 quote: app.store.quotes[item.symbol.id])
                            .tag(item.symbol)
                    }
                }
            }
        }
        .overlay {
            if app.store.watchlist.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("自选为空\n点击右上角 + 添加标的")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 行情（按市场）

struct MarketsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        List(selection: $app.selectedSymbol) {
            ForEach(app.activeMarkets) { market in
                let symbols = symbols(for: market)
                Section {
                    if symbols.isEmpty {
                        Text("点击右上角 + 添加")
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(symbols, id: \.id) { symbol in
                            QuoteRow(symbol: symbol,
                                     quote: app.store.quotes[symbol.id])
                                .tag(symbol)
                        }
                    }
                } header: {
                    HStack {
                        Text(market.displayName)
                        Spacer()
                        Text(market.tradingHours)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if app.activeMarkets.isEmpty {
                Text("未启用任何市场\n请到设置中开启")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 该市场下自选 + 已拉取的标的
    private func symbols(for market: Market) -> [Symbol] {
        app.store.watchlist
            .filter { $0.symbol.market == market }
            .map(\.symbol)
    }
}

// MARK: - 行情行

struct QuoteRow: View {
    @EnvironmentObject var app: AppState
    let symbol: Symbol
    let quote: Quote?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol.name)
                    .lineLimit(1)
                Text("\(symbol.code) · \(symbol.market.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let quote {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(fmtPrice(quote.price)) \(symbol.currency)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(quote.change >= 0 ? Color.red : Color.green)
                    Text("\(fmtSigned(quote.change))  \(fmtPercent(quote.changePercent))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(quote.change >= 0 ? Color.red : Color.green)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .task(id: symbol.id) {
            if app.store.quotes[symbol.id] == nil {
                let q = await app.store.quote(for: symbol)
                if let q {
                    app.store.updateQuote(q)
                }
            }
        }
    }

    private func fmtPrice(_ v: Double) -> String {
        v >= 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
    }
    private func fmtSigned(_ v: Double) -> String {
        String(format: "%+.2f", v)
    }
    private func fmtPercent(_ v: Double) -> String {
        String(format: "%+.2f%%", v)
    }
}
