// What was typed on the Song screen before a project exists, so quitting or a crash doesn't lose it.
import Foundation

public struct SongDraft: Codable, Equatable, Sendable {
    public var title = "", subject = "", notes = "", setting = "", lyrics = "", audioPath: String?
    public init(title: String = "", subject: String = "", notes: String = "", setting: String = "", lyrics: String = "", audioPath: String? = nil) {
        self.title = title; self.subject = subject; self.notes = notes; self.setting = setting; self.lyrics = lyrics; self.audioPath = audioPath
    }
    public var isEmpty: Bool { [title, subject, notes, setting, lyrics].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && audioPath == nil }
    public static var defaultURL: URL { Config.url.deletingLastPathComponent().appendingPathComponent("song-draft.json") }
    public static func load(from url: URL = defaultURL) -> SongDraft? {
        guard let data = try? Data(contentsOf: url), let draft = try? JSONDecoder().decode(SongDraft.self, from: data), !draft.isEmpty else { return nil }
        return draft
    }
    /// An empty draft removes the file.
    public func save(to url: URL = defaultURL) {
        if isEmpty { Self.clear(url); return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    public static func clear(_ url: URL = defaultURL) { try? FileManager.default.removeItem(at: url) }
}
