import AppKit
// Draws the app icon: a gradient squircle with a film strip and a music note. Usage: swift make_icon.swift <out.iconset>
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func png(_ px: Int, _ name: String) {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let sq = NSBezierPath(roundedRect: r, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGraphicsContext.current!.cgContext.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    NSGradient(colors: [NSColor(red: 0.42, green: 0.25, blue: 0.95, alpha: 1), NSColor(red: 0.95, green: 0.25, blue: 0.55, alpha: 1), NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)])!.draw(in: sq, angle: -55)
    NSGraphicsContext.current!.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
    // film strip
    NSColor.white.withAlphaComponent(0.20).setFill()
    let strip = NSBezierPath(roundedRect: NSRect(x: s * 0.16, y: s * 0.30, width: s * 0.68, height: s * 0.40), xRadius: s * 0.04, yRadius: s * 0.04); strip.fill()
    NSColor.white.withAlphaComponent(0.85).setFill()
    for i in 0..<6 { for y in [s * 0.325, s * 0.645] { NSBezierPath(roundedRect: NSRect(x: s * (0.19 + 0.105 * CGFloat(i)), y: y, width: s * 0.055, height: s * 0.03), xRadius: s * 0.008, yRadius: s * 0.008).fill() } }
    // music note
    NSColor.white.setFill()
    let c = NSGraphicsContext.current!.cgContext
    c.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.3))
    NSBezierPath(ovalIn: NSRect(x: s * 0.36, y: s * 0.38, width: s * 0.15, height: s * 0.115)).fill()
    NSBezierPath(rect: NSRect(x: s * 0.485, y: s * 0.44, width: s * 0.022, height: s * 0.20)).fill()
    let flag = NSBezierPath(); flag.move(to: NSPoint(x: s * 0.505, y: s * 0.64)); flag.curve(to: NSPoint(x: s * 0.60, y: s * 0.52), controlPoint1: NSPoint(x: s * 0.55, y: s * 0.63), controlPoint2: NSPoint(x: s * 0.60, y: s * 0.59))
    flag.line(to: NSPoint(x: s * 0.58, y: s * 0.50)); flag.curve(to: NSPoint(x: s * 0.505, y: s * 0.585), controlPoint1: NSPoint(x: s * 0.575, y: s * 0.55), controlPoint2: NSPoint(x: s * 0.54, y: s * 0.57)); flag.close(); flag.fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
for (px, n) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] { png(px, n) }
