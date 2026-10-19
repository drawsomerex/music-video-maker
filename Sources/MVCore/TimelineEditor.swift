// Explicit time boundaries: editing pictures never edits the song or the independent Shorts.
import Foundation

public enum TimelineEditor {
    public static let minimumSection = 0.5
    public static func split(_ sections: [PhotoSection], at time: Double, lines: [LyricLine]) -> [PhotoSection] {
        guard time.isFinite, let i = sections.firstIndex(where: { time >= $0.start + minimumSection && time <= $0.end - minimumSection }) else { return sections }
        var out = sections, right = sections[i]
        out[i].end = time; right.start = time
        out[i].lineIDs = sections[i].lineIDs.filter { lines.indices.contains($0) && lines[$0].start < time }
        right.lineIDs = sections[i].lineIDs.filter { lines.indices.contains($0) && lines[$0].start >= time }
        out.insert(right, at: i + 1)
        return numbered(out)
    }
    public static func join(_ sections: [PhotoSection], before index: Int) -> [PhotoSection] {
        guard index > 0, sections.indices.contains(index) else { return sections }
        var out = sections
        out[index - 1].end = out[index].end
        out[index - 1].lineIDs = Array(Set(out[index - 1].lineIDs + out[index].lineIDs)).sorted()
        let selected = out[index - 1].selectedCandidate?.id
        for c in out[index].candidates where !out[index - 1].candidates.contains(where: { $0.id == c.id }) { out[index - 1].candidates.append(c) }
        if let selected { out[index - 1].selected = out[index - 1].candidates.firstIndex { $0.id == selected } ?? -1 }
        else if let candidate = out[index].selectedCandidate { out[index - 1].selected = out[index - 1].candidates.firstIndex { $0.id == candidate.id } ?? -1 }
        out.remove(at: index)
        return numbered(out)
    }
    public static func numbered(_ sections: [PhotoSection]) -> [PhotoSection] {
        sections.enumerated().map { i, section in var s = section; s.id = i; s.repeatOf = nil; return s }
    }
    public static func assignLines(_ sections: [PhotoSection], lines: [LyricLine]) -> [PhotoSection] {
        sections.enumerated().map { i, section in
            var s = section
            s.lineIDs = lines.indices.filter { lines[$0].start >= s.start && (lines[$0].start < s.end || i == sections.count - 1) }
            return s
        }
    }
    public static func boundaries(_ sections: [PhotoSection]) -> [Double] { sections.dropFirst().map(\.start) }
    public static func applying(_ boundaries: [Double], to sections: [PhotoSection], lines: [LyricLine], duration: Double) -> [PhotoSection] {
        guard !sections.isEmpty, duration.isFinite, duration > 0 else { return sections }
        var out = sections
        while out.count > 1 { out = join(out, before: 1) }
        out[0].start = 0; out[0].end = duration
        out = assignLines(out, lines: lines)
        for t in Set(boundaries.filter { $0.isFinite }).sorted() { out = split(out, at: t, lines: lines) }
        return out
    }
    public static func splitShort(_ clip: ShortClip, at time: Double) throws -> [ShortClip] {
        guard time.isFinite, time >= clip.start + minimumSection, time <= clip.end - minimumSection else { throw MVError("Choose a split at least half a second from either end of the Short.") }
        var left = clip, right = clip
        left.end = time; left.name += " — 1"
        right.id = UUID(); right.start = time; right.name += " — 2"
        return [left, right]
    }
    public static func joinShorts(_ first: ShortClip, _ second: ShortClip) throws -> ShortClip {
        let start = min(first.start, second.start), end = max(first.end, second.end)
        guard end - start <= ShortClip.maxDuration else { throw MVError("The joined Short would be longer than 3 minutes. Move its ends closer before joining.") }
        var joined = first; joined.start = start; joined.end = end
        return joined
    }
}
