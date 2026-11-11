import XCTest
import AVFoundation
import CoreGraphics
@testable import MVCore

final class LoopStillTests: XCTestCase {
    func testLengthWords() {
        XCTAssertEqual(LoopVideo.lengthWords(LoopVideo.tenMinutes), "10 minutes")
        XCTAssertEqual(LoopVideo.lengthWords(0.5), "30 minutes")
        XCTAssertEqual(LoopVideo.lengthWords(1), "1 hour")
        XCTAssertEqual(LoopVideo.lengthWords(3, dash: true), "3-hour")
        XCTAssertEqual(LoopVideo.lengthWords(LoopVideo.tenMinutes, dash: true), "10-minute")
        XCTAssertEqual(LoopVideo.lengthWords(1.5), "1.5 hours")
        XCTAssertEqual(YouTubeKit.hoursText(LoopVideo.tenMinutes), "10 Minutes")
    }

    func testAStillClipIsPlayableAndSteady() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("still-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // a 1600 × 900 picture: red left half, blue right half
        let ctx = CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 900))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 800, y: 0, width: 800, height: 900))
        let pic = dir.appendingPathComponent("picture.png")
        let dest = CGImageDestinationCreateWithURL(pic as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        let out = dir.appendingPathComponent("still.mp4")
        try await LoopVideo.makeStillClip(picture: pic, output: out)
        let asset = AVURLAsset(url: out)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 1920); XCTAssertEqual(size.height, 1080)
        let length = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertEqual(length, LoopVideo.stillSeconds, accuracy: 0.1)
        let gen = AVAssetImageGenerator(asset: asset)
        let first = try gen.copyCGImage(at: .zero, actualTime: nil), last = try gen.copyCGImage(at: CMTime(seconds: 3.5, preferredTimescale: 600), actualTime: nil)
        func px(_ i: CGImage, _ x: Int) -> [UInt8] {
            let c = CGContext(data: nil, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
            let d = c.data!.assumingMemoryBound(to: UInt8.self), o = (i.height / 2 * c.bytesPerRow) + x * 4
            return [d[o], d[o + 1], d[o + 2]]
        }
        XCTAssertGreaterThan(px(first, 400)[0], 200); XCTAssertGreaterThan(px(first, 1500)[2], 200)
        for x in [400, 1500] { for (a, b) in zip(px(first, x), px(last, x)) { XCTAssertEqual(Int(a), Int(b), accuracy: 6, "a still stays the same for its whole length") } }
    }
}

/// Makes a real 10-minute album video from a still picture in a copy of a looping project. Runs only with MV_REAL_LOOP=<copy of a project folder>.
final class LoopStillRealTests: XCTestCase {
    func testTenMinuteAlbumFromAStill() async throws {
        let path = ProcessInfo.processInfo.environment["MV_REAL_LOOP"] ?? ""
        try XCTSkipIf(path.isEmpty, "set MV_REAL_LOOP")
        let dir = URL(fileURLWithPath: path)
        var p = try LoopVideo.load(dir)
        try await LoopVideo.useStill(&p, dir: dir)
        XCTAssertNotNil(p.clip)
        p.hours = LoopVideo.tenMinutes; p.playOnce = false
        try LoopVideo.ensureAnalysis(&p, dir: dir)
        let plan = try XCTUnwrap(LoopVideo.plan(p))
        print("STILL plan total:", plan.total, "songs:", p.tracks.count, "clip:", p.clip ?? "-", "warning:", p.clipWarning ?? "none")
        let out = dir.appendingPathComponent("test-10min.mp4")
        let t0 = Date()
        try await LoopVideo.render(p, dir: dir, output: out) { _, _ in }
        let asset = AVURLAsset(url: out)
        let dur = CMTimeGetSeconds(try await asset.load(.duration))
        let bytes = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int64) ?? 0
        print("STILL rendered:", dur, "s in", Date().timeIntervalSince(t0), "s,", bytes / 1_000_000, "MB")
        XCTAssertEqual(dur, 600, accuracy: 1.5)
        let l = await VideoRenderer.lengths(of: out)
        print("STILL lengths:", String(describing: l))
    }
}

final class PictureBarsTests: XCTestCase {
    func square(_ dir: URL) throws -> URL {
        let ctx = CGContext(data: nil, width: 1000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let u = dir.appendingPathComponent("cover.png")
        let d = CGImageDestinationCreateWithURL(u as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
        return u
    }
    func pixel(_ i: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let c = CGContext(data: nil, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
        let d = c.data!.assumingMemoryBound(to: UInt8.self), o = y * c.bytesPerRow + x * 4
        return [d[o], d[o + 1], d[o + 2]]
    }
    func testASquareCoverGetsBlackBarsAndIsNotCropped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bars-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("framed.jpg")
        try PictureFit.bars(try square(dir), output: out)
        let img = try XCTUnwrap(loadImage(out, maxPixel: 4000))
        XCTAssertEqual(Double(img.width) / Double(img.height), 16.0 / 9, accuracy: 0.01)
        XCTAssertLessThan(Int(pixel(img, 30, img.height / 2)[0]), 12, "black at the left edge")
        XCTAssertLessThan(Int(pixel(img, img.width - 30, img.height / 2)[0]), 12, "black at the right edge")
        let centre = pixel(img, img.width / 2, img.height / 2); XCTAssertGreaterThan(centre[0], 200); XCTAssertGreaterThan(centre[1], 200)
        XCTAssertLessThan(Int(pixel(img, img.width / 2, 4)[2]), 80, "the cover reaches the top and bottom: nothing is cropped, nothing is added above")
        XCTAssertFalse(PictureFit.needsFitting(out), "the framed picture is widescreen")
    }
    func testAStillClipOfASquareCoverHasBars() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("barclip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("still.mp4")
        try await LoopVideo.makeStillClip(picture: try square(dir), output: out)
        let frame = try AVAssetImageGenerator(asset: AVURLAsset(url: out)).copyCGImage(at: .zero, actualTime: nil)
        XCTAssertLessThan(Int(pixel(frame, 40, frame.height / 2)[0]), 25); XCTAssertGreaterThan(pixel(frame, frame.width / 2, frame.height / 2)[0], 200)
    }
}
