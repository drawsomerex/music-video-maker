import XCTest
@testable import MVCore

/// Talks to the real Jev on OpenRouter with the key saved in the app (a few thousandths of a cent). Runs only with MV_LIVE=1.
final class JevLiveTests: XCTestCase {
    func testLiveAnswers() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MV_LIVE"] == "1", "set MV_LIVE=1 to call the real service")
        let key = Config.load().effectiveOpenRouterKey
        try XCTSkipIf(key.isEmpty, "no OpenRouter key saved")
        let risky = await ClipRisk.check([.init(label: "A", idea: "A crowd of tourists walks into the square and out again while pigeons fly away out of sight"),
                                          .init(label: "B", idea: "Rain runs down a tall window of a quiet library at night, a candle flickers on the desk")], kind: .loop, apiKey: key)
        print("LIVE risk:", String(describing: risky))
        XCTAssertNotNil(risky, "the real service should answer")
        let a = await ErrorTriage.advice(for: "Your OpenRouter credit is $0.00 but the clip costs about $1.50. Add credit and try again.", apiKey: key)
        print("LIVE error advice:", String(describing: a?.kind))
        let b = await ErrorTriage.advice(for: "Add a song first.", apiKey: key)
        print("LIVE error advice 2:", String(describing: b?.kind))
    }
}

final class JevLiveShortTests: XCTestCase {
    func testLiveShortChoice() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MV_LIVE"] == "1", "set MV_LIVE=1 to call the real service")
        let dir = URL(fileURLWithPath: "/tmp/jevlive")
        let song = try XCTUnwrap((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first { ["mp3", "m4a", "wav"].contains($0.pathExtension.lowercased()) })
        let energy = try XCTUnwrap(LoopVideo.shortEnergy(song))
        for c in LoopVideo.shortCandidates(energy: energy, seconds: 45) { print("LIVE candidate:", c.start, c.words) }
        let loud = LoopVideo.shortWindow(energy: energy, seconds: 45)
        let chosen = await LoopVideo.shortWindowChosen(song, dir: dir, title: "Gathering Storm", about: "")
        print("LIVE loudest:", String(describing: loud), "chosen:", String(describing: chosen))
        XCTAssertNotNil(chosen)
        let again = await LoopVideo.shortWindowChosen(song, dir: dir, title: "Gathering Storm", about: "")
        XCTAssertEqual(again?.start, chosen?.start, "remembered")
    }
}
