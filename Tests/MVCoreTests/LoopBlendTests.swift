import XCTest
import CoreGraphics
@testable import MVCore

/// The loop fixes: parts that drift one way dissolve slowly, the colour lock, and something turning that changes direction.
/// The clips are made by a script in /tmp (each test is skipped when its clip is not there):
///   drift.mp4          top half: a cloud-like texture sliding slowly one way; bottom half: ripples swaying back and forth; the whole picture brightens 6 %
///   wheel-reverse.mp4  a real clip with a spoked wheel that turns one way, then the other way from 7 s
///   wheel-steady.mp4   the same wheel turning one way the whole time
///   waves-reverse.mp4  a real beach clip whose sea runs backwards after 7 s (back-and-forth water is natural, so it is not counted)
final class LoopBlendTests: XCTestCase {
    func clip(_ name: String) throws -> URL {
        let u = URL(fileURLWithPath: "/tmp/\(name)")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: u.path), "\(name) is made by the test-clip script")
        return u
    }
    /// Mean brightness of each half of a picture drawn by the loop painter.
    func draw(_ painter: LoopVideo.LoopPainter, at t: Double, W: Int = 96, H: Int = 54) -> (top: Double, bottom: Double, all: Double, px: [UInt8]) {
        var px = [UInt8](repeating: 0, count: W * H * 4)
        let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        painter.draw(loopTime: t, ctx: ctx)
        func level(_ rows: Range<Int>) -> Double {
            var s = 0.0
            for y in rows { for x in 0..<W { let i = (y * W + x) * 4; s += (Double(px[i]) + 2 * Double(px[i + 1]) + Double(px[i + 2])) / 4 } }
            return s / Double(rows.count * W)
        }
        return (level(0..<(H / 2)), level((H / 2)..<H), level(0..<H), px)          // the bitmap's first row is the top of the picture
    }

    func testOnlyTheDriftingPartGetsTheSlowDissolve() throws {
        let u = try clip("drift.mp4")
        let r = try XCTUnwrap(LoopVideo.bestLoop(u))
        let b = try XCTUnwrap(LoopVideo.loopBlend(u, trim: r.trim))
        let W = LoopBlend.gw, H = LoopBlend.gh
        let top = b.mask[0..<(W * H / 2 - W)].reduce(0, +) / Float(W * H / 2 - W), bottom = b.mask[(W * H / 2 + W)...].reduce(0, +) / Float(W * H / 2 - W)
        print(String(format: "slow dissolve: top %.2f, bottom %.2f, %.1f s; score %.2f", top, bottom, b.slowSeconds, r.score))
        XCTAssertGreaterThan(top, 0.7, "the sliding sky dissolves slowly")
        XCTAssertLessThan(bottom, 0.15, "the swaying ripples keep the short dissolve")
        XCTAssertGreaterThan(b.slowSeconds, 2 * (r.trim.blend ?? 1.6), "much slower than the normal dissolve")
        XCTAssertEqual(Double(b.drift.y), 1 + 0.06 * (r.trim.end! - r.trim.start - r.trim.blend!) / 15, accuracy: 0.012, "the brightening over one period is measured")
    }

    /// As the loop comes round, the sky is already part way through its slow dissolve; the ripples are only starting theirs.
    func testThePainterBlendsOnlyTheDriftingPart() throws {
        let u = try clip("drift.mp4")
        let r = try XCTUnwrap(LoopVideo.bestLoop(u))
        let painter = LoopVideo.LoopPainter(clip: u, W: 192, H: 108, title: nil, trim: r.trim)
        let b = try XCTUnwrap(painter.blend)
        XCTAssertGreaterThan(b.before, 0.5)
        let shot = painter.shot(0)
        XCTAssertNotNil(shot.late); XCTAssertNotNil(shot.early)
        let map = try XCTUnwrap(shot.map, "a map of how much of the beginning shows")
        var px = [UInt8](repeating: 0, count: LoopBlend.gw * LoopBlend.gh)
        let ctx = CGContext(data: &px, width: LoopBlend.gw, height: LoopBlend.gh, bitsPerComponent: 8, bytesPerRow: LoopBlend.gw, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(map, in: CGRect(x: 0, y: 0, width: LoopBlend.gw, height: LoopBlend.gh))
        let half = LoopBlend.gw * LoopBlend.gh / 2
        let top = Double(px[0..<half].reduce(0) { $0 + Int($1) }) / Double(half), bottom = Double(px[half...].reduce(0) { $0 + Int($1) }) / Double(half)
        print(String(format: "beginning shows: sky %.0f/255, ripples %.0f/255", top, bottom))
        XCTAssertGreaterThan(top, 25); XCTAssertLessThan(bottom, 5)
    }

    /// A grey map clips what is drawn: white shows it, black hides it (the way the slow dissolve is drawn).
    func testAMapShowsWhereItIsWhite() {
        var m: [UInt8] = [255, 0]
        let map = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                          provider: CGDataProvider(data: CFDataCreate(nil, &m, 2))!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        var px = [UInt8](repeating: 0, count: 2 * 4)
        let ctx = CGContext(data: &px, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        ctx.clip(to: CGRect(x: 0, y: 0, width: 2, height: 1), mask: map)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        XCTAssertEqual(px[0], 255, "white: drawn"); XCTAssertEqual(px[4], 0, "black: hidden")
    }

    /// The clip brightens 6 % over 15 s. With the colour lock that is spread over the whole loop, so it never pulses at the join.
    func testTheColourLockSpreadsTheBrightening() throws {
        let u = try clip("drift.mp4")
        let r = try XCTUnwrap(LoopVideo.bestLoop(u))
        let painter = LoopVideo.LoopPainter(clip: u, W: 96, H: 54, title: nil, trim: r.trim)
        let n = Int(painter.period * 30)
        let levels = (0..<(n + 30)).map { draw(painter, at: Double($0 % n) / 30).all }            // one period and a second past the join
        let steps = zip(levels, levels.dropFirst()).map { abs($1 - $0) }
        print(String(format: "brightness %.1f–%.1f, largest step %.2f", levels.min()!, levels.max()!, steps.max()!))
        XCTAssertLessThan(levels.max()! - levels.min()!, 2.5, "no build-up and drop: without the lock the picture would brighten about 5 levels and fall back at the join")
        XCTAssertLessThan(steps.max()!, 0.4)
    }

    func testAWheelThatTurnsTheOtherWayIsFound() throws {
        let c = LoopVideo.checkClip(try clip("wheel-reverse.mp4"))
        XCTAssertEqual(c.turns.count, 1); XCTAssertEqual(c.turns.first ?? 0, 7, accuracy: 0.6)
        let best = try XCTUnwrap(c.best)
        XCTAssertGreaterThan((best.end ?? c.length) - best.start, 6.5, "the loop keeps to one side of it")
        XCTAssertTrue(best.start >= 7 || (best.end ?? c.length) <= 7, "and never spans the change")
        XCTAssertNotNil(best.clean)
    }

    func testASteadyWheelAndWaterThatGoesBackAndForthAreLeftAlone() throws {
        XCTAssertEqual(LoopVideo.turnReversals(try clip("wheel-steady.mp4")), [])
        XCTAssertEqual(LoopVideo.turnReversals(try clip("waves-reverse.mp4")), [], "water going one way and then the other is natural (surf does it)")
        XCTAssertEqual(LoopVideo.turnReversals(try clip("drift.mp4")), [])
    }
}
