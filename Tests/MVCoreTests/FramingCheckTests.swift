import XCTest
import CoreGraphics
@testable import MVCore

final class FramingCheckTests: XCTestCase {
    /// A picture with a bright blob at (cx, cy) on a darker background (coordinates 0…1), 320×180.
    func picture(cx: Double, cy: Double, radius: Double = 0.18, bar: Bool = false) -> CGImage {
        let w = 320, h = 180
        var px = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let dx = Double(x) / Double(w) - cx, dy = Double(y) / Double(h) - cy
            var v = 60.0 + 40.0 * Double(y) / Double(h)
            if (dx * dx * 3 + dy * dy * 3).squareRoot() < radius * 1.7 { v = 230 }
            if bar && x > w * 3 / 4 { v = 20 }
            px[y * w + x] = UInt8(min(255, v))
        } }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return ctx.makeImage()!
    }
    func testSameFramingIsFlagged() {
        let a = picture(cx: 0.4, cy: 0.5), b = picture(cx: 0.41, cy: 0.5)
        let s = FramingCheck.score(a, b)
        XCTAssertTrue(FramingCheck.tooSimilar(luma: s.luma, edge: s.edge), "luma \(s.luma) edge \(s.edge)")
    }
    func testDifferentFramingIsNotFlagged() {
        let a = picture(cx: 0.25, cy: 0.35), b = picture(cx: 0.75, cy: 0.7, radius: 0.08, bar: true)
        let s = FramingCheck.score(a, b)
        XCTAssertFalse(FramingCheck.tooSimilar(luma: s.luma, edge: s.edge), "luma \(s.luma) edge \(s.edge)")
    }
    func testWarningOnlyAppliesToTheSamePreviousPicture() {
        var c = ImageCandidate(id: "a", provider: "", thumbURL: "", fullURL: "", pageURL: "", width: 1, height: 1, credit: "", query: "", rank: 0)
        c.framingLuma = 0.9; c.framingEdge = 0.7; c.framingAgainst = "full/a.jpg"
        XCTAssertTrue(c.looksLikePrevious("full/a.jpg"))
        XCTAssertFalse(c.looksLikePrevious("full/other.jpg"), "the picture before was replaced, so the old warning no longer applies")
        XCTAssertFalse(ImageCandidate(id: "b", provider: "", thumbURL: "", fullURL: "", pageURL: "", width: 1, height: 1, credit: "", query: "", rank: 0).looksLikePrevious("full/a.jpg"))
    }

    func testBackfillSavesPicturesAndClipsWithProperNames() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("mvlib-\(UUID().uuidString)")
        let work = root.appendingPathComponent("song"), lib = root.appendingPathComponent("lib")
        try fm.createDirectory(at: work.appendingPathComponent("full"), withIntermediateDirectories: true)
        try fm.createDirectory(at: work.appendingPathComponent("clips"), withIntermediateDirectories: true)
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data([1]).write(to: work.appendingPathComponent("full/a.png")); try Data([2]).write(to: work.appendingPathComponent("clips/c1.mp4")); try Data([3]).write(to: work.appendingPathComponent("clips/c2.mp4"))
        setenv("MV_PICTURES_DIR", lib.path, 1); defer { unsetenv("MV_PICTURES_DIR") }
        var cand = ImageCandidate(id: "a", provider: "", thumbURL: "", fullURL: "", pageURL: "", width: 1, height: 1, credit: "", query: "", rank: 0); cand.fullFile = "full/a.png"
        var sec = PhotoSection(id: 0, start: 4, end: 20, lineIDs: [], queries: [], candidates: [cand], selected: 0, seed: 1)
        var c1 = SectionClip(); c1.file = "clips/c1.mp4"; var c2 = SectionClip(); c2.file = "clips/c2.mp4"; sec.clips = [c1, c2]
        let intro = PhotoSection(id: -1, start: 0, end: 4, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 0)
        var plan = Plan(title: "My Song", subject: "", audioPath: "", audioFile: "", songDuration: 20, lines: [], intro: intro, sections: [sec], description: "", style: "", introDuration: 4, audioOffset: 4, alignmentCoverage: 1)
        XCTAssertEqual(PictureLibrary.backfill(plan: &plan, work: work), 3)
        let pic = try XCTUnwrap(plan.sections[0].candidates[0].libraryName)
        XCTAssertTrue(pic.hasSuffix("My Song 001.png"), pic)
        let base = (pic as NSString).deletingPathExtension
        XCTAssertEqual(plan.sections[0].clips.map(\.libraryName), [base + " clip 1.mp4", base + " clip 2.mp4"])
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: lib.path)), [pic, base + " clip 1.mp4", base + " clip 2.mp4"])
        XCTAssertEqual(PictureLibrary.backfill(plan: &plan, work: work), 0, "running it again adds nothing")
    }
}
