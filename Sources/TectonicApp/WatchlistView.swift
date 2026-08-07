import SwiftUI
import CoreKit

/// 自选列表：分组显示，点击进入详情
struct WatchlistView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let groups = app.store.groups()
        ScrollView {
            VStack(spacing: 6) {
                ForEach(groups, id: \.self) { group in
                    let items = app.store.watchlist.filter { $0.group == group }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group)
                            .font(.system(size: DS.metaSize, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                        ForEach(items, id: \.symbol.id) { item in
                            DSQuoteRow(name: item.symbol.name,
                                       subtitle: "\(item.symbol.code) · \(item.symbol.market.displayName)",
                                       price: quotePrice(item.symbol),
                                       change: quoteChange(item.symbol),
                                       isSelected: app.selectedSymbol?.id == item.symbol.id) {
                                app.selectedSymbol = item.symbol
                            }
                            .task(id: item.symbol.id) {
                                if app.store.quotes[item.symbol.id] == nil {
                                    if let q = await app.store.quote(for: item.symbol) {
                                        app.store.updateQuote(q)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .overlay {
            if app.store.watchlist.isEmpty {
                DSPlaceholder(icon: .star,
                              title: L10n.l("watchlist.empty"),
                              subtitle: L10n.l("watchlist.emptyHint"))
            }
        }
    }

    private func quotePrice(_ symbol: Symbol) -> String? {
        guard let q = app.store.quotes[symbol.id] else { return nil }
        return "\(fmt(q.price)) \(symbol.currency)"
    }

    private func quoteChange(_ symbol: Symbol) -> Double? {
        app.store.quotes[symbol.id]?.changePercent
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
    }
}

// MARK: - 行情（按市场）

struct MarketsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(app.activeMarkets) { market in
                    let symbols = symbols(for: market)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(market.displayName)
                                .font(.system(size: DS.metaSize, weight: .semibold))
                                .foregroundStyle(DS.textSecondary)
                            Spacer()
                            Text(market.tradingHours)
                                .font(.system(size: 10))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                        if symbols.isEmpty {
                            Text(L10n.l("markets.empty"))
                                .font(.system(size: DS.captionSize))
                                .foregroundStyle(DS.textTertiary)
                                .padding(.horizontal, 10)
                        } else {
                            ForEach(symbols, id: \.id) { symbol in
                                DSQuoteRow(name: symbol.name,
                                           subtitle: "\(symbol.code) · \(symbol.market.displayName)",
                                           price: quotePrice(symbol),
                                           change: quoteChange(symbol),
                                           isSelected: app.selectedSymbol?.id == symbol.id) {
                                    app.selectedSymbol = symbol
                                }
                                .task(id: symbol.id) {
                                    if app.store.quotes[symbol.id] == nil {
                                        if let q = await app.store.quote(for: symbol) {
                                            app.store.updateQuote(q)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .overlay {
            if app.activeMarkets.isEmpty {
                DSPlaceholder(icon: .chartLine,
                              title: L10n.l("markets.disabled"),
                              subtitle: L10n.l("markets.disabledHint"))
            }
        }
    }

    /// 该市场下自选 + 已拉取的标的
    private func symbols(for market: Market) -> [Symbol] {
        app.store.watchlist
            .filter { $0.symbol.market == market }
            .map(\.symbol)
    }

    private func quotePrice(_ symbol: Symbol) -> String? {
        guard let q = app.store.quotes[symbol.id] else { return nil }
        return "\(fmt(q.price)) \(symbol.currency)"
    }

    private func quoteChange(_ symbol: Symbol) -> Double? {
        app.store.quotes[symbol.id]?.changePercent
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.2f", v) : String(format: "%.4f", v)
    }
}
