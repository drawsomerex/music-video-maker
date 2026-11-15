import XCTest
@testable import MVCore

/// Title cards in a long looping video: with "Title cards: Every song" and "Scenes change: At each song change", a song's card must not show
/// over the previous scene. It waits until the 3-second cross-fade into its own scene has finished (scene change + sceneFade/2). The same card
/// times are used by the preview sample and the full render: both call LoopVideo.cardTimes.
final class LoopCardTimingTests: XCTestCase {
    /// `songs` turns of `length` seconds each, back to back (Automatic), or crossfading by `fadeIn` seconds.
    func plan(songs: Int = 4, length: Double = 180, fadeIn: Double = 0) -> LoopAudio.Plan {
        var plays: [LoopAudio.Play] = []
        var previousEnd = 0.0
        for k in 0..<songs {
            let start = k == 0 ? 0 : previousEnd - fadeIn
            plays.append(LoopAudio.Play(track: k, start: start, from: 0, to: length, fadeIn: k == 0 ? 0 : fadeIn, fadeOut: 0, gain: 1, round: 0))
            previousEnd = plays[k].end
        }
        return LoopAudio.Plan(plays: plays, total: previousEnd + 3, songsEnd: previousEnd)
    }

    func project(change: LoopSceneChange = .songs, clips: [String] = ["a.mp4", "b.mp4", "c.mp4"]) -> LoopProject {
        var p = LoopProject()
        p.title = "Album"
        p.clips = clips; p.clip = clips.first; p.sceneClips = clips
        p.sceneChange = change; p.cards = .everySong
        p.tracks = (0..<4).map { LoopTrack(file: "s\($0).mp3", title: "Song \($0 + 1)", seconds: 180) }
        return p
    }

    /// The time the video changes into turn `k`'s scene, read from the scenes the video really uses (SceneTimeline's sceneStarts).
    func sceneChange(_ k: Int, in pl: LoopAudio.Plan, starts: [(t: Double, clip: String)]) -> Double? {
        guard k > 0, pl.plays.indices.contains(k) else { return nil }
        let t = (pl.plays[k - 1].end + pl.plays[k].start) / 2
        return starts.contains { abs($0.t - t) < 1e-6 } ? t : nil
    }

    /// Every card for a song whose scene changes starts no earlier than the moment its new scene is fully shown.
    func testACardWaitsUntilTheCrossfadeIntoItsSceneHasFinished() {
        for fadeIn in [0.0, 3.0] {
            let p = project(), pl = plan(fadeIn: fadeIn)
            let starts = LoopVideo.sceneStarts(p, plan: pl)
            let cards = LoopVideo.cardTimes(p, plan: pl)
            XCTAssertEqual(starts.count, 4, "four songs, four scenes")
            XCTAssertEqual(cards.count, 4, "one card per song")
            var checked = 0
            for k in pl.plays.indices {
                guard let t = sceneChange(k, in: pl, starts: starts) else { continue }     // the first song has no change into it
                let title = p.tracks[pl.plays[k].track].title
                guard let card = cards.first(where: { $0.text == title }) else { return XCTFail("no card for \(title)") }
                XCTAssertGreaterThanOrEqual(card.start, t + LoopVideo.sceneFade / 2 - 1e-9,
                                            "the card for \(title) must wait for the cross-fade to finish (fadeIn \(fadeIn))")
                checked += 1
            }
            XCTAssertEqual(checked, 3, "three scene changes between four songs")
        }
    }

    /// The card is exactly the old start plus half the cross-fade for a song whose scene changes as the song starts.
    func testACardsStartMovesByHalfTheCrossfade() {
        let p = project(), pl = plan()
        let cards = LoopVideo.cardTimes(p, plan: pl)
        XCTAssertEqual(cards.map(\.start), [8.5 + 0.5, 180 + 1.5, 360 + 1.5, 540 + 1.5])
    }

    /// The very first card (the first song, under the video's title) keeps today's timing.
    func testTheFirstCardIsUnaffected() {
        let p = project(), pl = plan()

        let cards = LoopVideo.cardTimes(p, plan: pl)
        XCTAssertEqual(cards.first?.text, "Song 1")
        XCTAssertEqual(cards.first?.start ?? 0, LoopVideo.titleScreenEnd + 0.5, accuracy: 1e-9)
    }

    /// A song that keeps the same scene has no cross-fade, so its card shows as it does today.
    func testASongThatKeepsTheSameSceneKeepsTodaysTiming() {
        let p = project(clips: ["a.mp4"]), pl = plan()
        XCTAssertTrue(LoopVideo.songSceneChanges(p, plan: pl).isEmpty, "one clip: nothing to change to")
        XCTAssertEqual(LoopVideo.sceneStarts(p, plan: pl).count, 1)
        let cards = LoopVideo.cardTimes(p, plan: pl)
        XCTAssertEqual(cards.map(\.start), [LoopVideo.titleScreenEnd + 0.5, 180, 360, 540])
    }

    /// Scenes that change by time are not song changes: the cards keep today's timing.
    func testTimeScenesDoNotDelayCards() {
        let p = project(change: .time), pl = plan()
        XCTAssertTrue(LoopVideo.songSceneChanges(p, plan: pl).isEmpty)
        XCTAssertEqual(LoopVideo.cardTimes(p, plan: pl).map(\.start), [LoopVideo.titleScreenEnd + 0.5, 180, 360, 540])
    }

    /// A song's turn with repeats gets one card, at the turn's first play, and still after its scene's cross-fade.
    func testARepeatedTurnGetsOneCardAfterItsSceneChange() {
        var p = project(); p.tracks = (0..<2).map { LoopTrack(file: "s\($0).mp3", title: "Song \($0 + 1)", seconds: 180) }
        let plays = [LoopAudio.Play(track: 0, start: 0, from: 0, to: 180, fadeIn: 0, fadeOut: 0, gain: 1, round: 0),
                     LoopAudio.Play(track: 0, start: 180, from: 0, to: 180, fadeIn: 0, fadeOut: 0, gain: 1, round: 0, rep: 1),
                     LoopAudio.Play(track: 1, start: 360, from: 0, to: 180, fadeIn: 0, fadeOut: 0, gain: 1, round: 0)]
        let pl = LoopAudio.Plan(plays: plays, total: 543, songsEnd: 540)
        let starts = LoopVideo.sceneStarts(p, plan: pl)
        let cards = LoopVideo.cardTimes(p, plan: pl)
        XCTAssertEqual(cards.map(\.text), ["Song 1", "Song 2"], "one card per turn, not on the repeat")
        let t = (pl.plays[1].end + pl.plays[2].start) / 2
        XCTAssertTrue(starts.contains { abs($0.t - t) < 1e-6 }, "the scene changes into the second song's turn")
        XCTAssertGreaterThanOrEqual(cards[1].start, t + LoopVideo.sceneFade / 2 - 1e-9)
    }

    /// The scene changes the cards are timed from are the same scene starts the timeline fades into (so a card is never over a stale scene).
    func testTheSceneChangesAreTheTimelineSceneStarts() {
        let p = project(), pl = plan(fadeIn: 3)
        let starts = LoopVideo.sceneStarts(p, plan: pl)
        let changes = LoopVideo.songSceneChanges(p, plan: pl)
        XCTAssertEqual(changes.map(\.t), Array(starts.dropFirst().map(\.t)), "the same times, in the same order")
        for change in changes {
            XCTAssertEqual(pl.plays[change.play].start + pl.plays[change.play].fadeIn / 2, change.t, accuracy: 1e-9,
                           "a crossfading join is centred between the songs")
        }
    }

    /// Cards never overlap another card, and never run past the songs' useful time.
    func testCardsNeverOverlapOrRunPastTheEnd() {
        for fadeIn in [0.0, 3.0] {
            let p = project(), pl = plan(fadeIn: fadeIn)
            let cards = LoopVideo.cardTimes(p, plan: pl)
            for (a, b) in zip(cards, cards.dropFirst()) {
                XCTAssertGreaterThanOrEqual(b.start, a.start + LoopVideo.cardSeconds + 0.5 - 1e-9, "two cards never show on top of each other")
            }
            XCTAssertTrue(cards.allSatisfy { $0.start + LoopVideo.cardSeconds <= pl.songsEnd + 1e-9 }, "a card never runs past the songs' useful time")
        }
    }
}