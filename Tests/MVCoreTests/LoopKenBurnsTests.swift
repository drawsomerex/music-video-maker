import XCTest
import AVFoundation
import CoreGraphics
@testable import MVCore

/// A looping video's scene can be the picture with a slow pan and zoom instead of an AI clip: the camera follows a closed path, so the clip of
/// exactly one cycle (20 s) repeats without a seam, and the long video just plays it again and again like any other clip.
final class LoopKenBurnsTests: XCTestCase {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kenburns-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A picture of black and white stripes 50 px wide (so a zoom visibly moves them), `width` × `height`.
    private func stripes(_ dir: URL, name: String = "picture.png", width: Int = 1600, height: Int = 900) throws -> URL {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for k in 0..<(width / 50 + 2) {
            ctx.setFillColor(CGColor(gray: k % 2 == 0 ? 0 : 1, alpha: 1))
            ctx.fill(CGRect(x: k * 50, y: 0, width: 50, height: height))
        }
        let u = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(u as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return u
    }

    private func rgba(_ i: CGImage) -> (ctx: CGContext, d: UnsafeMutablePointer<UInt8>) {
        let c = CGContext(data: nil, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
        return (c, c.data!.assumingMemoryBound(to: UInt8.self))
    }

    /// The average difference between two pictures (0 = the same picture, 255 = black against white), sampled across the whole frame.
    private func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        let A = rgba(a), B = rgba(b)
        var sum = 0.0, n = 0.0
        for y in stride(from: 3, to: a.height - 3, by: 5) {
            for x in stride(from: 3, to: a.width - 3, by: 5) {
                let o = y * A.ctx.bytesPerRow + x * 4
                for k in 0..<3 { sum += abs(Double(A.d[o + k]) - Double(B.d[o + k])); n += 1 }
            }
        }
        return sum / max(n, 1)
    }

    private func frame(_ asset: AVURLAsset, _ time: CMTime) throws -> CGImage {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        return try gen.copyCGImage(at: time, actualTime: nil)
    }

    func testAKenBurnsClipIsTheRightLengthAndLoops() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("kenburns.mp4")
        try await LoopVideo.makeKenBurnsClip(picture: try stripes(dir), output: out)

        let asset = AVURLAsset(url: out)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await track!.load(.naturalSize)
        XCTAssertEqual(size.width, 1920); XCTAssertEqual(size.height, 1080)
        let length = CMTimeGetSeconds(try await asset.load(.duration))
        XCTAssertEqual(length, LoopVideo.kenBurnsSeconds, accuracy: 0.1, "one full cycle, so the clip can repeat as it is")

        let frames = Int((length * Double(LoopVideo.fps)).rounded())
        let first = try frame(asset, .zero)
        let last = try frame(asset, CMTime(value: CMTimeValue(frames - 1), timescale: CMTimeScale(LoopVideo.fps)))
        let middle = try frame(asset, CMTime(value: CMTimeValue(frames / 2), timescale: CMTimeScale(LoopVideo.fps)))
        XCTAssertLessThan(meanDifference(first, last), 6, "the camera comes back exactly where it began: no seam when the clip repeats")
        XCTAssertGreaterThan(meanDifference(first, middle), 20, "the picture moves: a slow pan and zoom, not a still")
    }

    func testAKenBurnsClipOfASquareCoverKeepsItsBlackBars() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("kenburns.mp4")
        // a square yellow cover, at a small size: the same geometry as 1080p, much quicker to encode
        let ctx = CGContext(data: nil, width: 1000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let pic = dir.appendingPathComponent("cover.png")
        let dest = CGImageDestinationCreateWithURL(pic as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)

        try await LoopVideo.makeKenBurnsClip(picture: pic, output: out, seconds: 4, width: 640, height: 360)
        let first = try frame(AVURLAsset(url: out), .zero)
        let A = rgba(first)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let o = y * A.ctx.bytesPerRow + x * 4
            return [A.d[o], A.d[o + 1], A.d[o + 2]]
        }
        XCTAssertEqual(first.width, 640); XCTAssertEqual(first.height, 360)
        XCTAssertLessThan(Int(pixel(20, 180)[0]), 25, "black bar at the left edge")
        XCTAssertLessThan(Int(pixel(620, 180)[0]), 25, "black bar at the right edge")
        let centre = pixel(320, 180)
        XCTAssertGreaterThan(centre[0], 200); XCTAssertGreaterThan(centre[1], 200, "the whole cover is shown, never cropped")
    }

    func testUseKenBurnsIsFreeAndPlaysItsWholeCycle() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try folder()
        let spend = dir.appendingPathComponent("spend.json")
        setenv("MV_PICTURES_DIR", lib.path, 1); setenv("MV_SPEND_FILE", spend.path, 1)
        defer { unsetenv("MV_PICTURES_DIR"); unsetenv("MV_SPEND_FILE"); try? FileManager.default.removeItem(at: lib) }

        let pic = try stripes(dir)
        var p = LoopProject(); p.title = "Test"; p.picture = pic.lastPathComponent
        try LoopVideo.save(p, dir)
        try await LoopVideo.useKenBurns(&p, dir: dir)

        let c = try XCTUnwrap(p.clip)
        XCTAssertTrue(p.clips.contains(c))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(c).path))
        XCTAssertEqual(p.versionCosts[c] ?? -1, 0)
        XCTAssertEqual(p.versionQualities[c], "Ken Burns (slow pan and zoom on the picture)")
        XCTAssertNil(p.clipWarning)
        let trim = try XCTUnwrap(p.trims[c])
        XCTAssertEqual(trim.start, 0, accuracy: 0.001)
        XCTAssertEqual(trim.end ?? 0, LoopVideo.kenBurnsSeconds, accuracy: 0.05)
        XCTAssertEqual(trim.blend ?? -1, 0, accuracy: 0.001)
        // what the painter will do with it: play the whole cycle and dissolve nothing at the join
        let length = CMTimeGetSeconds(AVURLAsset(url: dir.appendingPathComponent(c)).duration)
        let times = LoopVideo.loopTimes(trim, length: length)
        XCTAssertEqual(times.period, LoopVideo.kenBurnsSeconds, accuracy: 0.1)
        XCTAssertEqual(times.fade, 0, accuracy: 0.001)
        XCTAssertNotNil(p.loopScores[c], "the seamless join is rated like any other clip")
    }
}