// Ken Burns photo scenes and the transitions between them.
import Foundation
import CoreGraphics
import AppKit

/// A camera move chosen by hand: the view travels from `start` to `end` (0…1 across/down the picture) while it moves closer, stays level or moves wider.
public struct CameraPath: Equatable {
    public var start: CGPoint, end: CGPoint
    public var zoom: Int                  // 0 = closer, 1 = level, 2 = wider
    public init(start: CGPoint, end: CGPoint, zoom: Int) { self.start = start; self.end = end; self.zoom = zoom }

    /// Zoom at the start and the end that keeps both chosen points inside the picture (the renderer and the on-screen preview both use this).
    public func zooms(imageW iw: Double, imageH ih: Double, aspect: Double) -> (z0: Double, z1: Double) {
        let bw = (iw / ih > aspect) ? (ih * aspect) : iw, bh = bw / aspect
        let halfW = 0.5 * (bw / max(1, iw)), halfH = 0.5 * (bh / max(1, ih))
        func need(_ p: CGPoint) -> Double { max(halfW / max(0.02, 0.5 - abs(p.x - 0.5)), halfH / max(0.02, 0.5 - abs(p.y - 0.5))) }
        // Your own move is made as big as the picture allows: the view is zoomed in as far as is sensible (up to 2.4x), so the move is easy to see.
        // A larger zoom always keeps both points inside the picture, so the smallest zoom that fits is only the floor.
        let floorZ = max(need(start), need(end)) * 1.01
        let top = 2.4, nearBig = max(floorZ, 1.35)
        switch zoom {
        case 0: return (nearBig, top)                      // moves closer: from a fairly close view to the closest
        case 2: return (top, nearBig)                      // moves wider: from the closest view out
        default: let mid = max(floorZ, 1.8); return (mid, mid)       // stays level: a close, steady view that travels between the two points
        }
    }
    /// The visible part of the picture (as fractions of its width/height) at the start (`end == false`) or end of the move.
    public func frame(imageW iw: Double, imageH ih: Double, aspect: Double, end atEnd: Bool) -> CGSize {
        let bw = (iw / ih > aspect) ? (ih * aspect) : iw, bh = bw / aspect
        let z = atEnd ? zooms(imageW: iw, imageH: ih, aspect: aspect).z1 : zooms(imageW: iw, imageH: ih, aspect: aspect).z0
        return CGSize(width: bw / max(1, iw) / z, height: bh / max(1, ih) / z)
    }
}

/// A photo (or gradient fallback) with a smooth, aspect-safe Ken Burns camera move.
///
/// Why naive Ken Burns implementations "jump" or stall:
/// 1. Picking normalized centers outside the valid crop domain `[rw/(2*iw), 1 - rw/(2*iw)]` and clamping per-frame causes
///    the camera to stay pinned against the image border for part of the shot, suddenly detach with a velocity kink,
///    race across the middle, and slam into the opposite border.
/// 2. Interpolating zoom `z` linearly and center `(cx, cy)` independently causes optical magnification speed to vary
///    and the camera path to curve in screen space.
///
/// How this engine works:
/// - Endpoints `(c0, z0)` and `(c1, z1)` are computed inside the exact valid crop domain for the image & viewport aspect ratios.
/// - Timeline progress uses a blended cosine S-curve (`u = 0.28 * u0 + 0.72 * 0.5 * (1 - cos(π * u0))`) for gentle acceleration/deceleration.
/// - Zoom interpolates logarithmically (`z(u) = z0 * (z1 / z0)^u`) so perceived optical magnification speed is constant.
/// - Center position couples with inverse zoom (`alpha = (1/z0 - 1/z(u)) / (1/z0 - 1/z1)`), guaranteeing that all four edges
///   of the crop rectangle move in straight lines and every intermediate frame stays 100% inside the image without clamping jumps.
struct ClipSegment { let source: VideoClipSource; let offset: Double; let seconds: Double }

final class PhotoScene {
    let box: ImageBox?
    var clipTrack: [ClipSegment] = []   // generated video clips played back to back from the start of the scene; afterwards the last frame (`box`) gets a Ken Burns push-in
    var subjects: [CGPoint] = []        // the main subjects of the picture: the automatic camera travels from one to the next
    var tail = false                    // the scene plays a video clip first: after it the last frame holds and the camera moves between its two most prominent features
    var subjectsOrdered = false         // the subjects are the picture's own focal points 1 → 2: travel in that order instead of left → right
    var kbStart: Double = .nan          // when that Ken Burns begins (video time); NaN = at the start of the scene
    let video: VideoClipSource?          // a video clip that plays during this scene instead of a moving still picture
    let a: Double, b: Double            // video-time interval
    let seed: UInt64
    let focus: CGPoint                  // normalized saliency focus in [0, 1] x [0, 1]
    let vertical: Bool
    let energetic: Bool                 // true for punchy Shorts
    let camera: CameraPath?             // a move chosen by hand (nil = automatic)
    let mode: Int                       // 0 = push-in, 1 = pull-out, 2 = pan L→R, 3 = pan R→L, 4 = diagonal glide
    private let rndZoom: Double
    private let rndPanX: Double
    private let rndPanY: Double
    private let diagFlip: Bool

    init(box: ImageBox?, a: Double, b: Double, seed: UInt64, focus: CGPoint, vertical: Bool = false, shotInterval: Double? = nil, shake: Bool = false, calm: Bool = false, video: VideoClipSource? = nil, beats: [Double] = [], preferredMode: Int? = nil, camera: CameraPath? = nil) {
        self.camera = camera
        self.box = box
        self.video = video
        self.a = a
        self.b = b
        self.seed = seed
        self.focus = CGPoint(x: min(0.88, max(0.12, focus.x)), y: min(0.88, max(0.12, focus.y)))
        self.vertical = vertical
        self.energetic = (shotInterval != nil && !calm)

        var rng = SeededRNG(seed &+ 99)
        func unitRnd(_ r: inout SeededRNG) -> Double { Double(r.next() % 10000) / 10000.0 }

        if let pm = preferredMode {
            self.mode = ((pm % 5) + 5) % 5
        } else {
            let m = Int(rng.next() % 5)
            self.mode = vertical ? [0, 2, 3, 1, 4][m] : m
        }
        self.rndZoom = unitRnd(&rng)
        self.rndPanX = unitRnd(&rng) - 0.5
        self.rndPanY = unitRnd(&rng) - 0.5
        self.diagFlip = Bool.random(using: &rng)
    }

    /// Computes start `(c0, z0)` and end `(c1, z1)` camera states guaranteed to lie strictly within the image bounds
    /// for image size `(iw, ih)` and viewport size `(W, H)`.
    private func endpoints(iw: Double, ih: Double, W: Int, H: Int) -> (c0: CGPoint, z0: Double, c1: CGPoint, z1: Double) {
        let target = Double(W) / Double(H)
        let bw = (iw / ih > target) ? (ih * target) : iw
        let bh = bw / target
        // Normalized half-size of the z = 1.0 cover rectangle in [0, 1] image coordinates
        let halfW0 = 0.5 * (bw / max(1.0, iw))
        let halfH0 = 0.5 * (bh / max(1.0, ih))

        func clampCenter(_ p: CGPoint, zoom z: Double) -> CGPoint {
            // Leave a tiny 0.2% margin inside the image border so subpixel rounding never touches the edge
            let margin = 0.996
            let maxDX = max(0.0, (0.5 - halfW0 / z) * margin)
            let maxDY = max(0.0, (0.5 - halfH0 / z) * margin)
            return CGPoint(
                x: min(0.5 + maxDX, max(0.5 - maxDX, p.x)),
                y: min(0.5 + maxDY, max(0.5 - maxDY, p.y))
            )
        }

        if let cam = camera {                    // the user's own move: exactly their two points, zoom chosen so both fit inside the picture
            let z = cam.zooms(imageW: iw, imageH: ih, aspect: target)
            return (clampCenter(cam.start, zoom: z.z0), z.z0, clampCenter(cam.end, zoom: z.z1), z.z1)
        }

        // Scale the move distance gently by section duration so short (5s) and long (16s) sections have similar, calm speed
        let duration = max(2.0, b - a)
        let durScale = min(1.15, max(0.55, duration / 12.0)) * (energetic ? 1.18 : 1.0)
        let zoomDelta = (0.15 + 0.06 * rndZoom) * durScale

        let z0: Double
        let z1: Double
        let raw0: CGPoint
        let raw1: CGPoint

        // Gentle subject anchor biased toward focus point without forcing extreme corners
        let subj = CGPoint(
            x: 0.5 + (focus.x - 0.5) * 0.85,
            y: 0.5 + (focus.y - 0.5) * 0.80
        )

        switch mode {
        case 0:
            // Slow push-in toward subject focal point
            z0 = 1.025
            z1 = z0 + zoomDelta
            raw0 = CGPoint(x: lerp(0.5, subj.x, 0.45), y: lerp(0.5, subj.y, 0.45))
            raw1 = subj

        case 1:
            // Slow pull-back from subject focal point to wider framing
            z1 = 1.025
            z0 = z1 + zoomDelta
            raw0 = subj
            raw1 = CGPoint(x: lerp(0.5, subj.x, 0.45), y: lerp(0.5, subj.y, 0.45))

        case 2, 3:
            // Smooth horizontal pan across subject height with subtle zoom drift
            // The default move: a quick, confident sweep across the whole picture, ending on the subject
            let zLow = vertical ? 1.08 : 1.45
            let zHigh = zLow + zoomDelta * (vertical ? 0.55 : 1.2)
            let leftToRight = (mode == 2)
            z0 = leftToRight ? zLow : zHigh
            z1 = leftToRight ? zHigh : zLow

            let availX0 = max(0.0, 0.5 - halfW0 / z0)
            let availX1 = max(0.0, 0.5 - halfW0 / z1)
            let maxPan = min(availX0, availX1)
            let panRadius = vertical ? min(maxPan * 0.95, 0.40 * durScale) : (maxPan * 0.97)

            // Sweep from edge to edge of what the zoom allows (centred), so the whole width of the picture passes by
            let centerBiasX = 0.5
            let startX = leftToRight ? (centerBiasX - panRadius) : (centerBiasX + panRadius)
            let endX   = leftToRight ? (centerBiasX + panRadius) : (centerBiasX - panRadius)
            let yDrift = 0.012 * rndPanY * durScale

            raw0 = CGPoint(x: startX, y: subj.y - yDrift)
            raw1 = CGPoint(x: endX, y: subj.y + yDrift)

        default:
            // Cinematic diagonal rostrum glide toward subject
            z0 = 1.14
            z1 = z0 + zoomDelta * 0.90
            let dirX: Double = diagFlip ? 1.0 : -1.0
            let availX = max(0.0, 0.5 - halfW0 / z0)
            let availY = max(0.0, 0.5 - halfH0 / z0)
            let dx = min(availX * 0.85, (vertical ? 0.14 : 0.09) * durScale) * dirX
            let dy = min(availY * 0.85, 0.06 * durScale) * (rndPanY >= 0 ? 1.0 : -1.0)
            raw0 = CGPoint(x: subj.x - dx, y: subj.y - dy)
            raw1 = CGPoint(x: subj.x + dx * 0.5, y: subj.y + dy * 0.5)
        }

        let c0 = clampCenter(raw0, zoom: z0)
        let c1 = clampCenter(raw1, zoom: z1)
        return (c0, z0, c1, z1)
    }

    func draw(t: Double, ctx: CGContext, W: Int, H: Int) {
        let kb0 = kbStart.isNaN ? a : kbStart
        let u0 = clamp01((t - kb0) / max(0.001, b - kb0))
        // Blended cosine S-curve: silky acceleration and deceleration while staying alive during cross-dissolves
        let uCos = 0.5 - 0.5 * cos(.pi * u0)
        let u = 0.28 * u0 + 0.72 * uCos

        if !clipTrack.isEmpty {                                      // generated clips: play them, then fall through to the Ken Burns on the last frame
            let local = t - a
            if let seg = clipTrack.last(where: { local >= $0.offset - 0.001 }), local < seg.offset + seg.seconds, let frame = seg.source.frame(at: max(0, local - seg.offset)) {
                let iw = Double(frame.width), ih = Double(frame.height), target = Double(W) / Double(H)
                let bw = iw / ih > target ? ih * target : iw, bh = bw / target
                let rw = bw, rh = bh                                       // the clip plays exactly as made: a plain fill of the frame, no extra zoom
                let cx = iw / 2, cy = ih / 2
                let s = Double(W) / rw
                ctx.draw(frame, in: CGRect(x: -(cx - rw / 2) * s, y: -(ih - (cy - rh / 2 + rh)) * s, width: iw * s, height: ih * s))
                return
            }
        }
        if let v = video {
            let shot = v.looped(at: max(0, t - a), sceneLength: self.b - a)
            if let frame = shot.main {
                func put(_ img: CGImage) {
                    let iw = Double(img.width), ih = Double(img.height), target = Double(W) / Double(H)
                    let rw = iw / ih > target ? ih * target : iw, rh = rw / target       // cover crop, centred
                    let cx = iw / 2, cy = ih / 2, s = Double(W) / rw
                    ctx.draw(img, in: CGRect(x: -(cx - rw / 2) * s, y: -(ih - (cy - rh / 2 + rh)) * s, width: iw * s, height: ih * s))
                }
                put(frame)
                if let over = shot.over { ctx.saveGState(); ctx.setAlpha(CGFloat(shot.overAlpha)); put(over); ctx.restoreGState() }
                return
            }
        }
        guard let img = box?.get() else { drawGradient(ctx, W, H, u0); return }
        let iw = Double(img.width), ih = Double(img.height)
        let target = Double(W) / Double(H)
        let bw = iw / ih > target ? ih * target : iw        // base cover rect
        let bh = bw / target

        var ncx = 0.5, ncy = 0.5, z = 1.0
        if camera == nil {
            (ncx, ncy, z) = autoState(t: t, kb0: kb0, iw: iw, ih: ih, bw: bw, bh: bh)
        } else {
            let ep = endpoints(iw: iw, ih: ih, W: W, H: H)
            // Logarithmic (exponential) zoom interpolation for constant perceived optical magnification speed
            z = ep.z0 * pow(ep.z1 / ep.z0, u)
            // Perspective-coupled center interpolation: guarantees every edge of the crop window moves linearly
            // and never collides with the image boundary mid-shot.
            let invZ0 = 1.0 / ep.z0, invZ1 = 1.0 / ep.z1, invZ = 1.0 / z
            let alpha = abs(invZ1 - invZ0) > 1e-5 ? (invZ - invZ0) / (invZ1 - invZ0) : u
            ncx = lerp(ep.c0.x, ep.c1.x, alpha); ncy = lerp(ep.c0.y, ep.c1.y, alpha)
        }

        let rw = bw / z, rh = bh / z
        var cx = ncx * iw, cy = ncy * ih
        cx = min(max(cx, rw / 2), iw - rw / 2)
        cy = min(max(cy, rh / 2), ih - rh / 2)
        let rx = cx - rw / 2, ry = cy - rh / 2
        let s = Double(W) / rw
        ctx.draw(img, in: CGRect(x: -rx * s, y: -(ih - (ry + rh)) * s, width: iw * s, height: ih * s))
    }

    /// The automatic camera: it always moves, from one subject to the next (or from a wide view in to the one subject), at a steady, visible pace.
    /// Long scenes keep travelling back and forth between the subjects, so a scene is never left standing still.
    private func autoState(t: Double, kb0: Double, iw: Double, ih: Double, bw: Double, bh: Double) -> (Double, Double, Double) {
        let halfW0 = 0.5 * bw / iw, halfH0 = 0.5 * bh / ih
        func clampC(_ p: CGPoint, _ z: Double) -> CGPoint {
            let mx = max(0, (0.5 - halfW0 / z) * 0.996), my = max(0, (0.5 - halfH0 / z) * 0.996)
            return CGPoint(x: min(0.5 + mx, max(0.5 - mx, p.x)), y: min(0.5 + my, max(0.5 - my, p.y)))
        }
        let tight = vertical ? 1.3 : 1.75, wide = vertical ? 1.0 : 1.1
        var subs = subjects.isEmpty ? [focus] : subjects
        if !subjectsOrdered { subs.sort { $0.x < $1.x } }
        if mode == 3 || mode == 1 { subs.reverse() }                      // alternate the direction of travel from scene to scene
        let total = max(0.5, b - (kb0.isNaN ? a : kb0))
        var path: [(CGPoint, Double)]; var durs: [Double]
        if tail {
            // after a video clip: the last frame holds, the camera eases in from the full frame onto the most prominent feature, then travels to the second
            if subs.count == 1 { let f = subs[0]; subs.append(CGPoint(x: f.x < 0.5 ? min(0.85, f.x + 0.25) : max(0.15, f.x - 0.25), y: 0.5 + (f.y - 0.5) * 0.6)) }
            let ease = min(1.6, total * 0.3), rest = max(0.2, total - ease)
            path = [(CGPoint(x: 0.5, y: 0.5), 1.0), (subs[0], tight), (subs[1], tight)]; durs = [ease, rest]
            if rest >= 11 { path.append((subs[0], tight)); durs = [ease, rest / 2, rest / 2] }       // once back, in a long scene
        } else {
            var keys: [(CGPoint, Double)]
            if subs.count >= 2 { keys = subs.map { ($0, tight) } }
            else {
                let c = CGPoint(x: 0.5 + (subs[0].x - 0.5) * 0.25, y: 0.5 + (subs[0].y - 0.5) * 0.25)
                keys = mode == 1 ? [(subs[0], tight), (c, wide)] : [(c, wide), (subs[0], tight)]
            }
            // One journey only: from one side to the other, and once back when there is time for it (never back and forth again).
            if keys.count >= 3 { path = Array(keys.prefix(3)) }
            else { path = keys; if total >= 11 { path.append(keys[0]) } }
            durs = Array(repeating: total / Double(path.count - 1), count: path.count - 1)
        }
        let local = min(total, max(0, t - (kb0.isNaN ? a : kb0)))
        var k = 0, acc = 0.0
        while k < durs.count - 1 && local >= acc + durs[k] { acc += durs[k]; k += 1 }
        let f = min(1, max(0, (local - acc) / max(0.001, durs[k])))
        let e = 0.35 * f + 0.65 * (0.5 - 0.5 * cos(.pi * f))               // mostly smooth, never stopping dead between legs
        let (p0, z0) = path[k], (p1, z1) = path[k + 1]
        let z = z0 * pow(z1 / z0, e)
        let c = clampC(CGPoint(x: lerp(Double(p0.x), Double(p1.x), e), y: lerp(Double(p0.y), Double(p1.y), e)), z)
        return (Double(c.x), Double(c.y), z)
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

enum TransitionKind {
    case dissolve                  // smooth cross-dissolve
    case wipe(angle: Double)       // degrees; 0 = reveals left→right
    case iris(from: CGPoint)       // normalised, origin bottom-left
    case blinds(vertical: Bool, count: Int)
    case push(angle: Double)       // 0 = new image pushes in from the right
    case zoom(from: Double)        // new picture eases in from a slightly tighter crop
    case flash                     // quick white flash cut
    case whip(angle: Double)       // fast slide with motion ghosts

    /// Fast cuts for Shorts, drawn from the seeded style's pool.
    static func short(_ rng: inout SeededRNG, pool: [ShortStyle.Cut], calm: Bool, avoiding last: Int) -> (TransitionKind, Int) {
        var c: ShortStyle.Cut
        repeat { c = pool[Int(rng.next() % UInt64(pool.count))] } while c.rawValue == last && pool.count > 1
        switch c {
        case .zoom: return (.zoom(from: calm ? 1.06 : 1.16), c.rawValue)
        case .flash: return (calm ? .dissolve : .flash, c.rawValue)
        case .whip: return (calm ? .dissolve : .whip(angle: Bool.random(using: &rng) ? 0 : 180), c.rawValue)
        case .push: return (calm ? .dissolve : .push(angle: Bool.random(using: &rng) ? 0 : 180), c.rawValue)
        case .wipe: return (.wipe(angle: [0, 180, 35, 215][Int(rng.next() % 4)]), c.rawValue)
        }
    }

    static func random(_ rng: inout SeededRNG, avoiding last: Int) -> (TransitionKind, Int) {
        var k: Int
        repeat { k = Int(rng.next() % 7) } while k == last
        switch k {
        case 0, 1: return (.dissolve, k)
        case 2: return (.wipe(angle: 0), k)
        case 3: return (.wipe(angle: 180), k)
        case 4: return (.wipe(angle: 35), k)
        case 5: return (.zoom(from: 1.06), k)
        default: return (.iris(from: CGPoint(x: 0.5, y: 0.5)), k)
        }
    }
}

enum Transition {
    static func draw(_ kind: TransitionKind, p: Double, ctx: CGContext, W: Int, H: Int,
                     drawA: () -> Void, drawB: () -> Void) {
        let e = smooth(p)
        let w = Double(W), h = Double(H)
        switch kind {
        case .dissolve:
            drawA()
            ctx.saveGState()
            ctx.setAlpha(e)
            drawB()
            ctx.restoreGState()
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
            ctx.saveGState(); ctx.setAlpha(e)
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
