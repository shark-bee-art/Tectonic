# Tectonic — 财经金融 Mac 应用

苹果原生风格的财经信息整合 + AI 分析助手。8 市场行情（美股/加密/港股/A股/基金/日股/韩股/台股）、K线图表、自选管理、资讯流（AI 自动打标）、持仓导入、AI 问答（阅读页内嵌对话）。

## 技术栈

- Swift 6.3.3 + SwiftUI（macOS 26 原生）+ GRDB（SQLite）
- 分层：CoreKit（模型/数据源/存储/AI 网关）+ tectonic-cli（端到端验证）+ TectonicApp（UI）
- 数据源全部免费：腾讯行情（6 市场）、TWSE 官方（台股）、CoinGecko/Binance（加密）、天天基金（基金）
- AI 网关多供应商：本地 Ollama + 云端（OpenAI/DeepSeek/Kimi/通义/智谱…），API Key 仅本地存储

## 构建

```bash
swift build
swift test
.build/arm64-apple-macosx/debug/tectonic-cli quote us:AAPL
```

## 目录

```
Sources/
  CoreKit/          数据模型、数据源适配器、GRDB 存储、AI 网关（无 UI）
    DataSources/    腾讯 / TWSE / Yahoo / CoinGecko / Binance / 天天基金
  tectonic-cli/     命令行工具
  TectonicApp/      macOS SwiftUI App
Tests/CoreKitTests/ 单元测试
Notes/              验收笔记（不入库）
```
