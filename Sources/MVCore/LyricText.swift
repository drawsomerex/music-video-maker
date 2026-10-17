// Helpers for the "divide your lyrics into parts" feature: a line of three dashes (---) starts a new part, i.e. a new picture.
import Foundation

public enum LyricText {
    public struct Row: Identifiable {
        public var id: Int { index }
        public var index: Int            // lyric-line number (0-based, tags and blank lines don't count)
        public var text: String
        public var startsPart: Bool      // a --- divider sits right before this line (or it is the first line)
        public var blankBefore: Bool     // a blank line / [tag] sits before it (a natural verse break)
    }

    public static func isDivider(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespaces)
        return s.count >= 3 && (s.allSatisfy { $0 == "-" } || s.allSatisfy { $0 == "=" })
    }
    static func isTag(_ t: String) -> Bool { (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("(") && t.hasSuffix(")") && t.split(separator: " ").count <= 3) }

    /// The lyric lines of `raw` with where parts start.
    public static func rows(_ raw: String) -> [Row] {
        var out: [Row] = []; var part = true, blank = false
        for l in raw.components(separatedBy: .newlines) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || isTag(t) { blank = true; continue }
            if isDivider(t) { part = true; blank = true; continue }
            out.append(Row(index: out.count, text: t, startsPart: part, blankBefore: blank && !out.isEmpty)); part = false; blank = false
        }
        return out
    }
    public static func partCount(_ raw: String) -> Int { rows(raw).filter(\.startsPart).count }
    public static func hasDividers(_ raw: String) -> Bool { raw.components(separatedBy: .newlines).contains { isDivider($0) } }

    /// Adds a divider before lyric line `i`, or removes the one that is there.
    public static func toggleDivider(_ raw: String, before i: Int) -> String {
        guard i > 0 else { return raw }
        var out: [String] = []; var n = 0
        for l in raw.components(separatedBy: .newlines) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || isTag(t) || isDivider(t) { out.append(l); continue }
            if n == i {
                // strip dividers sitting directly above this line; if there were none, add one
                var removed = false
                while let last = out.last, isDivider(last) || last.trimmingCharacters(in: .whitespaces).isEmpty {
                    if isDivider(last) { removed = true }
                    out.removeLast()
                    if removed, let l2 = out.last, l2.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                }
                if !removed { out.append("---") }
            }
            out.append(l); n += 1
        }
        return out.joined(separator: "\n")
    }

    public static func clearDividers(_ raw: String) -> String { raw.components(separatedBy: .newlines).filter { !isDivider($0) }.joined(separator: "\n") }

    /// Turns every blank-line verse break into a part divider (a quick starting point to adjust).
    public static func dividersFromVerses(_ raw: String) -> String {
        let rs = rows(clearDividers(raw))
        return text(lines: rs.map(\.text), partStarts: rs.filter(\.blankBefore).map(\.index))
    }

    /// Lyrics text from line texts, with `---` before each line index in `partStarts` (index 0 ignored).
    public static func text(lines: [String], partStarts: [Int]) -> String {
        let starts = Set(partStarts.filter { $0 > 0 })
        var out: [String] = []
        for (i, l) in lines.enumerated() { if starts.contains(i) { out.append("---") }; out.append(l) }
        return out.joined(separator: "\n")
    }

    /// Divides the lyrics into `parts` parts of about the same number of lines, nudging each cut to a nearby verse break when there is one.
    public static func divideEvenly(_ raw: String, parts: Int) -> String {
        let rs = rows(clearDividers(raw))
        guard rs.count > 1, parts > 1 else { return clearDividers(raw) }
        let n = min(parts, rs.count)
        var cuts: [Int] = []
        for k in 1..<n {
            let ideal = Int((Double(k) * Double(rs.count) / Double(n)).rounded())
            let window = rs.count / (n * 4)
            let near = window == 0 ? [] : (max(1, ideal - window)...min(rs.count - 1, ideal + window)).filter { rs[$0].blankBefore }
            cuts.append(near.min { abs($0 - ideal) < abs($1 - ideal) } ?? ideal)
        }
        let uniq = Array(Set(cuts)).filter { $0 > 0 && $0 < rs.count }.sorted()
        return text(lines: rs.map(\.text), partStarts: uniq)
    }
}
