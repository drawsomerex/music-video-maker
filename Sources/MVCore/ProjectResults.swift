// Background generators own new media and costs, not the whole editable project snapshot.
import Foundation

extension Pipeline {
    static let projectWriteLock = NSRecursiveLock()

    /// Merge a completed paid output into the latest saved project under the same lock as ordinary saves.
    /// Keep the task's local result unchanged so its caller can merge the same cost delta into live state exactly once.
    static func saveMediaResult(_ done: Plan, startedFrom before: Plan, section index: Int, work: URL, artwork: Bool) throws {
        projectWriteLock.lock(); defer { projectWriteLock.unlock() }
        guard FileManager.default.fileExists(atPath: planURL(work).path) else { try savePlan(done, work); return }
        var current = try loadPlan(work)
        guard current.projectID == before.projectID else { throw MVError("The original project identity changed. The new media stays in its original folder.") }
        let produced = index < 0 ? done.intro : done.sections[index]
        let initial = index < 0 ? before.intro : before.sections[index]
        let originalJobs = Set((initial.clips + initial.retainedClips).compactMap(\.jobID))
        let savedJobs = Set(TimelineEditor.allMediaSections([current.intro] + current.sections).flatMap { $0.clips + $0.retainedClips }.compactMap(\.jobID))
        let duplicateProviderCost = TimelineEditor.uniqueClips(produced.retainedClips).filter { clip in
            guard let job = clip.jobID else { return false }; return !originalJobs.contains(job) && savedJobs.contains(job)
        }.reduce(0) { $0 + $1.costUSD }
        func merge(_ target: inout PhotoSection) {
            for candidate in produced.candidates where !target.candidates.contains(where: { $0.id == candidate.id }) { target.candidates.append(candidate) }
            target.retainedClips = TimelineEditor.uniqueClips(target.retainedClips + produced.retainedClips)
            if artwork && !Task.isCancelled && target.selectedCandidate?.id == initial.selectedCandidate?.id,
               let id = produced.selectedCandidate?.id {
                target.selected = target.candidates.firstIndex { $0.id == id } ?? target.selected
                target.mediaParts = nil; target.playbackOffset = 0; target.useClips = false
            }
        }
        if index < 0 { merge(&current.intro) }
        else if current.sections.indices.contains(index), current.sections.count == before.sections.count { merge(&current.sections[index]) }
        else { // A manually edited boundary can never lose a paid original.
            for i in current.sections.indices where current.sections[i].end > initial.start && current.sections[i].start < initial.end { merge(&current.sections[i]) }
        }
        current.totalGenerationCostUSD += max(0, done.totalGenerationCostUSD - before.totalGenerationCostUSD)
        current.totalVideoCostUSD += max(0, done.totalVideoCostUSD - before.totalVideoCostUSD - duplicateProviderCost)
        current.imagesGeneratedCount += max(0, done.imagesGeneratedCount - before.imagesGeneratedCount)
        if done.lastImageCostUSD != before.lastImageCostUSD { current.lastImageCostUSD = done.lastImageCostUSD }
        if done.castSheet != before.castSheet && current.castSheet == before.castSheet { current.castSheet = done.castSheet }
        try savePlan(current, work)
    }
}

extension LoopVideo {
    static let projectWriteLock = NSRecursiveLock()

    /// Three-way merge for a background loop operation. User edits win conflicts; paid additions and cost deltas survive Stop.
    static func saveMediaResult(_ done: LoopProject, startedFrom before: LoopProject, dir: URL) throws {
        projectWriteLock.lock(); defer { projectWriteLock.unlock() }
        guard isLoopProject(dir) else { try saveChecked(done, dir); return }
        let current = try load(dir)
        let duplicateProviderCost = done.clips.filter { !before.clips.contains($0) && current.clips.contains($0) }.reduce(0) { $0 + (done.versionCosts[$1] ?? 0) }
        guard current.id == before.id else { throw MVError("The original looping-project identity changed. New media stays in its original folder.") }
        func object(_ project: LoopProject) throws -> [String: Any] { try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as! [String: Any] }
        let base = try object(before), result = try object(done)
        var latest = try object(current)
        func same(_ a: Any?, _ b: Any?) -> Bool { NSDictionary(dictionary: ["value": a ?? NSNull()]).isEqual(to: ["value": b ?? NSNull()]) }
        let money = Set(["imagesUSD", "videoUSD", "pictureCount"])
        let originals = Set(["pictures", "clips", "enhanced", "enlarged"])
        for key in Set(base.keys).union(result.keys) where !same(result[key], base[key]) {
            guard let value = result[key] else {
                if same(latest[key], base[key]) { latest.removeValue(forKey: key) }
                continue
            }
            if money.contains(key) {
                let delta = (value as? NSNumber)?.doubleValue ?? 0
                latest[key] = ((latest[key] as? NSNumber)?.doubleValue ?? 0) + max(0, delta - ((base[key] as? NSNumber)?.doubleValue ?? 0) - (key == "videoUSD" ? duplicateProviderCost : 0))
            } else if originals.contains(key), let values = value as? [String] {
                var files = latest[key] as? [String] ?? []
                for file in values where !(base[key] as? [String] ?? []).contains(file) && !files.contains(file) { files.append(file) }
                latest[key] = files
            } else if let values = value as? [String: Any] {
                var dictionary = latest[key] as? [String: Any] ?? [:]
                let old = base[key] as? [String: Any] ?? [:]
                for (name, new) in values where !same(new, old[name]) && same(dictionary[name], old[name]) { dictionary[name] = new }
                latest[key] = dictionary
            } else if same(latest[key], base[key]), !(Task.isCancelled && ["picture", "clip", "scene", "motion"].contains(key)) {
                latest[key] = value
            }
        }
        let merged = try JSONDecoder().decode(LoopProject.self, from: JSONSerialization.data(withJSONObject: latest))
        try saveChecked(merged, dir)
    }
}
