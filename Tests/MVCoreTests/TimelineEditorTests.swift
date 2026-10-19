import XCTest
@testable import MVCore

final class TimelineEditorTests: XCTestCase {
    func line(_ id: Int, _ start: Double, _ end: Double) -> LyricLine { LyricLine(id: id, text: "Line \(id)", words: [TimedWord(text: "word", start: start, end: end)]) }
    func section(_ id: Int, _ start: Double, _ end: Double, _ lines: [Int] = []) -> PhotoSection { PhotoSection(id: id, start: start, end: end, lineIDs: lines, queries: [], candidates: [], selected: -1, seed: UInt64(bitPattern: Int64(id))) }
    func testJoinRemovesAutomaticBoundaryInsteadOfAddingDivider() {
        let lines = (0..<4).map { line($0, Double($0 * 15), Double($0 * 15 + 14)) }
        let original = Planner.structure(lines: lines, stanzaBreaks: [], songDuration: 60)
        XCTAssertEqual(original.count, 2)
        let joined = TimelineEditor.join(original, before: 1)
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined[0].lineIDs, [0, 1, 2, 3])
        let restored = TimelineEditor.applying([], to: original, lines: lines, duration: 60)
        XCTAssertEqual(restored.count, 1, "An explicit empty cut list must remain one picture")
    }
    func testMusicCanSplitAndJoinAcrossSingingWithoutChangingOtherBoundaries() {
        let lines = [line(0, 10, 20), line(1, 40, 50)]
        let original = [section(0, 0, 10), section(1, 10, 25, [0]), section(2, 25, 40), section(3, 40, 60, [1])]
        let split = TimelineEditor.split(original, at: 30, lines: lines)
        XCTAssertEqual(split.map(\.start), [0, 10, 25, 30, 40])
        let joined = TimelineEditor.join(split, before: 3)
        XCTAssertEqual(joined.map(\.start), original.map(\.start))
        let mixed = TimelineEditor.join(joined, before: 2)
        XCTAssertEqual(mixed.map(\.start), [0, 10, 40])
        XCTAssertEqual(mixed[1].lineIDs, [0])
    }
    func testArtworkSurvivesSplittingAndJoining() {
        var a = section(0, 0, 10), b = section(1, 10, 20)
        var first = ImageCandidate(id: "a", provider: "local", thumbURL: "", fullURL: "", pageURL: "", width: 100, height: 100, credit: "", query: "", rank: 0)
        first.fullFile = "full/a.png"
        var second = first; second.id = "b"; second.fullFile = "full/b.png"; second.videoFile = "full/b.mov"
        a.candidates = [first]; a.selected = 0; b.candidates = [second]; b.selected = 0
        let split = TimelineEditor.split([a, b], at: 5, lines: [])
        XCTAssertEqual(split[0].selectedCandidate, split[1].selectedCandidate)
        let joined = TimelineEditor.join([a, b], before: 1)
        XCTAssertEqual(joined[0].selectedCandidate?.id, "a")
        XCTAssertEqual(joined[0].candidates.count, 2)
        XCTAssertEqual(joined[0].candidates[1].videoFile, "full/b.mov")
    }
    func testShortSplitIsContinuousAndIndependent() throws {
        let c = ShortClip(name: "Clip", start: 10, end: 70)
        let pieces = try TimelineEditor.splitShort(c, at: 30)
        XCTAssertEqual(pieces.count, 2); XCTAssertNotEqual(pieces[0].id, pieces[1].id)
        XCTAssertEqual(pieces[0].start, 10); XCTAssertEqual(pieces[0].end, pieces[1].start); XCTAssertEqual(pieces[1].end, 70)
        XCTAssertEqual(pieces[0].styleSeed, c.styleSeed); XCTAssertEqual(pieces[1].styleSeed, c.styleSeed)
        XCTAssertThrowsError(try TimelineEditor.splitShort(c, at: 10))
        XCTAssertThrowsError(try TimelineEditor.splitShort(c, at: .nan))
    }
    func testShortJoinIncludesGapAndEnforcesThreeMinutes() throws {
        let a = ShortClip(name: "A", start: 0, end: 20), b = ShortClip(name: "B", start: 40, end: 80)
        let joined = try TimelineEditor.joinShorts(a, b)
        XCTAssertEqual(joined.start, 0); XCTAssertEqual(joined.end, 80)
        XCTAssertThrowsError(try TimelineEditor.joinShorts(a, ShortClip(name: "Too far", start: 170, end: 200)))
    }
    func testManualBoundariesSurvivePersistenceAndRetiming() throws {
        let lines = [line(0, 1, 9), line(1, 12, 19)]
        let sections = [section(0, 0, 10, [0]), section(1, 10, 20, [1])]
        var p = Plan(title: "Test", subject: "", audioPath: "", audioFile: "", songDuration: 20, lines: lines, intro: section(-1, 0, 4), sections: sections, description: "", style: "", introDuration: 4, audioOffset: 4, alignmentCoverage: 1)
        p.pictureBoundaries = []; p.shorts = [ShortClip(name: "Keep", start: 2, end: 15)]
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        XCTAssertEqual(decoded.pictureBoundaries, [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); json.removeValue(forKey: "pictureBoundaries")
        XCTAssertNil(try JSONDecoder().decode(Plan.self, from: JSONSerialization.data(withJSONObject: json)).pictureBoundaries)
        let moved = TimelineEditor.assignLines(sections, lines: [line(0, 2, 8), line(1, 8, 18)])
        XCTAssertEqual(moved.map(\.start), [0, 10]); XCTAssertEqual(moved[0].lineIDs, [0, 1])
        p.sections = TimelineEditor.join(sections, before: 1)
        XCTAssertEqual(p.shorts, decoded.shorts)
    }
    func testNestedAndUnclosedTagsAndOldTimedWords() {
        XCTAssertEqual(LyricText.clean("Sing [soft (very quiet)] now"), "Sing now")
        XCTAssertEqual(LyricText.clean("Sing [unfinished"), "Sing")
        let words = ["Sing", "[soft", "voice]", "now"].enumerated().map { TimedWord(text: $0.element, start: Double($0.offset), end: Double($0.offset + 1)) }
        XCTAssertEqual(LyricText.cleanWords(words).map(\.text), ["Sing", "now"])
        let raw = "[Verse]\nFirst\n[Chorus]\nSecond"
        XCTAssertEqual(LyricText.rows(raw).map(\.index), [0, 1])
        XCTAssertEqual(LyricAligner.parse(raw).lines, ["First", "Second"])
    }
    func testCleanupKeepsUnselectedPicturesAndVideos() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("mv-cleanup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work.appendingPathComponent("full"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
        var a = ImageCandidate(id: "a", provider: "local", thumbURL: "", fullURL: "", pageURL: "", width: 100, height: 100, credit: "", query: "", rank: 0)
        a.fullFile = "full/section_a.png"; a.thumbFile = "thumbs/section_a.png"
        var b = a; b.id = "b"; b.fullFile = "full/section_b.png"; b.thumbFile = "thumbs/section_b.png"; b.videoFile = "full/section_b.mov"
        let files = [a.fullFile!, a.thumbFile!, b.fullFile!, b.thumbFile!, b.videoFile!]
        for file in files + ["full/section_unused.png"] { try Data([1]).write(to: work.appendingPathComponent(file)) }
        var s = section(0, 0, 20); s.candidates = [a, b]; s.selected = 0
        var p = Plan(title: "Test", subject: "", audioPath: "", audioFile: "", songDuration: 20, lines: [], intro: section(-1, 0, 4), sections: [s], description: "", style: "", introDuration: 4, audioOffset: 4, alignmentCoverage: 1)
        p.sourceLyrics = "[Verse]\nWords (softly)\n\nNext verse"
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.sourceLyrics, p.sourceLyrics)
        Pipeline.cleanupUnreferencedImages(plan: p, work: work)
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: work.appendingPathComponent(file).path)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("full/section_unused.png").path))
    }
    func testInvalidSplitsAreNoOps() {
        let sections = [section(0, 0, 5)]
        for t in [Double.nan, Double.infinity, -1, 0, 0.1, 4.9, 5, 6] { XCTAssertEqual(TimelineEditor.split(sections, at: t, lines: []).count, 1) }
        XCTAssertEqual(TimelineEditor.join(sections, before: 0).count, 1)
    }
}
