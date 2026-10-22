import XCTest
@testable import MVCore

final class ProjectLibraryTests: XCTestCase {
    func testScanFindsBothKindsQuickly() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("mvproj-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        // a lyric project nested in its song folder, and a looping project
        let song = root.appendingPathComponent("Song A/Song A – project"); try fm.createDirectory(at: song, withIntermediateDirectories: true)
        let s = PhotoSection(id: -1, start: 0, end: 4, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 0)
        let plan = Plan(title: "Song A", subject: "", audioPath: "", audioFile: "", songDuration: 20, lines: [], intro: s, sections: [s], description: "", style: "", introDuration: 4, audioOffset: 0, alignmentCoverage: 1)
        setenv("MV_SPEND_FILE", root.appendingPathComponent("spend.json").path, 1); defer { unsetenv("MV_SPEND_FILE") }
        try Pipeline.savePlan(plan, song)
        let loop = root.appendingPathComponent("Rain – looping video"); try fm.createDirectory(at: loop, withIntermediateDirectories: true)
        var lp = LoopProject(); lp.title = "Rain"; LoopVideo.save(lp, loop)
        let t0 = Date()
        let found = ProjectLibrary.scan(root: root)
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1)
        XCTAssertEqual(Set(found.map(\.title)), ["Song A", "Rain"])
        XCTAssertEqual(found.first { $0.title == "Song A" }?.trashTarget(root: root).lastPathComponent, "Song A", "a song's own folder (with its videos) goes to the Trash, never the main folder")
        XCTAssertEqual(found.first { $0.title == "Rain" }?.trashTarget(root: root).lastPathComponent, "Rain – looping video")
    }

    /// A clip whose second half is its own mirror image (made by ffmpeg in /tmp; skipped when it is not there): found, and the loop keeps the first half.
    func testMirroredClipIsFoundAndTheRightWayRoundPartKept() throws {
        let u = URL(fileURLWithPath: "/tmp/mirrored.mp4")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: u.path))
        let c = LoopVideo.checkClip(u)
        XCTAssertEqual(c.mirrors.count, 1); XCTAssertEqual(c.mirrors.first ?? 0, 7.5, accuracy: 0.2)
        XCTAssertEqual(c.best?.start ?? -1, 0, accuracy: 0.01); XCTAssertEqual(c.best?.end ?? 0, 7.4, accuracy: 0.2)
    }
}
