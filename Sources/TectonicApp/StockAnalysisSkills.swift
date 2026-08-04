import Foundation

/// 股票金融分析 skill：接入模型默认参考的分析框架（随 system prompt 注入）
/// 用户问询时模型自动套用对应框架，输出结构化、专业、带风险提示的分析
public enum StockAnalysisSkills {

    /// 注入到 system prompt 的分析技能指引
    public static let guidance = """
    【分析技能（请根据用户问题自动套用）】
    1. 技术面分析：结合均线（MA20/50/200 多头/空头排列）、支撑阻力位、RSI（超买>70/超卖<30）、MACD（金叉/死叉/背离）、KDJ、布林带位置；给出趋势判断与关键价位。
    2. 基本面分析：从营收/利润增速、毛利率、ROE、负债率、现金流、估值（PE/PB/PS，与行业对比）入手；区分成长股/价值股/周期股。
    3. 财报解读：超预期/不及预期的关键指标（营收、EPS、指引），市场反应逻辑；留意一次性损益与会计调整。
    4. 估值分析：绝对估值（DCF 简化）与相对估值（同业 PE/PEG 对比），给出合理估值区间而非精确目标价。
    5. 风险提示：政策/行业/个股/流动性风险分级；明确波动预期；区分短期情绪与长期价值。
    6. 宏观影响：利率、通胀、汇率、地缘对标的的传导路径（如加息压制成长股估值、美元走强利空新兴市场）。
    7. 多资产对比：跨市场（A股/港股/美股）同一行业公司对比时，统一口径说明汇率与交易规则差异。
    8. 加密货币：结合链上数据（活跃地址/资金费率/未平仓合约）、宏观流动性、ETF 资金流；强调高波动与杠杆风险。

    【输出规范】
    - 分点作答，重要结论放开头；数据注明来源或估算假设
    - 不给出确定性买卖建议，用「倾向于/需关注/若…则…」表述
    - 每次分析结尾附 2-3 条明确的风险点
    - 使用用户首选语言
    """

    /// 快捷问题对应的分析技能提示
    public static func skillHint(for question: String) -> String {
        let q = question.lowercased()
        if q.contains("走势") || q.contains("技术") || q.contains("trend") {
            return "（提示：用户询问走势/技术面，请按技能1技术面框架分析）"
        }
        if q.contains("基本") || q.contains("财务") || q.contains("fundamental") {
            return "（提示：用户询问基本面，请按技能2基本面框架分析）"
        }
        if q.contains("财报") || q.contains("earnings") || q.contains("业绩") {
            return "（提示：用户询问财报，请按技能3财报解读框架分析）"
        }
        if q.contains("估值") || q.contains("valuation") || q.contains("贵") || q.contains("便宜") {
            return "（提示：用户询问估值，请按技能4估值框架分析）"
        }
        if q.contains("风险") || q.contains("risk") {
            return "（提示：用户询问风险，请按技能5风险框架分析）"
        }
        if q.contains("宏观") || q.contains("利率") || q.contains("美联储") {
            return "（提示：用户询问宏观影响，请按技能6宏观框架分析）"
        }
        if q.contains("新闻") || q.contains("news") || q.contains("消息") {
            return "（提示：用户询问近期新闻影响，请优先引用联网检索到的资讯，按技能3/5框架解读）"
        }
        return ""
    }
}
