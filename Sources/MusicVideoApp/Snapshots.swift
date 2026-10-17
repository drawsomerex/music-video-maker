// Developer aid: `MV_SNAPSHOT_DIR=/some/folder` renders the main screens to PNG files and quits (used to check layouts without a display).
import SwiftUI
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
            save("shorts", CGSize(width: 1180, height: 1500), ShortEditor(clip: model.currentShort!, snapshot: true))
            if let last = p.lines.last { model.update(c.id) { $0.start = last.start - 14; $0.end = last.end + 6 }; save("shorts-end", CGSize(width: 1180, height: 1500), ShortEditor(clip: model.currentShort!, snapshot: true)) }
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
        }
        NSApplication.shared.terminate(nil)
    }
}
