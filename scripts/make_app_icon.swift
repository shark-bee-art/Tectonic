import AppKit
import Foundation

// 无 Xcode 环境生成 .app 图标：AppKit 绘制 PNG → iconset → iconutil 转 icns
// 用法: swift make_app_icon.swift   → 输出 /tmp/tectonic-icon.png + /tmp/Tectonic.icns
// 打包时: cp /tmp/Tectonic.icns <App>.app/Contents/Resources/Tectonic.icns
// Info.plist 加 <key>CFBundleIconFile</key><string>Tectonic</string>（不含扩展名）
//
// Tectonic 主题：地质构造（板块断层）+ K线蜡烛 + 上升趋势线

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no context")
}

// 1. 圆角路径裁剪（macOS 图标风格）
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
path.addClip()

// 2. 渐变底（午夜蓝 → 深青，金融科技感）
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.30, alpha: 1.0),
    NSColor(calibratedRed: 0.02, green: 0.30, blue: 0.36, alpha: 1.0),
])!
gradient.draw(in: rect, angle: -60)

// 3. 地质断层（两道斜切板块线，半透明白）
func drawFault(xFrom: CGFloat, xTo: CGFloat, yAt: CGFloat, thickness: CGFloat) {
    let p = NSBezierPath()
    p.lineWidth = thickness
    p.lineJoinStyle = .round
    p.lineCapStyle = .round
    p.move(to: NSPoint(x: xFrom, y: yAt))
    p.line(to: NSPoint(x: xTo, y: yAt))
    NSColor.white.withAlphaComponent(0.10).setStroke()
    p.stroke()
}
drawFault(xFrom: -80, xTo: 1100, yAt: 260, thickness: 26)
drawFault(xFrom: -80, xTo: 1100, yAt: 300, thickness: 26)
drawFault(xFrom: -80, xTo: 1100, yAt: 820, thickness: 26)

// 4. K线蜡烛（3 根：跌/涨/涨）
func drawCandle(cx: CGFloat, top: CGFloat, bottom: CGFloat, open: CGFloat, close: CGFloat, wickTop: CGFloat, wickBottom: CGFloat, isUp: Bool) {
    let color = isUp
        ? NSColor(calibratedRed: 0.35, green: 0.88, blue: 0.55, alpha: 1.0)   // 涨：绿
        : NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.35, alpha: 1.0)   // 跌：红
    // 影线
    let wick = NSBezierPath()
    wick.lineWidth = 22
    wick.lineCapStyle = .round
    wick.move(to: NSPoint(x: cx, y: wickTop))
    wick.line(to: NSPoint(x: cx, y: wickBottom))
    color.setStroke()
    wick.stroke()
    // 实体
    let body = NSBezierPath(roundedRect: CGRect(x: cx - 68, y: min(open, close), width: 136, height: max(abs(open - close), 60)),
                            xRadius: 18, yRadius: 18)
    color.setFill()
    body.fill()
}

// 三根蜡烛（x 中心：310 / 512 / 714）
drawCandle(cx: 310, top: 250, bottom: 600, open: 470, close: 350, wickTop: 230, wickBottom: 620, isUp: false)
drawCandle(cx: 512, top: 330, bottom: 680, open: 390, close: 540, wickTop: 310, wickBottom: 700, isUp: true)
drawCandle(cx: 714, top: 460, bottom: 810, open: 560, close: 720, wickTop: 440, wickBottom: 830, isUp: true)

// 5. 上升趋势线（白色粗线，贯穿蜡烛高点）
let trend = NSBezierPath()
trend.lineWidth = 34
trend.lineJoinStyle = .round
trend.lineCapStyle = .round
trend.move(to: NSPoint(x: 150, y: 300))
trend.line(to: NSPoint(x: 430, y: 470))
trend.line(to: NSPoint(x: 640, y: 620))
trend.line(to: NSPoint(x: 890, y: 800))
NSColor.white.withAlphaComponent(0.92).setStroke()
trend.stroke()

// 趋势线端点箭头
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 830, y: 745))
arrow.line(to: NSPoint(x: 920, y: 830))
arrow.line(to: NSPoint(x: 880, y: 840))
arrow.line(to: NSPoint(x: 890, y: 800))
arrow.line(to: NSPoint(x: 845, y: 790))
arrow.close()
NSColor.white.withAlphaComponent(0.92).setFill()
arrow.fill()

image.unlockFocus()

// 6. 导出 PNG
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("export failed")
}
let pngPath = "/tmp/tectonic-icon.png"
try! png.write(to: URL(fileURLWithPath: pngPath))
print("PNG:", pngPath)

// 7. iconset
let iconsetPath = "/tmp/Tectonic.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let base = NSBitmapImageRep(data: tiff)!
func writeIcon(_ size: Int, name: String) {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    resized.unlockFocus()
    guard let t = resized.tiffRepresentation, let r = NSBitmapImageRep(data: t),
          let d = r.representation(using: .png, properties: [:]) else { return }
    try! d.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}
for s in [16, 32, 64, 128, 256, 512] {
    writeIcon(s, name: "icon_\(s)x\(s)")
    if s * 2 <= 1024 {
        writeIcon(s * 2, name: "icon_\(s)x\(s)@2x")
    }
}
try! png.write(to: URL(fileURLWithPath: "\(iconsetPath)/icon_512x512@2x.png"))

// 8. icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", "/tmp/Tectonic.icns"]
try! process.run()
process.waitUntilExit()
print("ICNS: /tmp/Tectonic.icns (exit \(process.terminationStatus))")
