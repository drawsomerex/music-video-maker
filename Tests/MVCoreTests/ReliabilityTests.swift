import XCTest
@testable import MVCore

final class UpdateSwapTests: XCTestCase {
    /// Runs the real script with a stand-in `open`, in a temp folder.
    private func run(appBehaviour: String) throws -> (installed: String, note: String?, backupKept: Bool) {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin"), work = root.appendingPathComponent("work")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true); try fm.createDirectory(at: work, withIntermediateDirectories: true)
        func app(_ url: URL, _ name: String) throws {
            let m = url.appendingPathComponent("Contents/MacOS"); try fm.createDirectory(at: m, withIntermediateDirectories: true)
            try name.write(to: url.appendingPathComponent("name"), atomically: true, encoding: .utf8)
            let exe = m.appendingPathComponent("MusicVideoApp")
            try "#!/bin/sh\nsleep \(name == "new" ? appBehaviour : "3")\n".write(to: exe, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        }
        let dest = root.appendingPathComponent("My App.app"), new = work.appendingPathComponent("new.app"), backup = root.appendingPathComponent("My App.app.backup"), note = root.appendingPathComponent("note")
        try app(dest, "old"); try app(new, "new")
        let open = bin.appendingPathComponent("open")
        try "#!/bin/sh\n\"$1/Contents/MacOS/MusicVideoApp\" >/dev/null 2>&1 &\nexit 0\n".write(to: open, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)
        let script = root.appendingPathComponent("swap.sh"); try UpdateSwap.script.write(to: script, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.environment = ["PATH": bin.path + ":/usr/bin:/bin"]
        p.arguments = [script.path, "999999", new.path, dest.path, backup.path, work.path, "", "", note.path, "9.9.9", "6", "6"]
        try p.run(); p.waitUntilExit()
        return (try String(contentsOf: dest.appendingPathComponent("name"), encoding: .utf8), try? String(contentsOf: note, encoding: .utf8), fm.fileExists(atPath: backup.path))
    }
    func testHealthyVersionStaysAndBackupGoes() throws {
        let r = try run(appBehaviour: "6")
        XCTAssertEqual(r.installed, "new"); XCTAssertNil(r.note); XCTAssertFalse(r.backupKept)
    }
    func testVersionThatDiesIsReplacedByTheBackup() throws {
        let r = try run(appBehaviour: "0.2")
        XCTAssertEqual(r.installed, "old"); XCTAssertEqual(r.note, "9.9.9"); XCTAssertFalse(r.backupKept)
    }
}

private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var codes: [Int] = []
    nonisolated(unsafe) static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let code = Self.codes[min(Self.calls, Self.codes.count - 1)]; Self.calls += 1
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data()); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class OpenRouterRetryTests: XCTestCase {
    private func call(_ codes: [Int], retrying: Set<Int> = [429, 500, 502, 503, 504]) async throws -> (code: Int, calls: Int) {
        StubProtocol.codes = codes; StubProtocol.calls = 0
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]
        let (_, r) = try await OpenRouterRetry.data(for: URLRequest(url: URL(string: "https://openrouter.ai/x")!), session: URLSession(configuration: c), retrying: retrying, firstWait: 0)
        return ((r as! HTTPURLResponse).statusCode, StubProtocol.calls)
    }
    func testBusyIsRetriedUntilItWorks() async throws { let r = try await call([429, 503, 200]); XCTAssertEqual(r.code, 200); XCTAssertEqual(r.calls, 3) }
    func testGivesUpAfterThreeRetries() async throws { let r = try await call([429]); XCTAssertEqual(r.code, 429); XCTAssertEqual(r.calls, 4) }
    func testNoCreditIsNotRetried() async throws { let r = try await call([402]); XCTAssertEqual(r.calls, 1) }
    func testPaidOrdersDoNotRetryServerErrors() async throws { let r = try await call([500], retrying: [429]); XCTAssertEqual(r.calls, 1) }
    func testClipChecksKeepGoingOnlyThroughBriefProblems() {
        for s in [408, 429, 500, 503] { XCTAssertTrue(OpenRouterRetry.isBriefProblem(status: s)) }
        for s in [200, 401, 403, 404] { XCTAssertFalse(OpenRouterRetry.isBriefProblem(status: s)) }
        XCTAssertTrue(OpenRouterRetry.isBriefProblem(URLError(.timedOut))); XCTAssertFalse(OpenRouterRetry.isBriefProblem(URLError(.cancelled))); XCTAssertFalse(OpenRouterRetry.isBriefProblem(CancellationError()))
    }
}

final class SongDraftTests: XCTestCase {
    func testSavesLoadsAndClearsWhenEmpty() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID().uuidString)/d.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let d = SongDraft(title: "T", lyrics: "L\nL", audioPath: "/x.mp3"); d.save(to: url)
        XCTAssertEqual(SongDraft.load(from: url), d)
        SongDraft().save(to: url)
        XCTAssertNil(SongDraft.load(from: url)); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

final class StyleWordTests: XCTestCase {
    func testMediumSurvives() {
        XCTAssertEqual(StylePreset.withoutLighting("soft pastel colours and light linework"), "soft pastel colours and light linework.")
        XCTAssertEqual(StylePreset.withoutLighting("soft morning light and watercolour washes"), "watercolour washes.")
        XCTAssertEqual(StylePreset.withoutLighting("oil painting with golden-hour light, thick brushwork"), "oil painting, thick brushwork.")
        XCTAssertEqual(StylePreset.withoutLighting("warm chiaroscuro lighting"), "")
    }
}

final class EvenVolumeTests: XCTestCase {
    func testQuietSongWithSharpPeaksIsNotRaisedIntoDistortion() {
        var quiet = TrackAnalysis(); quiet.start = 0; quiet.end = 100; quiet.loudness = -26; quiet.peak = 0.5
        var free = quiet; free.peak = 0.1
        let plan = LoopAudio.plan(analyses: [quiet, free], transition: .crossfade, crossfade: 2, gap: 0, evenVolume: true, shuffle: false, minimum: 150, seed: 1)
        XCTAssertLessThanOrEqual(plan.plays[0].gain * quiet.peak, 0.98 + 1e-9)
        XCTAssertEqual(plan.plays[1].gain, 3.98, accuracy: 0.02)
    }
}
