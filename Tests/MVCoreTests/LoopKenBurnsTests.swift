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

        try await LoopVideo.makeKenBurnsClip(picture: pic, output: out, path: LoopVideo.KenBurnsPath(points: LoopVideo.KenBurnsPath.standard.points, seconds: 6), width: 640, height: 360)
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

    func testAPathNeedsTwoPointsAndLoopsThroughAnyNumberOfThem() {
        XCTAssertEqual(LoopVideo.KenBurnsPath(points: [LoopVideo.KenBurnsPoint()]).cleaned.points.count, 2, "never fewer than two points")
        XCTAssertEqual(LoopVideo.KenBurnsPath(points: []).cleaned.points.count, 2)
        let dirty = LoopVideo.KenBurnsPath(points: [.init(x: .nan, y: 7, zoom: 99), .init(x: -3, y: .infinity, zoom: 0.2)], seconds: .nan).cleaned
        for q in dirty.points { XCTAssertTrue((0...1).contains(q.x) && (0...1).contains(q.y) && (1...3).contains(q.zoom)) }
        XCTAssertTrue(dirty.seconds.isFinite)
        let path = LoopVideo.KenBurnsPath(points: [.init(x: 0.2, y: 0.3, zoom: 1), .init(x: 0.8, y: 0.3, zoom: 1.5), .init(x: 0.5, y: 0.8, zoom: 2), .init(x: 0.3, y: 0.6, zoom: 1.2)])
        // it passes through each point, in order
        for (k, q) in path.points.enumerated() {
            let c = path.camera(at: Double(k) / Double(path.points.count))
            XCTAssertEqual(c.x, q.x, accuracy: 0.001); XCTAssertEqual(c.y, q.y, accuracy: 0.001); XCTAssertEqual(c.zoom, q.zoom, accuracy: 0.001)
        }
        // and it comes back to the start without a jump (the step just before the end is as small as any other)
        let a = path.camera(at: 0.9999), b = path.camera(at: 0)
        XCTAssertEqual(a.x, b.x, accuracy: 0.01); XCTAssertEqual(a.y, b.y, accuracy: 0.01); XCTAssertEqual(a.zoom, b.zoom, accuracy: 0.02)
    }

    func testAThreePointPathMakesAClipThatLoopsAndMoves() async throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("kb3.mp4")
        let path = LoopVideo.KenBurnsPath(points: [.init(x: 0.3, y: 0.5, zoom: 1.6), .init(x: 0.7, y: 0.5, zoom: 1.6), .init(x: 0.5, y: 0.5, zoom: 1.0)], seconds: 6)
        // a smooth picture (light to dark across, with a bright patch), so a small move is a small difference
        let ctx = CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 1, alpha: 1)] as CFArray, locations: [0, 1])!, start: .zero, end: CGPoint(x: 1600, y: 0), options: [])
        let pic = dir.appendingPathComponent("gradient.png")
        let dest = CGImageDestinationCreateWithURL(pic as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        try await LoopVideo.makeKenBurnsClip(picture: pic, output: out, path: path, width: 640, height: 360)
        let asset = AVURLAsset(url: out)
        let length = try await asset.load(.duration).seconds
        XCTAssertEqual(length, 6, accuracy: 0.1)
        let first = try frame(asset, .zero), mid = try frame(asset, CMTime(seconds: 2, preferredTimescale: 600)), last = try frame(asset, CMTime(seconds: 5.9, preferredTimescale: 600))
        XCTAssertGreaterThan(meanDifference(first, mid), 10, "the picture moves between the points")
        XCTAssertLessThan(meanDifference(last, first), meanDifference(mid, first), "the end leads back to the start")
    }
}
