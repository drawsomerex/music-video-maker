import XCTest
import CoreGraphics
@testable import MVCore

/// Outside photos that aren't 16:9. The extend step is checked without the picture maker: an upright slice of a widescreen picture is "extended"
/// with that widescreen picture shifted a little (the way a painted version never lines up exactly); the result must line the two up again and
/// keep the slice untouched. The picture is copied to /tmp/fit-full.png (skipped when it is not there).
final class PictureFitTests: XCTestCase {
    func testTheShapeIsRecognised() {
        XCTAssertEqual(PictureFit.cropRect(aspect: 0.75).height, 0.75 / (16.0 / 9), accuracy: 0.001, "a portrait photo: the full width, a band of its height")
        XCTAssertEqual(PictureFit.cropRect(aspect: 2.4).width, (16.0 / 9) / 2.4, accuracy: 0.001)
        XCTAssertEqual(PictureFit.cropRect(aspect: 0.75, centre: CGPoint(x: 0.5, y: 0)).minY, 0, "dragged to the top: stops at the edge")
    }

    func testExtendingKeepsThePhotoAndLinesUpTheNewSides() throws {
        let u = URL(fileURLWithPath: "/tmp/fit-full.png")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: u.path))
        let full = try XCTUnwrap(loadImage(u, maxPixel: 1536))                 // 1536 × 864
        let slice = try XCTUnwrap(full.cropping(to: CGRect(x: 468, y: 0, width: 600, height: 864)))
        let dx = 14.0, dy = 9.0                                                  // the painted version is off by this much (right, down)
        let painted = try XCTUnwrap(PictureFit.canvas(1536, 864) { $0.draw(full, in: CGRect(x: dx, y: -dy, width: 1536, height: 864)) })
        let out = try XCTUnwrap(PictureFit.composite(slice, painted: painted))
        XCTAssertEqual(out.width, 1536); XCTAssertEqual(out.height, 864)
        func px(_ img: CGImage) -> [UInt8] {
            var b = [UInt8](repeating: 0, count: img.width * img.height * 4)
            let c = CGContext(data: &b, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height)); return b
        }
        let a = px(out), b = px(full)
        func diff(_ xs: Range<Int>) -> Double {                                   // mean difference from the true widescreen picture in columns xs
            var s = 0.0, n = 0.0
            for y in 30..<834 { for x in xs { for k in 0..<3 { s += abs(Double(a[(y * 1536 + x) * 4 + k]) - Double(b[(y * 1536 + x) * 4 + k])); n += 1 } } }
            return s / n
        }
        let photo = diff(520..<1010), seam = diff(440..<500), side = diff(60..<400)
        print(String(format: "difference from the true picture: photo %.2f, at the join %.2f, new side %.2f", photo, seam, side))
        XCTAssertLessThan(photo, 1.5, "the photo itself is untouched")
        XCTAssertLessThan(seam, 4, "the new side lines up with the photo at the join")
        XCTAssertLessThan(side, 4, "and is moved back into place")
    }
}
