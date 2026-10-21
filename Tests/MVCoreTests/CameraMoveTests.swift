import XCTest
import CoreGraphics
@testable import MVCore

final class CameraMoveTests: XCTestCase {
    let iw = 1920.0, ih = 1080.0, bw = 1920.0, bh = 1080.0

    func scene(mode: Int, subjects: [CGPoint], tail: Bool = false, total: Double) -> PhotoScene {
        let s = PhotoScene(box: nil, a: 0, b: total, seed: 7, focus: CGPoint(x: 0.5, y: 0.5), preferredMode: mode)
        s.subjects = subjects; s.tail = tail; s.subjectsOrdered = true
        return s
    }
    /// The camera state at each tenth of a second.
    func samples(_ s: PhotoScene, total: Double) -> [(x: Double, y: Double, z: Double)] {
        let m = s.autoMove(iw: iw, ih: ih, bw: bw, bh: bh, total: total)
        return stride(from: 0.0, through: total, by: 0.1).map { PhotoScene.state(m, t: $0) }
    }
    func monotonic(_ v: [Double]) -> Bool { v == v.sorted() || v == v.sorted(by: >) }

    func testEveryMoveIsOneDirectionOnly() {
        let cases: [(Int, [CGPoint], Bool)] = [(0, [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.7)], false), (1, [CGPoint(x: 0.7, y: 0.4)], false),
                                                (2, [CGPoint(x: 0.3, y: 0.6), CGPoint(x: 0.6, y: 0.3)], true), (3, [], true), (4, [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.52, y: 0.5)], false)]
        for total in [2.0, 5.0, 9.0, 14.0, 25.0] { for (mode, subs, tail) in cases {
            let v = samples(scene(mode: mode, subjects: subs, tail: tail, total: total), total: total)
            XCTAssertTrue(monotonic(v.map(\.x)) && monotonic(v.map(\.y)) && monotonic(v.map(\.z)), "mode \(mode) tail \(tail) \(total) s: x, y and zoom each go one way only")
        } }
    }
    func testSpeedIsSteadyAndNeitherCrawlingNorRushing() {
        for total in [6.0, 10.0, 16.0, 30.0] {
            let s = scene(mode: 0, subjects: [CGPoint(x: 0.25, y: 0.4), CGPoint(x: 0.75, y: 0.6)], total: total)
            let v = samples(s, total: total), m = s.autoMove(iw: iw, ih: ih, bw: bw, bh: bh, total: total)
            // the cruise part (after the ease in, before the ease out)
            let mid = v.enumerated().filter { Double($0.offset) * 0.1 > m.ramp + 0.2 && Double($0.offset) * 0.1 < total - m.ramp - 0.2 }.map(\.element)
            let speeds = zip(mid, mid.dropFirst()).map { a, b in max(hypot((b.x - a.x) * iw, (b.y - a.y) * ih) * a.z / bw / 0.1, abs(log(b.z / a.z)) / 0.1 * 1.6) }
            let hi = speeds.max() ?? 0, lo = speeds.min() ?? 0
            XCTAssertLessThan(hi, 0.11, "\(total) s: never faster than a calm sweep (\(hi))")
            XCTAssertLessThan(hi / max(lo, 1e-9), 1.05, "\(total) s: the speed is constant while it cruises")
            if total <= 16 { XCTAssertGreaterThan(hi, 0.025, "\(total) s: fast enough to see (\(hi))") }
        }
    }
    func testMoveStaysInsideThePicture() {
        for total in [3.0, 12.0, 30.0] { for mode in 0..<5 {
            let s = scene(mode: mode, subjects: [CGPoint(x: 0.05, y: 0.95), CGPoint(x: 0.95, y: 0.05)], total: total)
            for p in samples(s, total: total) {
                let hw = 0.5 * bw / iw / p.z, hh = 0.5 * bh / ih / p.z
                XCTAssertTrue(p.x - hw >= -1e-6 && p.x + hw <= 1 + 1e-6 && p.y - hh >= -1e-6 && p.y + hh <= 1 + 1e-6 && p.z >= 1 - 1e-9)
            }
        } }
    }
    func testAfterAClipTheCameraStartsOnTheFullFrame() {
        let s = scene(mode: 0, subjects: [CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.7, y: 0.5)], tail: true, total: 10)
        let first = samples(s, total: 10).first!
        XCTAssertEqual(first.z, 1.0, accuracy: 1e-9); XCTAssertEqual(first.x, 0.5, accuracy: 1e-9); XCTAssertEqual(first.y, 0.5, accuracy: 1e-9)
    }
}
