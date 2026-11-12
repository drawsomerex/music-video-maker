import XCTest
import AVFoundation
@testable import MVCore

final class LoopSongVideosTests: XCTestCase {
    func song() -> TrackAnalysis {
        var a = TrackAnalysis(); a.start = 0.5; a.end = 240.5; a.loudness = -14; a.energy = Array(repeating: -12, count: 960)
        for k in 478..<482 { a.energy[k] = -40 }
        return a
    }
    /// Six songs, each repeating for 10 minutes, over two scenes (songs 1–3 and 4–6).
    func album() -> LoopProject {
        var p = LoopProject(); p.title = "Album"; p.clips = ["a.mp4", "b.mp4"]; p.clip = "a.mp4"; p.sceneChange = .songs; p.cards = .everySong; p.songVideos = true
        for k in 0..<6 {
            var t = LoopTrack(file: "tracks/\(k).mp3", title: "0\(k + 1) Song \(k + 1)", seconds: 240)
            t.repeatMode = .minutes(10); t.clip = k < 3 ? "a.mp4" : "b.mp4"
            p.tracks.append(t); p.analysis[t.file] = song()
        }
        p.playOnce = true
        return p
    }

    func testEachSongIsItsOwnTenMinuteVideoAndTheAlbumIsTheirSum() throws {
        let p = album()
        let whole = try XCTUnwrap(LoopVideo.plan(p)).total
        XCTAssertEqual(whole, 3600, accuracy: 120, "six 10-minute songs: about one hour (the joins between songs blend a few seconds)")
        var sum = 0.0
        for k in 0..<6 {
            let q = try XCTUnwrap(LoopVideo.songVideoProject(p, track: k))
            let total = try XCTUnwrap(LoopVideo.plan(q)).total
            XCTAssertEqual(total, 600, accuracy: 20, "song \(k + 1)'s own video is its ten minutes")
            sum += total
        }
        XCTAssertEqual(sum, whole, accuracy: 150)
    }
    func testASongVideoUsesItsOwnSceneAndTitle() throws {
        let p = album()
        let q = try XCTUnwrap(LoopVideo.songVideoProject(p, track: 4))
        XCTAssertEqual(q.tracks.count, 1); XCTAssertEqual(q.tracks[0].title, "05 Song 5")
        XCTAssertEqual(q.clip, "b.mp4"); XCTAssertEqual(q.sceneChange, .never)
        XCTAssertEqual(q.shownTitle, "Song 5"); XCTAssertEqual(q.cards, .beginning); XCTAssertFalse(q.songVideos)
        XCTAssertEqual(LoopVideo.songVideoProject(p, track: 0)?.clip, "a.mp4")
        XCTAssertNil(LoopVideo.songVideoProject(p, track: 9))
        XCTAssertEqual(LoopVideo.songVideoName(p, track: 4, seconds: 600), "05 Song 5 – 10 Minutes")
        XCTAssertEqual(p.tracks.count, 6, "the album itself is untouched")
    }
    func testOldProjectsHaveNoSongVideos() throws {
        XCTAssertFalse(try JSONDecoder().decode(LoopProject.self, from: Data("{\"title\":\"x\"}".utf8)).songVideos)
        let back = try JSONDecoder().decode(LoopProject.self, from: JSONEncoder().encode(album()))
        XCTAssertTrue(back.songVideos)
    }
}

/// Makes real song videos from a copy of a looping project. Runs only with MV_REAL_LOOP=<copy of a project folder>.
final class LoopSongVideosRealTests: XCTestCase {
    func testRealSongVideos() async throws {
        let path = ProcessInfo.processInfo.environment["MV_REAL_LOOP"] ?? ""
        try XCTSkipIf(path.isEmpty, "set MV_REAL_LOOP")
        let dir = URL(fileURLWithPath: path)
        var p = try LoopVideo.load(dir)
        p.tracks = Array(p.tracks.prefix(2)); for k in p.tracks.indices { p.tracks[k].repeatMode = .minutes(2); p.tracks[k].clip = nil }
        p.playOnce = true; p.sceneChange = .never
        try LoopVideo.ensureAnalysis(&p, dir: dir)
        let folder = dir.appendingPathComponent("song-videos-test")
        let made = try await LoopVideo.makeSongVideos(p, dir: dir, folder: folder)
        XCTAssertEqual(made.count, 2)
        for u in made {
            let d = CMTimeGetSeconds(try await AVURLAsset(url: u).load(.duration))
            print("SONGVIDEO", u.lastPathComponent, d, (try? FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(u.deletingPathExtension().lastPathComponent) }) ?? [])
            XCTAssertEqual(d, 120, accuracy: 12)
        }
    }
}
