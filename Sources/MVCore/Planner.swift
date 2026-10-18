// Splits the song into sections (about one picture per N seconds), respecting stanzas and choruses.
import Foundation

/// Splits the song into image "sections" (one photo each) along stanza / line boundaries,
/// targeting roughly one image per 10–18 s and never outside 6–30 s.
public enum Planner {
    public struct Options {
        public var target = 14.0, minLen = 7.0, maxLen = 26.0
        public init() {}
        /// One image roughly every `seconds` (the fewer images you want to generate, the larger this is).
        public init(imageInterval seconds: Double) { target = seconds; minLen = seconds * 0.5; maxLen = seconds * 1.8 }
    }

    /// `partBreaks`: parts the user divided by hand. When given, each part becomes exactly one picture (no automatic splitting or merging).
    public static func plan(lines: [LyricLine], stanzaBreaks: Set<Int>, partBreaks: Set<Int> = [], songDuration: Double, opts: Options = .init()) -> [PhotoSection] {
        guard !lines.isEmpty else {
            return evenSections(0, songDuration, opts: opts, startID: 0)
        }
        // 1. stanza units (arrays of line indices)
        let userParts = !partBreaks.isEmpty
        var units: [[Int]] = []; var cur: [Int] = []
        for i in lines.indices {
            if (userParts ? partBreaks : stanzaBreaks).contains(i) && !cur.isEmpty { units.append(cur); cur = [] }
            cur.append(i)
        }
        if !cur.isEmpty { units.append(cur) }

        // 2. split long units at line boundaries
        func span(_ u: [Int]) -> Double { lines[u.last!].end - lines[u.first!].start }
        var pieces: [[Int]] = []
        for u in units {
            if userParts || span(u) <= opts.maxLen { pieces.append(u); continue }
            let k = Int((span(u) / opts.target).rounded())
            let per = span(u) / Double(max(k, 2))
            var chunk: [Int] = []; var chunkStart = lines[u[0]].start
            for li in u {
                if !chunk.isEmpty && lines[li].end - chunkStart > per * 1.08 { pieces.append(chunk); chunk = []; chunkStart = lines[li].start }
                chunk.append(li)
            }
            if !chunk.isEmpty { pieces.append(chunk) }
        }
        // 3. merge short pieces into neighbours
        var merged: [[Int]] = []
        for p in pieces {
            if !userParts, let last = merged.last, span(last) < opts.minLen || span(p) < opts.minLen,
               span(last) + (lines[p.first!].start - lines[last.last!].end) + span(p) <= opts.maxLen {
                merged[merged.count - 1] = last + p
            } else { merged.append(p) }
        }
        // 4. boundaries at the midpoint of gaps; add pure-instrumental sections for long gaps
        struct Unit { var lines: [Int]; var s: Double; var e: Double }
        var items: [Unit] = merged.map { Unit(lines: $0, s: lines[$0.first!].start, e: lines[$0.last!].end) }
        var withGaps: [Unit] = []
        // Music before the first words gets its own picture once there are ≥ 3 s of it after the title card (which covers the first ~6 s).
        if let f = items.first, f.s >= 3.3, f.s - min(6.0, f.s - 0.6) >= 3.0 || f.s > opts.maxLen * 0.7 { withGaps.append(Unit(lines: [], s: 0, e: f.s)) }
        for (i, u) in items.enumerated() {
            if i > 0 {
                let gap = u.s - items[i-1].e
                if gap > opts.maxLen * 0.6 { withGaps.append(Unit(lines: [], s: items[i-1].e, e: u.s)) }
            }
            withGaps.append(u)
        }
        if let l = items.last, songDuration - l.e > opts.maxLen * 0.6 { withGaps.append(Unit(lines: [], s: l.e, e: songDuration)) }
        items = withGaps

        var out: [PhotoSection] = []
        for (i, u) in items.enumerated() {
            let start = i == 0 ? 0 : (items[i-1].e + u.s) / 2
            let end = i == items.count - 1 ? songDuration : (u.e + items[i+1].s) / 2
            if u.lines.isEmpty && end - start > opts.maxLen {
                out += evenSections(start, end, opts: opts, startID: out.count)
            } else {
                out.append(PhotoSection(id: out.count, start: start, end: end, lineIDs: u.lines, queries: [], candidates: [], selected: -1, seed: UInt64(out.count) &* 0x9E3779B97F4A7C15 &+ 7))
            }
        }
        for i in out.indices { out[i].id = i }
        return out
    }

    /// Music-only stretches shorter than this are not given a picture of their own.
    public static let shortestBreak = 4.0, longBreak = 40.0, longestPicture = 30.0

    /// One picture per verse and one per music break (the default). A music break longer than `longBreak` is split into equal pictures of at most `longestPicture`;
    /// breaks under `shortestBreak` belong to the verse next to them. `partBreaks` (your own cuts) decide where verses start; otherwise your verse marks do;
    /// with neither, every run of lyrics between two music breaks is a verse, and a run longer than 45 s is cut at its longest pauses.
    public static func structure(lines: [LyricLine], stanzaBreaks: Set<Int>, partBreaks: Set<Int> = [], songDuration: Double) -> [PhotoSection] {
        func make(_ s: Double, _ e: Double, _ ids: [Int], _ n: Int) -> PhotoSection {
            PhotoSection(id: n, start: s, end: e, lineIDs: ids, queries: [], candidates: [], selected: -1, seed: UInt64(n) &* 0x9E3779B97F4A7C15 &+ 7)
        }
        guard !lines.isEmpty else { return evenSections(0, songDuration, opts: .init(imageInterval: longestPicture * 0.8), startID: 0) }
        let gapBefore = lines.indices.map { $0 == 0 ? 0 : lines[$0].start - lines[$0 - 1].end }
        let isBreak: (Int) -> Bool = { $0 > 0 && gapBefore[$0] >= shortestBreak }
        let explicit = !partBreaks.isEmpty
        let marks = explicit ? partBreaks : stanzaBreaks
        let useMarks = explicit || (stanzaBreaks.count + 1 <= max(2, Int(songDuration / 6)) && !stanzaBreaks.isEmpty)
        // verse units: lines grouped by marks and by music breaks
        var units: [[Int]] = []; var cur: [Int] = []
        for i in lines.indices {
            if !cur.isEmpty && ((useMarks && marks.contains(i)) || isBreak(i)) { units.append(cur); cur = [] }
            cur.append(i)
        }
        if !cur.isEmpty { units.append(cur) }
        // no marks of any kind: cut a very long run at its longest pauses
        if !useMarks {
            var out: [[Int]] = []
            for u in units {
                let span = lines[u.last!].end - lines[u.first!].start
                guard span > 45, u.count > 3 else { out.append(u); continue }
                let k = Int((span / 25).rounded())
                let s0 = lines[u.first!].start
                var cutAt = Set<Int>()
                for j in 1..<max(2, k) {                              // near each equal-length point, cut at the longest pause around it
                    let target = s0 + span * Double(j) / Double(k), reach = span / Double(k) * 0.3
                    let near = u.dropFirst().filter { abs(lines[$0].start - target) <= reach && !cutAt.contains($0) }
                    if let best = near.max(by: { (lines[$0].start - lines[$0 - 1].end) < (lines[$1].start - lines[$1 - 1].end) })
                        ?? u.dropFirst().min(by: { abs(lines[$0].start - target) < abs(lines[$1].start - target) }) { cutAt.insert(best) }
                }
                var piece: [Int] = []
                for i in u { if cutAt.contains(i) && !piece.isEmpty { out.append(piece); piece = [] }; piece.append(i) }
                if !piece.isEmpty { out.append(piece) }
            }
            units = out
        }
        // items in time order: verses and music breaks
        struct Item { var lines: [Int]; var s: Double; var e: Double }
        var items: [Item] = []
        let first = lines[0].start
        if first >= 3.3, first - min(6.0, first - 0.6) >= 3.0 { items.append(Item(lines: [], s: 0, e: first)) }    // music before the words (after the title card)
        for (k, u) in units.enumerated() {
            if k > 0, let prev = units[k - 1].last, let f = u.first, lines[f].start - lines[prev].end >= shortestBreak { items.append(Item(lines: [], s: lines[prev].end, e: lines[f].start)) }
            items.append(Item(lines: u, s: lines[u.first!].start, e: lines[u.last!].end))
        }
        if let l = lines.last, songDuration - l.end >= shortestBreak { items.append(Item(lines: [], s: l.end, e: songDuration)) }
        var out: [PhotoSection] = []
        for (i, it) in items.enumerated() {
            let start = i == 0 ? 0 : (items[i - 1].e + it.s) / 2
            let end = i == items.count - 1 ? songDuration : (it.e + items[i + 1].s) / 2
            if it.lines.isEmpty && end - start > longBreak {                         // a very long music break: equal pictures of up to 30 s
                let k = Int(ceil((end - start) / longestPicture))
                for j in 0..<k { out.append(make(start + (end - start) * Double(j) / Double(k), start + (end - start) * Double(j + 1) / Double(k), [], out.count)) }
            } else { out.append(make(start, end, it.lines, out.count)) }
        }
        return out
    }

    static func evenSections(_ a: Double, _ b: Double, opts: Options, startID: Int) -> [PhotoSection] {
        let k = max(1, Int(((b - a) / opts.target).rounded()))
        return (0..<k).map { i in
            let s = a + (b - a) * Double(i) / Double(k), e = a + (b - a) * Double(i + 1) / Double(k)
            return PhotoSection(id: startID + i, start: s, end: e, lineIDs: [], queries: [], candidates: [], selected: -1, seed: UInt64(startID + i) &* 0x9E3779B97F4A7C15 &+ 7)
        }
    }

    /// Recomputes section edges after the lyrics were re-timed: each edge sits at the midpoint of the gap between neighbouring lyric blocks.
    public static func rebound(_ old: [PhotoSection], lines: [LyricLine], duration: Double) -> [PhotoSection] {
        var s = old
        func first(_ x: PhotoSection) -> Double? { x.lineIDs.compactMap { lines.indices.contains($0) ? lines[$0].start : nil }.min() }
        func last(_ x: PhotoSection) -> Double? { x.lineIDs.compactMap { lines.indices.contains($0) ? lines[$0].end : nil }.max() }
        for i in s.indices {
            if i == 0 { s[i].start = 0; continue }
            if let a = last(s[i - 1]), let b = first(s[i]) { s[i].start = (a + b) / 2; s[i - 1].end = s[i].start }
        }
        if !s.isEmpty { s[s.count - 1].end = duration }
        return s
    }
}
