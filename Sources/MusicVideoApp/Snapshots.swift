// Developer aid: `MV_SNAPSHOT_DIR=/some/folder` renders the main screens to PNG files and quits (used to check layouts without a display).
import SwiftUI
import AVFoundation
import AppKit
import MVCore

@MainActor
enum Snapshots {
    static var directory: URL? { ProcessInfo.processInfo.environment["MV_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) } }

    static func render(model: AppModel) {
        guard let dir = directory else { return }
        FileHandle.standardError.write(Data("[snapshots] rendering to \(dir.path)\n".utf8))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        model.title = "Highway Lights"; model.subject = "A song for the open road"
        model.lyrics = "The road is wide and the sky is high\nWe're chasing the sun as the day goes by\n\nHighway lights, hold me tight"
        if model.plan != nil { model.plan?.totalGenerationCostUSD = 0.432; model.plan?.imagesGeneratedCount = 9; model.plan?.sections[2].candidates = []; model.plan?.sections[2].selected = -1; model.plan?.sections[5].candidates = []; model.plan?.sections[5].selected = -1 }
        if model.plan != nil {
            model.plan?.shorts = Pipeline.autoShorts(plan: model.plan!)
            if let id = model.plan?.shorts.first?.id {
                model.selectedShort = id
                let p = model.plan!
                func rep(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
                model.leadIn = 1.5; model.tailOut = 1.5
                // snapping: near words -> word edge; in music-only stretches -> beat; Off -> exactly where pointed
                if let lw = p.lines.last?.words.last {
                    model.beats = stride(from: 0.4, to: p.songDuration, by: 0.55).map { $0 }
                    model.snapMode = .smart
                    let inWords = model.snap(lw.end - 0.02, near: 0.2) == lw.end
                    let tail = lw.end + 3.1; let b = model.snap(tail, near: 0.25)
                    let isBeat = model.beats.contains { abs($0 - b) < 1e-9 }
                    model.snapMode = .off; let off = model.snap(tail, near: 0.25) == tail
                    model.snapMode = .smart
                    rep("snap smart: near last word edge -> \(inWords ? "OK" : "WRONG"); in the music-only tail -> \(isBeat ? "OK (beat)" : "no beat found"); Off keeps the point -> \(off ? "OK" : "WRONG")")
                }
                model.selectLines(id, 3, 6); let a = model.currentShort!; let ex = Pipeline.clip(plan: p, lines: 3, to: 6, lead: 1.5, tail: 1.5)
                rep("selectLines 3-6 -> \(a.start)…\(a.end) expected \(ex.start)…\(ex.end) \(abs(a.start - ex.start) < 0.01 && abs(a.end - ex.end) < 0.01 ? "OK" : "WRONG")")
                let w = p.lines[4].words[1]
                rep("snap near word start: \(model.snapToWordEdge(w.start + 0.03, within: 0.1) == w.start ? "OK" : "WRONG"); far: \(model.snapToWordEdge(w.start + 0.5 * (w.end - w.start), within: 0.0001))")
                model.selectLines(id, 0, p.lines.count - 1); rep("whole song selected -> \(String(format: "%.1f", model.currentShort!.duration)) s (limit \(ShortClip.maxDuration)) \(model.currentShort!.duration <= ShortClip.maxDuration ? "OK" : "WRONG")")
                model.selectSection(id, index: 2); let sc = model.currentShort!; rep("section 2 -> \(sc.start)…\(sc.end)")
                model.selectLines(id, 3, 6); model.extendSelection(id, seconds: 30); rep("extend to ~30 s -> \(String(format: "%.1f", model.currentShort!.duration)) s")
                model.selectLines(id, 3, 6)
            }
        }
        if ProcessInfo.processInfo.environment["MV_STRUCT_TEST"] != nil, let p = model.plan {
            func rep(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
            let secs = Planner.structure(lines: p.lines, stanzaBreaks: [], partBreaks: [], songDuration: p.songDuration)
            rep("structure (no marks): \(secs.count) pictures: " + secs.map { String(format: "%@%.0f-%.0f", $0.lineIDs.isEmpty ? "♪" : "L", $0.start, $0.end) }.joined(separator: " "))
            let sb = Set(p.lines.indices.filter { $0 > 0 && $0 % 4 == 0 })
            let secs2 = Planner.structure(lines: p.lines, stanzaBreaks: sb, partBreaks: [], songDuration: p.songDuration)
            rep("structure (marks every 4 lines): \(secs2.count): " + secs2.map { String(format: "%@%.0f-%.0f", $0.lineIDs.isEmpty ? "♪" : "L", $0.start, $0.end) }.joined(separator: " "))
            rep("clean: [" + ["[Chorus] Hello (ooh yeah) world {x} <y>", "(backing)", "plain line", "broken [tag"].map { LyricText.clean($0) }.joined(separator: "|") + "]")
            let gaps = zip(p.lines, p.lines.dropFirst()).map { $1.start - $0.end }.filter { $0 > 4 }
            rep("music gaps >4s: \(gaps.map { String(format: "%.0f", $0) }) ; first line at \(p.lines.first?.start ?? 0), last ends \(p.lines.last?.end ?? 0) of \(p.songDuration)")
            model.plan = nil; model.stage = .setup
            model.lyrics = p.lines.indices.map { ($0 > 0 && $0 % 4 == 0 ? "\n" : "") + p.lines[$0].text }.joined(separator: "\n")
            model.analysis = AppModel.SongAnalysis(lines: p.lines, duration: p.songDuration, key: model.analysisKey)
            let shotUpdater = Updater()
            let r = ImageRenderer(content: LyricDividerView(scrollable: false).padding().environmentObject(model).environmentObject(shotUpdater).frame(width: 700, height: 1500).background(Color(nsColor: .windowBackgroundColor)))
            r.scale = 1.5
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]), let dir = directory { try? png.write(to: dir.appendingPathComponent("divide-timeline.png")) }
            NSApplication.shared.terminate(nil); return
        }
        let updater = Updater()
        updater.available = Updater.Release(version: "9.9.9", notes: "• Easier screens\n• Captions now follow the singing more closely\n• Bug fixes", zip: URL(string: "https://example.com/x.zip")!, sha256: nil, page: nil)
        func save(_ name: String, _ size: CGSize, _ view: some View) {
            let r = ImageRenderer(content: view.environmentObject(model).environmentObject(updater).frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        model.lyrics = "The road is wide and the sky is high\nWe're chasing the sun as the day goes by\n---\nHighway lights, hold me tight\nThrough the quiet of the night\nHeadlights flicker, engines hum\n---\nWhen the morning light has come\nWe will find our way back home"
        save("divide", CGSize(width: 520, height: 560), LyricDividerView(scrollable: false).padding())
        save("setup", CGSize(width: 1120, height: 760), SetupView())
        save("setup-small", CGSize(width: 860, height: 560), SetupView())
        save("cost-bar", CGSize(width: 1000, height: 40), CostBar())
        save("cost-bar-small", CGSize(width: 700, height: 40), CostBar())
        save("style-sheet", CGSize(width: 640, height: 700), StyleSheet(inProject: true))
        save("help", CGSize(width: 720, height: 620), HelpCenterView())
        save("ideas", CGSize(width: 560, height: 380), SettingIdeasSheet(applyToProject: false))
        if let p = model.plan, let c = model.currentShort {
            var peaks: [Float] = []
            for i in 0..<Int(p.songDuration * 100) {
                let a = abs(sin(Double(i) / 37.0)), b = 0.35 + 0.65 * abs(sin(Double(i) / 900.0))
                peaks.append(Float(a * b))
            }
            model.waveform = peaks
            model.selectLines(c.id, 3, 8)
            model.beats = stride(from: 0.4, to: p.songDuration, by: 0.55).map { $0 }
            save("shorts", CGSize(width: 1440, height: 780), ShortEditor(clip: model.currentShort!, snapshot: true))
            if let last = p.lines.last { model.update(c.id) { $0.start = last.start - 14; $0.end = last.end + 6 }; save("shorts-end", CGSize(width: 1440, height: 780), ShortEditor(clip: model.currentShort!, snapshot: true, edge: .end)); save("shorts-end-small", CGSize(width: 1040, height: 700), ShortEditor(clip: model.currentShort!, snapshot: true, edge: .end)) }
        }
        save("update-strip", CGSize(width: 1120, height: 70), UpdateStrip())
        save("update-sheet", CGSize(width: 520, height: 420), UpdateSheet())
        save("recording-fix", CGSize(width: 560, height: 360), RecordingFixSheet())
        save("first-run", CGSize(width: 760, height: 620), NativeSetupView())
        save("guide", CGSize(width: 600, height: 560), QuickGuideView())
        save("settings", CGSize(width: 600, height: 560), SettingsView())
        if model.plan != nil {
            save("plan", CGSize(width: 1120, height: 760), PlanView())
            save("plan-small", CGSize(width: 860, height: 560), PlanView())
            save("plan-large", CGSize(width: 1800, height: 1100), PlanView())
            save("plan-mid", CGSize(width: 1000, height: 700), PlanView())
            if let i = model.plan?.sections.firstIndex(where: { $0.selectedCandidate?.videoFile != nil }), let c = model.plan?.sections[i].selectedCandidate {
                save("video-trim-wide", CGSize(width: 1000, height: 430), VideoTrimView(section: i, candidate: c, partLength: 14).padding())
                save("video-trim-mid", CGSize(width: 640, height: 520), VideoTrimView(section: i, candidate: c, partLength: 14).padding())
                save("video-trim-narrow", CGSize(width: 440, height: 680), VideoTrimView(section: i, candidate: c, partLength: 14).padding())
            }
        }
        if let i = model.plan?.sections.firstIndex(where: { !$0.clips.isEmpty }) {
            save("clip-panel", CGSize(width: 900, height: 700), ClipPanel(section: i).padding())
            model.clipJob = { var j = ClipJob(section: i, chain: true, secondsList: [10, 10, 5]); j.index = 1; j.phase = "HeyGen is making the clip…"; j.started = Date().addingTimeInterval(-70); return j }()
            model.doneNote = DoneNote(text: "Done — drew 3 pictures · cost $0.12")
            model.busy = true; model.busyPhase = "2/5: Generating a picture…"; model.busyProgress = 0.4
            save("banners", CGSize(width: 1000, height: 190), TaskBanners())
            model.busy = false; model.clipJob = nil; model.doneNote = nil
        }
        if let gdir = ProcessInfo.processInfo.environment["MV_GALLERY"].map({ URL(fileURLWithPath: $0) }) {
            do {
            // "Real" screenshots: each screen is hosted in an offscreen window and drawn by AppKit, so lists, scroll views and menus appear as on screen.
            try? FileManager.default.createDirectory(at: gdir, withIntermediateDirectories: true)
            func shot(_ name: String, _ size: CGSize, _ view: some View, wait: Double = 0.8) {
                let root = view.environmentObject(model).environmentObject(updater).frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: root)
                let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                win.contentView = host; win.isReleasedWhenClosed = false
                win.setFrameOrigin(NSPoint(x: -30000, y: -30000)); win.orderFront(nil)      // shown far off screen so the views run their start-up work (previews, strips)
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(wait))
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
                host.cacheDisplay(in: host.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: gdir.appendingPathComponent("\(name).png")) }
                win.close()
            }
            func sz(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
            if ProcessInfo.processInfo.environment["MV_GALLERY_ONLY"] == "song", let p = model.plan {
                model.lyrics = ""
                _ = p
                shot("s-song-page", sz(1000, 1000), LyricDividerView(), wait: 2)
                NSApplication.shared.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["MV_GALLERY_ONLY"] == "loop", let d = ProcessInfo.processInfo.environment["MV_LOOP_DIR"] {   // the looping long music video screens
                shot("projects", sz(1100, 720), ProjectsView(), wait: 3)
                model.openLoop(URL(fileURLWithPath: d))
                RunLoop.current.run(until: Date().addingTimeInterval(4))          // the clip check and the new preview
                shot("loop-1100x720", sz(1100, 720), RootView(), wait: 3)
                shot("loop-clip-card", sz(1000, 1500), ScrollView { LoopView().frame(width: 1000) }, wait: 4)

                shot("loop-1720x1080", sz(1720, 1080), RootView(), wait: 3)
                model.closeLoop(); UserDefaults.standard.set(1, forKey: "startKind")
                shot("loop-start-1100x720", sz(1100, 720), RootView(), wait: 2)
                UserDefaults.standard.set(0, forKey: "startKind")
                NSApplication.shared.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["MV_GALLERY_ONLY"] == "layout" {          // the Pictures screen at a laptop window, the smallest window and full screen
                model.lyrics = ""; model.analysis = nil; model.selectedSection = 1; model.stage = .plan
                shot("l-pictures-1100x720", sz(1100, 720), RootView(), wait: 2.5)
                shot("l-pictures-860x560", sz(860, 560), RootView(), wait: 2.5)
                shot("l-pictures-1720x1080", sz(1720, 1080), RootView(), wait: 2.5)
                NSApplication.shared.terminate(nil); return
            }
            if ProcessInfo.processInfo.environment["MV_GALLERY_ONLY"] == "timeline" {
                model.lyrics = ""; model.analysis = nil; model.selectedSection = 3
                if model.currentShort == nil { model.addTimelineShort(at: 20) }
                shot("t-pictures-page", sz(1400, 900), PlanView(), wait: 2)
                shot("t-pictures-page-small", sz(900, 640), PlanView(), wait: 2)
                NSApplication.shared.terminate(nil); return
            }
            model.selectedSection = 0
            let vi = model.plan?.sections.firstIndex(where: { $0.selectedCandidate?.videoFile != nil }) ?? 4
            model.stage = .setup
            shot("01-song-screen", sz(1120, 760), SetupView())
            shot("02-song-screen-small-window", sz(860, 560), SetupView())
            shot("03-lyrics-divide-into-parts", sz(560, 700), LyricDividerView(scrollable: false).padding())
            shot("04-first-time-download-models", sz(760, 640), NativeSetupView())
            model.stage = .working
            shot("05-planning-progress", sz(1000, 640), ProgressStage())
            model.stage = .plan
            shot("06-pictures-title-card", sz(1280, 800), PlanView(), wait: 1.5)
            model.selectedSection = 2
            shot("07-pictures-part-without-picture", sz(1280, 800), PlanView(), wait: 1.5)
            if let c0 = model.plan?.sections[vi].selectedCandidate, let vf = c0.videoFile, let w = model.workDir {
                let g = AVAssetImageGenerator(asset: AVURLAsset(url: w.appendingPathComponent(vf))); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 480, height: 480)
                let len = c0.videoLength ?? 8
                let imgs = (0..<14).compactMap { i in (try? g.copyCGImage(at: CMTime(seconds: len * (Double(i) + 0.5) / 14, preferredTimescale: 600), actualTime: nil)).map { NSImage(cgImage: $0, size: .zero) } }
                VideoTrimView.preload = (imgs, imgs.first)
            }
            model.selectedSection = vi
            shot("08-pictures-video-clip-trim-controls", sz(1280, 2000), PlanView(snapshot: true), wait: 6)
            model.selectedSection = 1
            shot("09-pictures-small-window", sz(860, 560), PlanView(), wait: 1.5)
            shot("10-pictures-large-window", sz(1900, 1100), PlanView(), wait: 1.5)
            shot("11-art-style-picker", sz(640, 700), StyleSheet(inProject: true))
            shot("12-setting-and-description", sz(640, 520), DescriptionSheet())
            shot("13-setting-ideas", sz(560, 380), SettingIdeasSheet(applyToProject: false))
            shot("14-picture-maker-key-and-credit", sz(520, 420), OpenRouterKeySheet())
            if let c = model.currentShort, let p = model.plan, let w = model.workDir {
                var vs = VideoSettings(height: 960); vs.width = 540
                let comp = FrameComposer(plan: p, work: w, settings: vs, short: c)
                model.live.setStill(NSImage(cgImage: comp.still(at: 4), size: .zero), vertical: true)
                shot("15-shorts-start-of-clip", sz(1440, 860), ShortsView(), wait: 15)
                shot("16-shorts-end-of-clip", sz(1440, 860), ShortEditor(clip: c, edge: .end), wait: 6)
                shot("17-shorts-small-window", sz(1040, 700), ShortEditor(clip: c, edge: .end), wait: 6)
                shot("18-shorts-more-options", sz(640, 620), ShortMoreOptions(clipID: c.id))
            }
            shot("19-help-ask-a-question", sz(720, 620), HelpCenterView(tab: 0))
            shot("20-help-read-the-guide", sz(820, 620), HelpCenterView(tab: 1))
            shot("21-quick-start-guide", sz(600, 560), QuickGuideView())
            shot("22-report-a-problem", sz(640, 520), ReportSheet(center: model.reportCenter, tab: 0))
            model.reportCenter.reports = [
                SentReport(number: 12, title: "The Make button did nothing", date: Date().addingTimeInterval(-86400 * 3), state: "closed", inProgress: false, reply: "Fixed in version 1.5.4 — thank you!", notified: true),
                SentReport(number: 15, title: "Preview is a square instead of widescreen", date: Date().addingTimeInterval(-3600 * 5), state: "open", inProgress: true, reply: "", notified: false),
                SentReport(number: 16, title: "Words are slightly late in the second verse", date: Date().addingTimeInterval(-600), state: "open", inProgress: false, reply: "", notified: false)]
            shot("23-report-a-problem-my-reports", sz(640, 520), ReportSheet(center: model.reportCenter, tab: 1))
            shot("24-settings", sz(660, 620), SettingsView())
            shot("25-update-available-banner", sz(1120, 70), UpdateStrip())
            shot("26-update-available-window", sz(520, 420), UpdateSheet())
            shot("27-fix-recording-permission", sz(760, 440), RecordingFixSheet())
            shot("28-picture-cost-bar", sz(1000, 40), CostBar())
            model.stage = .rendering
            shot("29-making-the-video-progress", sz(1000, 640), ProgressStage())
            model.stage = .done
            model.outputURL = URL(fileURLWithPath: "/tmp/First Strike on the Caney River.mp4")
            shot("30-finished-video", sz(1000, 700), DoneView(), wait: 2)
            }
        }
        NSApplication.shared.terminate(nil)
    }
}
