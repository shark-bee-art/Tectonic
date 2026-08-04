import AppKit
import Foundation

// Tectonic 图标 v2 —— 苹果原生风格：深空灰渐变底 + 白色简约上升折线 + 末端红色涨点
// 参考 Apple Stocks 图标的气质：深底、单色线条、克制的渐变、无花哨元素
// 用法: swift make_app_icon.swift → /tmp/Tectonic.icns

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no context")
}

// 1. 圆角裁剪（macOS 标准图标圆角 ~220/1024）
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
path.addClip()

// 2. 深空灰渐变底（苹果股市同款气质：近黑 → 深灰蓝）
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1.0),   // 近黑
    NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.19, alpha: 1.0),   // 深灰蓝
])!
gradient.draw(in: rect, angle: -70)

// 3. 一条干净利落的上升折线（白色，圆角端点，贯穿画面对角线）
let trend = NSBezierPath()
trend.lineWidth = 64
trend.lineJoinStyle = .round
trend.lineCapStyle = .round
trend.move(to: NSPoint(x: 210, y: 330))
trend.line(to: NSPoint(x: 420, y: 470))
trend.line(to: NSPoint(x: 590, y: 430))
trend.line(to: NSPoint(x: 820, y: 640))
NSColor.white.withAlphaComponent(0.96).setStroke()
trend.stroke()

// 4. 末端红色圆点（涨），带一点光晕感
let dotCenter = NSPoint(x: 820, y: 640)
// 光晕
let glow = NSBezierPath(ovalIn: CGRect(x: dotCenter.x - 130, y: dotCenter.y - 130, width: 260, height: 260))
NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.18).setFill()
glow.fill()
// 实心点
let dot = NSBezierPath(ovalIn: CGRect(x: dotCenter.x - 62, y: dotCenter.y - 62, width: 124, height: 124))
NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.30, alpha: 1.0).setFill()
dot.fill()

image.unlockFocus()

// 5. 导出 PNG
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("export failed")
}
let pngPath = "/tmp/tectonic-icon.png"
try! png.write(to: URL(fileURLWithPath: pngPath))
print("PNG:", pngPath)

// 6. iconset
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

// 7. icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", "/tmp/Tectonic.icns"]
try! process.run()
process.waitUntilExit()
print("ICNS: /tmp/Tectonic.icns (exit \(process.terminationStatus))")
