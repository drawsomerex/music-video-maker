import XCTest
import AVFoundation
@testable import MVCore

/// Synthetic media only: no cloud orders, owner projects or installed-app preferences.
final class ClipSafetyTests: XCTestCase {
    func fixture(_ dir: URL, name: String, args: [String]) throws -> URL {
        let file = dir.appendingPathComponent(name)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg", "-v", "error", "-y"] + args + [file.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        return file
    }
    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mv-clip-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }; return dir
    }
    func testDurationAndBillingAreSharedAndBackwardCompatible() throws {
        for seconds in [3, 5, 8, 15] {
            let o = ClipOptions(seconds: seconds)
            XCTAssertEqual(o.generatedSeconds(), max(5, seconds))
            XCTAssertEqual(o.usedSeconds(), seconds)
            XCTAssertEqual(o.price(perSecond768: 0.036), Double(max(5, seconds)) * 0.036)
            XCTAssertEqual(ClipOptions(seconds: seconds, sharp: true).price(perSecond768: 0.036), Double(max(5, seconds)) * 0.10)
        }
        let old = try JSONDecoder().decode(LoopProject.self, from: Data(#"{"id":"old","title":"Old"}"#.utf8))
        XCTAssertNil(old.clipLength); XCTAssertFalse(old.sharpClip)
        XCTAssertEqual(ClipOptions().generatedSeconds(), 15)
    }
    func testHTMLAndHTTPErrorAreRejected() async throws {
        let url = URL(string: "https://example.com/clip.mp4")!
        for status in [200, 500] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
            do { try await OpenRouterVideo.validateDownload(Data(repeating: 65, count: 20_000), response: response); XCTFail("HTML accepted") }
            catch { }
        }
        XCTAssertTrue(OpenRouterVideo.trustedAPI(URL(string: "https://openrouter.ai/api/v1/videos/a")!))
        for value in ["http://openrouter.ai/x", "https://openrouter.ai.example.com/x", "https://other.com/x", "https://user@openrouter.ai/x"] {
            XCTAssertFalse(OpenRouterVideo.trustedAPI(URL(string: value)!))
        }
    }
    func testThreeFiveAndEightSecondClipsHaveAFeasibleLoop() async throws {
        let dir = try scratch()
        for seconds in [3, 5, 8] {
            let file = try fixture(dir, name: "clip-\(seconds).mp4", args: ["-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-t", "\(seconds)", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
            let result = try XCTUnwrap(LoopVideo.bestLoop(file))
            XCTAssertTrue(result.score.isFinite); XCTAssertLessThan(result.score, 90)
            let times = LoopVideo.loopTimes(result.trim, length: Double(seconds))
            XCTAssertGreaterThan(times.period, 0.5); XCTAssertLessThan(times.period, Double(seconds))
            XCTAssertLessThanOrEqual((result.trim.end ?? Double(seconds)), Double(seconds))
            let response = HTTPURLResponse(url: file, statusCode: 200, httpVersion: nil, headerFields: nil)!
            try await OpenRouterVideo.validateDownload(Data(contentsOf: file), response: response)
        }
    }
    func testCompressedRenderEndsAtChosenTimeAndFadesTheFinalScene() async throws {
        let dir = try scratch()
        _ = try fixture(dir, name: "blue.mp4", args: ["-f", "lavfi", "-i", "color=blue:size=320x180:rate=30", "-t", "3", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
        _ = try fixture(dir, name: "red.mp4", args: ["-f", "lavfi", "-i", "color=red:size=320x180:rate=30", "-t", "3", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
        _ = try fixture(dir, name: "song.wav", args: ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "14"])
        var p = LoopProject(); p.title = "Duration check"; p.hours = 100.0 / 3600; p.cards = .none
        p.tracks = [LoopTrack(file: "song.wav", title: "Test", seconds: 14)]; p.tracks[0].repeatMode = .minutes(15)
        p.analysis["song.wav"] = try LoopAudio.analyze(dir.appendingPathComponent("song.wav"))
        p.clips = ["blue.mp4", "red.mp4"]; p.clip = "blue.mp4"; p.sceneClips = p.clips; p.sceneChange = .time; p.sceneMinutes = 1
        let output = dir.appendingPathComponent("render.mp4")
        try await LoopVideo.render(p, dir: dir, output: output, W: 320, H: 180) { _, _ in }
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 100, accuracy: 1.0 / 30)
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        func rgb(_ time: Double) throws -> [UInt8] {
            let image = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
            var bytes = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return bytes
        }
        let before = try rgb(96), final = try rgb(99.9)
        XCTAssertGreaterThan(before[0], 180); XCTAssertLessThan(before[2], 40, "ending stays on the red second scene")
        XCTAssertLessThan(final.prefix(3).max() ?? 255, 30, "ending fades to black without returning to the first scene")
    }
}
