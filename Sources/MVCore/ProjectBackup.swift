// Version switching uses the same complete, self-contained backup for either project kind.
import Foundation

public enum ProjectBackup {
    public struct Manifest: Codable { public var kind: String; public var created: Date; public var files: [String] }

    /// Copies referenced originals, not derived previews/exports. Missing or unsafe media refuses the version switch.
    @discardableResult
    public static func create(plan: Plan, work: URL) throws -> URL {
        try Pipeline.savePlan(plan, work)
        var copy = plan
        let media = TimelineEditor.allMediaSections([plan.intro] + plan.sections)
        var files = Set(media.flatMap(\.candidates).flatMap { [$0.fullFile, $0.thumbFile, $0.videoFile].compactMap { $0 } })
        for s in media { for c in s.clips + s.retainedClips { files.insert(c.file); files.insert(c.lastFrame) } }
        for file in [plan.source, plan.subjectPicture, plan.castSheet].compactMap({ $0 }) { files.insert(file) }
        if !plan.audioFile.isEmpty { files.insert(plan.audioFile) }
        for name in ["pending_video_jobs.json", "video_jobs.jsonl"] where FileManager.default.fileExists(atPath: work.appendingPathComponent(name).path) { files.insert(name) }
        return try write(kind: "music", files: files, work: work) { folder in
            if copy.audioFile.isEmpty {
                let source = Pipeline.audioURL(plan, work: work)
                let name = "audio." + (source.pathExtension.isEmpty ? "wav" : source.pathExtension)
                guard FileManager.default.fileExists(atPath: source.path) else { throw MVError("The song is missing. Restore it before changing app versions.") }
                try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name)); copy.audioFile = name
            }
            try Pipeline.savePlan(copy, folder)
        }
    }

    @discardableResult
    public static func create(loop: LoopProject, work: URL) throws -> URL {
        try LoopVideo.saveChecked(loop, work)
        var files = Set(loop.pictures + loop.clips + loop.tracks.map(\.file))
        for name in [loop.songFile, loop.source ?? "", loop.subject ?? "", loop.castSheet ?? ""] where !name.isEmpty { files.insert(name) }
        return try write(kind: "loop", files: files, work: work) { folder in try LoopVideo.saveChecked(loop, folder) }
    }

    private static func write(kind: String, files: Set<String>, work: URL, save: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default, folder = work.appendingPathComponent("Version Backups/" + UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let root = work.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            let names = files.filter { !$0.isEmpty }.sorted()
            for name in names {
                guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { throw MVError("A project media path is unsafe to back up.") }
                let source = work.appendingPathComponent(name), target = folder.appendingPathComponent(name)
                guard source.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else { throw MVError("A project media link points outside its folder. Copy that media into the project before changing versions.") }
                guard fm.fileExists(atPath: source.path) else { throw MVError("The project file “\(name)” is missing. Restore or remove that unused version before changing app versions.") }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
            }
            try save(folder)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(Manifest(kind: kind, created: Date(), files: names)).write(to: folder.appendingPathComponent("BackupManifest.json"), options: .atomic)
            return folder
        } catch {
            try? fm.removeItem(at: folder) // only the unique incomplete backup; never the project's originals
            throw error
        }
    }
}
