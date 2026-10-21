// Does a new picture repeat the framing of the picture before it? A free check on the Mac (no cloud call): it compares where the light and dark areas
// and the edges sit in the two pictures. It only ever WARNS; nothing is redrawn automatically.
import Foundation
import CoreGraphics

public enum FramingCheck {
    /// Pictures whose brightness layout is at least this alike AND whose edges line up at least this well are reported as "the same framing".
    /// (Measured: different pictures reach about 0.79 / 0.29; the same picture zoomed in 10 % reaches 0.87 / 0.60.)
    public static let lumaLimit = 0.70, edgeLimit = 0.35

    public static func score(_ a: CGImage, _ b: CGImage) -> (luma: Double, edge: Double) {
        let l = corr(grid(a, 16, 9), grid(b, 16, 9))
        let e = corr(edges(grid(a, 32, 18), 32, 18), edges(grid(b, 32, 18), 32, 18))
        return (l, e)
    }
    public static func tooSimilar(luma: Double, edge: Double) -> Bool { luma >= lumaLimit && edge >= edgeLimit }

    /// Average brightness of each cell of a w×h grid.
    static func grid(_ img: CGImage, _ w: Int, _ h: Int) -> [Double] {
        let bw = w * 4, bh = h * 4                                           // draw small first, then average the cells (steady results for any picture size)
        var px = [UInt8](repeating: 0, count: bw * bh)
        guard let ctx = CGContext(data: &px, width: bw, height: bh, bitsPerComponent: 8, bytesPerRow: bw, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [Double](repeating: 0, count: w * h) }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: bw, height: bh))
        var out = [Double](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            var s = 0.0
            for dy in 0..<4 { for dx in 0..<4 { s += Double(px[(y * 4 + dy) * bw + x * 4 + dx]) } }
            out[y * w + x] = s / 16
        } }
        return out
    }
    static func edges(_ g: [Double], _ w: Int, _ h: Int) -> [Double] {
        var out = [Double](repeating: 0, count: w * h)
        for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            let gx = g[y * w + x + 1] - g[y * w + x - 1], gy = g[(y + 1) * w + x] - g[(y - 1) * w + x]
            out[y * w + x] = (gx * gx + gy * gy).squareRoot()
        } }
        return out
    }
    static func corr(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in a.indices { let x = a[i] - ma, y = b[i] - mb; ab += x * y; aa += x * x; bb += y * y }
        let d = (aa * bb).squareRoot()
        return d > 0 ? ab / d : 0
    }
}
