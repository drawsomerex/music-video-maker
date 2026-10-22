// Every project in the main folder (and recently opened ones elsewhere): music videos with lyrics and looping long videos,
// with what the Projects screen shows for each (title, picture, when it was last changed, what it cost, whether a video was made).
import Foundation

public struct ProjectInfo: Identifiable, Hashable {
    public enum Kind: String { case lyric, loop }
    public var id: String { folder.path }
    public var folder: URL                 // the project folder (project.mvproj or loop.json is inside)
    public var kind: Kind
    public var title: String
    public var modified: Date
    public var thumbnail: URL?
    public var spentUSD: Double
    public var video: URL?                 // the finished video, if one was made
    public var detail: String              // e.g. "14 pictures · 3 Shorts" or "8 hours · 15 s loop"
    /// What "Move to Trash" moves: the song's own folder (it also holds its finished videos), never the main folder.
    public func trashTarget(root: URL) -> URL {
        let parent = folder.deletingLastPathComponent()
        if kind == .lyric, parent.standardizedFileURL != root.standardizedFileURL, parent.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL { return parent }
        return folder
    }
}

public enum ProjectLibrary {
    public static func scan(root: URL, extra: [URL] = []) -> [ProjectInfo] {
        let fm = FileManager.default
        var folders: [URL] = []
        for d in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where d.lastPathComponent != "Pictures" && !d.lastPathComponent.hasPrefix(".") {
            if Pipeline.isProject(d) || LoopVideo.isLoopProject(d) { folders.append(d); continue }
            for e in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where Pipeline.isProject(e) || LoopVideo.isLoopProject(e) { folders.append(e) }
        }
        for e in extra where (Pipeline.isProject(e) || LoopVideo.isLoopProject(e)) && !folders.contains(where: { $0.standardizedFileURL == e.standardizedFileURL }) { folders.append(e) }
        return folders.compactMap(info).sorted { $0.modified > $1.modified }
    }

    static func info(_ dir: URL) -> ProjectInfo? {
        let fm = FileManager.default
        func modified(_ u: URL) -> Date { (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date ?? .distantPast }
        if LoopVideo.isLoopProject(dir), let p = try? LoopVideo.load(dir) {
            let file = dir.appendingPathComponent(LoopVideo.fileName)
            let video = p.output.map { URL(fileURLWithPath: $0) }.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
            let hours = p.hours == p.hours.rounded() ? "\(Int(p.hours)) h" : String(format: "%.1f h", p.hours)
            return ProjectInfo(folder: dir, kind: .loop, title: p.title, modified: modified(file), thumbnail: p.picture.map { dir.appendingPathComponent($0) },
                               spentUSD: p.imagesUSD + p.videoUSD, video: video, detail: "\(hours) · " + (p.clip == nil ? "no loop clip yet" : "loop clip ready"))
        }
        let file = Pipeline.planURL(dir)
        guard let d = try? Data(contentsOf: fm.fileExists(atPath: file.path) ? file : dir.appendingPathComponent("plan.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let title = o["title"] as? String ?? dir.lastPathComponent
        func thumb(_ s: [String: Any]?) -> URL? {
            guard let s, let sel = s["selected"] as? Int, let cands = s["candidates"] as? [[String: Any]], cands.indices.contains(sel) else { return nil }
            return ((cands[sel]["thumbFile"] as? String) ?? (cands[sel]["fullFile"] as? String)).map { dir.appendingPathComponent($0) }
        }
        let sections = o["sections"] as? [[String: Any]] ?? []
        let pic = thumb(o["intro"] as? [String: Any]) ?? sections.lazy.compactMap(thumb).first
        let made = sections.filter { thumb($0) != nil }.count + (thumb(o["intro"] as? [String: Any]) != nil ? 1 : 0)
        let shorts = (o["shorts"] as? [Any])?.count ?? 0
        let spent = ((o["totalGenerationCostUSD"] as? Double) ?? 0) + ((o["totalVideoCostUSD"] as? Double) ?? 0)
        // the finished video sits next to the project folder (or in the chosen output folder): "<title>.mp4"
        let name = title.replacingOccurrences(of: "/", with: "-") + ".mp4"
        let candidates = [dir.deletingLastPathComponent().appendingPathComponent(name), dir.appendingPathComponent(name)]
        return ProjectInfo(folder: dir, kind: .lyric, title: title, modified: modified(file), thumbnail: pic, spentUSD: spent,
                           video: candidates.first { fm.fileExists(atPath: $0.path) }, detail: "\(made) of \(sections.count + 1) pictures" + (shorts > 0 ? " · \(shorts) Shorts" : ""))
    }
}
