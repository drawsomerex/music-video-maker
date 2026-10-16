// Ken Burns photo scenes and the transitions between them.
import Foundation
import CoreGraphics

/// A photo (or gradient fallback) with a Ken Burns camera move.
final class PhotoScene {
    let box: ImageBox?
    let a: Double, b: Double            // video-time interval
    let seed: UInt64
    // camera: centre (normalised in image) and zoom at u=0 and u=1
    var c0 = CGPoint(x: 0.5, y: 0.5), c1 = CGPoint(x: 0.5, y: 0.5), z0 = 1.0, z1 = 1.12

    /// "Pattern interrupt" shots: the same picture re-framed every couple of seconds (wide pan → punch-in → opposite pan → alt detail…).
    struct Shot { var t0: Double, t1: Double, z0: Double, z1: Double; var c0: CGPoint, c1: CGPoint }
    var shots: [Shot] = []
    var shake = false
    /// Calm mode: one continuous camera path through a few waypoints (Catmull-Rom), no cuts.
    var path: [(z: Double, c: CGPoint)] = []
    var segLen = 7.0

    init(box: ImageBox?, a: Double, b: Double, seed: UInt64, focus: CGPoint, vertical: Bool = false, shotInterval: Double? = nil, shake: Bool = false, calm: Bool = false, beats: [Double] = []) {
        self.box = box; self.a = a; self.b = b; self.seed = seed; self.shake = shake
        var rng = SeededRNG(seed &+ 99)
        var mode = Int(rng.next() % 5)
        if vertical { mode = [0, 2, 3, 2, 3][mode] }   // tall crop of a wide picture: favour pans across it + push-ins
        let f = CGPoint(x: 0.5 + (focus.x - 0.5) * 0.9, y: 0.5 + (focus.y - 0.5) * 0.9)
        let side = Bool.random(using: &rng)
        func jitter() -> Double { Double(rng.next() % 1000) / 1000 * 0.06 - 0.03 }
        let fy = min(0.78, max(0.22, f.y))
        switch mode {
        case 0: z0 = 1.0; z1 = 1.30; c0 = CGPoint(x: 0.5, y: fy); c1 = f                          // push in toward subject
        case 1: z0 = 1.30; z1 = 1.0; c0 = f; c1 = CGPoint(x: 0.5, y: fy)                          // pull out
        case 2: z0 = 1.20; z1 = 1.26; c0 = CGPoint(x: 0.0, y: fy + jitter()); c1 = CGPoint(x: 1.0, y: fy + jitter())   // pan →
        case 3: z0 = 1.26; z1 = 1.20; c0 = CGPoint(x: 1.0, y: fy + jitter()); c1 = CGPoint(x: 0.0, y: fy + jitter())   // pan ←
        default: z0 = 1.08; z1 = 1.32; c0 = CGPoint(x: side ? 0.2 : 0.8, y: min(0.82, fy + 0.18)); c1 = CGPoint(x: side ? 0.78 : 0.22, y: max(0.18, fy - 0.18)) // diagonal drift + zoom
        }
        if let iv = shotInterval { if calm { buildPath(interval: iv, focus: f, rng: &rng) } else { buildShots(interval: iv, focus: f, beats: beats, rng: &rng) } }
    }

    private func buildPath(interval iv: Double, focus f: CGPoint, rng: inout SeededRNG) {
        func rnd() -> Double { Double(rng.next() % 1000) / 1000 }
        let total = max(0.5, b - a); let n = max(2, Int((total / iv).rounded(.up)) + 1)
        segLen = total / Double(n - 1)
        var x = 0.3 + rnd() * 0.4, tight = rng.next() % 2 == 0
        for _ in 0..<n {
            let z = tight ? 1.26 + rnd() * 0.14 : 1.08 + rnd() * 0.10
            let cx = tight ? f.x + (rnd() - 0.5) * 0.24 : x
            path.append((z, CGPoint(x: min(0.85, max(0.15, cx)), y: tight ? f.y + (rnd() - 0.5) * 0.12 : min(0.82, max(0.18, f.y + (rnd() - 0.5) * 0.14)))))
            x = min(0.8, max(0.2, x + (rnd() < 0.5 ? -1 : 1) * (0.18 + rnd() * 0.18)))   // never a big jump between waypoints
            tight.toggle()
        }
    }

    private func buildShots(interval iv: Double, focus f: CGPoint, beats: [Double], rng: inout SeededRNG) {
        func rnd() -> Double { Double(rng.next() % 1000) / 1000 }
        let total = max(0.5, b - a), n = max(1, Int((total / iv).rounded())), len = total / Double(n)
        let fy = min(0.78, max(0.22, f.y))
        // Snap internal shot cut times to the nearest musical beat within ±0.35s when available.
        var boundaries = [Double](repeating: a, count: n + 1)
        boundaries[0] = a; boundaries[n] = b
        if n > 1 {
            for k in 1..<n {
                let ideal = a + len * Double(k)
                let minT = boundaries[k - 1] + max(0.6, len * 0.45)
                let maxT = b - max(0.6, len * 0.45) * Double(n - k)
                if let snap = beats.filter({ $0 >= minT && $0 <= maxT && abs($0 - ideal) <= 0.35 }).min(by: { abs($0 - ideal) < abs($1 - ideal) }) {
                    boundaries[k] = snap
                } else {
                    boundaries[k] = min(maxT, max(minT, ideal))
                }
            }
        }
        var lastX = -1.0, kind = Int(rng.next() % 4)
        for k in 0..<n {
            kind = (kind + 1 + Int(rng.next() % 2)) % 4
            let alt = CGPoint(x: 0.2 + rnd() * 0.6, y: min(0.78, max(0.22, fy + (rnd() - 0.5) * 0.28)))
            var shot: Shot
            switch kind {
            case 0:  shot = Shot(t0: 0, t1: 0, z0: 1.06, z1: 1.20, c0: CGPoint(x: 0.22, y: fy), c1: CGPoint(x: 0.78, y: fy))         // pan across at subject height
            case 1:  shot = Shot(t0: 0, t1: 0, z0: 1.35, z1: 1.62, c0: f, c1: CGPoint(x: f.x + 0.03, y: f.y))                       // punch-in on the subject
            case 2:  shot = Shot(t0: 0, t1: 0, z0: 1.22, z1: 1.34, c0: CGPoint(x: 0.8, y: fy), c1: CGPoint(x: 0.25, y: fy))        // pan back at subject height
            default: shot = Shot(t0: 0, t1: 0, z0: 1.30, z1: 1.55, c0: alt, c1: CGPoint(x: alt.x - 0.06, y: alt.y + 0.02))          // detail elsewhere
            }
            if abs(shot.c0.x - lastX) < 0.15 { shot.c0.x = 1 - shot.c0.x }                                                          // never reuse the previous framing
            lastX = shot.c1.x
            shot.t0 = boundaries[k]; shot.t1 = boundaries[k + 1]
            shots.append(shot)
        }
    }

    func draw(t: Double, ctx: CGContext, W: Int, H: Int) {
        let u0 = clamp01((t - a) / max(0.001, b - a))
        let u = 0.5 * u0 + 0.5 * (u0 * u0 * (3 - 2 * u0))
        guard let img = box?.get() else { drawGradient(ctx, W, H, u0); return }
        let iw = Double(img.width), ih = Double(img.height)
        let target = Double(W) / Double(H)
        let bw = iw / ih > target ? ih * target : iw        // base cover rect
        let bh = bw / target
        var z = lerp(z0, z1, u)
        var ncx = lerp(c0.x, c1.x, u), ncy = lerp(c0.y, c1.y, u)
        if !path.isEmpty {
            let sTime = clamp01((t - a) / max(0.001, b - a)) * Double(path.count - 1)
            let i = min(path.count - 2, Int(sTime)), u = sTime - Double(i)
            let p0 = path[max(0, i - 1)], p1 = path[i], p2 = path[i + 1], p3 = path[min(path.count - 1, i + 2)]
            func cr(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (-a + 3 * b - 3 * c + d) * u * u * u) }
            z = cr(p0.z, p1.z, p2.z, p3.z); ncx = cr(p0.c.x, p1.c.x, p2.c.x, p3.c.x); ncy = cr(p0.c.y, p1.c.y, p2.c.y, p3.c.y)
        } else if !shots.isEmpty {
            let k = shots.lastIndex(where: { t >= $0.t0 }) ?? 0
            let sh = shots[k]
            let su0 = clamp01((t - sh.t0) / max(0.001, sh.t1 - sh.t0)), su = 0.5 * su0 + 0.5 * (su0 * su0 * (3 - 2 * su0))
            z = lerp(sh.z0, sh.z1, su); ncx = lerp(sh.c0.x, sh.c1.x, su); ncy = lerp(sh.c0.y, sh.c1.y, su)
            let dt = t - sh.t0
            if k > 0 && dt >= 0 && dt < 0.22 {                       // punch: start 12 % tighter and settle
                let e = 1 - pow(1 - dt / 0.22, 3); z *= 1 + 0.12 * (1 - e)
                if shake { let d = 1 - dt / 0.22; ncx += 0.012 * sin(dt * 95) * d; ncy += 0.008 * cos(dt * 110) * d }
            }
        }
        let rw = bw / z, rh = bh / z
        var cx = ncx * iw, cy = ncy * ih
        cx = min(max(cx, rw / 2), iw - rw / 2); cy = min(max(cy, rh / 2), ih - rh / 2)
        let rx = cx - rw / 2, ry = cy - rh / 2
        let s = Double(W) / rw
        ctx.draw(img, in: CGRect(x: -rx * s, y: -(ih - (ry + rh)) * s, width: iw * s, height: ih * s))
    }

    func drawGradient(_ ctx: CGContext, _ W: Int, _ H: Int, _ u: Double) {
        var rng = SeededRNG(seed &+ 5)
        let hue = Double(rng.next() % 360) / 360
        let c1 = NSColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1).cgColor
        let c2 = NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.22, alpha: 1).cgColor
        let g = CGGradient(colorsSpace: sRGB, colors: [c1, c2] as CFArray, locations: [0, 1])!
        let ang = u * 0.6
        ctx.drawLinearGradient(g, start: CGPoint(x: Double(W) * (0.2 + 0.2 * ang), y: Double(H)), end: CGPoint(x: Double(W) * (0.8 - 0.2 * ang), y: 0), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    }
}
import AppKit

enum TransitionKind {
    case wipe(angle: Double)       // degrees; 0 = reveals left→right
    case iris(from: CGPoint)       // normalised, origin bottom-left
    case blinds(vertical: Bool, count: Int)
    case push(angle: Double)       // 0 = new image pushes in from the right
    case zoom(from: Double)        // new picture eases in from a tighter crop
    case flash                     // quick white flash cut
    case whip(angle: Double)       // fast slide with motion ghosts

    /// Fast cuts for Shorts, drawn from the seeded style's pool.
    static func short(_ rng: inout SeededRNG, pool: [ShortStyle.Cut], calm: Bool, avoiding last: Int) -> (TransitionKind, Int) {
        var c: ShortStyle.Cut
        repeat { c = pool[Int(rng.next() % UInt64(pool.count))] } while c.rawValue == last && pool.count > 1
        switch c {
        case .zoom: return (.zoom(from: calm ? 1.15 : 1.45), c.rawValue)
        case .flash: return (.flash, c.rawValue)
        case .whip: return (.whip(angle: Bool.random(using: &rng) ? 0 : 180), c.rawValue)
        case .push: return (.push(angle: Bool.random(using: &rng) ? 0 : 180), c.rawValue)
        case .wipe: return (.wipe(angle: [0, 180, 35, 215][Int(rng.next() % 4)]), c.rawValue)
        }
    }

    static func random(_ rng: inout SeededRNG, avoiding last: Int) -> (TransitionKind, Int) {
        var k: Int
        repeat { k = Int(rng.next() % 9) } while k == last
        switch k {
        case 0: return (.wipe(angle: 0), k)
        case 1: return (.wipe(angle: 180), k)
        case 2: return (.wipe(angle: 90), k)
        case 3: return (.wipe(angle: 35), k)
        case 4: return (.wipe(angle: 215), k)
        case 5: return (.iris(from: CGPoint(x: 0.5, y: 0.5)), k)
        case 6: return (.blinds(vertical: true, count: 8), k)
        case 7: return (.push(angle: Bool.random(using: &rng) ? 0 : 180), k)
        default: return (.blinds(vertical: false, count: 6), k)
        }
    }
}

enum Transition {
    static func draw(_ kind: TransitionKind, p: Double, ctx: CGContext, W: Int, H: Int,
                     drawA: () -> Void, drawB: () -> Void) {
        let e = smooth(p)
        let w = Double(W), h = Double(H)
        switch kind {
        case .wipe(let angle):
            drawA()
            let th = angle * .pi / 180
            let dx = cos(th), dy = sin(th)
            let L = abs(w * dx) + abs(h * dy)
            let feather = h * 0.24
            let f = -L / 2 - feather / 2 + e * (L + feather)
            ctx.saveGState()
            ctx.translateBy(x: w / 2, y: h / 2); ctx.rotate(by: th)
            let s = feather / Double(Masks.rampLen)
            let rect = CGRect(x: f - Double(Masks.rampSolid + Masks.rampLen / 2) * s, y: -4096 * s * 0.5, width: Double(Masks.rampTotal) * s, height: 4096 * s)
            ctx.clip(to: rect, mask: Masks.linear)
            ctx.rotate(by: -th); ctx.translateBy(x: -w / 2, y: -h / 2)   // back to canvas space; the clip persists
            drawB()
            ctx.restoreGState()
        case .iris(let from):
            drawA()
            let cx = from.x * w, cy = from.y * h
            let far = max(hypot(cx, cy), hypot(w - cx, cy), hypot(cx, h - cy), hypot(w - cx, h - cy)) * 1.05
            let r = max(1, e * far)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), mask: Masks.radial)
            drawB()
            ctx.restoreGState()
        case .blinds(let vertical, let n):
            drawA()
            var rects: [CGRect] = []
            let stagger = 0.55
            for i in 0..<n {
                let f = clamp01((e * (1 + stagger) - Double(i) / Double(n) * stagger))
                if vertical { let sw = w / Double(n); rects.append(CGRect(x: Double(i) * sw, y: 0, width: sw * f + 0.5, height: h)) }
                else { let sh = h / Double(n); rects.append(CGRect(x: 0, y: Double(i) * sh, width: w, height: sh * f + 0.5)) }
            }
            ctx.saveGState(); ctx.clip(to: rects); drawB(); ctx.restoreGState()
        case .zoom(let from):
            drawA()
            ctx.saveGState(); ctx.setAlpha(min(1, e * 1.7))
            let sc = lerp(from, 1.0, e)
            ctx.translateBy(x: w / 2, y: h / 2); ctx.scaleBy(x: sc, y: sc); ctx.translateBy(x: -w / 2, y: -h / 2)
            drawB(); ctx.restoreGState()
        case .flash:
            if p < 0.5 { drawA() } else { drawB() }
            let a = 1 - abs(p - 0.5) * 2
            ctx.setFillColor(CGColor(gray: 1, alpha: a * 0.92)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        case .whip(let angle):
            let dir = cos(angle * .pi / 180), dirY = sin(angle * .pi / 180)
            let travelX = abs(dir) > 0.3 ? w : 0, travelY = abs(dirY) > 0.3 ? h : 0
            for (k, alpha) in [(0.0, 1.0), (0.06, 0.32), (0.12, 0.2)] {
                ctx.saveGState(); ctx.setAlpha(alpha)
                ctx.translateBy(x: -dir * (e - k) * travelX, y: -dirY * (e - k) * travelY); drawA(); ctx.restoreGState()
            }
            for (k, alpha) in [(0.0, 1.0), (0.06, 0.32), (0.12, 0.2)] {
                ctx.saveGState(); ctx.setAlpha(alpha)
                ctx.translateBy(x: dir * (1 - e - k) * travelX, y: dirY * (1 - e - k) * travelY); drawB(); ctx.restoreGState()
            }
        case .push(let angle):
            let dir = cos(angle * .pi / 180)      // +1 new comes from right
            ctx.saveGState(); ctx.translateBy(x: -dir * e * w, y: 0); drawA(); ctx.restoreGState()
            ctx.saveGState(); ctx.translateBy(x: dir * (1 - e) * w, y: 0); drawB(); ctx.restoreGState()
        }
    }
}
