import SwiftUI
import MVCore

struct TimelineSnapshot {
    var name: String
    var plan: Plan?
    var sections: [PhotoSection]?
    var shorts: [ShortClip]
    var key: String
    var selected: UUID?
}

@MainActor
extension AppModel {
    var timelineShorts: [ShortClip] {
        if let p = plan, timelineLines?.lines.map(\.text) == p.lines.map(\.text) { return p.shorts }
        return draftKey == analysisKey ? draftShorts : []
    }
    func ensureDraftKey() {
        if draftKey != analysisKey { draftSections = nil; draftShorts = []; draftKey = analysisKey; editUndo = []; editRedo = [] }
    }
    /// Your picture cuts are kept on disk next to the listening for this song, so they survive listening again or restarting the app.
    private var draftFile: URL { listenFolder.appendingPathComponent("pictures_draft.json") }
    private struct SavedDraft: Codable { var key: String; var sections: [PhotoSection] }
    func saveDraft() {
        guard let s = draftSections, draftKey == analysisKey else { return }
        if let d = try? JSONEncoder().encode(SavedDraft(key: analysisKey, sections: s)) { try? d.write(to: draftFile, options: .atomic) }
    }
    /// Brings back saved cuts when they belong to exactly this song and these words.
    func loadDraft() {
        guard draftSections == nil, let d = try? Data(contentsOf: draftFile), let saved = try? JSONDecoder().decode(SavedDraft.self, from: d), saved.key == analysisKey, !saved.sections.isEmpty else { return }
        draftSections = saved.sections; draftKey = saved.key
    }
    func clearTimelineSession() {
        skipNextPlanHistory = true; checkpointRevision = nil
        draftSections = nil; draftShorts = []; draftKey = ""; editUndo = []; editRedo = []
        timelineCursor = 0; listenTask?.cancel(); listening = false; previewTask?.cancel(); live.invalidate(); live.pause()
    }
    func snapshot(_ name: String) -> TimelineSnapshot { TimelineSnapshot(name: name, plan: plan, sections: draftSections, shorts: draftShorts, key: draftKey, selected: selectedShort) }
    func checkpoint(_ name: String, coalesce: Bool = false) {
        guard !timelineDragging else { return }
        ensureDraftKey()
        if checkpointRevision == planRevision { return }
        checkpointRevision = planRevision
        if coalesce && lastEditName == name && Date().timeIntervalSince(lastEditAt) < 0.7 { lastEditAt = Date(); return }
        editUndo.append(snapshot(name)); if editUndo.count > 60 { editUndo.removeFirst() }; editRedo = []
        lastEditName = name; lastEditAt = Date()
    }
    var historyAvailable: Bool { !busy && !listening && stage != .working && stage != .rendering && shortProgress == nil && !timelineDragging }
    func restore(_ state: TimelineSnapshot) {
        restoringHistory = true
        defer { restoringHistory = false; checkpointRevision = nil }
        var restored = state.plan
        if var target = restored, let current = plan {
            // Undo can change the chosen artwork; it cannot refund a paid generation or discard its saved media.
            target.totalGenerationCostUSD = max(target.totalGenerationCostUSD, current.totalGenerationCostUSD)
            target.imagesGeneratedCount = max(target.imagesGeneratedCount, current.imagesGeneratedCount)
            target.lastImageCostUSD = current.lastImageCostUSD ?? target.lastImageCostUSD
            func keep(_ source: [ImageCandidate], in section: inout PhotoSection) {
                for c in source where !section.candidates.contains(where: { $0.id == c.id }) { section.candidates.append(c) }
            }
            keep(current.intro.candidates, in: &target.intro)
            for i in target.sections.indices {
                let assets = current.sections.filter { $0.end > target.sections[i].start && $0.start < target.sections[i].end }.flatMap(\.candidates)
                keep(assets, in: &target.sections[i])
            }
            restored = target
        }
        plan = restored; draftSections = state.sections; draftShorts = state.shorts; draftKey = state.key; selectedShort = state.selected
        lastEditAt = .distantPast; stopPlayback(); previewTask?.cancel(); live.pause(); live.invalidate(); persist()
        selectedSection = min(selectedSection, (plan?.sections.count ?? 0) - 1)
        if showFullPreview { openFullPreview() }
        else if stage == .plan, currentShort != nil { refreshPreview(at: 0) }
    }
    func undoEdit() { guard historyAvailable, let state = editUndo.popLast() else { return }; editRedo.append(snapshot(state.name)); restore(state) }
    func redoEdit() { guard historyAvailable, let state = editRedo.popLast() else { return }; editUndo.append(snapshot(state.name)); restore(state) }
    func beginTimelineDrag() { guard !timelineDragging else { return }; checkpoint("Move Short boundary"); timelineDragging = true }
    func endTimelineDrag() { timelineDragging = false; persist(); refreshPreview(at: 0) }

    func commitPictures(_ sections: [PhotoSection]) {
        ensureDraftKey()
        if var p = plan, timelineLines?.lines.map(\.text) == p.lines.map(\.text) {
            p.sections = sections; p.pictureBoundaries = TimelineEditor.boundaries(sections); plan = p; draftSections = nil; persist()
        } else { draftSections = sections; planRevision += 1; checkpointRevision = nil; saveDraft() }
        selectedSection = min(selectedSection, sections.count - 1)
        live.invalidate()
    }
    func splitPicture(at time: Double) {
        guard let t = timelineLines, let sections = previewSections else { return }
        let v = snappedTimelineTime(time, start: true)
        let result = TimelineEditor.split(sections, at: v, lines: t.lines)
        guard result.count > sections.count else { snapDescription = "Choose a point at least half a second inside a picture."; return }
        // A split may only ADD this one cut. Anything else would lose your other pictures, so it is refused.
        let expected = (TimelineEditor.boundaries(sections) + [v]).sorted(), got = TimelineEditor.boundaries(result)
        guard result.count == sections.count + 1, got.count == expected.count, zip(got, expected).allSatisfy({ abs($0 - $1) < 0.001 }) else {
            snapDescription = "That change would have lost other pictures, so nothing was changed."; return
        }
        ensureDraftKey(); checkpoint("Split picture"); commitPictures(result)
        snapDescription = "New picture starts at \(preciseClock(v)). Audio and Shorts stay unchanged."
    }
    func joinPicture(before index: Int) {
        guard let sections = previewSections, index > 0, sections.indices.contains(index) else { return }
        ensureDraftKey(); checkpoint("Join pictures"); commitPictures(TimelineEditor.join(sections, before: index))
        snapDescription = "Pictures joined. Audio and Shorts stay unchanged."
    }
    func restoreAutomaticPictures() {
        guard let t = timelineLines else { return }
        ensureDraftKey(); checkpoint("Restore automatic picture divisions")
        let parsed = LyricAligner.parse(lyrics)
        var sections = Planner.structure(lines: t.lines, stanzaBreaks: parsed.stanzaBreaks, songDuration: t.duration)
        // Restore timing only. Retain all artwork as alternatives, selecting the artwork covering each new start.
        let old = previewSections ?? []
        for i in sections.indices {
            if let source = old.first(where: { sections[i].start >= $0.start && sections[i].start < $0.end }) {
                sections[i].candidates = source.candidates; sections[i].selected = source.selected; sections[i].prompt = source.prompt
            }
            for source in old { for c in source.candidates where !sections[i].candidates.contains(where: { $0.id == c.id }) { sections[i].candidates.append(c) } }
        }
        commitPictures(sections)
    }
    func setTimelineShorts(_ shorts: [ShortClip]) {
        ensureDraftKey()
        if var p = plan, timelineLines?.lines.map(\.text) == p.lines.map(\.text) { p.shorts = shorts; plan = p; persist() }
        else { draftShorts = shorts; planRevision += 1; checkpointRevision = nil }
        live.invalidate()
    }
    func addTimelineShort() {
        guard let t = timelineLines else { return }
        ensureDraftKey(); checkpoint("Add Short")
        let start = min(max(0, timelineCursor), max(0, t.duration - 2))
        let c = ShortClip(name: "Short \(timelineShorts.count + 1)", start: start, end: min(t.duration, start + 30))
        setTimelineShorts(timelineShorts + [c]); selectedShort = c.id
    }
    func suggestTimelineShorts() {
        guard let t = timelineLines else { return }
        ensureDraftKey(); checkpoint("Suggest Shorts")
        // Suggestions follow lyric pauses, independently of the current picture divisions.
        var out = timelineShorts, start = 0.0
        while start < t.duration - 0.5 {
            let target = min(t.duration, start + 30)
            let ends = t.lines.map(\.end).filter { $0 > start + 5 && abs($0 - target) < 5 }
            let end = ends.min(by: { abs($0 - target) < abs($1 - target) }) ?? target
            out.append(ShortClip(name: "Short \(out.count + 1)", start: start, end: end)); start = end
        }
        setTimelineShorts(out); selectedShort = out.last?.id
    }
    func editTimelineShort(_ id: UUID, change: (inout ShortClip) -> Void) {
        var shorts = timelineShorts; guard let i = shorts.firstIndex(where: { $0.id == id }), let t = timelineLines else { return }
        checkpoint("Edit Short", coalesce: true)
        let old = shorts[i]
        change(&shorts[i])
        let requested = shorts[i]
        shorts[i] = TimelineEditor.adjustedShort(requested, from: old, duration: t.duration)
        if shorts[i].start != requested.start { snapDescription = "The start cannot move earlier without making this Short longer than 3 minutes. The end stays fixed." }
        setTimelineShorts(shorts)
    }
    func splitTimelineShort(_ id: UUID) {
        var shorts = timelineShorts; guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        do {
            let pieces = try TimelineEditor.splitShort(shorts[i], at: snappedTimelineTime(timelineCursor, start: true))
            checkpoint("Split Short"); shorts.replaceSubrange(i...i, with: pieces); setTimelineShorts(shorts); selectedShort = pieces[0].id
        } catch { snapDescription = error.localizedDescription }
    }
    func joinTimelineShort(_ id: UUID) {
        var shorts = timelineShorts.sorted { $0.start < $1.start }; guard let i = shorts.firstIndex(where: { $0.id == id }), i + 1 < shorts.count else { return }
        do {
            let c = try TimelineEditor.joinShorts(shorts[i], shorts[i + 1]); checkpoint("Join Shorts")
            shorts.replaceSubrange(i...i + 1, with: [c]); setTimelineShorts(shorts); selectedShort = c.id
        } catch { snapDescription = error.localizedDescription }
    }
    func removeTimelineShort(_ id: UUID) { checkpoint("Delete Short"); setTimelineShorts(timelineShorts.filter { $0.id != id }); selectedShort = timelineShorts.first?.id }
    func snappedTimelineTime(_ time: Double, start: Bool) -> Double {
        guard timelineSnap, let lines = timelineLines?.lines else { return time }
        let words = lines.flatMap(\.words)
        if let w = words.first(where: { time > $0.start && time < $0.end }) {
            let v = start ? w.start : w.end
            snapDescription = "Aligned to \(start ? "beginning" : "end") of “\(w.text)” at \(preciseClock(v))."
            return v
        }
        return time
    }
    func selectArtwork(_ index: Int, section: Int) {
        guard var p = plan else { return }
        if section == -1 { guard p.intro.candidates.indices.contains(index) else { return } }
        else { guard p.sections.indices.contains(section), p.sections[section].candidates.indices.contains(index) else { return } }
        checkpoint("Choose saved artwork")
        if section == -1 { p.intro.selected = index } else { p.sections[section].selected = index }
        plan = p; draftSections = nil; live.invalidate(); persist()
    }
    func reassignPicture(from source: Int, to destination: Int) {
        guard var p = plan, source != destination, p.sections.indices.contains(source), p.sections.indices.contains(destination), let a = p.sections[source].selectedCandidate else { return }
        checkpoint("Move or swap pictures")
        let b = p.sections[destination].selectedCandidate
        func select(_ candidate: ImageCandidate?, in section: inout PhotoSection) {
            guard let c = candidate else { section.selected = -1; return }
            if let i = section.candidates.firstIndex(where: { $0.id == c.id }) { section.selected = i }
            else { section.candidates.append(c); section.selected = section.candidates.count - 1 }
        }
        select(a, in: &p.sections[destination]); select(b, in: &p.sections[source])
        plan = p; draftSections = nil; live.invalidate(); persist()
    }
    func backupForVersionChange() async throws {
        guard let p = plan, let w = workDir else { return }
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try Pipeline.savePlan(p, w)
            let folder = w.appendingPathComponent("Version Backups/\(UUID().uuidString)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var backup = p
            var files = Set(([p.intro] + p.sections).flatMap(\.candidates).flatMap { [$0.fullFile, $0.thumbFile, $0.videoFile].compactMap { $0 } })
            if !p.audioFile.isEmpty { files.insert(p.audioFile) }
            for file in files {
                guard !file.hasPrefix("/"), !file.split(separator: "/").contains("..") else { throw MVError("A project media path is unsafe to back up.") }
                let source = w.appendingPathComponent(file), target = folder.appendingPathComponent(file)
                guard fm.fileExists(atPath: source.path) else { continue }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
            }
            if p.audioFile.isEmpty {
                let source = Pipeline.audioURL(p, work: w)
                if fm.fileExists(atPath: source.path) {
                    let name = "audio." + (source.pathExtension.isEmpty ? "wav" : source.pathExtension)
                    try fm.copyItem(at: source, to: folder.appendingPathComponent(name)); backup.audioFile = name
                }
            }
            try Pipeline.savePlan(backup, folder)
        }.value
    }
}

func preciseClock(_ time: Double) -> String { let t = max(0, time); return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }
