import XCTest
@testable import CoreKit

final class PortfolioEngineTests: XCTestCase {

    private let accID = "acc1"
    private let day1 = Date(timeIntervalSince1970: 1_800_000_000)      // 基准日
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + Double(offset) * 86_400)
    }

    private func buy(_ id: String, asset: String = "AAPL", qty: Double, price: Double,
                     fee: Double = 0, date: Date? = nil, currency: String = "USD") -> Activity {
        Activity(id: id, accountID: accID, assetID: asset, type: .buy,
                 date: date ?? day1, quantity: qty, unitPrice: price,
                 fee: fee, currency: currency)
    }

    private func sell(_ id: String, asset: String = "AAPL", qty: Double, price: Double,
                      fee: Double = 0, date: Date? = nil, currency: String = "USD") -> Activity {
        Activity(id: id, accountID: accID, assetID: asset, type: .sell,
                 date: date ?? day1, quantity: qty, unitPrice: price,
                 fee: fee, currency: currency)
    }

    private func split(_ id: String, asset: String = "AAPL", ratio: Double, date: Date? = nil) -> Activity {
        Activity(id: id, accountID: accID, assetID: asset, type: .split,
                 date: date ?? day1, quantity: ratio)
    }

    private func cash(_ id: String, type: ActivityType, amount: Double, date: Date? = nil) -> Activity {
        Activity(id: id, accountID: accID, type: type, date: date ?? day1, amount: amount)
    }

    private var aapl: Asset { Asset(market: .us, code: "AAPL", name: "苹果", currency: "USD", assetType: .stock) }
    private var tsla: Asset { Asset(market: .us, code: "TSLA", name: "特斯拉", currency: "USD", assetType: .stock) }

    // MARK: - FIFO 基础

    /// 买入 → 开 lot；数量/成本正确（含费）
    func testBuyOpensLot() {
        let act = [buy("b1", qty: 10, price: 100, fee: 5)]
        let (lots, disposals) = LotEngine.computeLots(activities: act)
        XCTAssertEqual(lots.count, 1)
        XCTAssertEqual(disposals.count, 0)
        let lot = lots[0]
        XCTAssertEqual(lot.originalQuantity, 10)
        XCTAssertEqual(lot.remainingQuantity, 10)
        XCTAssertEqual(lot.costPerUnit, 100.5, accuracy: 0.0001)   // (1000+5)/10
        XCTAssertEqual(lot.originalCostBasis, 1005, accuracy: 0.0001)
        XCTAssertFalse(lot.isClosed)
    }

    /// 部分卖出 → FIFO 扣减；批次仍开
    func testPartialSell() {
        let act = [
            buy("b1", qty: 10, price: 100),
            sell("s1", qty: 4, price: 120)
        ]
        let (lots, disposals) = LotEngine.computeLots(activities: act)
        let lot = lots[0]
        XCTAssertEqual(lot.remainingQuantity, 6)
        XCTAssertEqual(lot.remainingCostBasis, 600, accuracy: 0.0001)
        XCTAssertFalse(lot.isClosed)
        XCTAssertEqual(disposals.count, 1)
        XCTAssertEqual(disposals[0].quantity, 4)
        XCTAssertEqual(disposals[0].proceeds, 480, accuracy: 0.0001)
        XCTAssertEqual(disposals[0].costBasis, 400, accuracy: 0.0001)
        XCTAssertEqual(disposals[0].realizedPnL, 80, accuracy: 0.0001)
    }

    /// 全部卖出 → lot 关闭；已实现盈亏正确
    func testFullSellClosesLot() {
        let act = [
            buy("b1", qty: 10, price: 100),
            sell("s1", qty: 10, price: 120)
        ]
        let (lots, disposals) = LotEngine.computeLots(activities: act)
        XCTAssertTrue(lots[0].isClosed)
        XCTAssertEqual(lots[0].closeDate, day1)
        XCTAssertEqual(disposals[0].realizedPnL, 200, accuracy: 0.0001)
    }

    /// 多批次 FIFO：先买的先卖
    func testFIFOOrdering() {
        let act = [
            buy("b1", qty: 10, price: 100, date: day(1)),
            buy("b2", qty: 10, price: 200, date: day(2)),
            sell("s1", qty: 15, price: 150, date: day(3))
        ]
        let (lots, disposals) = LotEngine.computeLots(activities: act)
        // 第一个 lot 全卖（10），第二个卖 5
        XCTAssertTrue(lots[0].isClosed)
        XCTAssertEqual(lots[1].remainingQuantity, 5)
        XCTAssertEqual(disposals.count, 2)
        // 已实现盈亏 = (150-100)*10 + (150-200)*5 = 500 - 250 = 250
        let totalPnL = disposals.reduce(0) { $0 + $1.realizedPnL }
        XCTAssertEqual(totalPnL, 250, accuracy: 0.0001)
    }

    /// 卖出费用分摊：FIFO 扣减时按比例分摊到处置
    func testSellFeeAllocation() {
        let act = [
            buy("b1", qty: 10, price: 100),
            sell("s1", qty: 4, price: 120, fee: 10)
        ]
        let (_, disposals) = LotEngine.computeLots(activities: act)
        // 费用按卖出数量比例分摊：10 * (4/4) = 10（单批次全分摊）
        XCTAssertEqual(disposals[0].proceeds, 480 - 10, accuracy: 0.0001)
        XCTAssertEqual(disposals[0].realizedPnL, 480 - 10 - 400, accuracy: 0.0001)
    }

    /// 拆股：2:1 → effective 数量翻倍、成本不变、splitRatio=2
    func testSplit() {
        let act = [
            buy("b1", qty: 10, price: 100, date: day(1)),
            split("sp1", ratio: 2, date: day(2)),
            sell("s1", qty: 5, price: 60, date: day(3))
        ]
        let (lots, _) = LotEngine.computeLots(activities: act)
        let lot = lots[0]
        XCTAssertEqual(lot.splitRatio, 2)
        XCTAssertEqual(lot.effectiveQuantity, 15, accuracy: 0.0001)   // (10-2.5)*2 = 15
        XCTAssertEqual(lot.remainingQuantity, 7.5, accuracy: 0.0001)   // as-acquired 单位
        XCTAssertEqual(lot.remainingCostBasis, 750, accuracy: 0.0001)  // 1000 - 2.5*100
        XCTAssertEqual(lot.costPerUnit, 100, accuracy: 0.0001)          // 原始成本不变
    }

    /// 现金活动不产生 lot
    func testCashActivitiesDoNotCreateLots() {
        let act = [
            cash("d1", type: .deposit, amount: 1000),
            cash("w1", type: .withdrawal, amount: 200),
            cash("div1", type: .dividend, amount: 50, date: day(2))
        ]
        let (lots, disposals) = LotEngine.computeLots(activities: act)
        XCTAssertTrue(lots.isEmpty)
        XCTAssertTrue(disposals.isEmpty)
    }

    // MARK: - 持仓推导

    /// 简单持仓：数量/成本/均价
    func testPositions() {
        let act = [
            buy("b1", qty: 10, price: 100, fee: 10),
            buy("b2", asset: "TSLA", qty: 2, price: 200)
        ]
        let lots = LotEngine.computeLots(activities: act).lots
        let assets: [String: Asset] = ["AAPL": aapl, "TSLA": tsla]
        let positions = PositionCalculator.positions(from: lots, assets: assets)
        XCTAssertEqual(positions.count, 2)
        let aaplPos = positions.first { $0.asset.code == "AAPL" }!
        XCTAssertEqual(aaplPos.quantity, 10)
        XCTAssertEqual(aaplPos.costBasis, 1010, accuracy: 0.0001)
        XCTAssertEqual(aaplPos.avgCostPerUnit, 101, accuracy: 0.0001)
    }

    /// 有行情价时市值/浮盈正确
    func testPositionValuation() {
        let act = [buy("b1", qty: 10, price: 100)]
        let lots = LotEngine.computeLots(activities: act).lots
        let assets: [String: Asset] = ["AAPL": aapl]
        let positions = PositionCalculator.positions(from: lots, assets: assets,
                                                     prices: ["AAPL": 120])
        let pos = positions[0]
        XCTAssertEqual(pos.marketValue, 1200, accuracy: 0.0001)
        XCTAssertEqual(pos.unrealizedPnL, 200, accuracy: 0.0001)
        XCTAssertEqual(pos.unrealizedPnLPercent, 20, accuracy: 0.0001)
    }

    // MARK: - 估值

    /// 现金 + 持仓总估值
    func testValuation() {
        let act = [
            cash("d1", type: .deposit, amount: 2000),
            buy("b1", qty: 10, price: 100),
            cash("div1", type: .dividend, amount: 50, date: day(2))
        ]
        let lots = LotEngine.computeLots(activities: act).lots
        let assets: [String: Asset] = ["AAPL": aapl]
        let v = ValuationCalculator.valuation(accountID: accID, activities: act,
                                              lots: lots, assets: assets,
                                              prices: ["AAPL": 120])
        // 现金 = 2000 - 1000 + 50 = 1050；市值 = 1200；总 = 2250
        XCTAssertEqual(v.cashBalance, 1050, accuracy: 0.0001)
        XCTAssertEqual(v.marketValue, 1200, accuracy: 0.0001)
        XCTAssertEqual(v.totalValue, 2250, accuracy: 0.0001)
        XCTAssertEqual(v.netContribution, 2000, accuracy: 0.0001)
        XCTAssertEqual(v.costBasis, 1000, accuracy: 0.0001)
        XCTAssertEqual(v.unrealizedPnL, 200, accuracy: 0.0001)
    }

    // MARK: - 历史快照

    /// 每天有活动 → 生成快照序列，总盈亏按净投入算
    func testHistorySnapshots() {
        let act = [
            cash("d1", type: .deposit, amount: 1000, date: day(1)),
            buy("b1", qty: 10, price: 100, date: day(2)),
            cash("div1", type: .dividend, amount: 30, date: day(3))
        ]
        let assets: [String: Asset] = ["AAPL": aapl]
        let snaps = HistoryCalculator.snapshots(accountID: accID, activities: act,
                                                assets: assets, prices: ["AAPL": 110])
        XCTAssertEqual(snaps.count, 3)
        XCTAssertEqual(snaps[0].totalValue, 1000, accuracy: 0.0001)   // 仅存款
        XCTAssertEqual(snaps[1].totalValue, 1000 - 1000 + 10 * 110, accuracy: 0.0001) // 买入后
        XCTAssertEqual(snaps[2].totalGain, 130, accuracy: 0.0001)     // 总价值 1130 - 净投入 1000
    }

    // MARK: - 汇率

    func testFxConverter() {
        let rates = [ExchangeRate(from: "USD", to: "CNY", rate: 7.2)]
        XCTAssertEqual(FxConverter.rate(from: "USD", to: "CNY", rates: rates), 7.2)
        XCTAssertEqual(FxConverter.rate(from: "CNY", to: "USD", rates: rates), 1 / 7.2, accuracy: 0.0001)
        XCTAssertEqual(FxConverter.rate(from: "USD", to: "USD", rates: rates), 1)
        XCTAssertEqual(FxConverter.rate(from: "JPY", to: "CNY", rates: rates), 1)  // 缺失不换算
    }
}
