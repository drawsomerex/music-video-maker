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
        do { try model.backupForVersionChange(); check(true, "backup before version change") } catch { check(false, "backup before version change") }
        model.restoreAutomaticPictures(); check(model.timelineShorts.count == oldShorts.count + 1, "restore pictures preserves Shorts")
        model.undoEdit()
        let realWork = model.workDir; model.workDir = URL(fileURLWithPath: root + "/missing/child"); model.persist()
        check(model.saveStatus != "Saved" && model.errorMessage != nil, "save failure is visible")
        model.workDir = realWork; model.errorMessage = nil; model.persist()
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
        FileHandle.standardError.write(Data("EDITOR CHECKS: \(checks) checks, \(failures) failures\n".utf8))
    }
}
