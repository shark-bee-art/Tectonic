import Foundation

/// 恐惧贪婪指数（alternative.me 免费无 Key，market-pulse MCP 同源）。
/// 接口: https://api.alternative.me/fng/?limit=1
/// 响应: {"data":[{"value":"27","value_classification":"Fear","timestamp":"1785888000"}]}
/// 指数约 8 小时更新一次，调用方应做缓存（Store 层 1 小时）。
public struct FearGreedIndex: Sendable, Equatable {
    public let value: Int
    public let classification: String
    public let timestamp: Date

    public init(value: Int, classification: String, timestamp: Date) {
        self.value = value
        self.classification = classification
        self.timestamp = timestamp
    }

    /// 中文分级（0-24 极端恐惧 / 25-44 恐惧 / 45-54 中性 / 55-74 贪婪 / 75-100 极端贪婪）
    public var level: String {
        switch value {
        case 0...24: return "极端恐惧"
        case 25...44: return "恐惧"
        case 45...54: return "中性"
        case 55...74: return "贪婪"
        default: return "极端贪婪"
        }
    }
}

public enum FearGreedSource {
    public static func fetch() async throws -> FearGreedIndex {
        let urlStr = "https://api.alternative.me/fng/?limit=1"
        guard let url = URL(string: urlStr) else {
            throw DataSourceError.invalidURL(urlStr)
        }
        let data = try await HTTP.get(url, timeout: 10)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]],
              let first = list.first,
              let valueStr = first["value"] as? String,
              let value = Int(valueStr),
              let classification = first["value_classification"] as? String else {
            throw DataSourceError.parseFailed("恐惧贪婪指数解析失败")
        }
        let ts = Double(first["timestamp"] as? String ?? "0") ?? 0
        return FearGreedIndex(
            value: value,
            classification: classification,
            timestamp: Date(timeIntervalSince1970: ts)
        )
    }
}
