import Foundation

/// Adds / removes this app's tile in the Dock (the same thing as dragging it there).
enum DockHelper {
    static func tiles() -> [[String: Any]] {
        guard let d = try? run("/usr/bin/defaults", ["export", "com.apple.dock", "-"]),
              let o = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return [] }
        return o["persistent-apps"] as? [[String: Any]] ?? []
    }
    static func path(of tile: [String: Any]) -> String? {
        guard let t = tile["tile-data"] as? [String: Any], let f = t["file-data"] as? [String: Any], let s = f["_CFURLString"] as? String else { return nil }
        return URL(string: s)?.path ?? s
    }
    static func contains(_ app: String) -> Bool { tiles().contains { path(of: $0)?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == app.trimmingCharacters(in: CharacterSet(charactersIn: "/")) } }

    static func set(_ app: String, present: Bool) throws {
        var list = tiles().filter { path(of: $0)?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) != app.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        if present {
            list.append(["tile-type": "file-tile", "tile-data": ["file-data": ["_CFURLString": URL(fileURLWithPath: app).absoluteString, "_CFURLStringType": 15], "file-label": URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent]])
        }
        // Replace the Dock's app list (keeping all its other preferences), then restart the Dock.
        _ = try run("/usr/bin/defaults", ["import", "com.apple.dock", "-"], input: try merged(list))
        _ = try run("/usr/bin/killall", ["Dock"], allowFail: true)
    }

    private static func merged(_ list: [[String: Any]]) throws -> Data {
        let cur = (try? run("/usr/bin/defaults", ["export", "com.apple.dock", "-"])).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
        var o = cur; o["persistent-apps"] = list
        return try PropertyListSerialization.data(fromPropertyList: o, format: .xml, options: 0)
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String], input: Data? = nil, allowFail: Bool = false) throws -> Data {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        if let input { let i = Pipe(); p.standardInput = i; try p.run(); i.fileHandleForWriting.write(input); try? i.fileHandleForWriting.close() } else { try p.run() }
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        if p.terminationStatus != 0 && !allowFail { throw NSError(domain: "Dock", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Couldn't change the Dock (\(exe) failed)."]) }
        return d
    }
}
