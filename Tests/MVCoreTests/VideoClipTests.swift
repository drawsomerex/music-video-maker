import XCTest
import CoreGraphics
@testable import MVCore

final class VideoClipTests: XCTestCase {
    /// Mean brightness 0…255 of a picture.
    func level(_ img: CGImage) -> Double {
        var px = [UInt8](repeating: 0, count: 64 * 36)
        let ctx = CGContext(data: &px, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 64, height: 36))
        return Double(px.reduce(0) { $0 + Int($1) }) / Double(px.count)
    }
    /// A test clip whose brightness rises with time (made by ffmpeg in /tmp; skipped when it is not there).
    /// The pictures read in order must match the ones picked one at a time.
    func testPicturesComeFromTheRightMoment() throws {
        let u = URL(fileURLWithPath: "/tmp/timeclip.mp4")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: u.path))
        let seq = VideoClipSource(url: u, maxPixel: 640)
        var out: [String] = []
        for t in Array(stride(from: 0.2, to: 9.5, by: 0.37)) + [1.0, 8.0, 0.5, 5.25] {      // in order (as when a video is made), then jumps (as in the preview)
            let fresh = VideoClipSource(url: u, maxPixel: 640)                                  // a new source answers its first request with the reader too, so compare to the generator
            let a = level(try XCTUnwrap(seq.frame(at: t))), g = level(try XCTUnwrap(fresh.generatorFrame(at: t)))
            out.append(String(format: "%.2f:%.0f/%.0f", t, a, g))
            XCTAssertEqual(a, g, accuracy: 3, "picture at \(t) s")
        }
        print(out.joined(separator: " "))
    }
}
