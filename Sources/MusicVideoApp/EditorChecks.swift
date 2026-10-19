// Opt-in checks on a supplied scratch project only. Never runs during ordinary launches.
import SwiftUI
import MVCore
import AVFoundation

@MainActor
enum EditorChecks {
    static func run(model: AppModel, updater: Updater) async {
        var failures = 0, checks = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            checks += 1; let ok = value(); if !ok { failures += 1 }
            FileHandle.standardError.write(Data("\(ok ? "PASS" : "FAIL") \(name)\n".utf8))
        }
        guard let root = Updater.env["MV_TEST_ROOT"], root.hasPrefix("/tmp/"), let p = model.plan, let work = model.workDir, work.path.hasPrefix(root), Updater.env["MV_TEST_PREFS"] != nil else {
            FileHandle.standardError.write(Data("FAIL scratch project and isolated preferences required\n".utf8)); return
        }
        if Updater.env["MV_REAL_SPLIT"] != nil {
            // The real flow on a real song's lines: listen only (no plan), many automatic pictures, then split inside one of them.
            let real = p
            model.plan = nil; model.stage = .setup; model.analysis = nil; model.clearTimelineSession()
            model.lyrics = real.lines.indices.map { ($0 > 0 && $0 % 4 == 0 ? "\n" : "") + real.lines[$0].text }.joined(separator: "\n")
            model.analysis = AppModel.SongAnalysis(lines: real.lines, duration: real.songDuration, key: model.analysisKey)
            let before = model.previewSections ?? []
            let cuts = TimelineEditor.boundaries(before)
            check(before.count >= 8, "many automatic pictures before the split")
            let target = before[min(3, before.count - 1)], ids = target.lineIDs.sorted()
            let t = real.lines[ids[min(1, ids.count - 1)]].start
            model.splitPicture(at: t)
            let after = model.previewSections ?? []
            check(after.count == before.count + 1, "split adds exactly one picture")
            check(TimelineEditor.boundaries(after) == (cuts + [t]).sorted(), "every automatic cut is still there")
            check(after.first(where: { $0.start == t })?.prompt == target.prompt, "new bottom picture starts with the same idea and artwork")
            model.splitPicture(at: t + 0.1)
            check((model.previewSections ?? []).count == after.count, "a split too close to an existing cut is refused")
            // cuts survive listening again (draft saved on disk)
            let keep = TimelineEditor.boundaries(model.previewSections ?? [])
            model.draftSections = nil; model.draftKey = ""
            model.loadDraft()
            check(TimelineEditor.boundaries(model.previewSections ?? []) == keep, "saved cuts come back after listening again")
            model.undoEdit()
            check(TimelineEditor.boundaries(model.previewSections ?? []) == cuts, "undo returns exactly to the automatic pictures")
            FileHandle.standardError.write(Data("REAL SPLIT CHECKS: \(checks) checks, \(failures) failures\n".utf8)); return
        }
        if Updater.env["MV_BOUNDARY_SELFTEST"] != nil {
            model.plan = nil; model.stage = .setup; model.analysis = nil; model.clearTimelineSession()
            model.lyrics = "First line\nSecond line\n\nThird line\nFourth line\n\nFifth line\nSixth line"
            let starts: [Double] = [5, 10, 25, 30, 45, 50]
            let lines = LyricText.rows(model.lyrics).enumerated().map { i, row in
                LyricLine(id: i, text: row.text, words: [TimedWord(text: row.text, start: starts[i], end: starts[i] + 3)])
            }
            model.analysis = AppModel.SongAnalysis(lines: lines, duration: 60, key: model.analysisKey)
            model.timelineSnap = false
            let automatic = model.previewSections ?? []
            let cuts = TimelineEditor.boundaries(automatic)
            FileHandle.standardError.write(Data("AUTOMATIC CUTS: \(cuts)\n".utf8))
            check(cuts.count >= 3, "fixture has multiple automatic cuts")
            model.splitPicture(at: lines[1].start)
            let after = TimelineEditor.boundaries(model.previewSections ?? [])
            FileHandle.standardError.write(Data("AFTER LINE SPLIT: \(after)\n".utf8))
            check(after == (cuts + [lines[1].start]).sorted(), "line split adds one cut without removing automatic cuts")
            model.splitPicture(at: lines[3].start)
            check(TimelineEditor.boundaries(model.previewSections ?? []) == (cuts + [lines[1].start, lines[3].start]).sorted(), "second line split preserves all previous cuts")
            model.undoEdit()
            check(TimelineEditor.boundaries(model.previewSections ?? []) == after, "undo split preserves automatic cuts and earlier manual cut")
            FileHandle.standardError.write(Data("BOUNDARY CHECKS: \(checks) checks, \(failures) failures\n".utf8)); return
        }
        model.goToStep(1)
        check(model.timelineLines != nil, "first page has timed lyrics")
        let original = model.previewSections ?? []
        let oldShorts = model.timelineShorts
        model.timelineSnap = false
        model.splitPicture(at: (original.first?.start ?? 0) + (original.first?.duration ?? 10) / 2)
        check(model.previewSections?.count == original.count + 1, "split music on first page")
        check(model.timelineShorts == oldShorts, "picture split leaves Shorts unchanged")
        model.joinPicture(before: 1)
        check(model.previewSections?.map(\.start) == original.map(\.start), "join music removes only chosen boundary")
        model.undoEdit(); check(model.previewSections?.count == original.count + 1, "undo join")
        model.redoEdit(); check(model.previewSections?.count == original.count, "redo join")
        if var changed = model.plan {
            changed.sections[0].prompt = "New picture idea after splitting"
            changed.sections[0].candidates[changed.sections[0].selected].camZoom = 2
            changed.totalGenerationCostUSD += 0.1; changed.imagesGeneratedCount += 1
            model.plan = changed
            model.subdivide(section: changed.sections[0], into: 2)
            check(model.plan?.sections[0].prompt == "New picture idea after splitting" && model.plan?.sections[0].selectedCandidate?.camZoom == 2, "timeline uses live artwork and camera edits")
            model.undoEdit()
            check(model.plan?.sections[0].prompt == "New picture idea after splitting", "undo split preserves earlier picture idea edit")
            model.undoEdit()
            check(model.plan?.totalGenerationCostUSD == changed.totalGenerationCostUSD && model.plan?.imagesGeneratedCount == changed.imagesGeneratedCount, "undo never refunds paid generation accounting")
            model.redoEdit()
            let count = model.plan?.sections.count
            model.busy = true; model.undoEdit(); model.busy = false
            check(model.plan?.sections.count == count, "keyboard history blocked during background work")
        }
        model.timelineCursor = 5; model.addTimelineShort()
        guard let id = model.selectedShort else { return }
        model.timelineCursor = 15; model.splitTimelineShort(id)
        check(model.timelineShorts.count == oldShorts.count + 2, "split Short produces two independent clips")
        check(model.previewSections?.map(\.start) == original.map(\.start), "Short split leaves pictures unchanged")
        model.joinTimelineShort(id)
        check(model.timelineShorts.count == oldShorts.count + 1, "join Shorts")
        model.reassignPicture(from: 0, to: 1)
        check(model.plan?.sections[0].selectedCandidate?.id == p.sections[1].selectedCandidate?.id, "swap artwork source")
        check(model.plan?.sections[1].selectedCandidate?.id == p.sections[0].selectedCandidate?.id, "swap artwork target")
        model.undoEdit()
        check(model.plan?.sections[0].selectedCandidate?.id == p.sections[0].selectedCandidate?.id, "undo artwork swap")
        model.beginTimelineDrag()
        model.editTimelineShort(id) { $0.end = 55 }
        check(model.timelineDragging, "drag groups edits")
        model.endTimelineDrag()
        if let saved = try? Pipeline.loadPlan(work) { check(saved.shorts.first(where: { $0.id == id })?.end == 55, "drag completion saves latest state") }
        else { check(false, "saved project can reopen") }
        do {
            try await model.backupForVersionChange()
            let backups = try FileManager.default.contentsOfDirectory(at: work.appendingPathComponent("Version Backups"), includingPropertiesForKeys: nil)
            let complete = backups.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("full/clip.mp4").path) && FileManager.default.fileExists(atPath: $0.appendingPathComponent("audio.wav").path) }
            check(complete, "backup contains source audio and referenced video")
        } catch { check(false, "backup before version change") }
        model.restoreAutomaticPictures(); check(model.timelineShorts.count == oldShorts.count + 1, "restore pictures preserves Shorts")
        model.undoEdit()
        let realWork = model.workDir; model.workDir = URL(fileURLWithPath: root + "/missing/child"); model.persist()
        check(model.saveStatus != "Saved" && model.errorMessage != nil, "save failure is visible")
        model.workDir = realWork; model.errorMessage = nil; model.persist()
        if var longPlan = model.plan {
            let real = model.snapshot("Restore test")
            longPlan.songDuration = 300
            let long = ShortClip(name: "Full length", start: 100, end: 280)
            longPlan.shorts = [long]; model.plan = longPlan
            model.editTimelineShort(long.id) { $0.start = 90 }
            check(model.timelineShorts.first?.start == 100 && model.timelineShorts.first?.end == 280, "moving start preserves end at three-minute cap")
            model.update(long.id) { $0.start = 90 }
            check(model.plan?.shorts.first?.start == 100 && model.plan?.shorts.first?.end == 280, "detailed editor preserves end at duration cap")
            model.restore(real)
        }
        if let clip = model.plan?.shorts.first {
            model.selectedShort = clip.id; model.stage = .plan
            model.shuffleLook(clip.id)
            let obsolete = model.previewTask
            model.undoEdit()
            check(obsolete?.isCancelled == true && model.currentShort?.styleSeed == clip.styleSeed, "undo cancels pending style preview and restores seed")
            await model.previewTask?.value
            check(model.live.duration == clip.duration && !model.live.preparing, "undo rebuilds restored Short preview")
            model.stage = .setup
        }
        updater.holdCurrent(); check(!updater.dueForAutoCheck && !updater.heldVersion.isEmpty, "stay on installed version")
        updater.skip("9.9.9"); check(updater.skippedVersions.contains("9.9.9"), "skip persists")
        updater.unskip("9.9.9"); check(!updater.skippedVersions.contains("9.9.9"), "unskip")
        updater.heldVersion = ""; Updater.defaults.removeObject(forKey: "lastUpdateCheck")
        if let audio = model.audioFileURL, let plan = model.plan {
            let task = Task { await model.live.load(plan: plan, work: work, clip: nil, audio: audio) }
            task.cancel(); await task.value
            check(!model.live.preparing, "cancelled preview leaves no preparing state")
            await model.live.load(plan: plan, work: work, clip: nil, audio: audio)
            check(!model.live.preparing, "preview builds from scratch fixture")
            let old = Task { await model.live.load(plan: plan, work: work, clip: nil, audio: audio) }
            old.cancel()
            let clip = ShortClip(name: "Preview check", start: 35, end: 38)
            await model.live.load(plan: plan, work: work, clip: clip, audio: audio); await old.value
            check(model.live.duration == 3 && model.live.vertical, "obsolete preview cannot replace selected Short")
            model.live.invalidate(); model.live.pause()
            var settings = VideoSettings(height: 360); settings.width = 202
            do {
                let out = URL(fileURLWithPath: root).appendingPathComponent("vertical-test.mp4")
                try await VideoRenderer.render(plan: plan, work: work, output: out, settings: settings, short: clip)
                let asset = AVURLAsset(url: out)
                let duration = try await asset.load(.duration)
                check(abs(CMTimeGetSeconds(duration) - 3) < 0.2, "vertical clip renders correct duration")
                let g = AVAssetImageGenerator(asset: asset); g.appliesPreferredTrackTransform = true
                let frame = try await g.image(at: CMTime(seconds: 1, preferredTimescale: 600))
                check(frame.image.width == 202 && frame.image.height == 360, "vertical clip crops to requested dimensions")
            } catch { check(false, "vertical clip render") }
        }
        if let file = Updater.env["MV_HELP_TEST"], let questions = try? String(contentsOfFile: file, encoding: .utf8) {
            for q in questions.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                let answer = await HelpAssistant.answer(question: q, status: model.helpStatus(screen: "Song timeline"), config: model.config)
                FileHandle.standardError.write(Data("HELP Q: \(q)\nHELP A: \(answer.text)\nHELP SOURCES: \(answer.sources.joined(separator: ", ")) ai=\(answer.fromAI)\n".utf8))
            }
        }
        FileHandle.standardError.write(Data("EDITOR CHECKS: \(checks) checks, \(failures) failures\n".utf8))
    }
}
