import Foundation
import CoreGraphics
import CoreText
import ImageIO
import AppKit
import CoreImage

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: bitmapInfo)!
    c.interpolationQuality = .high; c.setAllowsAntialiasing(true); c.setShouldSmoothFonts(false)
    return c
}

@inline(__always) func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
@inline(__always) func smooth(_ x: Double) -> Double { let t = clamp01(x); return t * t * t * (t * (t * 6 - 15) + 10) }
@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

/// Small deterministic RNG so every render of the same plan looks identical.
struct SeededRNG: RandomNumberGenerator {
    var s: UInt64
    init(_ seed: UInt64) { s = seed == 0 ? 0x1234567 : seed }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
}

/// Loads an image downsampled so its longest side ≤ maxPixel, honouring EXIF orientation.
func loadImage(_ url: URL, maxPixel: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    // Decode at full size (orientation applied), then downscale big pictures or Lanczos-upscale small ones.
    guard let full = CGImageSourceCreateThumbnailAtIndex(src, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 8192, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
    var out = full
    let longest = max(full.width, full.height)
    if longest < maxPixel {
        // Small AI pictures (≈1.4k px) zoomed by Ken Burns look soft with plain bilinear scaling; Lanczos + a touch of sharpening keeps edges crisp.
        let scale = Double(maxPixel) / Double(longest)
        let ci = CIImage(cgImage: full)
        let up = ci.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
        let sharp = up.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 2.0, kCIInputIntensityKey: 0.5])
        if let r = ciContext.createCGImage(sharp, from: sharp.extent.integral) { out = r }
    } else if longest > maxPixel {
        let s = Double(maxPixel) / Double(longest)
        let w = Int(Double(full.width) * s), h = Int(Double(full.height) * s)
        let c = makeContext(w, h); c.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h)); out = c.makeImage() ?? full
    }
    // Canonical BGRA so per-frame draws never need a colour/format conversion.
    let ctx = makeContext(out.width, out.height)
    ctx.draw(out, in: CGRect(x: 0, y: 0, width: out.width, height: out.height))
    return ctx.makeImage()
}
let ciContext = CIContext(options: [.useSoftwareRenderer: false])

/// Gray masks for `CGContext.clip(to:mask:)`: white = painted (opaque), black = clipped out.
enum Masks {
    static let rampSolid = 4096, rampLen = 256, rampTotal = 8192
    /// Horizontal: revealed (alpha 1) on the left, soft falloff of `rampLen` px, hidden on the right.
    static let linear: CGImage = {
        let w = rampTotal, h = 8
        var px = [UInt8](repeating: 0, count: w * h)
        for x in 0..<w {
            let a: Double = x < rampSolid ? 1 : (x >= rampSolid + rampLen ? 0 : 1 - Double(x - rampSolid) / Double(rampLen))
            let v = UInt8(Int((a * 255).rounded()))
            for y in 0..<h { px[y * w + x] = v }
        }
        return gray(px, w, h)
    }()
    /// Radial: centre revealed, soft edge between 0.82 and 1.0 of the radius.
    static let radial: CGImage = {
        let n = 512
        var px = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let dx = (Double(x) + 0.5) / Double(n) * 2 - 1, dy = (Double(y) + 0.5) / Double(n) * 2 - 1
            let r = (dx * dx + dy * dy).squareRoot()
            let a = r <= 0.82 ? 1.0 : (r >= 1 ? 0 : 1 - (r - 0.82) / 0.18)
            px[y * n + x] = UInt8(Int((a * 255).rounded()))
        } }
        return gray(px, n, n)
    }()
    static func gray(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage {
        let p = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: p, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}

/// Renders attributed text to an image with a soft drop shadow baked in (for titles).
func renderTextImage(_ attr: NSAttributedString, maxWidth: CGFloat, pad: CGFloat, shadow: Bool, shadowBlur: CGFloat) -> CGImage {
    let fs = CTFramesetterCreateWithAttributedString(attr)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
    let w = Int(ceil(size.width + pad * 2)), h = Int(ceil(size.height + pad * 2))
    let ctx = makeContext(w, h)
    let path = CGPath(rect: CGRect(x: pad, y: pad, width: size.width + 1, height: size.height + 1), transform: nil)
    let frame = CTFramesetterCreateFrame(fs, CFRange(), path, nil)
    if shadow {
        ctx.saveGState()
        ctx.translateBy(x: -20000, y: 0)
        ctx.setShadow(offset: CGSize(width: 20000, height: -shadowBlur * 0.35), blur: shadowBlur, color: CGColor(gray: 0, alpha: 0.8))
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }
    CTFrameDraw(frame, ctx)
    return ctx.makeImage()!
}

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
func serifFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

/// A picture that is decoded on first use and can be released again — keeps a long render's memory flat on small Macs.
final class ImageBox: @unchecked Sendable {
    let url: URL?, maxPixel: Int
    private var img: CGImage?, loaded = false
    private let lock = NSLock()
    init(url: URL?, maxPixel: Int) { self.url = url; self.maxPixel = maxPixel }
    func get() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if !loaded { img = url.flatMap { loadImage($0, maxPixel: maxPixel) }; loaded = true }
        return img
    }
    func unload() { lock.lock(); img = nil; loaded = false; lock.unlock() }
}
