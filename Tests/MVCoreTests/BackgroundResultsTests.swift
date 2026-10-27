import XCTest
@testable import MVCore

final class BackgroundResultsTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mv-results-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("MV_SPEND_FILE", dir.appendingPathComponent("spend.json").path, 1)
    }
    override func tearDownWithError() throws { unsetenv("MV_SPEND_FILE"); try? FileManager.default.removeItem(at: dir) }
    func section(_ start: Double, _ end: Double) -> PhotoSection { PhotoSection(id: 0, start: start, end: end, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 1) }
    func plan() -> Plan {
        var plan = Plan(title: "Before", subject: "", audioPath: dir.appendingPathComponent("song.wav").path, audioFile: "song.wav", songDuration: 30, lines: [], intro: section(0, 0), sections: [section(0, 10), section(10, 20), section(20, 30)], description: "", style: "", introDuration: 0, audioOffset: 0, alignmentCoverage: 1)
        plan.projectID = "owned"; return plan
    }
    func candidate(_ id: String = "same") -> ImageCandidate { ImageCandidate(id: id, provider: "local", thumbURL: "", fullURL: "", pageURL: "", width: 100, height: 100, credit: "", query: "", rank: 0) }
    func testNewAndLegacyProjectsKeepAStableTaskIdentity() throws {
        var fresh = plan(); fresh.projectID = Plan(title: "New", subject: "", audioPath: "", audioFile: "", songDuration: 5, lines: [], intro: section(0, 0), sections: [], description: "", style: "", introDuration: 0, audioOffset: 0, alignmentCoverage: 1).projectID
        XCTAssertFalse(fresh.projectID.isEmpty)
        try Pipeline.savePlan(fresh, dir); XCTAssertEqual(try Pipeline.loadPlan(dir).projectID, fresh.projectID)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh)) as! [String: Any]
        legacy.removeValue(forKey: "projectID"); try JSONSerialization.data(withJSONObject: legacy).write(to: Pipeline.planURL(dir))
        let opened = try Pipeline.loadPlan(dir)
        XCTAssertFalse(opened.projectID.isEmpty); XCTAssertEqual(try Pipeline.loadPlan(dir).projectID, opened.projectID)
    }
    func testPaidPictureResultPreservesInterveningSavedEdits() throws {
        let before = plan(); try Pipeline.savePlan(before, dir)
        var edited = before; edited.title = "After"; edited.sections[0].prompt = "My new idea"
        let chosen = candidate("user"); edited.sections[0].candidates = [chosen]; edited.sections[0].selected = 0
        try Pipeline.savePlan(edited, dir)
        var done = before; done.sections[0].candidates = [candidate("paid")]; done.sections[0].selected = 0; done.totalGenerationCostUSD = 0.07
        try Pipeline.saveMediaResult(done, startedFrom: before, section: 0, work: dir, artwork: true)
        let saved = try Pipeline.loadPlan(dir)
        XCTAssertEqual(saved.title, "After"); XCTAssertEqual(saved.sections[0].prompt, "My new idea")
        XCTAssertEqual(saved.sections[0].selectedCandidate?.id, "user")
        XCTAssertEqual(Set(saved.sections[0].candidates.map(\.id)), ["user", "paid"])
        XCTAssertEqual(saved.totalGenerationCostUSD, 0.07)
    }
    func testLoopResultMergesOnlyOwnedFieldsAndCostDelta() throws {
        let before = LoopProject(); try LoopVideo.saveChecked(before, dir)
        var edited = before; edited.title = "User title"; edited.hours = 8; edited.motion = "My motion"
        try LoopVideo.saveChecked(edited, dir)
        var done = before; done.pictures = ["paid.jpg"]; done.picture = "paid.jpg"; done.motion = "Old automatic motion"; done.imagesUSD = 0.08; done.pictureCount = 1
        try LoopVideo.saveMediaResult(done, startedFrom: before, dir: dir)
        let saved = try LoopVideo.load(dir)
        XCTAssertEqual(saved.title, "User title"); XCTAssertEqual(saved.hours, 8); XCTAssertEqual(saved.motion, "My motion")
        XCTAssertEqual(saved.picture, "paid.jpg"); XCTAssertEqual(saved.imagesUSD, 0.08); XCTAssertEqual(saved.pictureCount, 1)
    }
    func testPendingLoopLedgerSurvivesProjectSavesAndKeepsMultipleOrders() throws {
        var p = LoopProject(); try LoopVideo.saveChecked(p, dir)
        try LoopVideo.recordLoopJob(.init(id: "job-one", options: .init(seconds: 3, sharp: true)), dir: dir)
        try LoopVideo.recordLoopJob(.init(id: "job-two", options: .init(seconds: 8)), dir: dir)
        p.title = "Changed after Stop"; p.pendingJob = nil; try LoopVideo.saveChecked(p, dir)
        XCTAssertEqual(LoopVideo.pendingLoopJobs(dir).map(\.id), ["job-one", "job-two"])
        XCTAssertEqual(LoopVideo.pendingLoopJobs(dir).first?.options.generatedSeconds(), 5)
        try LoopVideo.removeLoopJob("job-one", dir: dir)
        XCTAssertEqual(LoopVideo.pendingLoopJobs(dir).map(\.id), ["job-two"])
    }
    func testReassignSameIDMovesDistinctTrimAndCamera() {
        var a = section(0, 10), b = section(10, 20)
        var first = candidate(), second = first
        first.videoStart = 1; first.camStartX = 0.2; second.videoStart = 5; second.camStartX = 0.8
        a.candidates = [first]; b.candidates = [second]; a.selected = 0; b.selected = 0
        let swapped = TimelineEditor.reassign([a, b], from: 0, to: 1)
        XCTAssertEqual(swapped[1].selectedCandidate?.videoStart, 1); XCTAssertEqual(swapped[0].selectedCandidate?.camStartX, 0.8)
        XCTAssertNotEqual(swapped[1].candidates[0].id, swapped[1].selectedCandidate?.id)
    }
    func testJoinedMediaEditsReachRenderedChildren() {
        var a = section(0, 10), b = section(10, 20)
        var c = candidate(); c.videoFile = "movie.mp4"; a.candidates = [c]; a.selected = 0
        var clip = SectionClip(); clip.file = "paid.mp4"; clip.seconds = 8; b.clips = [clip]; b.useClips = true
        var joined = TimelineEditor.join([a, b], before: 1)[0]
        var updated = c; updated.videoStart = 2; updated.camStartX = 0.1
        TimelineEditor.replaceCandidate(c, with: updated, in: &joined)
        TimelineEditor.editMedia(&joined) { s in for i in s.clips.indices { s.clips[i].trimStart = 1 }; s.repeatClips = true }
        let children = TimelineEditor.renderSections([joined])
        XCTAssertEqual(children[0].selectedCandidate?.videoStart, 2)
        XCTAssertEqual(children[0].selectedCandidate?.camStartX, 0.1)
        XCTAssertEqual(children[1].clips.first?.trimStart, 1); XCTAssertTrue(children[1].repeatClips)
    }
    func testShortKeepsBoundaryFootageAndChecksOnlyRenderedFiles() throws {
        var p = plan(); var a = candidate("a"), b = candidate("b"), bad = candidate("outside")
        a.videoFile = "a.mp4"; b.videoFile = "b.mp4"; bad.fullFile = "missing.jpg"
        p.sections[0].candidates = [a]; p.sections[1].candidates = [b]; p.sections[2].candidates = [bad]
        for i in p.sections.indices { p.sections[i].selected = 0 }
        p.intro.candidates = [bad]; p.intro.selected = 0
        for name in ["song.wav", "a.mp4", "b.mp4"] { try Data([0]).write(to: dir.appendingPathComponent(name)) }
        let short = ShortClip(name: "Extract", start: 8, end: 20)
        let clipped = FrameComposer.clip(p, to: short)
        XCTAssertEqual(clipped.sections.map(\.duration), [2, 10]); XCTAssertEqual(clipped.sections.map(\.playbackOffset), [8, 0])
        XCTAssertTrue(ExportHealth.music(p, work: dir, short: short).errors.isEmpty)
        XCTAssertFalse(ExportHealth.music(p, work: dir).errors.isEmpty)
    }
    func movie() throws -> Data {
        let file = dir.appendingPathComponent("fixture.mp4")
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-t", "5", "-c:v", "libx264", "-pix_fmt", "yuv420p", file.path]
        task.standardError = FileHandle.nullDevice; try task.run(); task.waitUntilExit(); XCTAssertEqual(task.terminationStatus, 0)
        return try Data(contentsOf: file)
    }
    func testMusicRecoveryRetainsOriginalWithoutActivatingItAndWaitsForLiveAcknowledgement() async throws {
        var p = plan(); var old = SectionClip(); old.file = "already-approved.mp4"; old.seconds = 5
        p.sections[0].clips = [old]; p.sections[0].useClips = true; try Pipeline.savePlan(p, dir)
        try Pipeline.savePending([.init(job: "accepted", section: 0, seconds: 5, offset: 5, prompt: "Test", started: Date(), usedSeconds: 3)], work: dir)
        let data = try movie(); var config = Config(); config.projectsFolder = dir.path
        let notes = await Pipeline.recoverPendingClips(plan: &p, work: dir, config: config, fetch: { _, _ in .finished(data, 0.18) })
        XCTAssertEqual(notes.count, 1); XCTAssertEqual(p.sections[0].clips.map(\.id), [old.id])
        XCTAssertEqual(p.sections[0].retainedClips.count, 1); XCTAssertEqual(p.sections[0].retainedClips[0].trimEnd, 3)
        XCTAssertEqual(Pipeline.pendingClipJobs(work: dir).count, 1, "core completion cannot clear recovery before live-state acknowledgement")
        try Pipeline.savePlan(p, dir); try Pipeline.acknowledgeClip("accepted", work: dir)
        XCTAssertTrue(Pipeline.pendingClipJobs(work: dir).isEmpty)
        XCTAssertEqual(p.totalVideoCostUSD, 0.18)
    }
    func testLoopRecoveryUsesAcceptedOptionsAndIsIdempotent() async throws {
        var p = LoopProject(); p.clipLength = 8; try LoopVideo.saveChecked(p, dir)
        try LoopVideo.recordLoopJob(.init(id: "paid-loop", options: .init(seconds: 3, sharp: true)), dir: dir)
        let data = try movie(); var config = Config(); config.projectsFolder = dir.path; config.videoRealismCheck = false
        _ = await LoopVideo.recoverClip(&p, dir: dir, config: config, fetch: { _, _ in .finished(data, 0.5) })
        let file = try XCTUnwrap(p.clip)
        XCTAssertEqual(p.clips.count, 1); XCTAssertLessThanOrEqual(p.trims[file]?.end ?? 100, 3)
        XCTAssertEqual(LoopVideo.pendingLoopJobs(dir).count, 1)
        _ = await LoopVideo.recoverClip(&p, dir: dir, config: config, fetch: { _, _ in .finished(data, 0.5) })
        XCTAssertEqual(p.clips.count, 1); XCTAssertEqual(p.videoUSD, 0.5, "same job never charges the project ledger twice")
        try LoopVideo.acknowledgeLoopJobs(p, dir: dir)
        XCTAssertTrue(LoopVideo.pendingLoopJobs(dir).isEmpty)
    }

}
