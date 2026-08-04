import XCTest
@testable import CoreKit

final class RobustCSVTests: XCTestCase {

    /// 英文通用表头（带空格列名）
    func testEnglishHeadersWithSpaces() {
        let csv = """
        Symbol,Quantity,Cost Basis,Current Price,Market Value
        AAPL,10,180.50,190.00,1900.00
        MSFT,5,320.00,350.00,1750.00
        """
        let r = RobustCSV.parse(csv)
        XCTAssertEqual(r.mapping[.symbol], 0)
        XCTAssertEqual(r.mapping[.quantity], 1)
        XCTAssertEqual(r.mapping[.costBasis], 2)
        let holdings = RobustCSV.extractHoldings(r, broker: "test")
        XCTAssertEqual(holdings.count, 2)
        XCTAssertEqual(holdings[0].symbol.code, "AAPL")
        XCTAssertEqual(holdings[0].quantity, 10)
        XCTAssertEqual(holdings[0].costBasis, 180.5, accuracy: 0.001)
    }

    /// 中文表头（代码/持仓数量/成本价）
    func testChineseHeaders() {
        let csv = """
        代码,名称,持仓数量,成本价,市值
        600519,贵州茅台,100,1500.00,152000.00
        000858,五粮液,200,120.00,13000.00
        """
        let r = RobustCSV.parse(csv)
        XCTAssertEqual(r.mapping[.symbol], 0)
        XCTAssertEqual(r.mapping[.quantity], 2)
        XCTAssertEqual(r.mapping[.costBasis], 3)
        let holdings = RobustCSV.extractHoldings(r, broker: "test")
        XCTAssertEqual(holdings.count, 2)
        XCTAssertEqual(holdings[0].symbol.market, .cn)   // 6 位数字 → A股
        XCTAssertEqual(holdings[0].symbol.code, "600519")
    }

    /// 带引号 + 逗号转义
    func testQuotedCSV() {
        let csv = """
        "Ticker","Shares","Average Cost"
        "TSLA","20","250.50"
        "NVDA","8","900.00"
        """
        let r = RobustCSV.parse(csv)
        let holdings = RobustCSV.extractHoldings(r, broker: "test")
        XCTAssertEqual(holdings.count, 2)
        XCTAssertEqual(holdings[0].symbol.code, "TSLA")
        XCTAssertEqual(holdings[1].costBasis, 900.0, accuracy: 0.001)
    }

    /// 金额清理（$、千分位、中文万）
    func testCleanNumber() {
        XCTAssertEqual(RobustCSV.cleanNumber("$1,234.50"), 1234.5)
        XCTAssertEqual(RobustCSV.cleanNumber("1,234.50"), 1234.5)
        XCTAssertEqual(RobustCSV.cleanNumber("5万"), 50_000)
        XCTAssertEqual(RobustCSV.cleanNumber("HK$12.34"), 12.34)
        XCTAssertNil(RobustCSV.cleanNumber("abc"))
    }

    /// 分号分隔符嗅探
    func testSemicolonDelimiter() {
        let csv = "Symbol;Quantity;Cost Basis\nAAPL;10;180.5\n"
        let r = RobustCSV.parse(csv)
        let holdings = RobustCSV.extractHoldings(r, broker: "test")
        XCTAssertEqual(holdings.count, 1)
        XCTAssertEqual(holdings[0].symbol.code, "AAPL")
    }

    /// TSV（tab 分隔）
    func testTSV() {
        let csv = "Symbol\tQuantity\tCost Basis\nAAPL\t10\t180.5\n"
        let r = RobustCSV.parse(csv)
        let holdings = RobustCSV.extractHoldings(r, broker: "test")
        XCTAssertEqual(holdings.count, 1)
        XCTAssertEqual(holdings[0].quantity, 10)
    }

    /// 空文件 / 无表头
    func testEmptyOrNoHeader() {
        let r1 = RobustCSV.parse("")
        XCTAssertTrue(r1.rows.isEmpty)
        let r2 = RobustCSV.parse("随便一行,没有表头\n")
        XCTAssertTrue(RobustCSV.extractHoldings(r2, broker: "test").isEmpty)
    }

    /// 加密资产识别
    func testCryptoDetection() {
        let csv = """
        Symbol,Quantity,Cost Basis
        BTCUSDT,0.5,62000
        ETHUSDT,2,3000
        """
        let r = RobustCSV.parse(csv)
        let holdings = RobustCSV.extractHoldings(r, broker: "test")
        XCTAssertEqual(holdings.count, 2)
        XCTAssertEqual(holdings[0].symbol.market, .crypto)
        XCTAssertEqual(holdings[0].assetType, .crypto)
    }
}
