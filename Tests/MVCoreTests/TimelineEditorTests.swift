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
    func testOnlyTheMovedShortBoundaryIsClamped() {
        let original = ShortClip(name: "Long", start: 100, end: 280)
        var earlier = original; earlier.start = 90
        let adjusted = TimelineEditor.adjustedShort(earlier, from: original, duration: 300)
        XCTAssertEqual(adjusted.start, 100); XCTAssertEqual(adjusted.end, 280)
        var later = original; later.end = 290
        let end = TimelineEditor.adjustedShort(later, from: original, duration: 300)
        XCTAssertEqual(end.start, 100); XCTAssertEqual(end.end, 280)
        var move = original; move.start = 110; move.end = 290
        let shifted = TimelineEditor.adjustedShort(move, from: original, duration: 300)
        XCTAssertEqual(shifted.start, 110); XCTAssertEqual(shifted.end, 290)
    }
    func testLegacyTagOnlyLinesAreRemovedAndSectionIndicesRemapped() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("mv-legacy-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let lines = [LyricLine(id: 0, text: "[Chorus]", words: []), line(1, 2, 8), line(2, 12, 18)]
        var p = Plan(title: "Legacy", subject: "", audioPath: "", audioFile: "", songDuration: 20, lines: lines, intro: section(-1, 0, 4), sections: [section(0, 0, 20, [0, 1, 2])], description: "", style: "", introDuration: 4, audioOffset: 4, alignmentCoverage: 1)
        p.partStarts = [2]
        try Pipeline.savePlan(p, work)
        let loaded = try Pipeline.loadPlan(work)
        XCTAssertEqual(loaded.lines.map(\.id), [0, 1]); XCTAssertEqual(loaded.sections[0].lineIDs, [0, 1]); XCTAssertEqual(loaded.partStarts, [1])
    }
    func testJoiningKeepsDifferentTrimsOfSameVideo() {
        var left = section(0, 0, 10), right = section(1, 10, 20)
        var c = ImageCandidate(id: "same-video", provider: "local", thumbURL: "", fullURL: "", pageURL: "", width: 100, height: 100, credit: "", query: "", rank: 0)
        c.videoFile = "full/clip.mp4"; c.videoEnd = 2
        left.candidates = [c]; left.selected = 0
        c.videoStart = 2; c.videoEnd = 4
        right.candidates = [c]; right.selected = 0
        let joined = TimelineEditor.join([left, right], before: 1)
        XCTAssertEqual(joined[0].candidates.count, 2)
        XCTAssertNotEqual(joined[0].candidates[0].id, joined[0].candidates[1].id)
        XCTAssertEqual(joined[0].selectedCandidate?.videoEnd, 2)
    }
    func testInvalidSplitsAreNoOps() {
        let sections = [section(0, 0, 5)]
        for t in [Double.nan, Double.infinity, -1, 0, 0.1, 4.9, 5, 6] { XCTAssertEqual(TimelineEditor.split(sections, at: t, lines: []).count, 1) }
        XCTAssertEqual(TimelineEditor.join(sections, before: 0).count, 1)
    }

    func clip(_ file: String, seconds: Double, offset: Double, trimStart: Double = 0, trimEnd: Double? = nil) -> SectionClip {
        var c = SectionClip(); c.file = file; c.seconds = seconds; c.offset = offset; c.trimStart = trimStart; c.trimEnd = trimEnd; return c
    }
    func testPaidClipsStayWithOnePictureWhenSplit() {
        var a = section(0, 0, 20)
        a.clips = [clip("clips/a.mp4", seconds: 10, offset: 0)]; a.useClips = true; a.repeatClips = true
        let split = TimelineEditor.split([a], at: 12, lines: [])
        XCTAssertEqual(split[0].clips.count, 1)
        XCTAssertTrue(split[1].clips.isEmpty, "both halves must not play the same paid clip")
        XCTAssertFalse(split[1].useClips)
    }
    func testJoinKeepsBothPicturesClipsOneAfterTheOther() {
        var a = section(0, 0, 10), b = section(1, 10, 20)
        a.clips = [clip("clips/a.mp4", seconds: 10, offset: 0)]; a.useClips = true
        b.clips = [clip("clips/b.mp4", seconds: 10, offset: 0, trimStart: 2, trimEnd: 7)]; b.useClips = true
        let joined = TimelineEditor.join([a, b], before: 1)
        XCTAssertEqual(joined[0].clips.map(\.file), ["clips/a.mp4", "clips/b.mp4"])
        XCTAssertEqual(joined[0].clips[1].offset, 10, accuracy: 0.001)
        XCTAssertFalse(joined[0].repeatClips, "two clips never repeat")
    }
    func testClipPlaysOnlyTheChosenPartAndDefaultsDoNotLoop() {
        let c = clip("clips/a.mp4", seconds: 10, offset: 0, trimStart: 2, trimEnd: 7)
        XCTAssertEqual(c.playSeconds, 5, accuracy: 0.001)
        XCTAssertEqual(clip("x", seconds: 10, offset: 0).playSeconds, 10, accuracy: 0.001)
        XCTAssertFalse(section(0, 0, 10).repeatClips, "a clip never loops unless asked")
        var cand = ImageCandidate(id: "a", provider: "local", thumbURL: "", fullURL: "", pageURL: "", width: 1, height: 1, credit: "", query: "", rank: 0)
        cand.videoFile = "full/x.mov"
        XCTAssertFalse(cand.videoRepeat, "an imported clip never loops unless asked")
    }
    func testOldPlansWithClipsStillOpen() throws {
        let json = #"{"id":"c1","file":"clips/old.mp4","lastFrame":"frames/old.jpg","seconds":8,"offset":0,"prompt":"p","costUSD":0.3}"#
        let c = try JSONDecoder().decode(SectionClip.self, from: Data(json.utf8))
        XCTAssertEqual(c.trimStart, 0); XCTAssertNil(c.trimEnd); XCTAssertNil(c.focalAX)
    }
}
