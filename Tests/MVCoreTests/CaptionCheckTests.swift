import XCTest
@testable import MVCore

final class CaptionCheckTests: XCTestCase {
    /// 16 kHz samples: silence with a 220 Hz tone wherever `bursts` say (seconds).
    func pcm(_ seconds: Double, bursts: [(Double, Double)]) -> [Int16] {
        var out = [Int16](repeating: 0, count: Int(seconds * 16000))
        for (a, b) in bursts { for i in Int(a * 16000)..<min(out.count, Int(b * 16000)) { out[i] = Int16(8000 * sin(2 * Double.pi * 220 * Double(i) / 16000)) } }
        return out
    }
    func line(_ i: Int, _ start: Double, _ len: Double = 2) -> LyricLine {
        LyricLine(id: i, text: "line \(i)", words: [TimedWord(text: "la", start: start, end: start + len / 2), TimedWord(text: "la", start: start + len / 2, end: start + len)])
    }

    func testLineStartingInSilenceMovesToTheNearestSound() {
        let env = CaptionCheck.envelope(pcm(60, bursts: [(5, 8), (12, 15), (30, 33), (40, 44)]))
        let r = CaptionCheck.run(lines: [line(0, 5.1), line(1, 12.05), line(2, 28.6), line(3, 40.2)], env: env, songDuration: 60)
        XCTAssertEqual(r.moved, [2]); XCTAssertTrue(r.unresolved.isEmpty)
        XCTAssertEqual(r.lines[2].start, 30.0, accuracy: 0.08, "moved onto the start of the sound")
        XCTAssertEqual(r.lines[0].start, 5.1, accuracy: 0.001, "lines that start on the music are not touched")
        XCTAssertEqual(r.soundEnd, 44, accuracy: 0.2)
        XCTAssertTrue(r.summary.contains("moved onto the music"))
    }
    func testLinesAfterTheMusicEndedAreReportedNotInvented() {
        let env = CaptionCheck.envelope(pcm(60, bursts: [(5, 8), (12, 15)]))
        let r = CaptionCheck.run(lines: [line(0, 5.1), line(1, 12.05), line(2, 55)], env: env, songDuration: 60)
        XCTAssertEqual(r.unresolved, [2]); XCTAssertEqual(r.lines[2].start, 55, accuracy: 0.001)
        XCTAssertTrue(r.summary.contains("could not be placed"))
    }
    func testNothingChangesWhenEveryLineStartsOnTheMusic() {
        let env = CaptionCheck.envelope(pcm(60, bursts: [(5, 8), (12, 15), (20, 24)]))
        let lines = [line(0, 5.05), line(1, 12.0), line(2, 20.3)]
        let r = CaptionCheck.run(lines: lines, env: env, songDuration: 60)
        XCTAssertTrue(r.moved.isEmpty); XCTAssertEqual(r.lines, lines); XCTAssertTrue(r.summary.hasPrefix("Checked all 3 captions"))
    }
    func testLineEndsNeverRunIntoTheNextLine() {
        let env = CaptionCheck.envelope(pcm(60, bursts: [(5, 30)]))
        var a = line(0, 5.0, 8); a.words[1].end = 14          // runs past the start of the next line
        let r = CaptionCheck.run(lines: [a, line(1, 10)], env: env, songDuration: 60)
        XCTAssertLessThanOrEqual(r.lines[0].end, r.lines[1].start)
    }
    func testSilentSongCannotBeChecked() {
        let r = CaptionCheck.run(lines: [line(0, 1)], env: CaptionCheck.envelope(pcm(30, bursts: [])), songDuration: 30)
        XCTAssertEqual(r.checked, 0)
    }
    func testOldPlansWithoutACaptionCheckStillOpen() throws {
        XCTAssertNil(try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(Plan(title: "t", subject: "", audioPath: "", audioFile: "", songDuration: 60, lines: [], intro: PhotoSection(id: -1, start: 0, end: 1, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 0), sections: [], description: "", style: "", introDuration: 0, audioOffset: 0, alignmentCoverage: 1))).captionCheck)
    }
}

/// Checks real projects' captions against their songs. Runs only with MV_REAL_PROJECTS="dir1:dir2" (copies of project folders).
final class CaptionCheckRealTests: XCTestCase {
    func testRealProjects() async throws {
        let dirs = (ProcessInfo.processInfo.environment["MV_REAL_PROJECTS"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        try XCTSkipIf(dirs.isEmpty, "set MV_REAL_PROJECTS")
        for d in dirs {
            var plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: Pipeline.planURL(d)))
            let before = plan.lines
            let r = await Pipeline.checkCaptions(plan: &plan, work: d)
            print("REAL", d.lastPathComponent, "timing:", plan.timing, "lines:", before.count, "duration:", plan.songDuration, "soundEnd:", r?.soundEnd ?? -1)
            print("REAL summary:", plan.captionCheck ?? "nil")
            for i in (r?.moved ?? []) + (r?.unresolved ?? []) { print("REAL line", i + 1, before[i].text.prefix(30), "was", String(format: "%.2f", before[i].start), "now", String(format: "%.2f", plan.lines[i].start)) }
            if let l = plan.lines.last { print("REAL last line starts", String(format: "%.2f", l.start), "ends", String(format: "%.2f", l.end)) }
        }
    }
}
