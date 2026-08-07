import Foundation

// MARK: - FIFO Lot 引擎

/// 税务批次引擎：按时间顺序重放活动，买入开 lot、卖出按 FIFO 关 lot、拆股调整数量。
/// 纯函数、无 I/O，可单测。对齐 Wealthfolio lots/lot_disposals 语义。
public enum LotEngine {

    /// 从活动列表推导出批次 + 处置明细。
    /// - Parameters:
    ///   - activities: 同一账户内、按日期升序排列的活动（引擎内部会再排序）
    /// - Returns: (所有批次, 所有处置)
    public static func computeLots(activities: [Activity]) -> (lots: [Lot], disposals: [LotDisposal]) {
        let sorted = activities
            .filter { $0.status == "POSTED" }
            .sorted { a, b in
                if a.date != b.date { return a.date < b.date }
                return a.id < b.id   // 同日期稳定排序
            }

        var lotsByAsset: [String: [Lot]] = [:]   // assetID -> 该资产 open lots（按开仓时间）
        var disposals: [LotDisposal] = []
        var allLots: [Lot] = []

        for activity in sorted {
            let assetID = activity.assetID ?? ""
            switch activity.type {
            case .buy:
                guard activity.quantity > 0, activity.unitPrice > 0 else { continue }
                let gross = activity.quantity * activity.unitPrice
                let totalCost = gross + activity.fee
                let costPerUnit = totalCost / activity.quantity
                var lot = Lot(accountID: activity.accountID, assetID: assetID,
                              openDate: activity.date, openActivityID: activity.id,
                              originalQuantity: activity.quantity,
                              costPerUnit: costPerUnit,
                              originalCostBasis: totalCost,
                              feeAllocated: activity.fee,
                              currency: activity.currency)
                lot.id = "lot-\(activity.id)"
                lotsByAsset[assetID, default: []].append(lot)
                allLots.append(lot)

            case .sell:
                guard activity.quantity > 0, activity.unitPrice > 0 else { continue }
                var remainingToSell = activity.quantity
                var openLots = lotsByAsset[assetID] ?? []
                var closedIndices: [Int] = []
                var updatedLots: [Lot] = []
                for (idx, var lot) in openLots.enumerated() where remainingToSell > 0 {
                    let effectiveRemaining = lot.effectiveQuantity
                    guard effectiveRemaining > 0 else { continue }
                    // 卖出数量是 effective（拆股后）单位 → 换算回 as-acquired 单位扣减
                    let disposedEffective = min(effectiveRemaining, remainingToSell)
                    let disposedAcquired = disposedEffective / lot.splitRatio
                    guard disposedAcquired > 0 else { continue }

                    // 成本：按 as-acquired 剩余成本基础比例分摊
                    let costPerRemaining = lot.remainingQuantity > 0 ? lot.remainingCostBasis / lot.remainingQuantity : 0
                    let disposedCost = costPerRemaining * disposedAcquired
                    // 卖出所得（净额：扣卖出费用按数量比例分摊）
                    let proceedsGross = disposedEffective * activity.unitPrice
                    let feeShare = activity.quantity > 0 ? activity.fee * (disposedEffective / activity.quantity) : activity.fee
                    let proceedsNet = proceedsGross - feeShare
                    let pnl = proceedsNet - disposedCost

                    var disposal = LotDisposal(lotID: lot.id, accountID: activity.accountID,
                                               assetID: assetID,
                                               disposalActivityID: activity.id,
                                               disposalDate: activity.date,
                                               quantity: disposedEffective,
                                               proceeds: proceedsNet,
                                               costBasis: disposedCost,
                                               realizedPnL: pnl,
                                               fee: feeShare,
                                               currency: activity.currency)
                    disposal.id = "disp-\(activity.id)-\(lot.id)"
                    disposals.append(disposal)

                    lot.remainingQuantity -= disposedAcquired
                    lot.remainingCostBasis -= disposedCost
                    remainingToSell -= disposedEffective

                    if lot.remainingQuantity <= 1e-9 {
                        lot.isClosed = true
                        lot.closeDate = activity.date
                        lot.closeActivityID = activity.id
                        lot.remainingQuantity = 0
                        lot.remainingCostBasis = 0
                        closedIndices.append(idx)
                    }
                    updatedLots.append(lot)
                }
                // 重新组装 open lots（保留未触碰的）
                for (idx, lot) in openLots.enumerated() where !closedIndices.contains(idx) && !updatedLots.contains(where: { $0.id == lot.id }) {
                    updatedLots.append(lot)
                }
                lotsByAsset[assetID] = updatedLots.sorted { $0.openDate < $1.openDate }
                // 同步 allLots 中对应 lot 状态
                let closedIDs = Set(disposals.filter { $0.disposalActivityID == activity.id }.map { $0.lotID })
                allLots = allLots.map { lot in
                    guard closedIDs.contains(lot.id) else { return lot }
                    if let updated = updatedLots.first(where: { $0.id == lot.id }) { return updated }
                    return lot
                }

            case .split:
                // 拆股：split_ratio 累计（remaining_quantity 保持 as-acquired 单位，成本不变）
                let ratio = activity.quantity > 0 ? activity.quantity : 1   // 2:1 拆股 quantity = 2
                guard ratio > 0, ratio != 1 else { continue }
                var openLots = lotsByAsset[assetID] ?? []
                var updated: [Lot] = []
                for var lot in openLots {
                    if lot.isClosed { updated.append(lot); continue }
                    lot.splitRatio *= ratio
                    updated.append(lot)
                }
                lotsByAsset[assetID] = updated
                allLots = allLots.map { lot in
                    guard lot.assetID == assetID, !lot.isClosed else { return lot }
                    if let updatedLot = updated.first(where: { $0.id == lot.id }) { return updatedLot }
                    return lot
                }

            default:
                // 分红/利息/存取款/转账/费用/税/调整 不产生 lot 变化
                break
            }
        }

        return (allLots, disposals)
    }
}

// MARK: - 持仓推导

/// 从批次聚合出每账户×资产的当前持仓。
public enum PositionCalculator {

    /// - Parameters:
    ///   - lots: 某账户的全部批次（含已关）
    ///   - assets: 资产目录（用于解析 assetID → Asset）
    ///   - prices: assetID → 最新价（缺失时用成本价）
    public static func positions(from lots: [Lot], assets: [String: Asset],
                                 prices: [String: Double] = [:]) -> [Position] {
        // 按 (accountID, assetID) 聚合 open lots
        var grouped: [String: (qty: Double, cost: Double)] = [:]
        for lot in lots where !lot.isClosed {
            let key = "\(lot.accountID)|\(lot.assetID)"
            var acc = grouped[key] ?? (0, 0)
            acc.qty += lot.effectiveQuantity
            acc.cost += lot.currentCostBasis
            grouped[key] = acc
        }
        return grouped.compactMap { key, acc in
            let parts = key.split(separator: "|")
            guard parts.count == 2 else { return nil }
            let accountID = String(parts[0])
            let assetID = String(parts[1])
            guard let asset = assets[assetID], acc.qty > 1e-9 else { return nil }
            let price = prices[assetID] ?? (acc.qty > 0 ? acc.cost / acc.qty : 0)
            let marketValue = acc.qty * price
            let pnl = marketValue - acc.cost
            let pct = acc.cost > 0 ? pnl / acc.cost * 100 : 0
            return Position(accountID: accountID, asset: asset,
                            quantity: acc.qty,
                            avgCostPerUnit: acc.qty > 0 ? acc.cost / acc.qty : 0,
                            costBasis: acc.cost,
                            marketPrice: price,
                            marketValue: marketValue,
                            unrealizedPnL: pnl,
                            unrealizedPnLPercent: pct)
        }
        .sorted { a, b in
            if a.asset.market != b.asset.market { return a.asset.market.rawValue < b.asset.market.rawValue }
            return a.asset.code < b.asset.code
        }
    }
}

// MARK: - 组合估值

/// 账户组合估值：现金 + 持仓市值，成本/净投入/盈亏。
public enum ValuationCalculator {

    /// 计算单账户估值。
    /// - Parameters:
    ///   - accountID: 账户
    ///   - activities: 该账户全部活动（POSTED）
    ///   - lots: 该账户全部批次
    ///   - assets: 资产目录
    ///   - prices: assetID → 最新价
    ///   - fx: 活动币种 → 账户币种的汇率换算（默认 1）
    public static func valuation(accountID: String,
                                 activities: [Activity],
                                 lots: [Lot],
                                 assets: [String: Asset],
                                 prices: [String: Double] = [:],
                                 fx: (String) -> Double = { _ in 1 }) -> PortfolioValuation {
        // 现金余额：净现金流累计（账户币种）
        var cash: Double = 0
        var netContribution: Double = 0
        var realizedPnL: Double = 0
        for a in activities where a.status == "POSTED" {
            cash += a.netCashFlow
            switch a.type {
            case .deposit, .transferIn:
                netContribution += abs(a.amount)
            case .withdrawal, .transferOut:
                netContribution -= abs(a.amount)
            default:
                break
            }
        }
        // 已实现盈亏（该账户处置合计）
        let disposals = LotEngine.computeLots(activities: activities).disposals
        realizedPnL = disposals.reduce(0) { $0 + $1.realizedPnL }

        let positions = PositionCalculator.positions(from: lots, assets: assets, prices: prices)
        let marketValue = positions.reduce(0) { $0 + $1.marketValue }
        let costBasis = positions.reduce(0) { $0 + $1.costBasis }
        let total = cash + marketValue
        let unrealized = marketValue - costBasis
        let pct = costBasis > 0 ? unrealized / costBasis * 100 : 0

        return PortfolioValuation(accountID: accountID,
                                  cashBalance: cash,
                                  marketValue: marketValue,
                                  totalValue: total,
                                  costBasis: costBasis,
                                  netContribution: netContribution,
                                  unrealizedPnL: unrealized,
                                  unrealizedPnLPercent: pct,
                                  realizedPnL: realizedPnL,
                                  positions: positions)
    }
}

// MARK: - 组合历史（每日估值）

/// 组合历史快照：对每个有活动的日期，用「截至当日」的活动重放生成估值点。
/// 持仓市值按最新价回溯（Tectonic 无历史行情库，用当前价近似历史仓位价值）。
public enum HistoryCalculator {

    /// 生成账户的历史快照序列（按日期升序）。
    /// - Parameters:
    ///   - activities: 该账户全部活动
    ///   - assets: 资产目录
    ///   - prices: assetID → 最新价（全部按当前价回溯）
    ///   - fx: 币种换算
    public static func snapshots(accountID: String,
                                 activities: [Activity],
                                 assets: [String: Asset],
                                 prices: [String: Double] = [:],
                                 fx: (String) -> Double = { _ in 1 }) -> [PortfolioSnapshot] {
        let posted = activities
            .filter { $0.status == "POSTED" }
            .sorted { a, b in
                if a.date != b.date { return a.date < b.date }
                return a.id < b.id
            }
        guard !posted.isEmpty else { return [] }

        // 去重日期
        let cal = Calendar.current
        var uniqueDates: [Date] = []
        for a in posted {
            let day = cal.startOfDay(for: a.date)
            if uniqueDates.last.map({ cal.startOfDay(for: $0) != day }) ?? true {
                uniqueDates.append(a.date)
            }
        }

        var snapshots: [PortfolioSnapshot] = []
        var prevTotal: Double? = nil
        var prevDate: Date? = nil
        var runningActivities: [Activity] = []

        for date in uniqueDates {
            let dayActivities = posted.filter { cal.startOfDay(for: $0.date) == cal.startOfDay(for: date) }
            runningActivities.append(contentsOf: dayActivities)

            let lots = LotEngine.computeLots(activities: runningActivities).lots
            let val = ValuationCalculator.valuation(accountID: accountID,
                                                    activities: runningActivities,
                                                    lots: lots,
                                                    assets: assets,
                                                    prices: prices,
                                                    fx: fx)
            let totalGain = val.totalValue - val.netContribution
            let totalGainPct = val.netContribution > 0 ? totalGain / val.netContribution * 100 : 0
            let dayGain: Double
            let dayGainPct: Double
            if let prev = prevTotal {
                dayGain = val.totalValue - prev
                dayGainPct = prev > 0 ? dayGain / prev * 100 : 0
            } else {
                dayGain = 0
                dayGainPct = 0
            }

            snapshots.append(PortfolioSnapshot(accountID: accountID,
                                               date: date,
                                               totalValue: val.totalValue,
                                               marketValue: val.marketValue,
                                               cashBalance: val.cashBalance,
                                               costBasis: val.costBasis,
                                               netContribution: val.netContribution,
                                               totalGain: totalGain,
                                               totalGainPercent: totalGainPct,
                                               dayGain: dayGain,
                                               dayGainPercent: dayGainPct))
            prevTotal = val.totalValue
            prevDate = date
        }
        return snapshots
    }
}

// MARK: - 汇率

/// 币种换算工具。汇率缺失时返回 1（不换算）。
public enum FxConverter {
    public static func rate(from: String, to: String, rates: [ExchangeRate]) -> Double {
        if from == to { return 1 }
        if let r = rates.first(where: { $0.from == from && $0.to == to }) { return r.rate }
        if let r = rates.first(where: { $0.from == to && $0.to == from }) { return 1 / r.rate }
        return 1
    }
}
