// swift-tools-version: 6.0
//
//  Tectonic — 财经金融 Mac 应用（信息整合 + AI 分析）
//
//  Target 划分：
//  - CoreKit       : 数据模型、数据源适配器、SQLite 存储(GRDB)、AI 网关 —— 无 UI
//  - CoreKitTests  : 单元测试
//  - tectonic-cli  : 命令行工具
//  - TectonicApp   : macOS SwiftUI App

import PackageDescription

let package = Package(
    name: "Tectonic",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
        .executable(name: "tectonic-cli", targets: ["tectonic-cli"]),
        .executable(name: "TectonicApp", targets: ["TectonicApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
    ],
    targets: [
        .target(
            name: "CoreKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/CoreKit"
        ),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"],
            path: "Tests/CoreKitTests"
        ),
        .executableTarget(
            name: "tectonic-cli",
            dependencies: ["CoreKit"],
            path: "Sources/tectonic-cli"
        ),
        .target(
            name: "TectonicIcons",
            path: "Sources/TectonicIcons"
        ),
        .executableTarget(
            name: "TectonicApp",
            dependencies: ["CoreKit", "TectonicIcons"],
            path: "Sources/TectonicApp",
            resources: [
                .process("Resources/Fonts")
            ]
        )
    ]
)
