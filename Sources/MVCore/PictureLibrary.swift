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

    /// Copies the pictures of every earlier song into the Pictures folder (oldest first, dated by when each picture was made). Songs already done are skipped.
    /// `skipping` is the project that is open in the app right now. Returns how many pictures were added and in how many songs.
    public static func backfill(config: Config = .load(), skipping open: URL? = nil, progress: ((String, Double) -> Void)? = nil) -> (added: Int, songs: Int) {
        let fm = FileManager.default, root = config.projectsRoot
        var works: [URL] = []
        for d in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where d.lastPathComponent != "Pictures" {
            if Pipeline.isProject(d) { works.append(d) }
            else { for e in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where Pipeline.isProject(e) { works.append(e) } }
        }
        var added = 0, songs = 0
        for (n, w) in works.enumerated() where w.standardizedFileURL != open?.standardizedFileURL {
            progress?("Adding pictures from song \(n + 1) of \(works.count)…", Double(n) / Double(max(1, works.count)))
            guard var plan = try? Pipeline.loadPlan(w) else { continue }
            var todo: [(date: Date, intro: Bool, s: Int, c: Int)] = []
            func scan(_ sec: PhotoSection, intro: Bool, _ si: Int) {
                for (ci, c) in sec.candidates.enumerated() where c.libraryName == nil {
                    guard let f = c.fullFile, let mod = (try? fm.attributesOfItem(atPath: w.appendingPathComponent(f).path))?[.modificationDate] as? Date else { continue }
                    todo.append((mod, intro, si, ci))
                }
            }
            scan(plan.intro, intro: true, -1); for (i, s) in plan.sections.enumerated() { scan(s, intro: false, i) }
            guard !todo.isEmpty else { continue }
            for t in todo.sorted(by: { $0.date < $1.date }) {
                let file = t.intro ? plan.intro.candidates[t.c].fullFile : plan.sections[t.s].candidates[t.c].fullFile
                guard let f = file, let name = save(w.appendingPathComponent(f), title: plan.title, date: t.date, config: config) else { continue }
                if t.intro { plan.intro.candidates[t.c].libraryName = name } else { plan.sections[t.s].candidates[t.c].libraryName = name }
                added += 1
            }
            try? Pipeline.savePlan(plan, w); songs += 1
        }
        progress?("Done", 1)
        return (added, songs)
    }
}
