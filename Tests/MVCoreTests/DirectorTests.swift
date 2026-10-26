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

    func testShotTypeGoesIntoThePromptAndIsSaved() throws {
        XCTAssertEqual(LoopVideo.conditions(weather: .any, time: .any), "")
        let c = LoopVideo.conditions(weather: .clear, time: .any, shot: .drone)
        XCTAssertTrue(c.contains("clear, cloudless sky")); XCTAssertTrue(c.contains("Type of shot: an aerial drone shot"))
        for s in ShotType.allCases where s != .any { XCTAssertFalse(s.words.isEmpty); XCTAssertFalse(s.name.isEmpty) }
        var p = LoopProject(); p.shot = .lowAngle
        let back = try JSONDecoder().decode(LoopProject.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.shot, .lowAngle)
        XCTAssertTrue(LoopVideo.conditions(back).contains("low-angle"))
    }

    func testSectionRemembersWhetherItUsesTheReference() throws {
        var s = PhotoSection(id: 0, start: 0, end: 10, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 1)
        s.usesSource = false; s.usesSourceFor = "A forest in rain"
        let back = try JSONDecoder().decode(PhotoSection.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.usesSource, false); XCTAssertEqual(back.usesSourceFor, "A forest in rain")
    }

    func testAStreetPhotoIsAPlaceNeverASubject() {
        // the photo check says what the photo is mainly of; that is what gets kept, whatever the director wanted
        let v = Director.parseJudgement("{\"shows\":true,\"is\":\"place\",\"note\":\"A wide road through a small town with shops on both sides.\"}", wanted: .subject)
        XCTAssertEqual(v?.shows, true); XCTAssertEqual(v?.keep, .place)
        XCTAssertEqual(Director.parseJudgement("{\"shows\":false,\"is\":\"subject\",\"note\":\"A logo.\"}", wanted: .subject)?.shows, false)
        let r = Pipeline.readSourceReply("```json\n{\"mainly\":\"place\",\"sentence\":\"A sunny Route 66 town street with shops and a vintage sign.\"}\n```")
        XCTAssertEqual(r?.mainly, .place); XCTAssertTrue(r?.sentence.hasPrefix("A sunny") == true)
        XCTAssertNil(Pipeline.readSourceReply("not json"))
    }

    func testHighestQualityPromptKeepsThePicture() {
        let p = Pipeline.highestQualityPrompt(idea: "A red barn on the plains", style: "Impasto oil painting.")
        XCTAssertTrue(p.contains("Keep EXACTLY the same picture")); XCTAssertTrue(p.contains("A red barn on the plains")); XCTAssertTrue(p.contains("Impasto oil painting"))
    }
}
