// Shorts overlays: word pill/pop captions, animated hook title and closing text.
import Foundation
import CoreGraphics
import CoreText
import AppKit

/// What FrameComposer needs from whatever draws the lyrics.
protocol LyricRendering: AnyObject {
    var bottom: Double? { get set }
    func draw(t: Double, ctx: CGContext) -> Double
    func drawScrim(ctx: CGContext, strength: Double)
    func visibleAmount(t: Double) -> Double
}
extension LyricLayer: LyricRendering {}

func easeOutBack(_ x: Double) -> Double { let c1 = 1.70158, c3 = c1 + 1; let t = clamp01(x) - 1; return 1 + c3 * t * t * t + c1 * t * t }
func easeOutBounce(_ x: Double) -> Double {
    var t = clamp01(x); let n1 = 7.5625, d1 = 2.75
    if t < 1 / d1 { return n1 * t * t }
    if t < 2 / d1 { t -= 1.5 / d1; return n1 * t * t + 0.75 }
    if t < 2.5 / d1 { t -= 2.25 / d1; return n1 * t * t + 0.9375 }
    t -= 2.625 / d1; return n1 * t * t + 0.984375
}

/// One piece of text as a bitmap (with optional soft shadow) plus its typographic size.
struct TextBitmap { var image: CGImage; var size: CGSize; var pad: CGFloat }

func textBitmap(_ text: String, font: NSFont, color: NSColor, shadow: Bool, kern: CGFloat = 0) -> TextBitmap {
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let line = CTLineCreateWithAttributedString(attr)
    var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
    let tw = CGFloat(CTLineGetTypographicBounds(line, &asc, &desc, &lead))
    let pad = font.pointSize * 0.42
    let w = Int(ceil(tw + pad * 2)), h = Int(ceil(asc + desc + pad * 2))
    let ctx = makeContext(w, h)
    if shadow {
        for (dy, blur, a) in [(0.07, 0.30, 0.85), (0.03, 0.09, 0.7)] {
            ctx.saveGState(); ctx.translateBy(x: -30000, y: 0)
            ctx.setShadow(offset: CGSize(width: 30000, height: -font.pointSize * dy), blur: font.pointSize * blur, color: CGColor(gray: 0, alpha: a))
            ctx.textPosition = CGPoint(x: pad, y: pad + desc); CTLineDraw(line, ctx); ctx.restoreGState()
        }
    }
    ctx.textPosition = CGPoint(x: pad, y: pad + desc); CTLineDraw(line, ctx)
    return TextBitmap(image: ctx.makeImage()!, size: CGSize(width: tw, height: asc + desc), pad: pad)
}

private func nsColor(_ c: CGColor) -> NSColor { NSColor(cgColor: c) ?? .yellow }

// MARK: Word-level lyrics

/// Lyrics shown a few words at a time; each word pops in on its own timing and the active word is highlighted.
final class WordLayer: LyricRendering {
    enum Mode { case pop, pill, stack }
    struct Item { var start: Double, end: Double; var normal: TextBitmap, accent: TextBitmap, dark: TextBitmap; var cx: Double, cy: Double }
    struct Phrase { var items: [Item]; var show: Double, hide: Double; var blockH: Double }
    var phrases: [Phrase] = []
    let W: Int, H: Int, mode: Mode, accent: CGColor
    let scrim: CGGradient
    var bottom: Double? = nil

    init(lines: [LyricLine], W: Int, H: Int, timeOffset: Double, mode: Mode, accent: CGColor, window: ClosedRange<Double>) {
        self.W = W; self.H = H; self.mode = mode; self.accent = accent
        scrim = CGGradient(colorsSpace: sRGB, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.5), CGColor(gray: 0, alpha: 0.8)] as CFArray, locations: [0, 0.55, 1])!
        let size = CGFloat(W) * (mode == .stack ? 0.135 : 0.074)
        let font = roundedFont(size: size, weight: mode == .stack ? .black : .heavy)
        let maxRow = Double(W) * 0.88, maxChars = mode == .stack ? 15 : 52, maxWords = mode == .stack ? 3 : 11
        var raw: [[TimedWord]] = []
        for l in lines where !l.words.isEmpty {
            guard l.end + timeOffset > window.lowerBound + 0.02, l.start + timeOffset < window.upperBound - 0.02 else { continue }
            var cur: [TimedWord] = []
            for (i, w) in l.words.enumerated() {
                cur.append(w)
                let chars = cur.map(\.text).joined(separator: " ").count
                let punct = w.text.last.map { ",.;:!?—".contains($0) } ?? false
                if cur.count >= maxWords || chars > maxChars - 4 || (punct && cur.count >= (mode == .stack ? 2 : 7)) || i == l.words.count - 1 { raw.append(cur); cur = [] }
            }
        }
        let space = Double(size) * 0.26
        for words in raw {
            var rowsOf: [[Item]] = [[]]; var rowW = 0.0
            var all: [Item] = []
            for w in words {
                let text = w.text.trimmingCharacters(in: CharacterSet(charactersIn: " "))
                let n = textBitmap(text, font: font, color: .white, shadow: true)
                let a = textBitmap(text, font: font, color: nsColor(accent), shadow: true)
                let d = mode == .pill ? textBitmap(text, font: font, color: NSColor(white: 0.05, alpha: 1), shadow: false) : n   // dark text only the pill style uses (saves memory on whole songs)
                let item = Item(start: w.start + timeOffset, end: w.end + timeOffset, normal: n, accent: a, dark: d, cx: 0, cy: 0)
                let iw = Double(n.size.width)
                if rowW + iw > maxRow && !rowsOf[rowsOf.count - 1].isEmpty { rowsOf.append([]); rowW = 0 }
                rowsOf[rowsOf.count - 1].append(item); rowW += iw + space
                all.append(item)
            }
            // positions: rows centred; row 0 on top
            let rowH = Double(size) * 1.2, blockH = rowH * Double(rowsOf.count)
            var placed: [Item] = []
            for (ri, row) in rowsOf.enumerated() {
                let widths = row.map { Double($0.normal.size.width) }
                let total = widths.reduce(0, +) + space * Double(row.count - 1)
                var x = -total / 2
                let cy = blockH / 2 - rowH * (Double(ri) + 0.5)
                for (k, var it) in row.enumerated() { it.cx = x + widths[k] / 2; it.cy = cy; placed.append(it); x += widths[k] + space }
            }
            phrases.append(Phrase(items: placed, show: (placed.first?.start ?? 0) - 0.10, hide: (placed.last?.end ?? 0) + 0.32, blockH: blockH))
        }
        for i in 0..<max(0, phrases.count - 1) { phrases[i].hide = min(phrases[i].hide, max(phrases[i].items.last?.end ?? 0, phrases[i + 1].show - 0.02)) }
    }

    func visibleAmount(t: Double) -> Double {
        var v = 0.0
        for p in phrases where t >= p.show && t <= p.hide { v = max(v, min(smooth((t - p.show) / 0.12), 1 - smooth((t - (p.hide - 0.15)) / 0.15))) }
        return v
    }

    func drawScrim(ctx: CGContext, strength: Double) {
        ctx.saveGState(); ctx.setAlpha(strength)
        ctx.drawLinearGradient(scrim, start: CGPoint(x: 0, y: Double(H) * min(0.97, max(0.60, (bottom ?? 0.2) + 0.42))), end: CGPoint(x: 0, y: 0), options: [])
        ctx.restoreGState()
    }

    @discardableResult
    func draw(t: Double, ctx: CGContext) -> Double {
        var vis = 0.0
        let cxm = Double(W) / 2
        for p in phrases where t >= p.show && t <= p.hide {
            let alpha = min(smooth((t - p.show) / 0.10), 1 - smooth((t - (p.hide - 0.15)) / 0.15))
            if alpha <= 0.01 { continue }
            vis = max(vis, alpha)
            let centerY = mode == .stack ? Double(H) * (bottom.map { $0 + 0.10 } ?? 0.30) : Double(H) * (bottom ?? 0.20) + p.blockH / 2
            ctx.saveGState(); ctx.setAlpha(alpha)
            let activeIdx = p.items.lastIndex(where: { t >= $0.start - 0.02 })
            if mode == .pill, let ai = activeIdx {
                let it = p.items[ai]; let prev = ai > 0 ? p.items[ai - 1] : it
                let k = smooth((t - (it.start - 0.05)) / 0.15)       // pill glides to the word, landing on its onset
                let x = lerp(prev.cx, it.cx, k), y = lerp(prev.cy, it.cy, k), w = lerp(Double(prev.normal.size.width), Double(it.normal.size.width), k)
                let ph = Double(it.normal.size.height) * 0.98, pw = w + Double(it.normal.size.height) * 0.42
                ctx.setFillColor(accent)
                ctx.addPath(CGPath(roundedRect: CGRect(x: cxm + x - pw / 2, y: centerY + y - ph / 2 - ph * 0.02, width: pw, height: ph), cornerWidth: ph * 0.32, cornerHeight: ph * 0.32, transform: nil)); ctx.fillPath()
            }
            for (i, it) in p.items.enumerated() {
                let isActive = activeIdx == i && t <= it.end + 0.12
                var sc = 1.0, a = 1.0
                var img = it.normal
                switch mode {
                case .pop, .stack:
                    let appear = (t - (it.start - 0.05)) / 0.17
                    if appear < 0 { continue }
                    sc = lerp(mode == .stack ? 1.7 : 0.55, 1, easeOutBack(appear)); a = min(1, appear * 3)
                    if isActive { img = it.accent; sc *= 1.08 }
                case .pill:
                    a = (activeIdx ?? -1) >= i ? 1 : 0.62
                    if isActive { img = it.dark }                        // no scale change: the pill alone marks the word
                }
                let pad = Double(img.pad)
                let iw = Double(img.image.width), ih = Double(img.image.height)
                ctx.saveGState(); ctx.setAlpha(alpha * a)
                ctx.translateBy(x: cxm + it.cx, y: centerY + it.cy); ctx.scaleBy(x: sc, y: sc)
                ctx.draw(img.image, in: CGRect(x: -iw / 2, y: -ih / 2 - (pad - pad), width: iw, height: ih))
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }
        return vis
    }
}

// MARK: Opening hook title

/// The kinetic title for the first ~2.5 s: words slam in, letters drop, or an accent bar wipes the text on.
final class HookTitleLayer {
    struct Word { var text: String; var normal: TextBitmap; var accent: TextBitmap; var cx: Double, cy: Double; var letters: [(TextBitmap, TextBitmap, Double)] }
    var words: [Word] = []
    let W: Int, H: Int, mode: ShortStyle.TitleMode, accent: CGColor
    var blockW = 0.0, blockH = 0.0
    static let length = 2.3

    init(text: String, W: Int, H: Int, mode: ShortStyle.TitleMode, accent: CGColor) {
        self.W = W; self.H = H; self.mode = mode; self.accent = accent
        let toks = text.uppercased().split(whereSeparator: { $0.isWhitespace }).prefix(10).map(String.init)
        guard !toks.isEmpty else { return }
        var size = CGFloat(W) * (mode == .drop ? 0.115 : 0.135)
        var font = roundedFont(size: size, weight: .black)
        func measure(_ f: NSFont) -> [Double] { toks.map { Double(textBitmap($0, font: f, color: .white, shadow: false).size.width) } }
        var widths = measure(font); let maxRow = Double(W) * 0.88
        func rows(_ w: [Double], _ space: Double) -> [[Int]] {
            var r: [[Int]] = [[]]; var x = 0.0
            for (i, v) in w.enumerated() { if x + v > maxRow && !r[r.count - 1].isEmpty { r.append([]); x = 0 }; r[r.count - 1].append(i); x += v + space }
            return r
        }
        var space = Double(size) * 0.24; var layout = rows(widths, space)
        while layout.count > 3 && size > CGFloat(W) * 0.07 { size *= 0.88; font = roundedFont(size: size, weight: .black); widths = measure(font); space = Double(size) * 0.24; layout = rows(widths, space) }
        let rowH = Double(size) * 1.08; blockH = rowH * Double(layout.count)
        var out = [Word?](repeating: nil, count: toks.count)
        for (ri, row) in layout.enumerated() {
            let total = row.map { widths[$0] }.reduce(0, +) + space * Double(row.count - 1)
            blockW = max(blockW, total)
            var x = -total / 2
            for i in row {
                let n = textBitmap(toks[i], font: font, color: .white, shadow: true)
                let a = textBitmap(toks[i], font: font, color: nsColor(accent), shadow: true)
                var letters: [(TextBitmap, TextBitmap, Double)] = []
                if mode == .drop {
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: toks[i], attributes: [.font: font]))
                    for (ci, ch) in toks[i].enumerated() {
                        let off = Double(CTLineGetOffsetForStringIndex(line, ci, nil))
                        letters.append((textBitmap(String(ch), font: font, color: .white, shadow: true), textBitmap(String(ch), font: font, color: nsColor(accent), shadow: true), off))
                    }
                }
                out[i] = Word(text: toks[i], normal: n, accent: a, cx: x + widths[i] / 2, cy: blockH / 2 - rowH * (Double(ri) + 0.5), letters: letters)
                x += widths[i] + space
            }
        }
        words = out.compactMap { $0 }
    }

    /// Darkening behind the title so it reads on any picture.
    func dimAmount(t: Double) -> Double { words.isEmpty ? 0 : 0.42 * (1 - smooth((t - 1.4) / 0.8)) }

    func draw(t: Double, ctx: CGContext) {
        guard !words.isEmpty, t < HookTitleLayer.length else { return }
        let cx0 = Double(W) / 2, cy0 = Double(H) * 0.64
        let exit = smooth((t - 1.75) / 0.45)
        let alpha = 1 - exit, grow = 1 + 0.22 * exit
        ctx.saveGState(); ctx.setAlpha(alpha)
        ctx.translateBy(x: cx0, y: cy0); ctx.scaleBy(x: grow, y: grow)

        func put(_ b: TextBitmap, x: Double, y: Double, scale: Double = 1, rot: Double = 0, a: Double = 1) {
            ctx.saveGState(); ctx.setAlpha(alpha * a)
            ctx.translateBy(x: x, y: y); ctx.rotate(by: rot); ctx.scaleBy(x: scale, y: scale)
            ctx.draw(b.image, in: CGRect(x: -Double(b.image.width) / 2, y: -Double(b.image.height) / 2, width: Double(b.image.width), height: Double(b.image.height)))
            ctx.restoreGState()
        }

        let stagger = words.count > 5 ? 0.11 : 0.17
        switch mode {
        case .slam:
            var shakeX = 0.0, shakeY = 0.0
            for (k, w) in words.enumerated() {
                let tk = 0.08 + stagger * Double(k), dt = t - tk
                if dt > 0 { let d = exp(-dt * 9); shakeX += sin(dt * 70) * 13 * d; shakeY += cos(dt * 83) * 9 * d }
            }
            ctx.translateBy(x: shakeX, y: shakeY)
            for (k, w) in words.enumerated() {
                let p = (t - (0.08 + stagger * Double(k))) / 0.20
                if p < 0 { continue }
                let e = easeOutBack(p)
                let last = k == words.count - 1
                put(last ? w.accent : w.normal, x: w.cx, y: w.cy, scale: lerp(2.4, 1, e), rot: lerp(k % 2 == 0 ? 0.12 : -0.12, 0, e), a: min(1, p * 4))
            }
        case .drop:
            var n = 0
            for (k, w) in words.enumerated() {
                let last = k == words.count - 1
                let startX = w.cx - Double(w.normal.size.width) / 2
                for (li, l) in w.letters.enumerated() {
                    let tn = 0.06 + 0.032 * Double(n); n += 1
                    let p = (t - tn) / 0.50
                    if p < 0 { continue }
                    let drop = (1 - easeOutBounce(p)) * Double(H) * 0.22
                    let lw = Double(l.0.size.width)
                    put(last ? l.1 : l.0, x: startX + l.2 + lw / 2, y: w.cy + drop, a: min(1, p * 5))
                }
            }
        case .bar:
            let prog = smooth((t - 0.12) / 0.55)
            let left = -blockW / 2 - 30, span = blockW + 60
            let edge = left + span * prog
            ctx.saveGState()
            ctx.clip(to: CGRect(x: left, y: -blockH, width: max(0, edge - left), height: blockH * 2))
            for (k, w) in words.enumerated() { put(k == words.count - 1 ? w.accent : w.normal, x: w.cx, y: w.cy) }
            ctx.restoreGState()
            let barA = prog < 1 ? 1.0 : 1 - smooth((t - 0.8) / 0.25)
            if barA > 0 {
                ctx.setFillColor(accent.copy(alpha: barA) ?? accent)
                ctx.fill(CGRect(x: edge - 9, y: -blockH / 2 - 14, width: 18, height: blockH + 28))
            }
            // underline grows after the reveal
            let ul = smooth((t - 0.75) / 0.45)
            ctx.setFillColor(accent)
            ctx.fill(CGRect(x: -blockW / 2, y: -blockH / 2 - 26, width: blockW * ul, height: max(5, Double(H) * 0.0035)))
        }
        ctx.restoreGState()
    }
}

// MARK: Closing call-to-action

final class CTALayer {
    let bitmap: TextBitmap?, accent: CGColor, W: Int, H: Int, start: Double
    init(text: String, W: Int, H: Int, start: Double, accent: CGColor) {
        self.W = W; self.H = H; self.start = start; self.accent = accent
        bitmap = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : textBitmap(text, font: roundedFont(size: CGFloat(W) * 0.052, weight: .bold), color: NSColor(white: 0.05, alpha: 1), shadow: false)
    }
    func draw(t: Double, ctx: CGContext, captionBottom: Double? = nil) {
        guard let b = bitmap, t >= start else { return }
        let a = smooth((t - start) / 0.25)
        let w = Double(b.size.width) + Double(W) * 0.07, h = Double(b.size.height) * 1.25
        let y = Double(H) * max(0.40, (captionBottom ?? 0.20) + 0.26) - (1 - a) * 30
        ctx.saveGState(); ctx.setAlpha(a)
        ctx.setFillColor(accent)
        ctx.addPath(CGPath(roundedRect: CGRect(x: Double(W) / 2 - w / 2, y: y - h / 2, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil)); ctx.fillPath()
        ctx.draw(b.image, in: CGRect(x: Double(W) / 2 - Double(b.image.width) / 2, y: y - Double(b.image.height) / 2, width: Double(b.image.width), height: Double(b.image.height)))
        ctx.restoreGState()
    }
}
