# Tectonic

**Native macOS finance & AI analysis companion** — an Apple-native (SwiftUI) information hub for markets, news, and your portfolio, backed by a built-in AI assistant.

Fully local, no account, no cloud sync. Your data stays on your Mac.

## Features

### 📈 Markets & Technicals
- **8 markets**: US stocks, Crypto, HK, A-shares, Funds, Korea, Japan, Taiwan
- Real-time quotes from free public sources (Tencent, TWSE, CoinGecko, Eastmoney indices)
- **Technical analysis panel**: support/resistance, MA (MA5/10/20/60/120/250), RSI, MACD, BOLL, KDJ, 52-week range, YTD — all computed locally
- Watchlist with groups, star/unstar, smart search across all markets

### 📰 News (pure RSS)
- Flash news / Research / Earnings, **RSS-only** (no APIs, no scrapers) — 11 curated feeds: 中新网财经, 日经中文网, 36Kr, CNBC, MarketWatch, CoinDesk, CoinTelegraph, The Block, Fortune, Forbes, Seeking Alpha
- Custom RSS feeds with validation before adding
- Reading view with detail pane

### 🗓️ Macro Economic Calendar
- Daily economic events from **investing.com** (the only API/scraper in the app, per design): CPI, GDP, PMI, unemployment, rate decisions…
- 8 regions: US / China / Eurozone / Japan / UK / Germany / Australia / Canada
- Grouped by day with actual / forecast / previous values and importance (1–3 stars)

### 🤖 AI Assistant (built-in)
- **Slide-out chat panel** on the right — the window expands, your UI never moves
- Multi-provider: local **Ollama** + cloud (OpenAI-compatible: DeepSeek / Kimi / Qwen / Zhipu…), API keys stored locally only
- **Web search integration**: bring your own key (Brave Search / Serper / Tavily — free tiers available), falls back to built-in RSS retrieval
- Built-in **stock/finance analysis skills**: technical, fundamental, earnings, valuation, macro, multi-asset, crypto frameworks injected into every model
- Quick questions + markdown-style adaptive bubbles

### 💼 Portfolio & Transactions
- Manual entry only (by design): holdings with market/asset type inference from the code (e.g. `00700` → HK, `600519` → A-share, `AAPL` → US)
- Trade journal: stocks / bonds / funds / currencies / crypto / **options** (call/put, strike, expiry)
- **Asset trend line** (cash-flow based) + **allocation donut chart** (Swift Charts)
- One-click add holdings to watchlist

### 🌐 i18n
- UI in 中文 / English / 日本語 — preferred language switches the whole app instantly

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI, macOS 26 (Liquid Glass), Swift Charts |
| Storage | GRDB 7.x (SQLite), migrations |
| Concurrency | Swift 6 strict concurrency (all models Sendable) |
| Data | Free public sources + RSS; investing.com calendar (scraper) |
| AI | OpenAI-compatible gateway + Ollama local |

## Build

```bash
# macOS 26, arm64; Swift 6.3 toolchain (no Xcode required)
swift build          # build all targets
swift test           # 39 unit tests
.build/arm64-apple-macosx/debug/tectonic-cli quote us:AAPL
.build/arm64-apple-macosx/debug/tectonic-cli news flash
```

## CLI

The `tectonic-cli` binary doubles as an end-to-end smoke tester:

```bash
tectonic-cli quote us:AAPL | tech cn:600519     # quotes & technicals
tectonic-cli watch add us:AAPL "Tech"            # watchlist
tectonic-cli news flash|research|earnings       # RSS feeds
tectonic-cli trades list|add|delete             # trade journal
tectonic-cli models --refresh                    # AI model catalog
```

## Project Layout

```
Sources/
  CoreKit/          models, data sources, GRDB storage, AI gateway, L10n (no UI)
  tectonic-cli/     command-line tool
  TectonicApp/      macOS SwiftUI app
Tests/CoreKitTests/ unit tests (39)
scripts/            icon generator, Info.plist
```

## Release

DMG installer attached to each [GitHub Release](https://github.com/shark-bee-art/Tectonic/releases) — drag to Applications. The app is ad-hoc signed for local use.

## Notes

- Market data is for reference only — not investment advice.
- Web-search API keys are entered in Settings → AI Model → Web Search (get one from Brave / Serper / Tavily official sites).
- Option quotes are not yet available (free Yahoo chains are rate-limited); options are supported for positions & trade journal.
