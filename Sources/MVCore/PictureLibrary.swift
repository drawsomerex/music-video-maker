// One shared "Pictures" folder next to the projects, holding every picture (drawn by the app, or added by you) with an easy-to-scroll name:
//   2026-10-21 First Strike on the Caney River 007.png        (date · project · an increasing number)
// Each project keeps its own copy too, so a project stays complete when you move it. On a Mac disk the copy takes no extra space (it is a clone).
import Foundation

public enum PictureLibrary {
    public static func folder(config: Config = .load()) -> URL {
        let u = ProcessInfo.processInfo.environment["MV_PICTURES_DIR"].map { URL(fileURLWithPath: $0) } ?? config.projectsRoot.appendingPathComponent("Pictures")      // the variable is for tests only
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func safe(_ title: String) -> String {
        let t = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled" : String(t.prefix(80))
    }

    /// Copies `source` into the Pictures folder as "<date> <project> <number>.<ext>" and returns that file name (nil if it could not be saved).
    @discardableResult
    public static func save(_ source: URL, title: String, date: Date = Date(), config: Config = .load()) -> String? {
        let fm = FileManager.default, dir = folder(config: config), name = safe(title)
        // the next number for this project: one more than the highest already used, so the numbers only ever go up
        var highest = 0
        for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            let base = (f as NSString).deletingPathExtension
            guard base.hasSuffix(" ") == false, let r = base.range(of: " " + name + " ", options: [.backwards]) , let n = Int(base[r.upperBound...]) else { continue }
            highest = max(highest, n)
        }
        let day = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: date) }()
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let file = String(format: "%@ %@ %03d.%@", day, name, highest + 1, ext)
        do { try fm.copyItem(at: source, to: dir.appendingPathComponent(file)); return file } catch { return nil }
    }

    /// Copies a generated video clip into the Pictures folder beside the picture it was made from: "<the picture's name> clip 1.mp4" (then "clip 2", …).
    /// A picture that is not in the folder yet gets an ordinary numbered name. Returns the file name, or nil if it could not be saved.
    @discardableResult
    public static func saveClip(_ source: URL, pictureName: String?, title: String, date: Date = Date(), config: Config = .load()) -> String? {
        guard let pic = pictureName else { return save(source, title: title, date: date, config: config) }
        let fm = FileManager.default, dir = folder(config: config)
        let base = (pic as NSString).deletingPathExtension
        let taken = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(base + " clip ") }.count
        let file = "\(base) clip \(taken + 1).\(source.pathExtension.isEmpty ? "mp4" : source.pathExtension.lowercased())"
        do { try fm.copyItem(at: source, to: dir.appendingPathComponent(file)); return file } catch { return nil }
    }

    /// Copies the pictures, imported videos and generated video clips of one song that are not in the Pictures folder yet (oldest first, dated by when each was made).
    /// Clips are named after the picture they were made from. Returns how many files were added.
    @discardableResult
    public static func backfill(plan: inout Plan, work w: URL, config: Config = .load()) -> Int {
        let fm = FileManager.default
        func modified(_ rel: String) -> Date? { (try? fm.attributesOfItem(atPath: w.appendingPathComponent(rel).path))?[.modificationDate] as? Date }
        var todo: [(date: Date, intro: Bool, s: Int, c: Int)] = []
        func scan(_ sec: PhotoSection, intro: Bool, _ si: Int) {
            for (ci, c) in sec.candidates.enumerated() where c.libraryName == nil {
                guard let f = c.videoFile ?? c.fullFile, let mod = modified(f) else { continue }
                todo.append((mod, intro, si, ci))
            }
        }
        scan(plan.intro, intro: true, -1); for (i, s) in plan.sections.enumerated() { scan(s, intro: false, i) }
        var added = 0
        for t in todo.sorted(by: { $0.date < $1.date }) {
            let cand = t.intro ? plan.intro.candidates[t.c] : plan.sections[t.s].candidates[t.c]
            guard let f = cand.videoFile ?? cand.fullFile, let name = save(w.appendingPathComponent(f), title: plan.title, date: modified(f) ?? Date(), config: config) else { continue }
            if t.intro { plan.intro.candidates[t.c].libraryName = name } else { plan.sections[t.s].candidates[t.c].libraryName = name }
            added += 1
        }
        // the generated video clips (named after their picture, so they sit next to it); pictures are done first so each picture has its name
        for (si, sec) in ([plan.intro] + plan.sections).enumerated() {
            for (ci, clip) in sec.clips.enumerated() where clip.libraryName == nil {
                guard fm.fileExists(atPath: w.appendingPathComponent(clip.file).path),
                      let name = saveClip(w.appendingPathComponent(clip.file), pictureName: sec.selectedCandidate?.libraryName, title: plan.title, date: modified(clip.file) ?? Date(), config: config) else { continue }
                if si == 0 { plan.intro.clips[ci].libraryName = name } else { plan.sections[si - 1].clips[ci].libraryName = name }
                added += 1
            }
        }
        return added
    }

    /// The same for every earlier song in the main folder. `skipping` is the song that is open in the app (it is done in memory by the app, not from disk).
    /// Returns how many files were added and in how many songs.
    public static func backfill(config: Config = .load(), skipping open: URL? = nil, progress: ((String, Double) -> Void)? = nil) -> (added: Int, songs: Int) {
        let fm = FileManager.default, root = config.projectsRoot
        var works: [URL] = []
        for d in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where d.lastPathComponent != "Pictures" {
            if Pipeline.isProject(d) { works.append(d) }
            else { for e in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where Pipeline.isProject(e) { works.append(e) } }
        }
        var added = 0, songs = 0
        for (n, w) in works.enumerated() where w.standardizedFileURL != open?.standardizedFileURL {
            progress?("Adding pictures and clips from song \(n + 1) of \(works.count)…", Double(n) / Double(max(1, works.count)))
            guard var plan = try? Pipeline.loadPlan(w) else { continue }
            let n = backfill(plan: &plan, work: w, config: config)
            guard n > 0 else { continue }
            try? Pipeline.savePlan(plan, w); added += n; songs += 1
        }
        progress?("Done", 1)
        return (added, songs)
    }
}
