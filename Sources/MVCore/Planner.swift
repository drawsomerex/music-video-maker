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

    public static func plan(lines: [LyricLine], stanzaBreaks: Set<Int>, songDuration: Double, opts: Options = .init()) -> [PhotoSection] {
        guard !lines.isEmpty else {
            return evenSections(0, songDuration, opts: opts, startID: 0)
        }
        // 1. stanza units (arrays of line indices)
        var units: [[Int]] = []; var cur: [Int] = []
        for i in lines.indices {
            if stanzaBreaks.contains(i) && !cur.isEmpty { units.append(cur); cur = [] }
            cur.append(i)
        }
        if !cur.isEmpty { units.append(cur) }

        // 2. split long units at line boundaries
        func span(_ u: [Int]) -> Double { lines[u.last!].end - lines[u.first!].start }
        var pieces: [[Int]] = []
        for u in units {
            if span(u) <= opts.maxLen { pieces.append(u); continue }
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
            if let last = merged.last, span(last) < opts.minLen || span(p) < opts.minLen,
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
