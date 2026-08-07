#!/usr/bin/env python3
"""Generate BrandIcon.swift: simple-icons 品牌 logo → base64(Float32) fill 渲染
映射：Symbol code → (brand slug, 品牌色 hex)
无 logo 的标的（MSFT/AMZN/指数等）不生成——由代码块 + 品牌色兜底。
"""
import os, re, glob, math, struct, base64, json

SRC = "/tmp/simple-icons-develop/icons"
OUT = "/Users/zhousicheng/Documents/Obsidian Vault/项目/Tectonic/Sources/TectonicIcons/BrandIcon.swift"

# ---------- SVG path 解析（复用 lucide gen 的 flatten_svg，fill 模式无需采样曲线太多点） ----------

def tokenize(d: str):
    num_re = re.compile(r'[+-]?(?:0(?:\.\d*)?|[1-9]\d*(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
    tokens = []
    i = 0
    n = len(d)
    while i < n:
        c = d[i]
        if c in "MmLlHhVvCcSsQqTtAaZz":
            params = []
            i += 1
            while i < n:
                while i < n and d[i] in " ,\t\n\r":
                    i += 1
                if i >= n:
                    break
                if d[i] in "MmLlHhVvCcSsQqTtAaZz":
                    break
                m = num_re.match(d, i)
                if not m:
                    i += 1
                    continue
                matched = m.group(0)
                if re.fullmatch(r'[+-]?0{2,}', matched):
                    sign = matched[0] if matched[0] in "+-" else ""
                    params.append(float(sign + "0"))
                    i = m.start() + len(sign) + 1
                else:
                    params.append(float(matched))
                    i = m.end()
            tokens.append((c, params))
        else:
            i += 1
    return tokens

def arc_to_points(x1, y1, rx, ry, phi_deg, large_arc, sweep, x2, y2, n=24):
    if x1 == x2 and y1 == y2:
        return []
    if rx == 0 or ry == 0:
        return [(x1, y1), (x2, y2)]
    phi = math.radians(phi_deg % 360)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx2, dy2 = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos_p * dx2 + sin_p * dy2
    y1p = -sin_p * dx2 + cos_p * dy2
    rx, ry = abs(rx), abs(ry)
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(num / den, 0)) if den != 0 else 0
    if large_arc == sweep:
        coef = -coef
    cxp = coef * (rx * y1p / ry)
    cyp = coef * (-ry * x1p / rx)
    cx = cos_p * cxp - sin_p * cyp + (x1 + x2) / 2
    cy = sin_p * cxp + cos_p * cyp + (y1 + y2) / 2
    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        length = math.sqrt(ux*ux + uy*uy) * math.sqrt(vx*vx + vy*vy)
        if length == 0:
            return 0
        ang = math.acos(max(-1, min(1, dot / length)))
        if ux * vy - uy * vx < 0:
            ang = -ang
        return ang
    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    theta1 = angle(1, 0, ux, uy)
    delta = angle(ux, uy, vx, vy)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi
    pts = []
    steps = max(int(abs(delta) / (2 * math.pi) * n * 8), 8)
    for i in range(steps + 1):
        t = theta1 + delta * i / steps
        ex = rx * math.cos(t)
        ey = ry * math.sin(t)
        px = cos_p * ex - sin_p * ey + cx
        py = sin_p * ex + cos_p * ey + cy
        pts.append((px, py))
    return pts

class CGPoint:
    def __init__(self, x, y): self.x, self.y = float(x), float(y)

def flatten_path(d: str) -> list:
    tokens = tokenize(d)
    polylines = []
    current = CGPoint(0, 0)
    start = CGPoint(0, 0)
    last_control = None
    i = 0
    while i < len(tokens):
        cmd, params = tokens[i]
        i += 1
        p = 0
        def num():
            nonlocal p
            if p < len(params):
                v = params[p]; p += 1
                return v
            return None
        while True:
            if cmd in "MmLl":
                x, y = num(), num()
                if x is None or y is None: break
                if cmd in "Mm":
                    if cmd == "M": current = CGPoint(x, y)
                    else: current = CGPoint(current.x + x, current.y + y)
                    start = CGPoint(current.x, current.y)
                    polylines.append([(current.x, current.y)])
                    cmd = "L" if cmd == "M" else "l"
                    if p >= len(params):
                        break
                    continue
                nx = x if cmd == "L" else current.x + x
                ny = y if cmd == "L" else current.y + y
                polylines[-1].append((nx, ny))
                current = CGPoint(nx, ny)
                if p >= len(params):
                    break
                continue
            elif cmd in "Hh":
                x = num()
                if x is None: break
                nx = x if cmd == "H" else current.x + x
                polylines[-1].append((nx, current.y))
                current = CGPoint(nx, current.y)
                if p >= len(params): break
                continue
            elif cmd in "Vv":
                y = num()
                if y is None: break
                ny = y if cmd == "V" else current.y + y
                polylines[-1].append((current.x, ny))
                current = CGPoint(current.x, ny)
                if p >= len(params): break
                continue
            elif cmd in "Cc":
                vals = [num() for _ in range(6)]
                if vals[0] is None: break
                x1, y1, x2, y2, x, y = vals
                c1 = CGPoint(x1 if cmd == "C" else current.x + x1, y1 if cmd == "C" else current.y + y1)
                c2 = CGPoint(x2 if cmd == "C" else current.x + x2, y2 if cmd == "C" else current.y + y2)
                nx = x if cmd == "C" else current.x + x
                ny = y if cmd == "C" else current.y + y
                pts = []
                for t in range(0, 41):
                    tt = t / 40
                    mt = 1 - tt
                    px = mt**3 * current.x + 3*mt**2*tt*c1.x + 3*mt*tt**2*c2.x + tt**3*nx
                    py = mt**3 * current.y + 3*mt**2*tt*c1.y + 3*mt*tt**2*c2.y + tt**3*ny
                    pts.append((px, py))
                polylines[-1].extend(pts[1:])
                last_control = c2
                current = CGPoint(nx, ny)
                if p >= len(params): break
                continue
            elif cmd in "Ss":
                vals = [num() for _ in range(4)]
                if vals[0] is None: break
                x2, y2, x, y = vals
                c1 = last_control if last_control else CGPoint(current.x, current.y)
                if cmd == "s":
                    c1 = CGPoint(2*current.x - c1.x, 2*current.y - c1.y)
                c2 = CGPoint(x2 if cmd == "S" else current.x + x2, y2 if cmd == "S" else current.y + y2)
                nx = x if cmd == "S" else current.x + x
                ny = y if cmd == "S" else current.y + y
                pts = []
                for t in range(0, 41):
                    tt = t / 40
                    mt = 1 - tt
                    px = mt**3 * current.x + 3*mt**2*tt*c1.x + 3*mt*tt**2*c2.x + tt**3*nx
                    py = mt**3 * current.y + 3*mt**2*tt*c1.y + 3*mt*tt**2*c2.y + tt**3*ny
                    pts.append((px, py))
                polylines[-1].extend(pts[1:])
                last_control = c2
                current = CGPoint(nx, ny)
                if p >= len(params): break
                continue
            elif cmd in "Qq":
                vals = [num() for _ in range(4)]
                if vals[0] is None: break
                x1, y1, x, y = vals
                c1 = CGPoint(x1 if cmd == "Q" else current.x + x1, y1 if cmd == "Q" else current.y + y1)
                nx = x if cmd == "Q" else current.x + x
                ny = y if cmd == "Q" else current.y + y
                pts = []
                for t in range(0, 31):
                    tt = t / 30
                    mt = 1 - tt
                    px = mt**2 * current.x + 2*mt*tt*c1.x + tt**2*nx
                    py = mt**2 * current.y + 2*mt*tt*c1.y + tt**2*ny
                    pts.append((px, py))
                polylines[-1].extend(pts[1:])
                last_control = c1
                current = CGPoint(nx, ny)
                if p >= len(params): break
                continue
            elif cmd in "Tt":
                vals = [num() for _ in range(2)]
                if vals[0] is None: break
                x, y = vals
                c1 = last_control if last_control else CGPoint(current.x, current.y)
                c1 = CGPoint(2*current.x - c1.x, 2*current.y - c1.y)
                nx = x if cmd == "T" else current.x + x
                ny = y if cmd == "T" else current.y + y
                pts = []
                for t in range(0, 31):
                    tt = t / 30
                    mt = 1 - tt
                    px = mt**2 * current.x + 2*mt*tt*c1.x + tt**2*nx
                    py = mt**2 * current.y + 2*mt*tt*c1.y + tt**2*ny
                    pts.append((px, py))
                polylines[-1].extend(pts[1:])
                last_control = c1
                current = CGPoint(nx, ny)
                if p >= len(params): break
                continue
            elif cmd in "Aa":
                vals = [num() for _ in range(7)]
                if vals[0] is None or vals[5] is None or vals[6] is None: break
                rx, ry, rot, laf, sf, x, y = vals
                x1, y1 = current.x, current.y
                nx = x if cmd == "A" else current.x + x
                ny = y if cmd == "A" else current.y + y
                pts = arc_to_points(x1, y1, rx, ry, rot, int(laf), int(sf), nx, ny, n=24)
                if pts:
                    polylines[-1].extend(pts[1:])
                    current = CGPoint(nx, ny)
                if p >= len(params): break
                continue
            elif cmd in "Zz":
                if polylines and len(polylines[-1]) > 1:
                    polylines[-1].append(polylines[-1][0])
                current = CGPoint(start.x, start.y)
                break
            else:
                break
            if p >= len(params):
                break
    result = []
    for poly in polylines:
        if len(poly) >= 2 and abs(poly[0][0]-poly[-1][0]) < 0.01 and abs(poly[0][1]-poly[-1][1]) < 0.01:
            poly = poly[:-1]
        result.append(poly)
    return result

def flatten_svg(svg: str) -> list:
    all_pl = []
    for m in re.finditer(r'<path[^>]*\bd="([^"]*)"', svg):
        all_pl.extend(flatten_path(m.group(1)))
    return all_pl

def encode_icon(polylines: list) -> str:
    flat = []
    for poly in polylines:
        for x, y in poly:
            flat.append(x)
            flat.append(y)
        flat.append(-1.0)
    buf = struct.pack(f'<{len(flat)}f', *flat)
    return base64.b64encode(buf).decode()

# ---------- 品牌映射（Symbol code → simple-icons slug + 品牌色） ----------

BRANDS = {
    # 美股
    "AAPL":   ("apple",    "#A2AAAD"),   # Apple 灰
    "NVDA":   ("nvidia",   "#76B900"),   # NVIDIA 绿
    "GOOGL":  ("google",   "#4285F4"),   # Google 蓝
    "META":   ("meta",     "#0866FF"),   # Meta 蓝
    "TSLA":   ("tesla",    "#CC0000"),   # Tesla 红
    "NFLX":   ("netflix",  "#E50914"),   # Netflix 红（预留）
    # 加密
    "BTCUSDT":("bitcoin",  "#F7931A"),   # Bitcoin 橙
    "ETHUSDT":("ethereum", "#627EEA"),   # Ethereum 蓝
    # 日股
    "7203":   ("toyota",   "#EB0A1E"),   # Toyota 红
    # 韩股
    "005930": ("samsung",  "#1428A0"),   # Samsung 蓝
}

# 无 logo 标的 → 品牌色块 + 代码文字（ticker 方块）
FALLBACK_COLORS = {
    "MSFT":   "#00A4EF",   # Microsoft 蓝
    "AMZN":   "#FF9900",   # Amazon 橙
    "00700":  "#07C160",   # 腾讯绿
    "2330":   "#005B96",   # TSMC 蓝
    "QQQ":    "#0066B3",   # Invesco 蓝
    "VOO":    "#006400",   # Vanguard 绿
    "HSI":    "#C8102E",   # 恒生红
    "N225":   "#B02A30",   # 日经红
    "TWII":   "#003B5C",   # 台股蓝
    "sh000001": "#D32F2F",
    "sh000300": "#1976D2",
    "sh000688": "#7B1FA2",
    "sh510300": "#388E3C",
    "110022": "#F57C00",
    "AAPL2": None,  # 占位
}

# ---------- 生成 ----------

icons = {}
missing = []
for code, (slug, hex_color) in BRANDS.items():
    path = os.path.join(SRC, f"{slug}.svg")
    if not os.path.exists(path):
        missing.append((code, slug))
        continue
    pls = flatten_svg(open(path).read())
    if not pls:
        missing.append((code, slug))
        continue
    icons[code] = (slug, hex_color, encode_icon(pls))

print(f"品牌图标生成: {len(icons)}/{len(BRANDS)}")
if missing:
    print(f"缺失: {missing}")

lines = []
lines.append("import SwiftUI")
lines.append("")
lines.append("// MARK: - 品牌图标（simple-icons 开源品牌标志，CC0）")
lines.append("// 数据格式：SVG path 生成时展平 → Float32 扁平数组 → base64（fill 渲染）")
lines.append("")
lines.append("/// 标的代码 → 品牌信息（slug 显示名 + 品牌色 + base64 数据）")
lines.append("public enum BrandIcon {")
lines.append("")
lines.append("    /// 有品牌 logo 的标的代码集合")
lines.append("    public static let available: Set<String> = [")
for code in sorted(icons.keys()):
    lines.append(f"        \"{code}\",")
lines.append("    ]")
lines.append("")
lines.append("    /// 品牌色（十六进制）——有 logo 或无 logo 兜底块都用")
lines.append("    public static func brandColor(_ code: String) -> String? {")
lines.append("        switch code {")
for code, (slug, hex_color, _b64) in icons.items():
    lines.append(f"        case \"{code}\": \"{hex_color}\"")
for code, hex_color in FALLBACK_COLORS.items():
    if hex_color:
        lines.append(f"        case \"{code}\": \"{hex_color}\"")
lines.append("        default: nil")
lines.append("        }")
lines.append("    }")
lines.append("")
lines.append("    /// base64(Float32 扁平数组) 品牌 logo 数据；nil = 无 logo（用代码方块兜底）")
lines.append("    public static func data(_ code: String) -> String? {")
lines.append("        switch code {")
for code in sorted(icons.keys()):
    lines.append(f"        case \"{code}\": \"{icons[code][2]}\"")
lines.append("        default: nil")
lines.append("        }")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append("/// 品牌 logo 渲染（fill 模式）")
lines.append("public struct BrandLogoView: View {")
lines.append("    public let code: String")
lines.append("    public var size: CGFloat = 28")
lines.append("")
lines.append("    public init(code: String, size: CGFloat = 28) {")
lines.append("        self.code = code")
lines.append("        self.size = size")
lines.append("    }")
lines.append("")
lines.append("    public var body: some View {")
lines.append("        Group {")
lines.append("            if let b64 = BrandIcon.data(code),")
lines.append("               let paths = Self.decode(b64) {")
lines.append("                // 品牌 logo（fill 黑色，白色方块底）")
lines.append("                ZStack {")
lines.append("                    RoundedRectangle(cornerRadius: size * 0.24)")
lines.append("                        .fill(.white)")
lines.append("                        .overlay(")
lines.append("                            RoundedRectangle(cornerRadius: size * 0.24)")
lines.append("                                .stroke(Color.black.opacity(0.08), lineWidth: 1)")
lines.append("                        )")
lines.append("                    BrandPath(paths: paths)")
lines.append("                        .fill(Color.black)")
lines.append("                        .frame(width: size * 0.72, height: size * 0.72)")
lines.append("                }")
lines.append("                .frame(width: size, height: size)")
lines.append("            } else {")
lines.append("                // 兜底：品牌色方块 + 代码缩写")
lines.append("                RoundedRectangle(cornerRadius: size * 0.24)")
lines.append("                    .fill(Color(hex: BrandIcon.brandColor(code) ?? \"#666666\"))")
lines.append("                    .frame(width: size, height: size)")
lines.append("                    .overlay(")
lines.append("                        Text(Self.abbr(code))")
lines.append("                            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))")
lines.append("                            .foregroundStyle(.white)")
lines.append("                    )")
lines.append("            }")
lines.append("        }")
lines.append("        .frame(width: size, height: size)")
lines.append("    }")
lines.append("")
lines.append("    /// 代码缩写（最多 2-3 字符）")
lines.append("    static func abbr(_ code: String) -> String {")
lines.append("        let letters = code.filter { $0.isLetter && $0.isASCII }")
lines.append("        if letters.count >= 3 { return String(letters.prefix(3)).uppercased() }")
lines.append("        if letters.count >= 2 { return String(letters.prefix(2)).uppercased() }")
lines.append("        return String(code.prefix(3)).uppercased()")
lines.append("    }")
lines.append("")
lines.append("    /// base64 → [[CGPoint]]")
lines.append("    static func decode(_ b64: String) -> [[CGPoint]]? {")
lines.append("        guard let raw = Data(base64Encoded: b64) else { return nil }")
lines.append("        var floats: [Float] = []")
lines.append("        floats.reserveCapacity(raw.count / 4)")
lines.append("        raw.withUnsafeBytes { buf in")
lines.append("            for i in stride(from: 0, to: buf.count, by: 4) {")
lines.append("                floats.append(buf.loadUnaligned(fromByteOffset: i, as: Float.self))")
lines.append("            }")
lines.append("        }")
lines.append("        var paths: [[CGPoint]] = []")
lines.append("        var cur: [CGPoint] = []")
lines.append("        var pendingX: Float? = nil")
lines.append("        for v in floats {")
lines.append("            if v < 0 {")
lines.append("                if !cur.isEmpty { paths.append(cur); cur = [] }")
lines.append("                pendingX = nil")
lines.append("            } else if let px = pendingX {")
lines.append("                cur.append(CGPoint(x: CGFloat(px), y: CGFloat(v)))")
lines.append("                pendingX = nil")
lines.append("            } else {")
lines.append("                pendingX = v")
lines.append("            }")
lines.append("        }")
lines.append("        if !cur.isEmpty { paths.append(cur) }")
lines.append("        return paths.isEmpty ? nil : paths")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append("/// 品牌 path（fill）")
lines.append("public struct BrandPath: Shape {")
lines.append("    public let paths: [[CGPoint]]")
lines.append("    public init(paths: [[CGPoint]]) { self.paths = paths }")
lines.append("    public func path(in rect: CGRect) -> Path {")
lines.append("        var p = Path()")
lines.append("        let scale = min(rect.width / 24.0, rect.height / 24.0)")
lines.append("        let ox = rect.midX - 12 * scale")
lines.append("        let oy = rect.midY - 12 * scale")
lines.append("        for poly in paths {")
lines.append("            guard let first = poly.first else { continue }")
lines.append("            p.move(to: CGPoint(x: first.x * scale + ox, y: first.y * scale + oy))")
lines.append("            for pt in poly.dropFirst() {")
lines.append("                p.addLine(to: CGPoint(x: pt.x * scale + ox, y: pt.y * scale + oy))")
lines.append("            }")
lines.append("            p.closeSubpath()")
lines.append("        }")
lines.append("        return p")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append("extension Color {")
lines.append("    /// hex 字符串 → Color")
lines.append("    public init(hex: String) {")
lines.append("        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)")
lines.append("        var v: UInt64 = 0")
lines.append("        Scanner(string: h).scanHexInt64(&v)")
lines.append("        let r, g, b: Double")
lines.append("        switch h.count {")
lines.append("        case 6: r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255")
lines.append("        case 8: r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255; b = Double((v >> 8) & 0xFF) / 255")
lines.append("        default: r = 0.5; g = 0.5; b = 0.5")
lines.append("        }")
lines.append("        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)")
lines.append("    }")
lines.append("}")
lines.append("")

open(OUT, "w").write("\n".join(lines))
print(f"generated {OUT}")
