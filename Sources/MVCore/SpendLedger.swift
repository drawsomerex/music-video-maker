// A permanent record of what you have spent, kept outside the song folders (in Application Support), so "All songs together" never drops:
// not when the app updates, not when a song is moved, re-planned or its folder is deleted. Each song only ever counts up.
import Foundation

public enum SpendLedger {
    public struct Entry: Codable, Equatable {
        public var title = "", path = ""
        public var imagesUSD = 0.0, videoUSD = 0.0
        public var pictures = 0
    }
    struct File: Codable { var songs: [String: Entry] = [:] }

    nonisolated(unsafe) private static var lastWritten: [String: Entry] = [:]
    private static let queue = DispatchQueue(label: "spend-ledger")

    static var fileURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let f = env["MV_SPEND_FILE"] { return URL(fileURLWithPath: f) }                                        // tests
        if env["MV_TEST_PREFS"] != nil { return FileManager.default.temporaryDirectory.appendingPathComponent("mv-test-spend.json") }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicVideo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spend.json")
    }

    static func read() -> File { (try? JSONDecoder().decode(File.self, from: Data(contentsOf: fileURL))) ?? File() }
    static func write(_ f: File) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(f).write(to: fileURL, options: .atomic)
    }

    /// Records a song's spend. Numbers only ever go up, so re-planning a song or deleting pictures never lowers the total.
    public static func record(_ key: String, _ e: Entry) {
        guard !key.isEmpty, e.imagesUSD > 0 || e.videoUSD > 0 else { return }
        queue.sync { recordLocked(key, e) }
    }
    private static func recordLocked(_ key: String, _ e: Entry) {
        if lastWritten[key] == e { return }
        var f = read()
        if !e.path.isEmpty { for (k, old) in f.songs where k != key && old.path == e.path && k.hasPrefix("path:") { f.songs[k] = nil } }      // an old path-keyed entry becomes this one
        var m = f.songs[key] ?? Entry()
        m.title = e.title; m.path = e.path
        m.imagesUSD = max(m.imagesUSD, e.imagesUSD); m.videoUSD = max(m.videoUSD, e.videoUSD); m.pictures = max(m.pictures, e.pictures)
        f.songs[key] = m
        write(f); lastWritten[key] = e
    }

    public static func total() -> (usd: Double, pictures: Int, songs: Int) {
        let f = read()
        return (f.songs.values.reduce(0) { $0 + $1.imagesUSD + $1.videoUSD }, f.songs.values.reduce(0) { $0 + $1.pictures }, f.songs.values.filter { $0.imagesUSD + $0.videoUSD > 0 }.count)
    }
}
