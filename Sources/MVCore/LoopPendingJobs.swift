// Paid loop orders live outside the editable project snapshot: Stop, Undo and normal saves cannot erase them.
import Foundation

extension LoopVideo {
    public struct PendingLoopJob: Codable, Equatable {
        public var id: String
        public var options: ClipOptions
        public var started: Date
        public init(id: String, options: ClipOptions, started: Date = Date()) { self.id = id; self.options = options; self.started = started }
    }
    private static let pendingLock = NSRecursiveLock()
    static func pendingLoopURL(_ dir: URL) -> URL { dir.appendingPathComponent("pending_loop_jobs.json") }
    public static func pendingLoopJobs(_ dir: URL) -> [PendingLoopJob] {
        pendingLock.lock(); defer { pendingLock.unlock() }
        guard let data = try? Data(contentsOf: pendingLoopURL(dir)) else { return [] }
        return (try? JSONDecoder().decode([PendingLoopJob].self, from: data)) ?? []
    }
    static func writeLoopJobs(_ jobs: [PendingLoopJob], dir: URL) throws {
        try JSONEncoder().encode(jobs).write(to: pendingLoopURL(dir), options: .atomic)
    }
    static func recordLoopJob(_ job: PendingLoopJob, dir: URL) throws {
        pendingLock.lock(); defer { pendingLock.unlock() }
        let file = pendingLoopURL(dir)
        var jobs = FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode([PendingLoopJob].self, from: Data(contentsOf: file)) : []
        if !jobs.contains(where: { $0.id == job.id }) { jobs.append(job) }
        try writeLoopJobs(jobs, dir: dir)
    }
    static func removeLoopJob(_ id: String, dir: URL) throws {
        pendingLock.lock(); defer { pendingLock.unlock() }
        try writeLoopJobs(pendingLoopJobs(dir).filter { $0.id != id }, dir: dir)
    }
    static func clipFile(job id: String) -> String { "clip-" + String(stableSeed(id)) + ".mp4" }
    public static func acknowledgeLoopJobs(_ project: LoopProject, dir: URL) throws {
        for job in pendingLoopJobs(dir) {
            let file = clipFile(job: job.id)
            if project.clips.contains(file), FileManager.default.fileExists(atPath: dir.appendingPathComponent(file).path) { try removeLoopJob(job.id, dir: dir) }
        }
    }

}
