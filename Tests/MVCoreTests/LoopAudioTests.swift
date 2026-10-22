import XCTest
@testable import MVCore

/// Uses test songs made by ffmpeg in /tmp/pl (skipped when they are not there): one that fades out, one that stops hard, one that is very quiet.
final class LoopAudioTests: XCTestCase {
    func url(_ n: String) -> URL { URL(fileURLWithPath: "/tmp/pl/" + n) }
    func analyses() throws -> [TrackAnalysis] {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/pl/fades.wav"))
        return try ["fades.wav", "hardstop.wav", "quiet.mp3"].map { try LoopAudio.analyze(url($0)) }
    }

    func testListeningFindsLoudnessAndEndings() throws {
        let a = try analyses()
        // ffmpeg's EBU R128 meter says −21.4, −16.1 and −38.6 LUFS
        XCTAssertEqual(a[0].loudness, -21.4, accuracy: 1.0); XCTAssertEqual(a[1].loudness, -16.1, accuracy: 1.0); XCTAssertEqual(a[2].loudness, -38.6, accuracy: 1.0)
        XCTAssertTrue(a[0].fadesOut, "the first song fades out over its last 10 s"); XCTAssertFalse(a[1].fadesOut, "the second stops at full volume")
        XCTAssertTrue(a[1].hardStart, "the second starts at full volume"); XCTAssertFalse(a[2].hardStart, "the third fades in")
    }

    func testEverySongPlaysWholeAndTheVideoNeverCutsOne() throws {
        let a = try analyses()
        for mode in LoopTransition.allCases {
            let plan = LoopAudio.plan(analyses: a, transition: mode, crossfade: 6, gap: 2, evenVolume: true, shuffle: true, minimum: 600, seed: 42)
            XCTAssertGreaterThanOrEqual(plan.songsEnd, 600, "\(mode): at least the chosen length")
            XCTAssertLessThan(plan.plays.dropLast().last!.end, 600, "\(mode): it stops at the first song that reaches the length")
            for p in plan.plays { XCTAssertEqual(p.length, a[p.track].length, accuracy: 0.001, "\(mode): no song is shortened") }
            XCTAssertEqual(plan.total, plan.songsEnd + 3, accuracy: 0.001)
            // shuffled rounds never play the same song twice in a row
            for (x, y) in zip(plan.plays, plan.plays.dropFirst()) { XCTAssertNotEqual(x.track, y.track) }
            XCTAssertEqual(plan.firstRound.map(\.track), [0, 1, 2], "the first time through is in your order")
        }
    }

    func testJoins() throws {
        let a = try analyses()
        let auto = LoopAudio.plan(analyses: a, transition: .automatic, crossfade: 6, gap: 2, evenVolume: true, shuffle: false, minimum: 100, seed: 1).plays
        XCTAssertLessThan(auto[1].start, auto[0].end, "after a song that fades out, the next starts during the fade")
        XCTAssertEqual(auto[1].fadeIn, 0, "a song that opens with a hit is never faded in")
        XCTAssertEqual(auto[2].start, auto[1].end + 2, accuracy: 0.001, "after a clean stop: a 2-second pause")
        let gaps = LoopAudio.plan(analyses: a, transition: .albumGaps, crossfade: 6, gap: 1.5, evenVolume: true, shuffle: false, minimum: 100, seed: 1).plays
        XCTAssertEqual(gaps[1].start, gaps[0].end + 1.5, accuracy: 0.001)
        let cf = LoopAudio.plan(analyses: a, transition: .crossfade, crossfade: 8, gap: 2, evenVolume: true, shuffle: false, minimum: 100, seed: 1).plays
        XCTAssertEqual(cf[0].end - cf[1].start, 8, accuracy: 0.001)
        // loudness: the quiet song is raised toward the others
        XCTAssertGreaterThan(auto[2].gain, 3)
    }

    func testTheMixHasNoGapsInsideBlendsAndNeverClips() throws {
        let a = try analyses()
        let plan = LoopAudio.plan(analyses: a, transition: .seamless, crossfade: 6, gap: 2, evenVolume: true, shuffle: false, minimum: 120, seed: 1)
        let mixer = LoopAudio.Mixer(urls: ["fades.wav", "hardstop.wav", "quiet.mp3"].map(url), plan: plan)
        var buf = [Float](repeating: 0, count: 4800 * 2), peak: Float = 0, quietest = Float.greatestFiniteMagnitude
        let frames = Int(plan.songsEnd * 48000) - 48000
        var f = 48000
        while f < frames {
            try mixer.fill(&buf, start: f, count: 4800)
            var e: Float = 0
            for v in buf { peak = max(peak, abs(v)); e += v * v }
            quietest = min(quietest, (e / Float(buf.count)).squareRoot())
            f += 4800
        }
        XCTAssertLessThanOrEqual(peak, 1.0, "never clips")
        XCTAssertGreaterThan(quietest, 0.005, "Seamless: no silent moment between songs")
    }

    func testEachSongOnceIsOneTimeThroughWhateverTheLength() throws {
        let a = try analyses()
        for mode in LoopTransition.allCases {
            let plan = LoopAudio.plan(analyses: a, transition: mode, crossfade: 6, gap: 2, evenVolume: true, shuffle: true, minimum: 36000, seed: 7, onePass: true)
            XCTAssertEqual(plan.plays.map(\.track), [0, 1, 2], "\(mode): every song exactly once, in your order")
            XCTAssertLessThan(plan.total, 200, "\(mode): the video is as long as the album, not the hours")
        }
        let one = LoopAudio.plan(analyses: [a[0]], transition: .seamless, crossfade: 6, gap: 2, evenVolume: true, shuffle: false, minimum: 36000, seed: 7, onePass: true)
        XCTAssertEqual(one.plays.count, 1); XCTAssertEqual(one.total, a[0].length + 3, accuracy: 0.001)
    }
}
