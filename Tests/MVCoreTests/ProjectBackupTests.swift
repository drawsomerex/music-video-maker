import XCTest
@testable import MVCore

final class ProjectBackupTests: XCTestCase {
    func folder() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("mv-backup-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    func testLoopBackupContainsAudioPicturesClipsAndReferences() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        var p = LoopProject()
        p.tracks = [LoopTrack(file: "tracks/song.wav", title: "Song", seconds: 5)]
        p.pictures = ["picture.jpg"]; p.picture = "picture.jpg"; p.clips = ["clip.mp4"]; p.clip = "clip.mp4"
        p.source = "reference.jpg"; p.castSheet = "cast.jpg"
        let files = p.tracks.map(\.file) + p.pictures + p.clips + [p.source!, p.castSheet!]
        for file in files { let u = root.appendingPathComponent(file); try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try Data([1, 2, 3]).write(to: u) }
        let backup = try ProjectBackup.create(loop: p, work: root)
        XCTAssertEqual(try LoopVideo.load(backup).id, p.id)
        for file in files { XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(file)), Data([1, 2, 3])) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("BackupManifest.json").path))
    }
    func testMissingMediaRefusesBackupAndRemovesIncompleteFolder() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        var p = LoopProject(); p.pictures = ["missing.jpg"]
        XCTAssertThrowsError(try ProjectBackup.create(loop: p, work: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Version Backups").path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(LoopVideo.fileName).path))
    }
    func testUnsafePathsNeverEscapeProjectFolder() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        var p = LoopProject(); p.pictures = ["../private.jpg"]
        XCTAssertThrowsError(try ProjectBackup.create(loop: p, work: root))
    }
    func testLoopSaveFailureIsReportedToCaller() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/missing")
        XCTAssertThrowsError(try LoopVideo.saveChecked(LoopProject(), missing))
        XCTAssertFalse(LoopVideo.save(LoopProject(), missing))
    }
}
