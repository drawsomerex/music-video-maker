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
    public static func save(_ source: URL, title: String, config: Config = .load()) -> String? {
        let fm = FileManager.default, dir = folder(config: config), name = safe(title)
        // the next number for this project: one more than the highest already used, so the numbers only ever go up
        var highest = 0
        for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            let base = (f as NSString).deletingPathExtension
            guard base.hasSuffix(" ") == false, let r = base.range(of: " " + name + " ", options: [.backwards]) , let n = Int(base[r.upperBound...]) else { continue }
            highest = max(highest, n)
        }
        let day = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: Date()) }()
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let file = String(format: "%@ %@ %03d.%@", day, name, highest + 1, ext)
        do { try fm.copyItem(at: source, to: dir.appendingPathComponent(file)); return file } catch { return nil }
    }
}
