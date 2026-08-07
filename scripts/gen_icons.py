#!/usr/bin/env python3
"""Generate TectonicIcon.swift v3: 自研 SVG path 解析器（含 arc 标准算法）→ 折线点序列。
不依赖 svgpathtools：tokenizer 处理紧凑格式，arc 用 F.6 端点参数化正确采样。
Swift 端只画 move/addLine —— 无运行时解析。
"""
import os, re, glob, math

SRC = "/tmp/lucide"
OUT = "/Users/zhousicheng/Documents/Obsidian Vault/项目/Tectonic/Sources/TectonicApp/TectonicIcon.swift"

SAMPLES_PER_UNIT = 3.0

# ---------- SVG path 解析器（自研） ----------

def tokenize(d: str):
    """返回 [(cmd, [nums])] 列表：命令字母 + 其参数
    数字按 SVG 规范一次匹配一个完整数字（禁止前导零 → 00 拆成 0,0；005.5 → 0,0,5.5）"""
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
                # SVG 压缩格式陷阱：'00' = 两个 0（large-arc=0, sweep=0）
                # 匹配串是纯整数、由多个 0 组成（如 00 / 000 / -00）→ 只取一个 0，剩余留给下轮
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
    """SVG arc 端点参数化 → 折线点（F.6 标准算法）"""
    if x1 == x2 and y1 == y2:
        return []
    if rx == 0 or ry == 0:
        return [(x1, y1), (x2, y2)]
    phi = math.radians(phi_deg % 360)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    # 半差
    dx2, dy2 = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cos_p * dx2 + sin_p * dy2
    y1p = -sin_p * dx2 + cos_p * dy2
    rx, ry = abs(rx), abs(ry)
    # 修正半径
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    # 中心
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
    # 起始/结束角
    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    theta1 = angle(1, 0, ux, uy)
    delta = angle(ux, uy, vx, vy)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi
    # 采样
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
    def __repr__(self): return f"({self.x:.2f},{self.y:.2f})"

def flatten_path(d: str) -> list:
    """SVG path → [[(x,y),...]] 折线（正确处理 arc）"""
    tokens = tokenize(d)
    polylines = []
    current = CGPoint(0, 0)
    start = CGPoint(0, 0)
    last_cmd = ""
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
        # 处理命令（含隐式重复：同命令多组参数）
        varImplicit = False  # M 后隐式 L
        while True:
            if cmd in "MmLl":
                x, y = num(), num()
                if x is None or y is None: break
                if cmd in "Mm":
                    # 真正 M/m：新建折线，处理后 continue（本组参数不当作 line）
                    if cmd == "M": current = CGPoint(x, y)
                    else: current = CGPoint(current.x + x, current.y + y)
                    start = CGPoint(current.x, current.y)
                    polylines.append([(current.x, current.y)])
                    cmd = "L" if cmd == "M" else "l"
                    if p >= len(params):
                        break
                    continue  # 同命令剩余参数按隐式 l/L 继续
                # L/l（含 M/m 隐式转换后的后续组）
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
            elif cmd in "Vv":
                y = num()
                if y is None: break
                ny = y if cmd == "V" else current.y + y
                polylines[-1].append((current.x, ny))
                current = CGPoint(current.x, ny)
            elif cmd in "Cc":
                x1, y1, x2, y2, x, y = [num() for _ in range(6)]
                if x is None: break
                c1 = CGPoint(x1 if cmd == "C" else current.x + x1, y1 if cmd == "C" else current.y + y1)
                c2 = CGPoint(x2 if cmd == "C" else current.x + x2, y2 if cmd == "C" else current.y + y2)
                nx = x if cmd == "C" else current.x + x
                ny = y if cmd == "C" else current.y + y
                # 贝塞尔采样
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
            elif cmd in "Ss":
                x2, y2, x, y = [num() for _ in range(4)]
                if x is None: break
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
            elif cmd in "Qq":
                x1, y1, x, y = [num() for _ in range(4)]
                if x is None: break
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
            elif cmd in "Tt":
                x, y = num(), num()
                if x is None: break
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
            elif cmd in "Aa":
                rx, ry, rot, laf, sf, x, y = [num() for _ in range(7)]
                if x is None or y is None: break
                x1, y1 = current.x, current.y
                nx = x if cmd == "A" else current.x + x
                ny = y if cmd == "A" else current.y + y
                pts = arc_to_points(x1, y1, rx, ry, rot, int(laf), int(sf), nx, ny,
                                    n=int(12*SAMPLES_PER_UNIT))
                if pts:
                    polylines[-1].extend(pts[1:])
                    current = CGPoint(nx, ny)
            elif cmd in "Zz":
                if polylines and len(polylines[-1]) > 1:
                    polylines[-1].append(polylines[-1][0])
                current = CGPoint(start.x, start.y)
                # 闭合后新路径
                if i < len(tokens) and tokens[i][0] in "MmLl":
                    pass  # 下一个 M 会新建
            else:
                break
            # 隐式重复：同命令还有剩余参数
            if p >= len(params):
                break
            if cmd in "MmLlHhVvCcSsQqTtAaZz" and p < len(params):
                continue
            break
    # 去掉闭合重复点
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

# ---------- 生成 ----------
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

lines = []
lines.append("import SwiftUI")
lines.append("")
lines.append("// MARK: - Tectonic 图标系统（Lucide 开源线性图标，ISC License）")
lines.append("// 矢量自绘：SVG path 已在生成时展平为折线点序列（arc 标准算法采样），Swift 端只画 move/addLine")
lines.append("")
lines.append("/// 图标枚举（case 名与业务代码一致）")
lines.append("enum TectonicIcon: String, CaseIterable {")
for name in sorted(icons.keys()):
    lines.append(f"    case {name}")
lines.append("}")
lines.append("")
lines.append("/// 图标视图：折线 stroke 渲染（round cap/join），尺寸/颜色可调")
lines.append("struct TectonicIconView: View {")
lines.append("    let icon: TectonicIcon")
lines.append("    var size: CGFloat = 16")
lines.append("    var color: Color = .primary")
lines.append("    var strokeWidth: CGFloat = 2")
lines.append("")
lines.append("    var body: some View {")
lines.append("        IconPolyline(paths: icon.polylines)")
lines.append("            .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))")
lines.append("            .frame(width: size, height: size)")
lines.append("            .accessibilityHidden(true)")
lines.append("    }")
lines.append("}")
lines.append("")
lines.append("/// 折线 Shape：24x24 viewBox 内，缩放到目标尺寸")
lines.append("struct IconPolyline: Shape {")
lines.append("    let paths: [[CGPoint]]")
lines.append("")
lines.append("    func path(in rect: CGRect) -> Path {")
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
lines.append("    /// 每个图标的折线点序列（24x24 viewBox，已展平）")
lines.append("    var polylines: [[CGPoint]] {")
lines.append("        switch self {")
for name in sorted(icons.keys()):
    polys_str = []
    for poly in icons[name]:
        pts_str = ", ".join(f"CGPoint(x: {x:.2f}, y: {y:.2f})" for x, y in poly)
        polys_str.append(f"[{pts_str}]")
    lines.append(f"        case .{name}:")
    lines.append(f"            [{', '.join(polys_str)}]")
lines.append("        }")
lines.append("    }")
lines.append("}")
lines.append("")

open(OUT, 'w').write("\n".join(lines))
total_pts = sum(len(pts) for pls in icons.values() for pts in pls)
print(f"generated {OUT}: {len(icons)} icons, {total_pts} points")
