// Explicit time boundaries: editing pictures never edits the song or the independent Shorts.
import Foundation

public enum TimelineEditor {
    public static let minimumSection = 0.5
    public static func split(_ sections: [PhotoSection], at time: Double, lines: [LyricLine]) -> [PhotoSection] {
        guard time.isFinite, let i = sections.firstIndex(where: { time >= $0.start + minimumSection && time <= $0.end - minimumSection }) else { return sections }
        var out = sections
        let original = sections[i]
        var left = cropped(original, from: original.start, to: time)
        var right = cropped(original, from: time, to: original.end)
        left.lineIDs = original.lineIDs.filter { lines.indices.contains($0) && lines[$0].start < time }
        right.lineIDs = original.lineIDs.filter { lines.indices.contains($0) && lines[$0].start >= time }
        out[i] = left; out.insert(right, at: i + 1)
        return numbered(out)
    }
    public static func join(_ sections: [PhotoSection], before index: Int) -> [PhotoSection] {
        guard index > 0, sections.indices.contains(index) else { return sections }
        var out = sections
        let left = out[index - 1]
        var right = out[index]
        let usedIDs = Set(allMediaSections([left]).flatMap(\.clips).map(\.id))
        var renamed: [String: String] = [:]
        for clip in allMediaSections([right]).flatMap(\.clips) where usedIDs.contains(clip.id) { if renamed[clip.id] == nil { renamed[clip.id] = UUID().uuidString } }
        editMedia(&right) { part in for i in part.clips.indices { if let id = renamed[part.clips[i].id] { part.clips[i].id = id } } }

        // Keep visible assignments and their source times. Stored, disabled alternatives never become active merely because of a join.
        out[index - 1].mediaParts = renderSections([left]) + renderSections([right])
        out[index - 1].end = right.end
        out[index - 1].lineIDs = Array(Set(left.lineIDs + right.lineIDs)).sorted()
        out[index - 1].retainedClips = uniqueClips(left.retainedClips + left.clips + right.retainedClips + right.clips)
        let moved = right.clips.map { c -> SectionClip in var c = c; c.offset += right.start - left.start; return c }
        out[index - 1].clips = (left.useClips ? left.clips : []) + (right.useClips ? moved : [])
        out[index - 1].useClips = left.useClips || right.useClips
        out[index - 1].repeatClips = false
        let selected = out[index - 1].selectedCandidate?.id
        let rightSelected = out[index].selectedCandidate
        var rightChoice = rightSelected.flatMap { candidate in out[index - 1].candidates.firstIndex(of: candidate) }
        for candidate in out[index].candidates where !out[index - 1].candidates.contains(candidate) {
            var c = candidate
            if out[index - 1].candidates.contains(where: { $0.id == c.id }) { c.id += ":" + UUID().uuidString }
            out[index - 1].candidates.append(c)
            if candidate == rightSelected { rightChoice = out[index - 1].candidates.count - 1 }
        }
        if let selected { out[index - 1].selected = out[index - 1].candidates.firstIndex { $0.id == selected } ?? -1 }
        else if let rightChoice { out[index - 1].selected = rightChoice }
        out.remove(at: index)
        return numbered(out)
    }
    /// Apply a displayed media edit to the saved children a joined row actually renders.
    public static func editMedia(_ section: inout PhotoSection, _ edit: (inout PhotoSection) -> Void) {
        edit(&section)
        if var parts = section.mediaParts {
            for index in parts.indices { editMedia(&parts[index], edit) }
            section.mediaParts = parts
        }
    }
    public static func replaceCandidate(_ original: ImageCandidate, with replacement: ImageCandidate, in section: inout PhotoSection) {
        editMedia(&section) { s in
            for index in s.candidates.indices where s.candidates[index] == original { s.candidates[index] = replacement }
        }
    }
    public static func uniqueClips(_ clips: [SectionClip]) -> [SectionClip] {
        var seen = Set<String>(); return clips.filter { seen.insert($0.jobID ?? $0.id).inserted }
    }
    /// Crops the timeline window, not the underlying movie. All source types use the same elapsed-time mapping.
    public static func cropped(_ section: PhotoSection, from start: Double, to end: Double) -> PhotoSection {
        var s = section
        s.playbackOffset += start - section.start; s.start = start; s.end = end
        if let parts = section.mediaParts {
            s.mediaParts = parts.filter { $0.end > start && $0.start < end }.map { cropped($0, from: max(start, $0.start), to: min(end, $0.end)) }
        }
        return s
    }
    public static func shifted(_ section: PhotoSection, by delta: Double) -> PhotoSection {
        var s = section; s.start += delta; s.end += delta
        s.mediaParts = s.mediaParts?.map { shifted($0, by: delta) }; return s
    }
    /// Flatten joined assignments for preview/export only; the editor continues to show one joined picture row.
    public static func renderSections(_ sections: [PhotoSection], depth: Int = 0) -> [PhotoSection] {
        guard depth < 32 else { return sections.map { var s = $0; s.mediaParts = nil; return s } }
        return sections.flatMap { section -> [PhotoSection] in
            guard let parts = section.mediaParts, !parts.isEmpty else { return [section] }
            var out = renderSections(parts, depth: depth + 1).filter { $0.end > section.start && $0.start < section.end }
            guard !out.isEmpty else { var s = section; s.mediaParts = nil; return [s] }
            out = out.map { cropped($0, from: max(section.start, $0.start), to: min(section.end, $0.end)) }
            if out[0].start > section.start { out[0].playbackOffset += section.start - out[0].start; out[0].start = section.start }
            out[out.count - 1].end = section.end
            return out
        }
    }
    /// Includes inactive originals too, for backups, history and reference-aware file retention.
    public static func allMediaSections(_ sections: [PhotoSection]) -> [PhotoSection] {
        var out: [PhotoSection] = [], queue = sections
        while !queue.isEmpty, out.count < 4096 { let s = queue.removeLast(); out.append(s); queue += s.mediaParts ?? [] }
        return out
    }
    /// Reassign the visible photo/movie together. Reference files are retained at both ends for version selection and Undo.
    public static func reassign(_ sections: [PhotoSection], from source: Int, to destination: Int) -> [PhotoSection] {
        guard source != destination, sections.indices.contains(source), sections.indices.contains(destination) else { return sections }
        let a = sections[source], b = sections[destination]
        guard a.selectedCandidate != nil || (a.useClips && !a.clips.isEmpty) else { return sections }
        var out = sections
        func put(_ media: PhotoSection, into target: inout PhotoSection) {
            if let c = media.selectedCandidate {
                if let i = target.candidates.firstIndex(of: c) { target.selected = i }
                else { var incoming = c; if target.candidates.contains(where: { $0.id == incoming.id }) { incoming.id += ":" + UUID().uuidString }; target.candidates.append(incoming); target.selected = target.candidates.count - 1 }
            } else { target.selected = -1 }
            target.clips = media.clips; target.useClips = media.useClips; target.repeatClips = media.repeatClips
            target.playbackOffset = media.playbackOffset
            target.mediaParts = media.mediaParts?.map { shifted($0, by: target.start - media.start) }
            target.retainedClips = uniqueClips(target.retainedClips + a.retainedClips + a.clips + b.retainedClips + b.clips)
        }
        put(a, into: &out[destination]); put(b, into: &out[source]); return out
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
    /// A start-only edit clamps the start itself; it never silently moves the opposite edge.
    public static func adjustedShort(_ edited: ShortClip, from original: ShortClip, duration: Double) -> ShortClip {
        guard duration.isFinite, duration >= minimumSection, edited.start.isFinite, edited.end.isFinite else { return original }
        var c = edited
        if edited.start != original.start && edited.end == original.end {
            c.end = min(duration, original.end)
            c.start = min(c.end - minimumSection, max(max(0, c.end - ShortClip.maxDuration), edited.start))
        } else {
            c.start = max(0, min(c.start, duration - minimumSection))
            c.end = min(duration, max(c.start + minimumSection, min(c.end, c.start + ShortClip.maxDuration)))
        }
        return c
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
