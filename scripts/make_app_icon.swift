import AppKit
import Foundation

// Tectonic 图标 v3 —— 白底黑线（用户选定）
// 白色背景 + 黑色简约上升折线 + 末端黑色圆点，极简苹果风格
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

// 2. 白色底（纯白，干净）
NSColor.white.setFill()
rect.fill()

// 3. 黑色上升折线（圆角端点，贯穿画面）
let trend = NSBezierPath()
trend.lineWidth = 72
trend.lineJoinStyle = .round
trend.lineCapStyle = .round
trend.move(to: NSPoint(x: 210, y: 330))
trend.line(to: NSPoint(x: 420, y: 470))
trend.line(to: NSPoint(x: 590, y: 430))
trend.line(to: NSPoint(x: 820, y: 640))
NSColor.black.setStroke()
trend.stroke()

// 4. 末端黑色圆点（简洁，无光晕）
let dotCenter = NSPoint(x: 820, y: 640)
let dot = NSBezierPath(ovalIn: CGRect(x: dotCenter.x - 70, y: dotCenter.y - 70, width: 140, height: 140))
NSColor.black.setFill()
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
