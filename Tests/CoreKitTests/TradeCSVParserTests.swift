import XCTest
@testable import CoreKit

final class TradeCSVParserTests: XCTestCase {

    /// 嘉信（Schwab）交易 CSV 真实表头格式
    func testSchwabTransactions() {
        let csv = """
        "Action","Date","Symbol","Description","Quantity","Price","Fees","Amount"
        "Buy","08/01/2026","AAPL","APPLE INC",10,180.50,0,1805.00
        "Sell","08/02/2026","MSFT","MICROSOFT CORP",5,350.00,1,1749.00
        "Buy to Close","08/03/2026","SPY","SPDR S&P 500 ETF",2,550.00,0,1100.00
        """
        let trades = TradeCSVParser.parse(csv)
        XCTAssertEqual(trades.count, 3)
        XCTAssertEqual(trades[0].symbol, "AAPL")
        XCTAssertEqual(trades[0].direction, "buy")
        XCTAssertEqual(trades[0].quantity, 10)
        XCTAssertEqual(trades[0].price, 180.5, accuracy: 0.001)
        XCTAssertEqual(trades[0].fee, 0)
        // 日期 MM/dd/yyyy
        XCTAssertNotNil(trades[0].date)
        let comps = Calendar.current.dateComponents([.month, .day, .year], from: trades[0].date!)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.year, 2026)
        // Buy to Close 归为 buy
        XCTAssertEqual(trades[2].direction, "buy")
    }

    /// 盈透（IBKR）Activity 简化导出
    func testIBKRTrades() {
        let csv = """
        Symbol,Quantity,Price,Date,Action
        TSLA,20,250.50,2026-07-15,Buy
        NVDA,-8,900.00,2026-07-16,Sell
        """
        let trades = TradeCSVParser.parse(csv)
        XCTAssertEqual(trades.count, 2)
        XCTAssertEqual(trades[0].symbol, "TSLA")
        XCTAssertEqual(trades[1].direction, "sell")
        XCTAssertEqual(trades[1].quantity, 8)   // 负数数量取绝对值
        XCTAssertEqual(trades[1].price, 900.0, accuracy: 0.001)
    }

    /// 富途（Futu）交易导出
    func testFutuTrades() {
        let csv = """
        代码,名称,方向,成交数量,成交价,手续费,成交时间
        00700,腾讯控股,买入,100,380.00,3.00,2026-07-20
        09988,阿里巴巴,卖出,200,120.00,5.00,2026-07-21
        """
        let trades = TradeCSVParser.parse(csv)
        XCTAssertEqual(trades.count, 2)
        XCTAssertEqual(trades[0].symbol, "00700")
        XCTAssertEqual(trades[0].direction, "buy")
        XCTAssertEqual(trades[0].market, .hk)
        XCTAssertEqual(trades[1].direction, "sell")
    }

    /// 方向由金额正负推断（无 Action 列）
    func testAmountDirectionInference() {
        let csv = """
        Date,Symbol,Quantity,Price,Amount
        2026-06-01,AAPL,10,100,1000
        2026-06-02,AAPL,-10,110,-1100
        """
        let trades = TradeCSVParser.parse(csv)
        XCTAssertEqual(trades.count, 2)
        guard trades.count == 2 else { return }
        XCTAssertEqual(trades[0].direction, "buy")
        XCTAssertEqual(trades[1].direction, "sell")
    }

    /// 日期多格式
    func testDateFormats() {
        XCTAssertNotNil(TradeCSVParser.parseDate("08/01/2026"))
        XCTAssertNotNil(TradeCSVParser.parseDate("2026-08-01"))
        XCTAssertNotNil(TradeCSVParser.parseDate("2026年8月1日"))
        XCTAssertNotNil(TradeCSVParser.parseDate("2026/08/01"))
        XCTAssertNil(TradeCSVParser.parseDate("not a date"))
    }
}
