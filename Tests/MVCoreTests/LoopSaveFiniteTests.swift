import XCTest
import CoreGraphics
@testable import MVCore

/// A project must always be savable: no clip kind (generated-like, still, Ken Burns) may leave a number that JSON cannot hold.
final class LoopSaveFiniteTests: XCTestCase {
    private func picture(_ dir: URL) throws -> String {
        let ctx = CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for k in 0..<34 { ctx.setFillColor(CGColor(gray: k % 2 == 0 ? 0 : 1, alpha: 1)); ctx.fill(CGRect(x: k * 50, y: 0, width: 50, height: 900)) }
        let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("p.png") as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return "p.png"
    }
    func testStillAndKenBurnsProjectsEncode() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("savefinite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        var p = LoopProject(); p.picture = try picture(dir)
        try await LoopVideo.useStill(&p, dir: dir)
        XCTAssertNoThrow(try JSONEncoder().encode(p), "still: \(p.loopScores) \(p.loopDrift) \(p.trims)")
        try await LoopVideo.useKenBurns(&p, dir: dir)
        XCTAssertNoThrow(try JSONEncoder().encode(p), "kenburns: \(p.loopScores) \(p.loopDrift) \(p.trims)")
    }
}
