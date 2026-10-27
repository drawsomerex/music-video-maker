import XCTest
@testable import MVCore

/// A song repeating within a looping video: a number of times, for a number of minutes (cut at a quiet moment, blended into what comes next), or for its scene.
final class LoopRepeatTests: XCTestCase {
    /// A 4-minute song (sound from 0.5 s to 240.5 s) whose level dips (−40 dB) for a second 120 s into the file: 9:52 into a 10-minute turn (its third play starts at 7:52).
    func song(fades: Bool = false) -> TrackAnalysis {
        var a = TrackAnalysis(); a.start = 0.5; a.end = 240.5; a.loudness = -14; a.fadesOut = fades; a.fadeLength = fades ? 8 : 0
        a.energy = Array(repeating: -12, count: 960)
        for k in 478..<482 { a.energy[k] = -40 }            // 0.5 + 478 × 0.25 = 120 s into the file
        return a
    }

    func testTimesPlaysTheSongInARowWithSmoothJoins() {
        let a = [song(), song()]
        let plan = LoopAudio.plan(analyses: a, transition: .automatic, crossfade: 6, gap: 2, evenVolume: false, shuffle: false, minimum: 1, seed: 1, onePass: true, repeats: [.times(3), .once])
        XCTAssertEqual(plan.plays.map(\.track), [0, 0, 0, 1])
        XCTAssertEqual(plan.plays.map(\.rep), [0, 1, 2, 0])
        for k in 0..<2 {      // each repeat blends the end into the start (4 s), never cut
            XCTAssertEqual(plan.plays[k].end - plan.plays[k + 1].start, 4, accuracy: 0.001)
            XCTAssertEqual(plan.plays[k].fadeOut, 4, accuracy: 0.001); XCTAssertEqual(plan.plays[k + 1].fadeIn, 4, accuracy: 0.001)
        }
        XCTAssertFalse(plan.plays.contains { $0.cut })
        XCTAssertEqual(plan.turns.map(\.track), [0, 1], "a song's repeats are one turn")
        XCTAssertEqual(plan.firstRound.map(\.track), [0, 1], "the chapters list each song once")
    }

    func testMinutesCutsAtAQuietMomentAndBlendsIntoTheNextSong() {
        let a = [song(), song()]
        let plan = LoopAudio.plan(analyses: a, transition: .automatic, crossfade: 6, gap: 2, evenVolume: false, shuffle: false, minimum: 1, seed: 1, onePass: true, repeats: [.minutes(10), .once])
        let turn = plan.plays.filter { $0.track == 0 }
        XCTAssertEqual(turn.count, 3, "10 minutes of a 4-minute song: two whole plays and part of a third")
        let last = turn.last!
        XCTAssertTrue(last.cut); XCTAssertEqual(last.fadeOut, 6, accuracy: 0.001)
        XCTAssertLessThanOrEqual(last.end, 600.5, "it ends by the 10 minutes")
        XCTAssertGreaterThan(last.end, 585, "and not much before")
        XCTAssertEqual(last.to, 120.0, accuracy: 0.3, "the cut lands on the quiet moment just before the time")
        let next = plan.plays[turn.count]
        XCTAssertEqual(next.track, 1)
        XCTAssertEqual(last.end - next.start, 6, accuracy: 0.001, "the next song blends in over the cut song's fade-out, even in Back to back")
        XCTAssertEqual(next.fadeIn, 6, accuracy: 0.001)
    }

    func testAShortTimeCutsTheFirstPlayAndAOneSongVideoComesBackRound() {
        // one song for 2 minutes at a time, video of 10 minutes: cut, blend into its own start, cut again…
        let plan = LoopAudio.plan(analyses: [song()], transition: .seamless, crossfade: 6, gap: 2, evenVolume: false, shuffle: false, minimum: 600, seed: 1, repeats: [.minutes(2)])
        XCTAssertTrue(plan.plays.dropLast().allSatisfy { $0.cut && $0.length <= 121 && $0.length > 100 })
        for (x, y) in zip(plan.plays, plan.plays.dropFirst()) { XCTAssertEqual(x.end - y.start, 6, accuracy: 0.001) }
        XCTAssertGreaterThanOrEqual(plan.songsEnd, 600)
    }

    func testALastRepeatOfOnlyAFewSecondsIsLeftOut() {
        // 8 min 10 s: two whole plays (≈ 476 s with the join) leave about 14 s, too short for a third play: the turn ends there
        let plan = LoopAudio.plan(analyses: [song(), song()], transition: .automatic, crossfade: 6, gap: 2, evenVolume: false, shuffle: false, minimum: 1, seed: 1, onePass: true, repeats: [.minutes(8 + 10.0 / 60), .once])
        XCTAssertEqual(plan.plays.filter { $0.track == 0 }.count, 2)
        XCTAssertFalse(plan.plays[1].cut)
    }

    func testSceneMeansTheSceneLengthAndRepeatsAreSaved() throws {
        XCTAssertEqual(TrackRepeat.scene.resolved(sceneMinutes: 15), .minutes(15))
        XCTAssertEqual(TrackRepeat.times(3).resolved(sceneMinutes: 15), .times(3))
        var t = LoopTrack(file: "a.mp3", title: "A", seconds: 240); t.repeatMode = .minutes(15)
        let back = try JSONDecoder().decode(LoopTrack.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.repeatMode, .minutes(15))
        let old = try JSONDecoder().decode(LoopTrack.self, from: Data(#"{"file":"a.mp3","title":"A","seconds":240}"#.utf8))
        XCTAssertEqual(old.repeatMode, .once, "older projects: every song plays once, as before")
        XCTAssertEqual(TrackRepeat.minutes(60).label, "1 hour"); XCTAssertEqual(TrackRepeat.minutes(15).label, "15 min"); XCTAssertEqual(TrackRepeat.times(3).label, "3 times")
    }

    func testSceneChangesHappenBetweenSongsNotBetweenRepeats() {
        var p = LoopProject(); p.sceneChange = .songs
        let plan = LoopAudio.plan(analyses: [song(), song()], transition: .automatic, crossfade: 6, gap: 2, evenVolume: false, shuffle: false, minimum: 1, seed: 1, onePass: true, repeats: [.times(3), .times(2)])
        let changes = LoopVideo.sceneChangeTimes(p, plan: plan)
        XCTAssertEqual(changes.count, 1, "one song change, though the songs repeat")
        XCTAssertEqual(changes[0], plan.plays[3].start + 0, accuracy: 3)
    }
}
