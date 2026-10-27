// Making a clip loop cleanly where a single dissolve can't:
//
//   • parts that move one way (clouds sliding across the sky, a slow change of light) never match from the end to the start, so a short dissolve
//     shows them jumping back. Those parts get their own, much slower dissolve (the rest keeps the short one), so they never visibly jump.
//   • a slow drift of brightness or colour over the clip is spread evenly over the whole loop (colour lock), so the join doesn't pulse.
//   • something that turns (a water wheel) and changes direction partway through is found, like a mirror flip, so the loop keeps to one direction.
import Foundation
import AVFoundation
import CoreGraphics
import Vision
import simd

/// How one clip's loop is blended. Times are seconds into the clip file.
public struct LoopBlend {
    public static let gw = 48, gh = 27
    /// For each small square of the picture (48 × 27): 0 = the normal dissolve, 1 = the slow one (parts that drift one way).
    public var mask: [Float]
    /// The slow dissolve runs from `before` seconds before the loop's start point to `after` seconds after it.
    public var before: Double, after: Double
    /// Colour drift over one period of the loop (the end ÷ the start; red, green, blue). 1 = none.
    public var drift: SIMD3<Float>
    /// Share of the picture (0…1) that gets the slow dissolve.
    public var share: Double
    /// How visible the join is (same scale as the best-loop score: 1 ≈ as close as two neighbouring frames).
    public var score: Double
    public var slowSeconds: Double { before + after }
}

/// The clip as small colour pictures, 12 a second (red, green, blue for each of the 48 × 27 squares).
struct SmallFrames {
    var t: [Double] = []
    var rgb: [[SIMD3<Float>]] = []
    var length = 0.0
    func grey(_ i: Int) -> [Float] { rgb[i].map { ($0.x + 2 * $0.y + $0.z) / 4 } }
    func index(_ time: Double) -> Int { min(max(0, Int((time * 12).rounded())), max(0, t.count - 1)) }

    init(_ url: URL, W: Int = LoopBlend.gw, H: Int = LoopBlend.gh) {
        let asset = AVURLAsset(url: url)
        length = CMTimeGetSeconds(asset.duration)
        guard let track = asset.tracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: asset) else { return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        r.add(out); r.startReading()
        var lastT = -1.0
        while let sb = out.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) {
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if time - lastT < 1.0 / 12 - 0.001 { continue }
            lastT = time
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), bpr = CVPixelBufferGetBytesPerRow(pb)
            var px = [SIMD3<Float>](repeating: .zero, count: W * H)
            for y in 0..<H { for x in 0..<W { let p = base + y * bpr + x * 4; px[y * W + x] = SIMD3(Float(p[2]), Float(p[1]), Float(p[0])) } }
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            t.append(time); rgb.append(px)
        }
        if !t.isEmpty, !(length.isFinite && length > 0) { length = t.last! + 1.0 / 12 }
    }
}

extension LoopVideo {
    /// The loop geometry the painter uses for a trim: start, period and the short dissolve (seconds into the clip).
    public static func loopTimes(_ trim: ClipTrim, length: Double) -> (start: Double, period: Double, fade: Double) {
        let s = max(0, trim.start), seconds = max(0.5, min(trim.end ?? length, length) - s)
        let f = min(trim.blend ?? clipBlend, seconds / 3)
        return (s, max(0.5, seconds - f), f)
    }

    /// Works out the blend for a clip's loop: which parts drift one way (and so get the slow dissolve), how long that dissolve can be inside the usable
    /// part of the clip, the colour drift, and how visible the join is. Takes about half a second.
    public static func loopBlend(_ url: URL, trim: ClipTrim) -> LoopBlend? { loopBlend(SmallFrames(url), trim: trim) }

    static func loopBlend(_ fr: SmallFrames, trim: ClipTrim) -> LoopBlend? {
        guard fr.t.count > 24 else { return nil }
        let length = fr.length, G = LoopBlend.gw * LoopBlend.gh
        let (s, P, f) = loopTimes(trim, length: length)
        let cs = max(0, trim.clean?.first ?? 0), ce = min(length, trim.clean?.last ?? length)
        // the slow dissolve: as long as the usable part allows on both sides of the loop's start point (never more than half a period each side)
        let before = max(0, min(s - cs, P / 2 - 0.25)), after = max(0, min(ce - (s + P) - 1.0 / 12, P / 2 - 0.25))
        // colour drift over one period, measured over the short dissolve (both sides are on screen then)
        func mean(_ i: Int) -> SIMD3<Float> { fr.rgb[i].reduce(.zero, +) / Float(G) }
        func smoothMean(_ time: Double) -> SIMD3<Float> {                // a second's average, so flicker and waves don't count
            let a = fr.index(time - 0.5), b = fr.index(time + 0.5)
            return (a...b).map(mean).reduce(.zero, +) / Float(b - a + 1)
        }
        var ratio = SIMD3<Float>(repeating: 0), n: Float = 0
        for k in stride(from: 0.0, through: f, by: 1.0 / 12) { ratio += smoothMean(s + P + k) / simd_max(smoothMean(s + k), SIMD3(repeating: 1)); n += 1 }
        var drift = ratio / max(n, 1)
        drift = simd_clamp(drift, SIMD3(repeating: 0.85), SIMD3(repeating: 1.15))
        if simd_reduce_max(simd_abs(drift - 1)) < 0.004 { drift = SIMD3(repeating: 1) }
        // with the colour lock applied, how far each square's end is from its start, against how much it changes by itself in a second
        func gain(_ time: Double) -> SIMD3<Float> { colourGain(drift, at: time, start: s, period: P) }
        func lockedGrey(_ i: Int) -> [Float] { let g = gain(fr.t[i]); return fr.rgb[i].map { let c = $0 * g; return (c.x + 2 * c.y + c.z) / 4 } }
        var seam = [Float](repeating: 0, count: G), natural = [Float](repeating: 0, count: G)
        var pairs: Float = 0
        for k in stride(from: 0.0, through: f, by: 1.0 / 12) {
            let a = lockedGrey(fr.index(s + k)), b = lockedGrey(fr.index(s + P + k))
            for x in 0..<G { seam[x] += abs(a[x] - b[x]) }
            pairs += 1
        }
        for x in 0..<G { seam[x] /= max(pairs, 1) }
        var steps: Float = 0
        let lo = fr.index(cs), hi = fr.index(ce) - 12
        if hi > lo {
            for i in stride(from: lo, to: hi, by: 3) {
                let a = lockedGrey(i), b = lockedGrey(i + 12)
                for x in 0..<G { natural[x] += abs(a[x] - b[x]) }
                steps += 1
            }
            for x in 0..<G { natural[x] /= steps }
        }
        // drifting parts: the join there differs much more than the part changes by itself; softened so the edges blend
        let slowFactor = Float(f / max(f, before + after))
        var m0 = (0..<G).map { x -> Float in
            let r = seam[x] / max(natural[x], 1.2)
            let v = min(1, max(0, (r - 1.6) / 1.6)); return v * v * (3 - 2 * v)
        }
        if before + after < f * 1.3 { m0 = [Float](repeating: 0, count: G) }       // no room for a slower dissolve: keep the normal one everywhere
        let mask = blur(blur(m0)).map { min(1, $0 * 1.25) }
        let share = Double(mask.reduce(0, +) / Float(G))
        // how visible the join is: the difference left at the join, weighted by how quickly it is dissolved, against the scene's own change
        var shown: Float = 0, total: Float = 0
        for x in 0..<G { shown += seam[x] * ((1 - mask[x]) + mask[x] * slowFactor); total += natural[x] }
        let score = Double(shown / max(total, Float(G) * 0.25))
        return LoopBlend(mask: mask, before: share > 0.002 ? before : 0, after: share > 0.002 ? after : 0, drift: drift, share: share, score: score)
    }

    /// The colour lock: the colour drift is spread evenly over the period, so the loop's end and start match. `time` is seconds into the clip.
    static func colourGain(_ drift: SIMD3<Float>, at time: Double, start: Double, period: Double) -> SIMD3<Float> {
        guard drift != SIMD3(repeating: 1) else { return SIMD3(repeating: 1) }
        let e = Float(-(time - start) / period)
        return SIMD3(pow(drift.x, e), pow(drift.y, e), pow(drift.z, e))
    }

    /// A soft 3 × 3 blur of a 48 × 27 map.
    static func blur(_ m: [Float]) -> [Float] {
        let W = LoopBlend.gw, H = LoopBlend.gh
        var out = m
        for y in 0..<H { for x in 0..<W {
            var s: Float = 0, n: Float = 0
            for dy in -1...1 { for dx in -1...1 { let xx = x + dx, yy = y + dy; if xx >= 0, xx < W, yy >= 0, yy < H { let w: Float = (dx == 0 && dy == 0) ? 2 : 1; s += m[yy * W + xx] * w; n += w } } }
            out[y * W + x] = s / n
        } }
        return out
    }

    // MARK: something turning that changes direction
    /// Times (seconds) where something that turns, like a water wheel, starts turning the other way for good. Reads the motion between neighbouring
    /// pictures (Apple Vision, 6 times a second, small) and looks around each spot: a turning thing moves round it on every side. Water that washes up
    /// a beach and back, or swaying grass, moves one way and then the other, which is natural, and is not counted. Takes a few seconds.
    public static func turnReversals(_ url: URL) -> [Double] {
        let W = 320, H = 180, GX = 32, GY = 18
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: asset) else { return [] }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        r.add(out); r.startReading()
        var pics: [(Double, CVPixelBuffer)] = [], lastT = -1.0
        while let sb = out.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if t - lastT < 1.0 / 12 - 0.001 { continue }
            lastT = t
            var copy: CVPixelBuffer?                                   // the reader hands its buffers back: keep a copy
            CVPixelBufferCreate(nil, W, H, kCVPixelFormatType_32BGRA, nil, &copy)
            guard let c = copy else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly); CVPixelBufferLockBaseAddress(c, [])
            let sbpr = CVPixelBufferGetBytesPerRow(pb), dbpr = CVPixelBufferGetBytesPerRow(c)
            for y in 0..<H { memcpy(CVPixelBufferGetBaseAddress(c)! + y * dbpr, CVPixelBufferGetBaseAddress(pb)! + y * sbpr, W * 4) }
            CVPixelBufferUnlockBaseAddress(c, []); CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            pics.append((t, c))
        }
        guard pics.count > 60 else { return [] }
        // the motion in each of 32 × 18 squares, in pixels (of a 320-wide picture) per second
        var cellV: [[SIMD2<Float>]] = [], times: [Double] = []
        for i in stride(from: 0, to: pics.count - 1, by: 2) {
            let req = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: pics[i + 1].1, options: [:])
            req.computationAccuracy = .medium
            req.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
            guard (try? VNImageRequestHandler(cvPixelBuffer: pics[i].1, options: [:]).perform([req])) != nil,
                  let fb = (req.results?.first as? VNPixelBufferObservation)?.pixelBuffer else { continue }
            CVPixelBufferLockBaseAddress(fb, .readOnly)
            let fw = CVPixelBufferGetWidth(fb), fh = CVPixelBufferGetHeight(fb), bpr = CVPixelBufferGetBytesPerRow(fb), base = CVPixelBufferGetBaseAddress(fb)!
            let perSecond = Float(W) / Float(fw) / Float(pics[i + 1].0 - pics[i].0)
            var v = [SIMD2<Float>](repeating: .zero, count: GX * GY), n = [Float](repeating: 0, count: GX * GY)
            for y in 0..<fh {
                let row = (base + y * bpr).assumingMemoryBound(to: Float.self)
                let cy = min(GY - 1, y * GY / fh)
                for x in 0..<fw { let c = cy * GX + min(GX - 1, x * GX / fw); v[c] += SIMD2(row[2 * x], row[2 * x + 1]); n[c] += 1 }
            }
            CVPixelBufferUnlockBaseAddress(fb, .readOnly)
            for k in 0..<(GX * GY) where n[k] > 0 { v[k] *= perSecond / n[k] }
            cellV.append(v); times.append(pics[i].0)
        }
        guard let L = times.last, L > 6.5 else { return [] }
        func side(_ d: SIMD2<Float>) -> Int { abs(d.x) >= abs(d.y) ? (d.x > 0 ? 0 : 2) : (d.y > 0 ? 1 : 3) }
        var hits: [(x: Int, y: Int, t: Double, strength: Float)] = []
        for cy in 0..<GY { for cx in 0..<GX { for rr in [1, 2] {
            var ring: [(cell: Int, dir: SIMD2<Float>)] = []
            for dy in -rr...rr { for dx in -rr...rr where max(abs(dx), abs(dy)) == rr {
                let nx = cx + dx, ny = cy + dy
                if nx >= 0, nx < GX, ny >= 0, ny < GY { ring.append((ny * GX + nx, simd_normalize(SIMD2(Float(dx), Float(dy))))) }
            } }
            guard ring.count == 8 * rr else { continue }
            // how much the ring moves round the spot, on each of its four sides
            let w = cellV.map { v in (0..<4).map { q in ring.filter { side($0.dir) == q }.reduce(Float(0)) { $0 + ($1.dir.x * v[$1.cell].y - $1.dir.y * v[$1.cell].x) } } }
            let m = cellV.map { v in (0..<4).map { q in ring.filter { side($0.dir) == q }.reduce(Float(0)) { $0 + simd_length(v[$1.cell]) } } }
            guard m.map({ $0.reduce(0, +) }).reduce(0, +) / Float(m.count * ring.count) > 0.6 else { continue }      // barely moving
            func turning(_ idx: ArraySlice<Int>) -> Float {         // signed; 0 unless it goes round the same way on every side
                let per = (0..<4).map { q in idx.reduce(Float(0)) { $0 + w[$1][q] } / max(1e-6, idx.reduce(Float(0)) { $0 + m[$1][q] }) }
                let total = per.reduce(0, +) / 4
                return per.allSatisfy({ $0 * total > 0 && abs($0) > 0.3 }) ? total : 0
            }
            let all = Array(times.indices)
            var best: (Double, Float)? = nil
            for T in stride(from: 3.0, through: L - 3, by: 0.5) {
                let split = times.firstIndex { $0 >= T } ?? times.count
                let c1 = turning(all[..<split]), c2 = turning(all[split...])
                if c1 * c2 < 0, abs(c1) > 0.5, abs(c2) > 0.5 { let st = min(abs(c1), abs(c2)); if best == nil || st > best!.1 { best = (T, st) } }
            }
            if let b = best { hits.append((cx, cy, b.0, b.1)) }
        } } }
        // one turning thing shows as a small patch of neighbouring spots that all change at the same moment (a sheared edge of surf is a thin line)
        var used = Set<Int>(), found: [Double] = []
        for h in hits.sorted(by: { $0.strength > $1.strength }) where !used.contains(h.y * GX + h.x) && h.strength >= 0.7 {
            let patch = hits.filter { abs($0.x - h.x) <= 3 && abs($0.y - h.y) <= 3 && abs($0.t - h.t) <= 0.75 }
            for p in patch { used.insert(p.y * GX + p.x) }
            let rows = Set(patch.map(\.y)).count, cols = Set(patch.map(\.x)).count
            guard patch.count >= 4, rows >= 2, cols >= 2 else { continue }
            let t = patch.map(\.t).sorted()[patch.count / 2]
            if !found.contains(where: { abs($0 - t) < 1.5 }) { found.append(t) }
        }
        return found.sorted()
    }
}
