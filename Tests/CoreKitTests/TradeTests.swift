import XCTest
@testable import CoreKit

final class TradeTests: XCTestCase {

    /// 交易总额计算（期权含乘数）
    func testTradeAmounts() {
        let buy = Trade(name: "苹果", code: "AAPL", market: .us, direction: "buy",
                        quantity: 10, price: 180.5, fee: 1)
        XCTAssertEqual(buy.grossAmount, 1805, accuracy: 0.001)
        XCTAssertEqual(buy.netAmount, 1804, accuracy: 0.001)

        let sell = Trade(name: "苹果", code: "AAPL", market: .us, direction: "sell",
                         quantity: 5, price: 3.2, fee: 0,
                         option: OptionSpec(callPut: "call", strikePrice: 200))
        // 期权：5 张 × 3.2 × 100 乘数 = 1600（卖出为负）
        XCTAssertEqual(sell.grossAmount, -1600, accuracy: 0.001)
        XCTAssertEqual(sell.netAmount, -1600, accuracy: 0.001)
    }

    /// 资产净值曲线（累计现金流：买-，卖+）
    func testEquityCurve() {
        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let day2 = Date(timeIntervalSince1970: 1_800_086_400)
        var trades: [Trade] = []
        trades.append(Trade(date: day1, name: "A", code: "A", direction: "buy", quantity: 1, price: 100))
        trades.append(Trade(date: day2, name: "A", code: "A", direction: "sell", quantity: 1, price: 120))
        let curve = Trade.equityCurve(from: trades)
        XCTAssertEqual(curve.count, 2)
        XCTAssertEqual(curve[0].1, -100, accuracy: 0.001)   // 买入支出 100
        XCTAssertEqual(curve[1].1, 20, accuracy: 0.001)     // 卖出收入 120 → 净 +20
    }

    /// 期权 Spec 显示名
    func testOptionDisplayName() {
        let opt = OptionSpec(callPut: "call", strikePrice: 200)
        XCTAssertTrue(opt.displayName.contains("看涨"))
    }
}

extension Trade {
    /// 静态工具：从交易列表计算净值曲线（供单测）
    static func equityCurve(from trades: [Trade]) -> [(Date, Double)] {
        var points: [(Date, Double)] = []
        var equity: Double = 0
        for tx in trades.sorted(by: { $0.date < $1.date }) {
            let amount = abs(tx.netAmount)
            let cash = tx.direction == "buy" ? -amount : amount
            equity += cash
            points.append((tx.date, equity))
        }
        return points
    }
}
