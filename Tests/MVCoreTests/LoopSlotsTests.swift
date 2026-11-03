import XCTest
@testable import MVCore

final class LoopSlotsTests: XCTestCase {
    func project(songs n: Int, change: LoopSceneChange = .songs) -> LoopProject {
        var p = LoopProject(); p.sceneChange = change
        p.tracks = (0..<n).map { LoopTrack(file: "tracks/\($0).mp3", title: "Song \($0 + 1)", seconds: 180) }
        return p
    }
    func testOneBlankSlotPerSong() {
        var p = project(songs: 12)
        let f = LoopVideo.syncSlots(&p, focus: nil)
        XCTAssertEqual(LoopVideo.slots(p).count, 12)
        XCTAssertTrue(LoopVideo.slots(p).allSatisfy { $0.clip == nil && $0.songs.count == 1 })
        XCTAssertEqual(f, LoopVideo.slots(p)[0].id)
        XCTAssertEqual(LoopVideo.blankSlots(p).blank, 12)
    }
    func testLegacyAutoSongsKeepPlayingTheSameWay() {
        var p = project(songs: 4); p.clips = ["a.mp4", "b.mp4"]; p.clip = "b.mp4"; p.scene = "A loch"; p.picture = "p.jpg"
        let before = LoopVideo.songClips(p).map(\.clip)
        LoopVideo.syncSlots(&p, focus: nil)
        let s = LoopVideo.slots(p)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.map { $0.clip }, ["b.mp4", nil, nil, nil]); XCTAssertEqual(s[0].idea, "A loch")
        XCTAssertEqual(LoopVideo.songClips(p).map(\.clip), before, "blank scenes borrow, so the video is unchanged")
    }
    func testSongsThatShareAClipShareAScene() {
        var p = project(songs: 4); p.clips = ["a.mp4", "b.mp4"]; p.tracks[0].clip = "a.mp4"; p.tracks[1].clip = "a.mp4"; p.tracks[2].clip = "b.mp4"; p.clip = "a.mp4"
        LoopVideo.syncSlots(&p, focus: nil)
        XCTAssertEqual(LoopVideo.slots(p).map { $0.songs.count }, [2, 1, 1])
        let first = LoopVideo.slots(p)[0].id
        LoopVideo.separateSlot(&p, id: first, focus: first)
        XCTAssertEqual(LoopVideo.slots(p).map { $0.clip }, ["a.mp4", nil, "b.mp4", nil])
        XCTAssertEqual(p.tracks.map(\.clip), ["a.mp4", nil, "b.mp4", nil])
    }
    func testFillingASlotTiesItsSongs() {
        var p = project(songs: 3); p.clips = ["a.mp4"]; p.clip = "a.mp4"
        var f = LoopVideo.syncSlots(&p, focus: nil)
        f = LoopVideo.syncSlots(&p, focus: f)
        let second = LoopVideo.slots(p)[1].id
        LoopVideo.selectSlot(&p, from: f, to: second)
        XCTAssertNil(p.clip, "a blank scene is selected: the project's clip in use is that scene's")
        p.clips.append("b.mp4"); p.clip = "b.mp4"        // a clip made while it is selected
        LoopVideo.syncSlots(&p, focus: second)
        XCTAssertEqual(p.tracks[1].clip, "b.mp4")
        XCTAssertEqual(Set(p.sceneClips), ["a.mp4", "b.mp4"])
    }
    func testLeavingSelectsAFilledScene() {
        var p = project(songs: 3); p.clips = ["a.mp4"]; p.clip = "a.mp4"
        var f = LoopVideo.syncSlots(&p, focus: nil)
        LoopVideo.selectSlot(&p, from: f, to: LoopVideo.slots(p)[2].id); f = LoopVideo.slots(p)[2].id
        XCTAssertNil(p.clip)
        LoopVideo.selectFirstFilled(&p, from: f)
        XCTAssertEqual(p.clip, "a.mp4")
    }
    func testReorderingASceneReordersItsSong() {
        var p = project(songs: 3)
        LoopVideo.syncSlots(&p, focus: nil)
        let third = LoopVideo.slots(p)[2].id
        LoopVideo.moveSlot(&p, id: third, to: 0, focus: nil)
        XCTAssertEqual(p.tracks.map(\.title), ["Song 3", "Song 1", "Song 2"])
        XCTAssertEqual(LoopVideo.slots(p).first?.id, third)
    }
    func testRemovedSongRemovesItsScene() {
        var p = project(songs: 3)
        LoopVideo.syncSlots(&p, focus: nil)
        p.tracks.remove(at: 1)
        LoopVideo.syncSlots(&p, focus: nil)
        XCTAssertEqual(LoopVideo.slots(p).count, 2)
        p.tracks.append(LoopTrack(file: "x.mp3", title: "New", seconds: 100))
        LoopVideo.syncSlots(&p, focus: nil)
        XCTAssertEqual(LoopVideo.slots(p).count, 3)
    }
    func testTimeScenesStartAtFourAndGrowAndShrink() {
        var p = project(songs: 1, change: .time); p.clips = ["a.mp4"]; p.clip = "a.mp4"
        let f = LoopVideo.syncSlots(&p, focus: nil)
        XCTAssertEqual(LoopVideo.slots(p).count, 4)
        LoopVideo.addSlot(&p, focus: f); XCTAssertEqual(LoopVideo.slots(p).count, 5)
        LoopVideo.removeSlot(&p, id: LoopVideo.slots(p).last!.id, focus: f); XCTAssertEqual(LoopVideo.slots(p).count, 4)
        XCTAssertEqual(p.sceneClips, ["a.mp4"])
    }
    func testSlotsRoundTripAndOldProjectsOpen() throws {
        var p = project(songs: 2); LoopVideo.syncSlots(&p, focus: nil)
        let back = try JSONDecoder().decode(LoopProject.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.sceneSlots, p.sceneSlots)
        let old = try JSONDecoder().decode(LoopProject.self, from: Data("{\"title\":\"x\"}".utf8))
        XCTAssertTrue(old.sceneSlots.isEmpty)
    }
}
