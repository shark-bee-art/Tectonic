import XCTest
@testable import CoreKit

/// SEC EDGAR 基本面数据源解析测试（不依赖网络，用小样本 JSON 模拟 companyfacts 结构）
final class EDGARTests: XCTestCase {

    // MARK: ticker 归一化

    func testNormalizeTicker() {
        XCTAssertEqual(EDGARSource.normalizeTicker("BRK.B"), "BRK-B")
        XCTAssertEqual(EDGARSource.normalizeTicker("aapl"), "AAPL")
        XCTAssertEqual(EDGARSource.normalizeTicker(" brk.b "), "BRK-B")
        XCTAssertEqual(EDGARSource.normalizeTicker("MSFT"), "MSFT")
    }

    // MARK: duration / instant 解析

    /// 构造 companyfacts 结构的小样本：Revenue（年度+季度）、Assets（instant）
    private func makeFactsJSON() -> [String: Any] {
        [
            "facts": [
                "us-gaap": [
                    // duration：年度（363 天）+ 季度（90 天）
                    "RevenueFromContractWithCustomerExcludingAssessedTax": [
                        "units": [
                            "USD": [
                                ["start": "2023-10-01", "end": "2024-09-28", "val": 380_000_000_000.0],
                                ["start": "2024-09-29", "end": "2025-09-27", "val": 416_000_000_000.0],
                                ["start": "2025-01-01", "end": "2025-04-01", "val": 90_000_000_000.0],
                            ]
                        ]
                    ],
                    "NetIncomeLoss": [
                        "units": [
                            "USD": [
                                ["start": "2024-09-29", "end": "2025-09-27", "val": 112_000_000_000.0],
                            ]
                        ]
                    ],
                    "EarningsPerShareBasic": [
                        "units": [
                            "USD/shares": [
                                ["start": "2024-09-29", "end": "2025-09-27", "val": 7.49],
                            ]
                        ]
                    ],
                    // instant：只有 end
                    "Assets": [
                        "units": [
                            "USD": [
                                ["end": "2025-06-28", "val": 360_000_000_000.0],
                                ["end": "2025-09-27", "val": 359_000_000_000.0],
                                ["end": "2026-06-27", "val": 383_000_000_000.0],
                            ]
                        ]
                    ],
                    "Liabilities": [
                        "units": [
                            "USD": [
                                ["end": "2026-06-27", "val": 275_000_000_000.0],
                            ]
                        ]
                    ],
                    "StockholdersEquity": [
                        "units": [
                            "USD": [
                                ["end": "2026-06-27", "val": 108_000_000_000.0],
                            ]
                        ]
                    ],
                    "CommonStockSharesOutstanding": [
                        "units": [
                            "shares": [
                                ["end": "2026-06-27", "val": 14_600_000_000.0],
                            ]
                        ]
                    ],
                ]
            ]
        ]
    }

    func testParseAnnualAndInstant() throws {
        let symbol = Symbol(market: .us, code: "AAPL", name: "Apple Inc.")
        let fd = try EDGARSource.parse(makeFactsJSON(), symbol: symbol)

        // duration：取最近财年（2025-09-27），忽略季度
        XCTAssertEqual(fd.revenue, 416_000_000_000.0)
        XCTAssertEqual(fd.revenueYear, "2025-09-27")
        XCTAssertEqual(fd.netIncome, 112_000_000_000.0)
        XCTAssertEqual(fd.eps, 7.49)

        // instant：取最新报告期
        XCTAssertEqual(fd.assets, 383_000_000_000.0)
        XCTAssertEqual(fd.balanceDate, "2026-06-27")
        XCTAssertEqual(fd.liabilities, 275_000_000_000.0)
        XCTAssertEqual(fd.equity, 108_000_000_000.0)
        XCTAssertEqual(fd.sharesOutstanding, 14_600_000_000.0)
    }

    // MARK: 派生指标

    func testDerivedMetrics() {
        let symbol = Symbol(market: .us, code: "AAPL", name: "Apple Inc.")
        let fd = FundamentalData(
            symbol: symbol,
            revenue: 416_000_000_000, netIncome: 112_000_000_000,
            operatingIncome: 133_000_000_000, grossProfit: 195_000_000_000,
            eps: 7.49, revenueYear: "2025-09-27",
            assets: 383_000_000_000, liabilities: 275_000_000_000,
            equity: 108_000_000_000, sharesOutstanding: 14_600_000_000,
            balanceDate: "2026-06-27"
        )
        // ROE = 净利 / 权益
        XCTAssertEqual(fd.roe ?? 0, 112_000_000_000.0 / 108_000_000_000.0 * 100, accuracy: 0.01)
        // 资产负债率
        XCTAssertEqual(fd.debtRatio ?? 0, 275_000_000_000.0 / 383_000_000_000.0 * 100, accuracy: 0.01)
        // PE = 价 / EPS
        XCTAssertEqual(fd.pe(price: 230) ?? 0, 230.0 / 7.49, accuracy: 0.01)
        XCTAssertNil(fd.pe(price: 0))   // 无效价格
        XCTAssertNil(fd.pe(price: -5))
        // PB = 价×流通股 / 权益
        let expectedPB = 230.0 * 14_600_000_000.0 / 108_000_000_000.0
        XCTAssertEqual(fd.pb(price: 230) ?? 0, expectedPB, accuracy: 0.01)
        XCTAssertNil(fd.pb(price: 0))
    }

    /// 空数据（无匹配）时各字段为 nil，不抛错
    func testParseEmptyFacts() throws {
        let symbol = Symbol(market: .us, code: "ZZZZ", name: "None")
        let empty: [String: Any] = ["facts": ["us-gaap": [:]]]
        let fd = try EDGARSource.parse(empty, symbol: symbol)
        XCTAssertNil(fd.revenue)
        XCTAssertNil(fd.assets)
        XCTAssertNil(fd.roe)
    }
}
