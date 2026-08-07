import SwiftUI
import CoreKit

/// 自选列表：分组显示，Position Row 形态（RH）
struct WatchlistView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let groups = app.store.groups()
        ScrollView {
            VStack(spacing: DS.space8) {
                ForEach(groups, id: \.self) { group in
                    let items = app.store.watchlist.filter { $0.group == group }
                    VStack(alignment: .leading, spacing: 2) {
                        // RH Section Header：18pt semibold
                        Text(group)
                            .font(.system(size: DS.sectionHeaderSize, weight: .semibold))
                            .kerning(-0.1)
                            .foregroundStyle(DS.textPrimary)
                            .padding(.horizontal, DS.space4)
                            .padding(.bottom, 4)

                        ForEach(items, id: \.symbol.id) { item in
                            PositionRow(name: item.symbol.name,
                                        ticker: "\(item.symbol.code) · \(item.symbol.market.displayName)",
                                        icon: marketIcon(item.symbol.market),
                                        value: quotePrice(item.symbol),
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
            .padding(.vertical, DS.space4)
        }
        .background(DS.bgApp)
        .overlay {
            if app.store.watchlist.isEmpty {
                DSPlaceholder(icon: .star,
                              title: L10n.l("watchlist.empty"),
                              subtitle: L10n.l("watchlist.emptyHint"))
            }
        }
    }

    private func marketIcon(_ m: Market) -> TectonicIcon {
        switch m {
        case .us: .buildingBank
        case .crypto: .currencyBitcoin
        case .hk: .buildingSkyscraper
        case .cn: .building
        case .fund: .chartDonut
        case .kr: .buildingCommunity
        case .jp: .sun
        case .tw: .mountain
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

// MARK: - 行情（按市场，RH Position Row）

struct MarketsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: DS.space8) {
                ForEach(app.activeMarkets) { market in
                    let symbols = symbols(for: market)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(market.displayName)
                                .font(.system(size: DS.sectionHeaderSize, weight: .semibold))
                                .kerning(-0.1)
                                .foregroundStyle(DS.textPrimary)
                            Spacer()
                            Text(market.tradingHours)
                                .font(.system(size: DS.tickerSize, weight: .medium))
                                .foregroundStyle(DS.textTertiary)
                        }
                        .padding(.horizontal, DS.space4)
                        .padding(.bottom, 4)

                        if symbols.isEmpty {
                            Text(L10n.l("markets.empty"))
                                .font(.system(size: DS.bodySmallSize))
                                .foregroundStyle(DS.textTertiary)
                                .padding(.horizontal, DS.space4)
                        } else {
                            ForEach(symbols, id: \.id) { symbol in
                                PositionRow(name: symbol.name,
                                            ticker: "\(symbol.code) · \(symbol.market.displayName)",
                                            icon: marketIcon(symbol.market),
                                            value: quotePrice(symbol),
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
            .padding(.vertical, DS.space4)
        }
        .background(DS.bgApp)
        .overlay {
            if app.activeMarkets.isEmpty {
                DSPlaceholder(icon: .chartLine,
                              title: L10n.l("markets.disabled"),
                              subtitle: L10n.l("markets.disabledHint"))
            }
        }
    }

    private func symbols(for market: Market) -> [Symbol] {
        app.store.watchlist
            .filter { $0.symbol.market == market }
            .map(\.symbol)
    }

    private func marketIcon(_ m: Market) -> TectonicIcon {
        switch m {
        case .us: .buildingBank
        case .crypto: .currencyBitcoin
        case .hk: .buildingSkyscraper
        case .cn: .building
        case .fund: .chartDonut
        case .kr: .buildingCommunity
        case .jp: .sun
        case .tw: .mountain
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
