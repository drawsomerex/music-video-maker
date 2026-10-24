import XCTest
@testable import MVCore

/// More than one scene in a looping video, Shorts names, and the detail every style asks for.
final class LoopScenesTests: XCTestCase {
    /// Four songs of 3 minutes each, back to back.
    func plan(songs: Int = 4, length: Double = 180) -> LoopAudio.Plan {
        let plays = (0..<songs).map { LoopAudio.Play(track: $0, start: Double($0) * length, from: 0, to: length, fadeIn: 0, fadeOut: 0, gain: 1, round: 0) }
        return LoopAudio.Plan(plays: plays, total: Double(songs) * length + 3, songsEnd: Double(songs) * length)
    }
    func project(_ change: LoopSceneChange, minutes: Double = 10) -> LoopProject {
        var p = LoopProject(); p.clips = ["a.mp4", "b.mp4", "c.mp4"]; p.clip = "a.mp4"; p.sceneClips = p.clips; p.sceneChange = change; p.sceneMinutes = minutes
        return p
    }

    func testOneSceneUnlessAskedAndTwoClips() {
        XCTAssertEqual(LoopVideo.sceneStarts(project(.never), plan: plan()).count, 1)
        var p = project(.songs); p.sceneClips = ["a.mp4"]; p.clips = ["a.mp4"]
        XCTAssertEqual(LoopVideo.sceneStarts(p, plan: plan()).count, 1, "one clip: nothing to change to")
    }

    func testScenesChangeAtEachSongInTurn() {
        let s = LoopVideo.sceneStarts(project(.songs), plan: plan())
        XCTAssertEqual(s.map(\.t), [0, 180, 360, 540])
        XCTAssertEqual(s.map(\.clip), ["a.mp4", "b.mp4", "c.mp4", "a.mp4"], "the clips take turns")
    }

    func testScenesChangeByTimeAndBoth() {
        let t = LoopVideo.sceneStarts(project(.time, minutes: 4), plan: plan())
        XCTAssertEqual(t.map(\.t), [0, 240, 480])
        // both: song changes at 3, 6 and 9 min, timed ones every 2 min; the timed one at 6 min falls on a song change and is left out
        let b = LoopVideo.sceneStarts(project(.both, minutes: 2), plan: plan())
        XCTAssertEqual(b.map(\.t), [0, 120, 180, 240, 360, 480, 540, 600])
        for (x, y) in zip(b, b.dropFirst()) { XCTAssertGreaterThanOrEqual(y.t - x.t, 30) }
    }

    func testNoChangeDuringTheTitleOrTheEnding() {
        let s = LoopVideo.sceneStarts(project(.time, minutes: 1), plan: plan(songs: 1, length: 150))
        XCTAssertTrue(s.dropFirst().allSatisfy { $0.t >= LoopVideo.titleScreenEnd + 5 && $0.t <= 130 })
    }

    func testShortsUseTheSongNameWithoutItsNumber() {
        XCTAssertEqual(LoopVideo.songName("03 By Burn and Brae", 2), "By Burn and Brae")
        XCTAssertEqual(LoopVideo.songName("12 - Hands Across the Forth", 11), "Hands Across the Forth")
        XCTAssertEqual(LoopVideo.songName("1999", 0), "1999", "a title that is a number stays")
        XCTAssertEqual(LoopVideo.songName("The Abbey Lamp", 0), "The Abbey Lamp")
    }

    func testEveryStyleAsksForSuperHighDetail() {
        for s in StyleLibrary.shippedList() { XCTAssertTrue(s.prompt.contains(StylePreset.detail), s.name) }
        XCTAssertTrue(StylePreset.withDetail("A watercolor of a fox.").hasSuffix(StylePreset.detail))
        XCTAssertEqual(StylePreset.withDetail("Ultra-detailed oil painting."), "Ultra-detailed oil painting.", "not added twice")
    }
}

/// A building or landscape is kept accurate (only the angle moves a little); a creature gets a new angle and pose. The photos are copied to /tmp.
final class SubjectKindTests: XCTestCase {
    func testPlacesAndCreaturesAreToldApart() throws {
        let cases: [(String, SubjectKind)] = [("subject-castle.jpg", .place), ("subject-valley.jpg", .place), ("subject-cow.jpg", .creature), ("subject-fox.jpg", .creature)]
        for (f, want) in cases {
            let u = URL(fileURLWithPath: "/tmp/" + f)
            try XCTSkipUnless(FileManager.default.fileExists(atPath: u.path))
            XCTAssertEqual(SubjectPicture.detect(u), want, f)
            XCTAssertEqual(SubjectPicture.kind(.creature, file: u), .creature, "your own choice wins")
        }
        XCTAssertTrue(SubjectPicture.instruction(.place).contains("ACCURATE"))
        XCTAssertTrue(SubjectPicture.instruction(.creature).contains("DIFFERENT pose"))
        XCTAssertLessThan(SubjectPicture.tooClose(.place), SubjectPicture.tooClose(.creature))
    }
}

/// A style never decides the light; the scene's weather words turn "Cloudless sky" off; the weather and time menus are put into words.
final class StyleLightTests: XCTestCase {
    func testStylesLoseTheirLighting() {
        let s = StylePreset.withoutLighting("Photorealistic 35mm cinematic still frame, natural golden-hour and practical lighting, shallow depth of field, Kodak Vision3 film grain and anamorphic lens bokeh.")
        XCTAssertFalse(s.lowercased().contains("golden"))
        XCTAssertTrue(s.contains("Kodak Vision3 film grain"))
        for p in StyleLibrary.shippedList() {
            XCTAssertNil(p.prompt.range(of: #"\b(lighting|golden[- ]hour|sunbeams?|spotlights?|moonlit)\b"#, options: [.regularExpression, .caseInsensitive]), p.name)
        }
        XCTAssertTrue(StylePreset.styleClause("Oil painting, warm chiaroscuro lighting.").contains("never from the style"))
    }
    func testWeatherWordsTurnCloudlessSkyOff() {
        XCTAssertTrue(LoopVideo.mentionsSky("A lighthouse battered by a violent storm"))
        XCTAssertTrue(LoopVideo.mentionsSky("Snow falling on a quiet village"))
        XCTAssertFalse(LoopVideo.mentionsSky("A stone bridge over a quiet river"))
        var p = LoopProject(); p.weather = .storm; p.timeOfDay = .dusk
        XCTAssertTrue(LoopVideo.conditions(p).contains("thunderstorm")); XCTAssertTrue(LoopVideo.conditions(p).contains("dusk"))
        XCTAssertEqual(LoopVideo.conditions(LoopProject()), "")
    }
}
