#!/usr/bin/env python3
"""Generate TectonicIcon.swift v4: 图标数据 base64 编码（Float32 扁平数组），运行时解码。
解决 35K 点字面量导致的 Swift 编译 6-13 分钟问题 → 编译秒级。
"""
import os, re, glob, math, struct, base64

SRC = "/tmp/lucide"
OUT = "/Users/zhousicheng/Documents/Obsidian Vault/项目/Tectonic/Sources/TectonicIcons/TectonicIcon.swift"

SAMPLES_PER_UNIT = 3.0

# ---------- SVG path 解析器（自研，同 v3，已验证正确） ----------

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
                for t in range(0, int(10*SAMPLES_PER_UNIT)+1):
                    tt = t / (10*SAMPLES_PER_UNIT)
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
                for t in range(0, int(10*SAMPLES_PER_UNIT)+1):
                    tt = t / (10*SAMPLES_PER_UNIT)
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
                for t in range(0, int(10*SAMPLES_PER_UNIT)+1):
                    tt = t / (10*SAMPLES_PER_UNIT)
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
                for t in range(0, int(10*SAMPLES_PER_UNIT)+1):
                    tt = t / (10*SAMPLES_PER_UNIT)
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
                pts = arc_to_points(x1, y1, rx, ry, rot, int(laf), int(sf), nx, ny,
                                    n=int(12*SAMPLES_PER_UNIT))
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
    for m in re.finditer(r'<circle[^>]*>', svg):
        tag = m.group(0)
        def a(name):
            am = re.search(name + r'="([^"]*)"', tag)
            return float(am.group(1)) if am else 0.0
        cx, cy, r = a("cx"), a("cy"), a("r")
        pts = []
        for i in range(48):
            ang = 2 * math.pi * i / 48
            pts.append((cx + r*math.cos(ang), cy + r*math.sin(ang)))
        all_pl.append(pts)
    for m in re.finditer(r'<line\b[^>]*>', svg):
        tag = m.group(0)
        def la(name):
            lm = re.search(name + r'="([^"]*)"', tag)
            return float(lm.group(1)) if lm else 0.0
        all_pl.append([(la("x1"), la("y1")), (la("x2"), la("y2"))])
    for m in re.finditer(r'<rect\b[^>]*>', svg):
        tag = m.group(0)
        def ra(name):
            rm = re.search(name + r'="([^"]*)"', tag)
            return float(rm.group(1)) if rm else 0.0
        x, y, w, h, r = ra("x"), ra("y"), ra("width"), ra("height"), ra("rx")
        r = min(r, w/2, h/2)
        if r <= 0:
            all_pl.append([(x, y), (x+w, y), (x+w, y+h), (x, y+h)])
        else:
            pts = []
            def ap(cx, cy, s, e, rr, n=10):
                return [(cx + rr*math.cos(s+(e-s)*i/n), cy + rr*math.sin(s+(e-s)*i/n)) for i in range(n+1)]
            pts.append((x+r, y)); pts.append((x+w-r, y))
            pts += ap(x+w-r, y+r, -math.pi/2, 0, r)
            pts.append((x+w, y+h-r))
            pts += ap(x+w-r, y+h-r, 0, math.pi/2, r)
            pts.append((x+r, y+h))
            pts += ap(x+r, y+h-r, math.pi/2, math.pi, r)
            pts.append((x, y+r))
            pts += ap(x+r, y+r, math.pi, 3*math.pi/2, r)
            all_pl.append(pts)
    return all_pl

# ---------- 编码：每个图标 → base64 Float32 扁平数组 ----------
# 格式: [n_polylines, n0, x,y,x,y..., n1, x,y..., ...]
# 用 -1 分隔折线更简单: [x,y,x,y,...,-1,x,y,...,-1] 每折线以 -1 结束
def encode_icon(polylines: list) -> str:
    flat = []
    for poly in polylines:
        for x, y in poly:
            flat.append(x)
            flat.append(y)
        flat.append(-1.0)  # 折线分隔符（坐标恒 >=0，-1 安全）
    # Float32 打包
    buf = struct.pack(f'<{len(flat)}f', *flat)
    return base64.b64encode(buf).decode()

icons = {}
for f in sorted(glob.glob(f"{SRC}/*.svg")):
    name = os.path.basename(f)[:-4]
    svg = open(f).read()
    pls = flatten_svg(svg)
    if not pls:
        print(f"WARN empty: {name}")
        continue
    icons[name] = pls

print(f"icons flattened: {len(icons)}")

# 生成 Swift（base64 字符串，编译秒级）
lines = []
lines.append("import SwiftUI")
lines.append("")
lines.append("// MARK: - Tectonic 图标系统（Lucide 开源线性图标，ISC License）")
lines.append("// 数据格式：SVG path 生成时展平（arc 标准算法）→ Float32 扁平数组 → base64 字符串")
lines.append("// 运行时解码（秒级），编译期零海量常量 → 编译快")
lines.append("")
lines.append("public enum TectonicIcon: String, CaseIterable, Sendable {")
for name in sorted(icons.keys()):
    lines.append(f"    case {name}")
lines.append("}")
lines.append("")
lines.append("public struct TectonicIconView: View {")
lines.append("    public let icon: TectonicIcon")
lines.append("    public var size: CGFloat = 16")
lines.append("    public var color: Color = .primary")
lines.append("    public var strokeWidth: CGFloat = 2")
lines.append("")
lines.append("    public init(icon: TectonicIcon, size: CGFloat = 16, color: Color = .primary, strokeWidth: CGFloat = 2) {")
lines.append("        self.icon = icon")
lines.append("        self.size = size")
lines.append("        self.color = color")
lines.append("        self.strokeWidth = strokeWidth")
lines.append("    }")
lines.append("")
lines.append("    public var body: some View {")
lines.append("        IconPolyline(paths: icon.polylines)")
lines.append("            .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))")
lines.append("            .frame(width: size, height: size)")
lines.append("            .accessibilityHidden(true)")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append("public struct IconPolyline: Shape {")
lines.append("    public let paths: [[CGPoint]]")
lines.append("")
lines.append("    public init(paths: [[CGPoint]]) { self.paths = paths }")
lines.append("")
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
lines.append("        }")
lines.append("        return p")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append("extension TectonicIcon {")
lines.append("    /// base64(Float32 扁平数组)；每折线以 -1 分隔")
lines.append("    private var data: String {")
lines.append("        switch self {")
for name in sorted(icons.keys()):
    lines.append(f"        case .{name}: \"{encode_icon(icons[name])}\"")
lines.append("        }")
lines.append("    }")
lines.append("")
lines.append("    /// 解码为折线点序列（Float32 扁平数组，每折线以 -1 分隔）")
lines.append("    public var polylines: [[CGPoint]] {")
lines.append("        guard let raw = Data(base64Encoded: data) else { return [] }")
lines.append("        var floats: [Float] = []")
lines.append("        floats.reserveCapacity(raw.count / 4)")
lines.append("        raw.withUnsafeBytes { buf in")
lines.append("            for i in stride(from: 0, to: buf.count, by: 4) {")
lines.append("                let v = buf.loadUnaligned(fromByteOffset: i, as: Float.self)")
lines.append("                floats.append(v)")
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
lines.append("        return paths")
lines.append("    }")
lines.append("}")
lines.append("")

open(OUT, 'w').write("\n".join(lines))
print(f"generated {OUT}: {len(icons)} icons (base64)")
