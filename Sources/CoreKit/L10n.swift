import Foundation

/// 应用本地化（中/英/日）：首选语言 = 整个应用界面语言。
/// 所有 UI 文案通过 l("key") 取词；语言切换后 AppState 转发变化驱动 UI 刷新。
public enum L10n {

    /// 当前界面语言（默认中文）
    public static var currentLanguage: String {
        UserDefaults.standard.string(forKey: "preferred_language") ?? "zh"
    }

    /// 取词：l("sidebar.watchlist") → 当前语言文案；缺失回退中文，再缺失返回 key
    public static func l(_ key: String) -> String {
        let lang = currentLanguage
        if let table = dict[key], let s = table[lang], !s.isEmpty { return s }
        if let table = dict[key], let s = table["zh"], !s.isEmpty { return s }
        return key
    }

    /// 语言显示名
    public static var languageDisplayName: String {
        switch currentLanguage {
        case "en": "English"
        case "ja": "日本語"
        default: "中文"
        }
    }

    // MARK: - 文案表（key → 三语）

    public static let dict: [String: [String: String]] = [
        // 侧边栏
        "sidebar.navigation": ["zh": "导航", "en": "Navigate", "ja": "ナビゲーション"],
        "sidebar.watchlist": ["zh": "自选", "en": "Watchlist", "ja": "ウォッチリスト"],
        "sidebar.markets": ["zh": "行情", "en": "Markets", "ja": "相場"],
        "sidebar.news": ["zh": "资讯", "en": "News", "ja": "ニュース"],
        "sidebar.flash": ["zh": "快讯", "en": "Flash", "ja": "速報"],
        "sidebar.research": ["zh": "研报", "en": "Research", "ja": "リサーチ"],
        "sidebar.earnings": ["zh": "财报", "en": "Earnings", "ja": "決算"],
        "sidebar.calendar": ["zh": "日历", "en": "Calendar", "ja": "カレンダー"],
        "sidebar.assets": ["zh": "资产", "en": "Assets", "ja": "資産"],
        "sidebar.holdings": ["zh": "持仓", "en": "Holdings", "ja": "保有銘柄"],
        "sidebar.transactions": ["zh": "交易记录", "en": "Transactions", "ja": "取引履歴"],
        // 通用
        "common.refresh": ["zh": "刷新", "en": "Refresh", "ja": "更新"],
        "common.add": ["zh": "添加", "en": "Add", "ja": "追加"],
        "common.remove": ["zh": "移除", "en": "Remove", "ja": "削除"],
        "common.delete": ["zh": "删除", "en": "Delete", "ja": "削除"],
        "common.edit": ["zh": "编辑", "en": "Edit", "ja": "編集"],
        "common.cancel": ["zh": "取消", "en": "Cancel", "ja": "キャンセル"],
        "common.done": ["zh": "完成", "en": "Done", "ja": "完了"],
        "common.save": ["zh": "保存", "en": "Save", "ja": "保存"],
        "common.search": ["zh": "搜索", "en": "Search", "ja": "検索"],
        "common.import": ["zh": "导入", "en": "Import", "ja": "インポート"],
        "common.clear": ["zh": "清空", "en": "Clear", "ja": "クリア"],
        "common.loading": ["zh": "加载中…", "en": "Loading…", "ja": "読み込み中…"],
        "common.thinking": ["zh": "思考中…", "en": "Thinking…", "ja": "考え中…"],
        "common.send": ["zh": "发送", "en": "Send", "ja": "送信"],
        "common.yes": ["zh": "是", "en": "Yes", "ja": "はい"],
        "common.no": ["zh": "否", "en": "No", "ja": "いいえ"],
        "common.failed": ["zh": "失败", "en": "Failed", "ja": "失敗"],
        // 设置
        "settings.title": ["zh": "设置", "en": "Settings", "ja": "設定"],
        "settings.marketTab": ["zh": "市场", "en": "Markets", "ja": "市場"],
        "settings.aiTab": ["zh": "AI 模型", "en": "AI Model", "ja": "AIモデル"],
        "settings.newsTab": ["zh": "资讯源", "en": "News Sources", "ja": "ニュースソース"],
        "settings.generalTab": ["zh": "通用", "en": "General", "ja": "一般"],
        "settings.language": ["zh": "首选语言", "en": "Preferred Language", "ja": "表示言語"],
        "settings.languageHint": ["zh": "整个应用的界面语言", "en": "App interface language", "ja": "アプリの表示言語"],
        "settings.refreshInterval": ["zh": "行情刷新频率", "en": "Quote Refresh", "ja": "相場更新頻度"],
        "settings.refreshIntervalHint": ["zh": "手动刷新随时可用（⌘R）", "en": "Manual refresh always available (⌘R)", "ja": "手動更新はいつでも可能（⌘R）"],
        "settings.minutes": ["zh": "分钟", "en": "min", "ja": "分"],
        "settings.hour": ["zh": "小时", "en": "hour", "ja": "時間"],
        "settings.aiLanguage": ["zh": "AI 回答语言", "en": "AI Reply Language", "ja": "AI応答言語"],
        "settings.aiLanguageHint": ["zh": "AI 问询与资讯解读使用该语言回复", "en": "AI replies in this language", "ja": "AIの応答言語"],
        "settings.model": ["zh": "模型", "en": "Model", "ja": "モデル"],
        "settings.customModel": ["zh": "自定义模型…", "en": "Custom model…", "ja": "カスタムモデル…"],
        "settings.modelCustomField": ["zh": "自定义模型名称", "en": "Custom model name", "ja": "カスタムモデル名"],
        "settings.modelUpdated": ["zh": "每周自动更新", "en": "Auto-refreshed weekly", "ja": "毎週自動更新"],
        "settings.provider": ["zh": "供应商", "en": "Provider", "ja": "プロバイダー"],
        "settings.apiKey": ["zh": "API Key（仅本地存储）", "en": "API Key (local only)", "ja": "APIキー（ローカルのみ）"],
        "settings.apiKeyPlaceholder": ["zh": "输入 API Key", "en": "Enter API Key", "ja": "APIキーを入力"],
        "settings.baseURL": ["zh": "接口地址", "en": "Base URL", "ja": "ベースURL"],
        "settings.marketShow": ["zh": "显示开关", "en": "Visibility", "ja": "表示設定"],
        "settings.marketShowHint": ["zh": "选择要显示的市场（按固定顺序展示）", "en": "Choose visible markets (fixed order)", "ja": "表示する市場を選択（固定順）"],
        "settings.restoreBuiltin": ["zh": "恢复内置标的", "en": "Restore Built-in Symbols", "ja": "内蔵銘柄を復元"],
        "settings.newsFeeds": ["zh": "订阅源", "en": "Feeds", "ja": "フィード"],
        "settings.addRSS": ["zh": "添加自定义 RSS 订阅源", "en": "Add Custom RSS Feed", "ja": "カスタムRSSを追加"],
        "settings.restoreFeeds": ["zh": "恢复预置订阅源", "en": "Restore Preset Feeds", "ja": "プリセットフィードを復元"],
        "settings.feedsEmpty": ["zh": "无订阅源（可在下方添加）", "en": "No feeds (add below)", "ja": "フィードなし（下で追加）"],
        // 自选/行情
        "watchlist.empty": ["zh": "自选为空\n点击右上角 + 添加标的", "en": "Watchlist is empty\nTap + to add symbols", "ja": "ウォッチリストが空\n+ で銘柄を追加"],
        "markets.empty": ["zh": "暂无启用市场\n请在设置中开启", "en": "No markets enabled\nEnable in Settings", "ja": "有効な市場なし\n設定で有効化"],
        "detail.addWatchlist": ["zh": "添加自选", "en": "Add to Watchlist", "ja": "ウォッチリストに追加"],
        "detail.removeWatchlist": ["zh": "移出自选", "en": "Remove from Watchlist", "ja": "ウォッチリストから削除"],
        "detail.technical": ["zh": "技术面", "en": "Technical", "ja": "テクニカル"],
        "detail.aiChat": ["zh": "AI 分析", "en": "AI Analysis", "ja": "AI分析"],
        "detail.quickTrend": ["zh": "走势如何", "en": "Trend", "ja": "トレンド"],
        "detail.quickFundamental": ["zh": "基本面", "en": "Fundamentals", "ja": "ファンダメンタル"],
        "detail.quickNews": ["zh": "近期新闻", "en": "Recent News", "ja": "最近のニュース"],
        // 资讯
        "news.aiChat": ["zh": "AI 问询", "en": "AI Chat", "ja": "AIチャット"],
        "news.quickImpact": ["zh": "影响分析", "en": "Impact", "ja": "影響分析"],
        "news.quickOutlook": ["zh": "后续走势", "en": "Outlook", "ja": "今後の見通し"],
        "news.quickRisk": ["zh": "风险点", "en": "Risks", "ja": "リスク"],
        "news.openInBrowser": ["zh": "浏览器打开", "en": "Open in Browser", "ja": "ブラウザで開く"],
        "news.empty": ["zh": "暂无内容\n请在设置 → 资讯源中启用订阅源", "en": "No content\nEnable feeds in Settings → News Sources", "ja": "コンテンツなし\n設定→ニュースソースで有効化"],
        // 持仓
        "holdings.empty": ["zh": "暂无持仓数据", "en": "No holdings", "ja": "保有銘柄なし"],
        "holdings.emptyHint": ["zh": "导入券商导出的 CSV / JSON 文件\n模型自动识别字段（富途/老虎/IBKR/Robinhood/币安等）", "en": "Import broker CSV/JSON\nAI recognizes fields (Futu/Tiger/IBKR/Robinhood/Binance…)", "ja": "証券会社のCSV/JSONをインポート\nAIが項目を自動認識"],
        "holdings.importFile": ["zh": "导入持仓文件", "en": "Import Holdings", "ja": "保有銘柄をインポート"],
        "holdings.importHint": ["zh": "支持券商 CSV / JSON，AI 自动识别字段；可一键导入自选", "en": "Broker CSV/JSON; AI parses fields; one-click add to watchlist", "ja": "証券CSV/JSON対応、AI自動認識、ワンクリックでウォッチリストへ"],
        "holdings.importToWatchlist": ["zh": "一键导入自选", "en": "Add All to Watchlist", "ja": "すべてウォッチリストへ"],
        "holdings.imported": ["zh": "已导入", "en": "Imported", "ja": "インポート済み"],
        "holdings.aiParsing": ["zh": "模型识别中…", "en": "AI parsing…", "ja": "AI解析中…"],
        "holdings.holdings": ["zh": "持仓", "en": "Holdings", "ja": "保有銘柄"],
        "holdings.assetChart": ["zh": "资产变化", "en": "Asset Trend", "ja": "資産推移"],
        "holdings.distribution": ["zh": "持仓分布", "en": "Allocation", "ja": "配分"],
        "holdings.totalValue": ["zh": "总市值", "en": "Total Value", "ja": "時価総額"],
        "holdings.cost": ["zh": "成本", "en": "Cost", "ja": "原価"],
        "holdings.profitLoss": ["zh": "盈亏", "en": "P/L", "ja": "損益"],
        "holdings.broker": ["zh": "券商", "en": "Broker", "ja": "証券会社"],
        // 交易记录
        "tx.title": ["zh": "交易记录", "en": "Transactions", "ja": "取引履歴"],
        "tx.empty": ["zh": "暂无交易记录\n点击 + 添加一笔交易", "en": "No transactions\nTap + to add", "ja": "取引なし\n+ で追加"],
        "tx.add": ["zh": "添加交易", "en": "Add Transaction", "ja": "取引を追加"],
        "tx.edit": ["zh": "编辑交易", "en": "Edit Transaction", "ja": "取引を編集"],
        "tx.date": ["zh": "日期", "en": "Date", "ja": "日付"],
        "tx.type": ["zh": "类型", "en": "Type", "ja": "種別"],
        "tx.assetType": ["zh": "资产类别", "en": "Asset Class", "ja": "資産クラス"],
        "tx.name": ["zh": "名称", "en": "Name", "ja": "名称"],
        "tx.code": ["zh": "代码", "en": "Symbol", "ja": "コード"],
        "tx.direction": ["zh": "方向", "en": "Direction", "ja": "売買"],
        "tx.buy": ["zh": "买入", "en": "Buy", "ja": "買い"],
        "tx.sell": ["zh": "卖出", "en": "Sell", "ja": "売り"],
        "tx.quantity": ["zh": "数量", "en": "Quantity", "ja": "数量"],
        "tx.price": ["zh": "价格", "en": "Price", "ja": "価格"],
        "tx.fee": ["zh": "手续费", "en": "Fee", "ja": "手数料"],
        "tx.total": ["zh": "总额", "en": "Total", "ja": "合計"],
        "tx.notes": ["zh": "备注", "en": "Notes", "ja": "メモ"],
        "tx.deleteConfirm": ["zh": "删除这笔交易？", "en": "Delete this transaction?", "ja": "この取引を削除しますか？"],
        // 资产类别
        "asset.stock": ["zh": "股票", "en": "Stock", "ja": "株式"],
        "asset.bond": ["zh": "债券", "en": "Bond", "ja": "債券"],
        "asset.fund": ["zh": "基金", "en": "Fund", "ja": "ファンド"],
        "asset.currency": ["zh": "货币", "en": "Currency", "ja": "通貨"],
        "asset.crypto": ["zh": "加密货币", "en": "Crypto", "ja": "暗号資産"],
        "asset.option": ["zh": "期权", "en": "Option", "ja": "オプション"],
        "asset.other": ["zh": "其他", "en": "Other", "ja": "その他"],
        // 期权字段
        "option.call": ["zh": "看涨", "en": "Call", "ja": "コール"],
        "option.put": ["zh": "看跌", "en": "Put", "ja": "プット"],
        "option.strike": ["zh": "行权价", "en": "Strike", "ja": "行使価格"],
        "option.expiry": ["zh": "到期日", "en": "Expiry", "ja": "満期日"],
        // 占位
        "placeholder.detail": ["zh": "选择左侧标的查看详情", "en": "Select a symbol to view details", "ja": "左から銘柄を選択"],
        "placeholder.news": ["zh": "选择左侧资讯查看详情", "en": "Select an article to view", "ja": "左から記事を選択"],
        "placeholder.holdingDetail": ["zh": "选择持仓查看详情", "en": "Select a holding", "ja": "保有銘柄を選択"],
    ]
}
