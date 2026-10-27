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
        XCTAssertFalse(try XCTUnwrap(OpenRouterVideo.downloadLocation(["unsigned_urls": [], "urls": ["https://storage.example.com/signed.mp4?token=example"]])).authenticated)
        XCTAssertTrue(try XCTUnwrap(OpenRouterVideo.downloadLocation(["unsigned_urls": ["https://openrouter.ai/clip"], "urls": []])).authenticated)
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
    func testMovieSourceTimeMatchesAcrossShortsSplitsAndJoins() throws {
        let dir = try scratch()
        _ = try fixture(dir, name: "time.mp4", args: ["-f", "lavfi", "-i", "testsrc2=size=160x90:rate=30", "-t", "20", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
        let empty = PhotoSection(id: -1, start: 0, end: 0, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 1)
        for generated in [false, true] { for repeats in [false, true] {
            var part = PhotoSection(id: 0, start: 0, end: 20, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 2)
            if generated {
                var clip = SectionClip(); clip.file = "time.mp4"; clip.seconds = 20; clip.trimStart = 1.25; clip.trimEnd = 18.25
                part.clips = [clip]; part.useClips = true; part.repeatClips = repeats
            } else {
                var candidate = ImageCandidate(id: "movie", provider: "local", thumbURL: "", fullURL: "", pageURL: "", width: 160, height: 90, credit: "", query: "", rank: 0)
                candidate.videoFile = "time.mp4"; candidate.videoStart = 1.25; candidate.videoEnd = 18.25; candidate.videoRepeat = repeats
                part.candidates = [candidate]; part.selected = 0
            }
            var plan = Plan(title: "Time", subject: "", audioPath: "", audioFile: "", songDuration: 20, lines: [], intro: empty, sections: [part], description: "", style: "", introDuration: 0, audioOffset: 0, alignmentCoverage: 1)
            var settings = VideoSettings(height: 90); settings.width = 160
            var short = ShortClip(name: "Window", start: 8, end: 16); short.dynamic = false; short.loop = false
            func pixels(_ image: CGImage) -> [UInt8] {
                var bytes = [UInt8](repeating: 0, count: 64 * 36 * 4)
                let context = CGContext(data: &bytes, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 36)); return bytes
            }
            let reference = pixels(FrameComposer(plan: plan, work: dir, settings: settings).still(at: 10))
            for edit in 0..<3 {
                if edit == 1 { plan.sections = TimelineEditor.split(plan.sections, at: 7, lines: []) }
                if edit == 2 { plan.sections = TimelineEditor.join(plan.sections, before: 1) }
                let actual = pixels(FrameComposer(plan: plan, work: dir, settings: settings, short: short).still(at: 2))
                let difference = zip(reference, actual).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
                XCTAssertLessThan(Double(difference) / Double(actual.count), 2, "generated=\(generated), repeats=\(repeats), edit=\(edit)")
            }
        } }
    }

}
