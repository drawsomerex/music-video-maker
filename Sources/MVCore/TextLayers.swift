// Title card and karaoke lyric rendering.
import Foundation
import CoreGraphics
import CoreText
import AppKit

/// Pre-rendered karaoke lyrics. Each lyric line is wrapped into ≤2–3 rows; every row is two bitmaps
/// (shadow+dim text, bright text) so per-frame work is just two image draws and a soft clip.
final class LyricLayer {
    struct Row {
        var base: CGImage; var bright: CGImage
        var w: Double, h: Double, advance: Double
        var textX: Double                 // x of first glyph inside bitmap
        var keys: [(t: Double, x: Double)] // time → x (bitmap px) of the sweep
    }
    struct Visual { var rows: [Row]; var show: Double; var hide: Double; var start: Double; var end: Double }
    var visuals: [Visual] = []
    var bottom: Double? = nil           // caption block bottom (fraction of frame height); nil = default
    let W: Int, H: Int
    let unit: Double, vertical: Bool
    let scrim: CGGradient

    init(lines: [LyricLine], W: Int, H: Int, timeOffset: Double, vertical: Bool = false, window: ClosedRange<Double>? = nil) {
        self.W = W; self.H = H; self.vertical = vertical; self.unit = Double(min(W, H))
        scrim = CGGradient(colorsSpace: sRGB, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.5), CGColor(gray: 0, alpha: 0.78)] as CFArray, locations: [0, 0.55, 1])!
        let maxW = CGFloat(W) * (vertical ? 0.76 : 0.80)        // Shorts: inside YouTube's safe area (its buttons cover the sides)
        let live = lines.enumerated().filter { !$0.element.words.isEmpty }.map { $0.element }
            .filter { l in window.map { l.end + timeOffset > $0.lowerBound + 0.02 && l.start + timeOffset < $0.upperBound - 0.02 } ?? true }
        // Hand-off timing: roomy gaps fade in 0.45 s early / out 0.6 s late; tight gaps switch cleanly (out, then in) with no overlap.
        var shows = live.map { $0.start + timeOffset - 0.45 }
        var hides = live.map { $0.end + timeOffset + 0.6 }
        for i in 1..<max(1, live.count) {
            let gap = live[i].start - live[i - 1].end
            if gap < 1.05 {
                let m = live[i - 1].end + timeOffset + gap * 0.8
                hides[i - 1] = m; shows[i] = m
            }
        }
        for (i, l) in live.enumerated() {
            var size = CGFloat(unit) * (vertical ? 0.080 : 0.064)
            var rows = LyricLayer.buildRows(l, size: size, maxWidth: maxW, H: Int(unit), offset: timeOffset)
            if rows.count > (vertical ? 3 : 2) { size = CGFloat(unit) * (vertical ? 0.064 : 0.052); rows = LyricLayer.buildRows(l, size: size, maxWidth: maxW, H: Int(unit), offset: timeOffset) }
            // a single word longer than the width cannot wrap: make the line smaller until every row fits
            while size > CGFloat(unit) * 0.036, rows.contains(where: { $0.w - 2 * $0.textX > Double(maxW) * 1.02 }) {
                size *= 0.9; rows = LyricLayer.buildRows(l, size: size, maxWidth: maxW, H: Int(unit), offset: timeOffset)
            }
            visuals.append(Visual(rows: rows, show: shows[i], hide: hides[i], start: l.start + timeOffset, end: l.end + timeOffset))
        }
    }

    static func buildRows(_ l: LyricLine, size: CGFloat, maxWidth: CGFloat, H: Int, offset: Double) -> [Row] {
        let font = roundedFont(size: size, weight: .bold)
        let text = l.text
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white, .kern: size * 0.005])
        let ts = CTTypesetterCreateWithAttributedString(attr)
        var rows: [Row] = []
        var idx = 0
        let ns = text as NSString
        // word char ranges (advance past whitespace and anchor at word start so short words never match inside earlier words)
        var wordRanges: [NSRange] = []; var cursor = 0
        for w in l.words {
            while cursor < ns.length, let sc = UnicodeScalar(ns.character(at: cursor)), CharacterSet.whitespacesAndNewlines.contains(sc) { cursor += 1 }
            let rem = NSRange(location: cursor, length: max(0, ns.length - cursor))
            let anchored = ns.range(of: w.text, options: [.anchored], range: rem)
            let r = anchored.location != NSNotFound ? anchored : ns.range(of: w.text, options: [], range: rem)
            wordRanges.append(r)
            if r.location != NSNotFound { cursor = r.location + r.length }
        }
        let pad = CGFloat(H) * 0.05
        // Balance two-row lines: shrink the wrap width until a 2-row line splits roughly evenly.
        var wrapWidth = maxWidth
        let fullW = CGFloat(CTLineGetTypographicBounds(CTTypesetterCreateLine(ts, CFRange(location: 0, length: ns.length)), nil, nil, nil))
        if fullW > maxWidth && fullW < maxWidth * 2 * 0.92 { wrapWidth = min(maxWidth, fullW / 2 * 1.12) }
        while idx < ns.length {
            var len = CTTypesetterSuggestLineBreak(ts, idx, Double(wrapWidth))
            if len < 1 { len = 1 }
            let line = CTTypesetterCreateLine(ts, CFRange(location: idx, length: len))
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            let tw = CTLineGetTypographicBounds(line, &asc, &desc, &lead) - CTLineGetTrailingWhitespaceWidth(line)
            let bw = Int(ceil(tw + pad * 2)), bh = Int(ceil(asc + desc + pad * 2))
            func render(white: CGFloat, shadow: Bool) -> CGImage {
                let ctx = makeContext(bw, bh)
                if shadow {
                    ctx.saveGState(); ctx.translateBy(x: -30000, y: 0)
                    ctx.setShadow(offset: CGSize(width: 30000, height: -size * 0.06), blur: size * 0.28, color: CGColor(gray: 0, alpha: 0.9))
                    ctx.textPosition = CGPoint(x: pad, y: pad + desc); CTLineDraw(line, ctx)
                    ctx.restoreGState()
                    // second tighter shadow for crisp edges
                    ctx.saveGState(); ctx.translateBy(x: -30000, y: 0)
                    ctx.setShadow(offset: CGSize(width: 30000, height: -size * 0.025), blur: size * 0.08, color: CGColor(gray: 0, alpha: 0.7))
                    ctx.textPosition = CGPoint(x: pad, y: pad + desc); CTLineDraw(line, ctx)
                    ctx.restoreGState()
                }
                ctx.setFillColor(CGColor(gray: 1, alpha: white))
                ctx.textPosition = CGPoint(x: pad, y: pad + desc); CTLineDraw(line, ctx)
                return ctx.makeImage()!
            }
            let base = render(white: 0.58, shadow: true), bright = render(white: 1, shadow: false)
            // keypoints
            var keys: [(Double, Double)] = []
            for (k, r) in wordRanges.enumerated() where r.location != NSNotFound && r.location >= idx && r.location < idx + len {
                let xs = CTLineGetOffsetForStringIndex(line, r.location, nil)
                let xe = CTLineGetOffsetForStringIndex(line, min(r.location + r.length, idx + len), nil)
                keys.append((l.words[k].start + offset, Double(pad + xs))); keys.append((l.words[k].end + offset, Double(pad + xe)))
            }
            rows.append(Row(base: base, bright: bright, w: Double(bw), h: Double(bh), advance: Double((asc + desc) * 1.12), textX: Double(pad), keys: keys))
            idx += len
        }
        return rows
    }

    private func sweepX(_ r: Row, t: Double) -> Double {
        guard let f = r.keys.first, let l = r.keys.last else { return 0 }
        if t <= f.t { return f.x - 0.5 * 0 - 2 }
        if t >= l.t { return r.w }
        for i in 1..<r.keys.count where t <= r.keys[i].t {
            let a = r.keys[i - 1], b = r.keys[i]
            return b.t > a.t ? lerp(a.x, b.x, (t - a.t) / (b.t - a.t)) : b.x
        }
        return r.w
    }

    /// Returns the lyric visibility 0…1 (used to modulate the scrim) after drawing.
    @discardableResult
    func draw(t: Double, ctx: CGContext) -> Double {
        var vis = 0.0
        let Hd = unit, Wd = Double(W)
        for v in visuals where t >= v.show && t <= v.hide {
            let aIn = smooth((t - v.show) / 0.3), aOut = 1 - smooth((t - (v.hide - 0.22)) / 0.22)
            let alpha = min(aIn, aOut)
            if alpha <= 0.001 { continue }
            vis = max(vis, alpha)
            let rise = (1 - aIn) * Hd * 0.022 - (1 - aOut) * Hd * 0.012
            let lineH = v.rows.first?.advance ?? 0
            let n = Double(v.rows.count)
            ctx.saveGState(); ctx.setAlpha(alpha)
            for (j, r) in v.rows.enumerated() {
                let x = (Wd - r.w) / 2
                let y = (bottom.map { Double(H) * $0 } ?? (vertical ? Double(H) * 0.20 : Hd * 0.075)) + (n - 1 - Double(j)) * lineH - rise
                ctx.draw(r.base, in: CGRect(x: x, y: y, width: r.w, height: r.h))
                let sx = sweepX(r, t: t)
                if sx > r.textX - 4 {
                    ctx.saveGState()
                    let feather = Hd * 0.03
                    let sc = feather / Double(Masks.rampLen)
                    let mr = CGRect(x: x + sx - Double(Masks.rampSolid + Masks.rampLen / 2) * sc, y: y - 20, width: Double(Masks.rampTotal) * sc, height: r.h + 40)
                    ctx.clip(to: mr, mask: Masks.linear)
                    ctx.draw(r.bright, in: CGRect(x: x, y: y, width: r.w, height: r.h))
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()
        }
        return vis
    }

    func drawScrim(ctx: CGContext, strength: Double) {
        ctx.saveGState(); ctx.setAlpha(strength)
        ctx.drawLinearGradient(scrim, start: CGPoint(x: 0, y: Double(H) * min(0.97, max(vertical ? 0.58 : 0.52, (bottom ?? 0.1) + 0.40))), end: CGPoint(x: 0, y: 0), options: [])
        ctx.restoreGState()
    }
}

/// Opening title card drawn on top of the intro scene's background.
final class IntroLayer {
    let title: CGImage, subtitle: CGImage?
    let W: Int, H: Int
    let end: Double

    init(title: String, subject: String, W: Int, H: Int, end: Double) {
        self.W = W; self.H = H; self.end = end
        let hh = CGFloat(H)
        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = hh * 0.008
        let tAttr = NSAttributedString(string: title, attributes: [.font: serifFont(size: hh * 0.118, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: para, .kern: hh * 0.002])
        self.title = renderTextImage(tAttr, maxWidth: CGFloat(W) * 0.82, pad: hh * 0.06, shadow: true, shadowBlur: hh * 0.03)
        let sub = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if sub.isEmpty { subtitle = nil } else {
            let sAttr = NSAttributedString(string: sub.uppercased(), attributes: [.font: roundedFont(size: hh * 0.029, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.92), .paragraphStyle: para, .kern: hh * 0.0075])
            subtitle = renderTextImage(sAttr, maxWidth: CGFloat(W) * 0.7, pad: hh * 0.04, shadow: true, shadowBlur: hh * 0.02)
        }
    }

    func draw(t: Double, ctx: CGContext) {
        let Wd = Double(W), Hd = Double(H)
        // dim + vignette
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.38)); ctx.fill(CGRect(x: 0, y: 0, width: Wd, height: Hd))
        let vg = CGGradient(colorsSpace: sRGB, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.55)] as CFArray, locations: [0.35, 1])!
        ctx.drawRadialGradient(vg, startCenter: CGPoint(x: Wd / 2, y: Hd / 2), startRadius: 0, endCenter: CGPoint(x: Wd / 2, y: Hd / 2), endRadius: Wd * 0.62, options: [.drawsAfterEndLocation])

        let tIn = smooth((t - 0.35) / 1.3)
        let scale = lerp(1.05, 1.0, tIn)
        let tw = Double(title.width), th = Double(title.height)
        let cy = Hd * (subtitle == nil ? 0.5 : 0.545)
        ctx.saveGState(); ctx.setAlpha(tIn)
        ctx.translateBy(x: Wd / 2, y: cy); ctx.scaleBy(x: scale, y: scale)
        ctx.draw(title, in: CGRect(x: -tw / 2, y: -th / 2, width: tw, height: th))
        ctx.restoreGState()

        if let sub = subtitle {
            let ruleP = smooth((t - 1.0) / 1.0)
            let ry = cy - th / 2 + Hd * 0.035
            let rw = Wd * 0.14 * ruleP
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.85 * ruleP))
            ctx.fill(CGRect(x: Wd / 2 - rw / 2, y: ry, width: rw, height: max(2, Hd * 0.0025)))
            let sIn = smooth((t - 1.5) / 1.0)
            let sw = Double(sub.width), sh = Double(sub.height)
            ctx.saveGState(); ctx.setAlpha(sIn)
            ctx.draw(sub, in: CGRect(x: Wd / 2 - sw / 2, y: ry - sh - Hd * 0.002 + (1 - sIn) * -Hd * 0.01, width: sw, height: sh))
            ctx.restoreGState()
        }
    }
}
