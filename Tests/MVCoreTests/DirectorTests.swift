import XCTest
@testable import MVCore

final class DirectorTests: XCTestCase {
    func testPictureCheckParsesFaultsAndPasses() {
        let ok = PictureCheck.parse("```json\n{\"ok\":true}\n```", cost: 0.001)
        XCTAssertNotNil(ok); XCTAssertNil(ok?.problem)
        let bad = PictureCheck.parse("{\"ok\":false,\"problem\":\"Scribbled letters on the wall\",\"fix\":\"Remove the letters on the wall\"}", cost: 0)
        XCTAssertEqual(bad?.problem, "Scribbled letters on the wall"); XCTAssertEqual(bad?.fix, "Remove the letters on the wall")
        XCTAssertNil(PictureCheck.parse("no json here", cost: 0))
        XCTAssertTrue(PictureCheck.fixPrompt("Remove the letters").contains("Change ONLY that"))
    }

    func testSongBriefPutsDescriptionFirstThenLyrics() {
        let b = Director.songBrief(description: "A sailor comes home", notes: "", lyrics: "Over the sea\nI come back")
        let d = b.range(of: "SONG DESCRIPTION")!, l = b.range(of: "THE LYRICS")!
        XCTAssertLessThan(d.lowerBound, l.lowerBound)
        XCTAssertTrue(Director.songBrief(description: "", notes: "", lyrics: "").contains("instrumental"))
    }

    func testBrightnessDefaultsAndCodableRoundTrip() throws {
        var t = LoopTrack(file: "a.mp3", title: "A", seconds: 10)
        XCTAssertNil(t.lyrics)
        t.lyrics = "hello"
        let back = try JSONDecoder().decode(LoopTrack.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.lyrics, "hello")
        XCTAssertEqual(PictureQuality.high.rawValue, "high")
        XCTAssertTrue(Brightness.bright.words.lowercased().contains("bright"))
    }
}
