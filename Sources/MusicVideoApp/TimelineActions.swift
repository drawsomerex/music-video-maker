import SwiftUI
import MVCore

struct TimelineSnapshot {
    var name: String
    var plan: Plan?
    var sections: [PhotoSection]?
    var shorts: [ShortClip]
    var key: String
    var selected: UUID?
    var loop: LoopProject? = nil
    var loopFolder: URL? = nil
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
    func snapshot(_ name: String) -> TimelineSnapshot { TimelineSnapshot(name: name, plan: plan, sections: draftSections, shorts: draftShorts, key: draftKey, selected: selectedShort, loop: stage == .loop ? loopProject : nil, loopFolder: stage == .loop ? loopDir : nil) }
    func checkpoint(_ name: String, coalesce: Bool = false) {
        guard !timelineDragging else { return }
        if stage != .loop { ensureDraftKey() }
        if checkpointRevision == planRevision { return }
        checkpointRevision = planRevision
        if coalesce && lastEditName == name && Date().timeIntervalSince(lastEditAt) < 0.7 { lastEditAt = Date(); return }
        editUndo.append(snapshot(name)); if editUndo.count > 60 { editUndo.removeFirst() }; editRedo = []
        lastEditName = name; lastEditAt = Date(); retainHistoryMedia()
    }
    /// Shared activity gate for history, project switches and app-version changes, including both workflows and accepted paid jobs.
    var hasActiveWork: Bool { busy || listening || stage == .working || stage == .rendering || videoJob != nil || shortProgress != nil || clipJob != nil || loopJob != nil || loopListening != nil || timelineDragging || isRecording || downloadingModel }
    var historyAvailable: Bool { !hasActiveWork }
    func mayLeaveProject() -> Bool {
        guard !hasActiveWork else { notice = "Finish or stop the current task before opening or closing a project. Anything already made is kept."; return false }
        return true
    }
    func restore(_ state: TimelineSnapshot) {
        restoringHistory = true
        defer { restoringHistory = false; checkpointRevision = nil }
        if var restored = state.loop, state.loopFolder == loopDir, let current = loopProject {
            restored.imagesUSD = max(restored.imagesUSD, current.imagesUSD); restored.videoUSD = max(restored.videoUSD, current.videoUSD)
            restored.pictureCount = max(restored.pictureCount, current.pictureCount)
            for file in current.pictures where !restored.pictures.contains(file) { restored.pictures.append(file) }
            for file in current.clips where !restored.clips.contains(file) { restored.clips.append(file) }
            restored.pendingJob = current.pendingJob; restored.pendingOptions = current.pendingOptions // Undo cannot cancel a paid provider job.
            loopProject = restored; persistLoop(); return
        }
        var restored = state.plan
        if var target = restored, let current = plan {
            // Undo can change the chosen artwork; it cannot refund a paid generation or discard its saved media.
            target.totalGenerationCostUSD = max(target.totalGenerationCostUSD, current.totalGenerationCostUSD)
            target.imagesGeneratedCount = max(target.imagesGeneratedCount, current.imagesGeneratedCount)
            target.lastImageCostUSD = current.lastImageCostUSD ?? target.lastImageCostUSD
            target.totalVideoCostUSD = max(target.totalVideoCostUSD, current.totalVideoCostUSD)
            func keep(_ source: [ImageCandidate], in section: inout PhotoSection) {
                for c in source where !section.candidates.contains(where: { $0.id == c.id }) { section.candidates.append(c) }
            }
            keep(current.intro.candidates, in: &target.intro)
            target.intro.retainedClips = TimelineEditor.uniqueClips(target.intro.retainedClips + current.intro.retainedClips + current.intro.clips)
            for i in target.sections.indices {
                let assets = current.sections.filter { $0.end > target.sections[i].start && $0.start < target.sections[i].end }.flatMap(\.candidates)
                keep(assets, in: &target.sections[i])
                // generated video clips are paid for too: Undo may switch back to Ken Burns, but never loses a clip
                target.sections[i].retainedClips = TimelineEditor.uniqueClips(target.sections[i].retainedClips + current.sections.filter { $0.end > target.sections[i].start && $0.start < target.sections[i].end }.flatMap { $0.retainedClips + $0.clips })
            }
            restored = target
        }
        plan = restored; draftSections = state.sections; draftShorts = state.shorts; draftKey = state.key; selectedShort = state.selected
        lastEditAt = .distantPast; stopPlayback(); previewTask?.cancel(); live.pause(); live.invalidate(); persist()
        retainHistoryMedia()
        selectedSection = min(selectedSection, (plan?.sections.count ?? 0) - 1)
        if showFullPreview { openFullPreview() }
        else if stage == .plan, currentShort != nil { refreshPreview(at: 0) }
    }
    func undoEdit() { guard historyAvailable, let state = editUndo.popLast() else { return }; editRedo.append(snapshot(state.name)); restore(state) }
    func redoEdit() { guard historyAvailable, let state = editRedo.popLast() else { return }; editUndo.append(snapshot(state.name)); restore(state) }
    func beginTimelineDrag(_ name: String = "Move Short boundary") { guard !timelineDragging else { return }; checkpoint(name); timelineDragging = true }
    func endTimelineDrag() { timelineDragging = false; persist(); refreshPreview(at: 0) }

    // MARK: dragging on the scaled timeline (live: no saving or preview rebuild until the mouse is released)
    private var sectionsFollowPlan: Bool { plan.map { p in timelineLines?.lines.map(\.text) == p.lines.map(\.text) } ?? false }
    /// Moves the border between picture `i-1` and picture `i` to `time`. The neighbours resize; nothing else changes.
    func moveBoundaryLive(_ i: Int, to time: Double) {
        guard let tl = timelineLines, var secs = previewSections, secs.indices.contains(i), i > 0 else { return }
        let lo = secs[i - 1].start + TimelineEditor.minimumSection, hi = secs[i].end - TimelineEditor.minimumSection
        guard hi > lo else { return }
        let v = min(max(time, lo), hi)
        secs[i - 1].end = v; secs[i].start = v
        secs = TimelineEditor.assignLines(secs, lines: tl.lines)
        if sectionsFollowPlan, var p = plan { p.sections = secs; p.pictureBoundaries = TimelineEditor.boundaries(secs); plan = p }
        else { draftSections = secs }
    }
    func endBoundaryDrag() {
        timelineDragging = false; checkpointRevision = nil
        if sectionsFollowPlan { persist() } else { saveDraft() }
        live.invalidate()
    }
    /// Moves or resizes a Short while dragging.
    func moveShortLive(_ id: UUID, start: Double, end: Double) {
        guard let t = timelineLines else { return }
        var shorts = timelineShorts; guard let i = shorts.firstIndex(where: { $0.id == id }) else { return }
        let old = shorts[i]; var c = old; c.start = start; c.end = end
        shorts[i] = TimelineEditor.adjustedShort(c, from: old, duration: t.duration)
        if sectionsFollowPlan, var p = plan { p.shorts = shorts; plan = p } else { draftShorts = shorts }
    }
    func addTimelineShort(at time: Double) {
        guard let t = timelineLines else { return }
        ensureDraftKey(); checkpoint("Add Short")
        let start = min(max(0, time), max(0, t.duration - 2))
        let c = ShortClip(name: "Short \(timelineShorts.count + 1)", start: start, end: min(t.duration, start + 30))
        setTimelineShorts(timelineShorts + [c]); selectedShort = c.id
    }

    func commitPictures(_ sections: [PhotoSection]) {
        ensureDraftKey()
        if var p = plan, timelineLines?.lines.map(\.text) == p.lines.map(\.text) {
            p.sections = sections; p.pictureBoundaries = TimelineEditor.boundaries(sections); plan = p; draftSections = nil; persist()
        } else { draftSections = sections; planRevision += 1; checkpointRevision = nil; saveDraft() }
        selectedSection = min(selectedSection, sections.count - 1)
        live.invalidate()
    }
    /// While a picture or clip is being made, the pictures must keep their places (the result is put back into the same picture).
    var structureLocked: Bool { busy || clipJob != nil || workingSection != nil }
    func refuseWhileWorking() -> Bool {
        if structureLocked { snapDescription = "Wait until the picture or clip being made is finished, then split, join or move pictures."; notice = snapDescription }
        return structureLocked
    }
    func splitPicture(at time: Double) {
        if plan != nil, refuseWhileWorking() { return }
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
        if plan != nil, refuseWhileWorking() { return }
        guard let sections = previewSections, index > 0, sections.indices.contains(index) else { return }
        ensureDraftKey(); checkpoint("Join pictures"); commitPictures(TimelineEditor.join(sections, before: index))
        snapDescription = "Pictures joined. Audio and Shorts stay unchanged."
    }
    func restoreAutomaticPictures() {
        if plan != nil, refuseWhileWorking() { return }
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
        if section == -1 { p.intro.selected = index; p.intro.useClips = false; p.intro.mediaParts = nil; p.intro.playbackOffset = 0 }
        else { p.sections[section].selected = index; p.sections[section].useClips = false; p.sections[section].mediaParts = nil; p.sections[section].playbackOffset = 0 }
        plan = p; draftSections = nil; live.invalidate(); persist()
    }
    /// Throws away one saved version of a part's artwork (never the one in use). Undo brings it back; its files stay until the song is cleaned up later.
    func deleteArtwork(_ index: Int, section: Int) {
        guard var p = plan, section != workingSection else { return }
        func drop(_ s: inout PhotoSection) {
            guard s.candidates.indices.contains(index), index != s.selected else { return }
            s.candidates.remove(at: index)
            if s.selected > index { s.selected -= 1 }
        }
        checkpoint("Throw away a picture version")
        if section < 0 { drop(&p.intro) } else if p.sections.indices.contains(section) { drop(&p.sections[section]) }
        plan = p; persist()
    }
    func reassignPicture(from source: Int, to destination: Int) {
        if refuseWhileWorking() { return }
        guard var p = plan, source != destination, p.sections.indices.contains(source), p.sections.indices.contains(destination) else { return }
        checkpoint("Move or swap artwork and video")
        p.sections = TimelineEditor.reassign(p.sections, from: source, to: destination)
        plan = p; draftSections = nil; live.invalidate(); persist()
    }
    /// Cleanup reads this lease before removing unreferenced files; an in-memory Undo entry keeps its original on disk.
    func retainHistoryMedia() {
        guard let w = workDir else { return }
        let files = Set((editUndo + editRedo).compactMap(\.plan).flatMap { p in
            TimelineEditor.allMediaSections([p.intro] + p.sections).flatMap { s in
                s.candidates.flatMap { [$0.fullFile, $0.thumbFile, $0.videoFile].compactMap { $0 } } + (s.clips + s.retainedClips).flatMap { [$0.file, $0.lastFrame] }
            }
        })
        if let data = try? JSONEncoder().encode(files.sorted()) { try? data.write(to: w.appendingPathComponent("history_media.json"), options: .atomic) }
    }
    func backupForVersionChange() async throws {
        if stage == .loop, let p = loopProject, let w = loopDir {
            _ = try await Task.detached(priority: .userInitiated) { try ProjectBackup.create(loop: p, work: w) }.value
        } else if let p = plan, let w = workDir {
            _ = try await Task.detached(priority: .userInitiated) { try ProjectBackup.create(plan: p, work: w) }.value
        }
    }

}

func preciseClock(_ time: Double) -> String { let t = max(0, time); return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }
