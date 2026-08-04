import Foundation

/// 内置预置标的：每个市场 1-2 个最受关注的标的/指数。
/// 首次启动自动导入自选（幂等），设置中可「恢复内置标的」。
public enum BuiltinSymbols {

    public static let all: [Symbol] = [
        // 美股：七巨头 + 指数ETF
        Symbol(market: .us, code: "AAPL", name: "苹果"),
        Symbol(market: .us, code: "NVDA", name: "英伟达"),
        Symbol(market: .us, code: "MSFT", name: "微软"),
        Symbol(market: .us, code: "GOOGL", name: "谷歌"),
        Symbol(market: .us, code: "AMZN", name: "亚马逊"),
        Symbol(market: .us, code: "META", name: "Meta"),
        Symbol(market: .us, code: "TSLA", name: "特斯拉"),
        Symbol(market: .us, code: "QQQ", name: "纳指100ETF"),
        Symbol(market: .us, code: "VOO", name: "标普500ETF"),
        // 加密
        Symbol(market: .crypto, code: "BTCUSDT", name: "比特币"),
        Symbol(market: .crypto, code: "ETHUSDT", name: "以太坊"),
        // 港股
        Symbol(market: .hk, code: "00700", name: "腾讯控股"),
        Symbol(market: .hk, code: "HSI", name: "恒生指数"),
        // A股：指数 + ETF（sh 前缀区分沪市指数/ETF）
        Symbol(market: .cn, code: "sh000001", name: "上证指数"),
        Symbol(market: .cn, code: "sh000300", name: "沪深300"),
        Symbol(market: .cn, code: "sh000688", name: "科创板50"),
        Symbol(market: .cn, code: "sh510300", name: "沪深300ETF"),
        // 基金
        Symbol(market: .fund, code: "110022", name: "易方达消费行业"),
        // 日股
        Symbol(market: .jp, code: "7203", name: "丰田汽车"),
        Symbol(market: .jp, code: "N225", name: "日经225"),
        // 韩股
        Symbol(market: .kr, code: "005930", name: "三星电子"),
        // 台股
        Symbol(market: .tw, code: "2330", name: "台积电"),
        Symbol(market: .tw, code: "TWII", name: "台湾加权指数"),
    ]

    /// 首次启动导入标志
    public static let importedFlagKey = "builtin_symbols_imported"
}
