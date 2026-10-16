import SwiftUI
import AVFoundation
import MVCore
#if NATIVE_MLX
import MVNative
#endif

@MainActor
final class AppModel: ObservableObject {
    enum Stage { case setup, working, plan, rendering, done }

    @Published var stage: Stage = .setup
    @Published var audioURL: URL?
    @Published var audioDuration: Double = 0
    @Published var title = ""
    @Published var subject = ""
    @Published var lyrics = ""
    @Published var imageInterval = 15.0
    @Published var quality = 1080

    @Published var phase = ""
    @Published var progress = 0.0
    @Published var plan: Plan?
    @Published var workDir: URL?
    @Published var outputURL: URL?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var config = Config.load()
    @Published var busy = false

    // First-run setup of the on-device models (native build only)
    @Published var nativeTier = "balanced"
    @Published var settingUp = false
    @Published var setupPhase = ""
    @Published var setupProgress = 0.0
    var setupStarted = Date()
    var isNativeBuild: Bool {
        #if NATIVE_MLX
        return true
        #else
        return false
        #endif
    }
    var needsNativeSetup: Bool {
        #if NATIVE_MLX
        return !NativeEngine.isInstalled
        #else
        return false
        #endif
    }

    func runNativeSetup() {
        #if NATIVE_MLX
        guard let tier = NativeEngine.Tier(rawValue: nativeTier) else { return }
        settingUp = true; setupStarted = Date(); setupPhase = "Starting…"; setupProgress = 0
        Task {
            do {
                try await NativeEngine.setup(tier: tier) { [weak self] p, f in Task { @MainActor in self?.setupPhase = p; self?.setupProgress = f } }
                settingUp = false; objectWillChange.send()
            } catch { settingUp = false; errorMessage = "Setup didn't finish: \(error.localizedDescription). It resumes where it left off when you try again." }
        }
        #endif
    }

    // Dock
    @Published var inDock = DockHelper.contains(Bundle.main.bundlePath)
    @Published var dockNote: String?
    func toggleDock() {
        let path = Bundle.main.bundlePath
        if !inDock && path.contains("/.build") { dockNote = "Move the app to /Applications first, then add it."; return }
        do { try DockHelper.set(path, present: !inDock); inDock = DockHelper.contains(path); dockNote = nil }
        catch { dockNote = error.localizedDescription }
    }

    func chooseSaveFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Save Here"; p.message = "Choose the folder where all projects, pictures and finished videos are saved."
        if p.runModal() == .OK, let u = p.url { config.projectsFolder = u.path; try? config.save() }
    }

    // Projects
    @Published var recents: [URL] = (UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []).map { URL(fileURLWithPath: $0) }.filter { Pipeline.isProject($0) }

    // Shorts editor
    @Published var waveform: [Float] = []
    @Published var selectedShort: UUID?
    @Published var playhead: Double?
    let live = LivePreview()
    @Published var showFullPreview = false
    @Published var shortProgress: Double?
    @Published var shortOutput: URL?
    @Published var hookBusy = false
    @Published var capped = false   // flashes a note when an edit hit the 3:00 limit
    @Published var leadIn = 3.0     // seconds of music before the first picked word
    @Published var tailOut = 3.0    // seconds of music after the last picked word
    var audioPlayer: AVAudioPlayer?
    var playTimer: Timer?
    var previewTask: Task<Void, Never>?
    var willQuit: NSObjectProtocol?

    init() {
        // Stop the hidden oMLX engine (if we started one) when the app quits.
        willQuit = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in OMLXServer.shared.shutdown() }
        // Test hooks: MV_DEMO_PLAN=<work folder> opens the plan screen; MV_DEMO_DONE=<mp4> opens the finished screen.
        let env = ProcessInfo.processInfo.environment
        if let w = env["MV_DEMO_PLAN"], let p = try? Pipeline.loadPlan(URL(fileURLWithPath: w)) {
            plan = p; workDir = URL(fileURLWithPath: w); title = p.title; stage = .plan
            if let m = env["MV_DEMO_DONE"] { outputURL = URL(fileURLWithPath: m); stage = .done }
        }
    }

    var canStart: Bool { audioURL != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty && !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var estimatedImages: Int { audioDuration > 0 ? max(2, Int((audioDuration / imageInterval).rounded()) + 1) : 0 }
    var missing: [Int] { plan.map(Pipeline.missing) ?? [] }
    var loadedCount: Int { plan.map { $0.sections.count + 1 - Pipeline.missing($0).count } ?? 0 }
    var totalImages: Int { plan.map { $0.sections.count + 1 } ?? 0 }

    /// Folder that holds projects (chosen in Settings; default ~/Movies/Music Videos).
    var outputRoot: URL { config.projectsRoot }

    func setAudio(_ url: URL) {
        audioURL = url
        if title.isEmpty {
            var t = url.deletingPathExtension().lastPathComponent
            if let r = t.range(of: " (") { t = String(t[..<r.lowerBound]) }
            title = t
        }
        Task { audioDuration = (try? await MVCore.audioDuration(path: url.path)) ?? 0 }
    }

    private var handler: ProgressHandler {
        { [weak self] phase, p in Task { @MainActor in self?.phase = phase; self?.progress = p } }
    }

    // MARK: Step 1
    func start() {
        guard let audio = audioURL else { return }
        config = Config.load()
        stage = .working; phase = "Starting…"; progress = 0
        let t = title.trimmingCharacters(in: .whitespaces), s = subject, l = lyrics, every = imageInterval
        Task {
            do {
                // Never overwrite an existing project: a second song/plan with the same title gets "Title 2", "Title 3"…
                let base = t.replacingOccurrences(of: "/", with: "-")
                var folder = outputRoot.appendingPathComponent(base); var n = 2
                while Pipeline.isProject(Pipeline.workDir(output: folder, title: t)) { folder = outputRoot.appendingPathComponent("\(base) \(n)"); n += 1 }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let work = Pipeline.workDir(output: folder, title: t)
                workDir = work
                plan = try await Pipeline.plan(audioPath: audio.path, title: t, subject: s, lyrics: l, work: work, imageInterval: every, config: config, progress: handler)
                stage = .plan; remember(work); loadWaveform()
            } catch { errorMessage = error.localizedDescription; stage = .setup }
        }
    }

    // MARK: Step 2
    func persist() { if let p = plan, let w = workDir { try? Pipeline.savePlan(p, w) } }

    func setPrompt(_ text: String, section: Int) {
        guard var p = plan else { return }
        if section < 0 { p.intro.prompt = text } else { p.sections[section].prompt = text }
        plan = p; persist()
    }

    func setStyle(_ text: String) { plan?.style = text; persist() }
    func setDescription(_ text: String) { plan?.description = text; persist() }

    func regeneratePrompts() {
        guard var p = plan else { return }
        busy = true
        Task {
            do { try await Pipeline.regeneratePrompts(plan: &p, config: config); plan = p; persist(); notice = "Prompts rewritten from the description." }
            catch { errorMessage = error.localizedDescription }
            busy = false
        }
    }

    func redescribe() {
        guard var p = plan else { return }
        busy = true
        Task {
            do { try await Pipeline.redescribe(plan: &p, config: config); try await Pipeline.regeneratePrompts(plan: &p, config: config); plan = p; persist() }
            catch { errorMessage = error.localizedDescription }
            busy = false
        }
    }

    func load(_ url: URL, section: Int) {
        guard var p = plan, let w = workDir else { return }
        do { if let warn = try Pipeline.attach(imageAt: url, section: section, plan: &p, work: w) { notice = warn }; plan = p }
        catch { errorMessage = error.localizedDescription }
    }

    func loadFolder(_ url: URL) {
        guard var p = plan, let w = workDir else { return }
        let r = Pipeline.attachFolder(url, plan: &p, work: w); plan = p
        notice = "Loaded \(r.loaded.count) picture(s)." + (r.warnings.isEmpty ? "" : "\n" + r.warnings.joined(separator: "\n"))
    }

    func removeImage(section: Int) {
        guard var p = plan, let w = workDir else { return }
        Pipeline.removeImage(section: section, plan: &p, work: w); plan = p
    }

    func reuse(section: Int, from source: Int) {
        guard let p = plan, let w = workDir, let f = p.sections[source].selectedCandidate?.fullFile else { return }
        load(w.appendingPathComponent(f), section: section)
    }

    func rewritePrompt(section: Int) {
        guard var p = plan else { return }
        busy = true
        Task {
            do { try await Pipeline.rewritePrompt(plan: &p, section: section, config: config); plan = p; persist() }
            catch { errorMessage = error.localizedDescription }
            busy = false
        }
    }

    func fullPrompt(section: Int) -> String { plan.map { Pipeline.fullPrompt($0, section: section) } ?? "" }

    func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }

    func copyAllPrompts() {
        guard let p = plan else { return }
        copy((-1..<p.sections.count).map { i in
            String(format: "%02d", i + 1) + ".\n" + Pipeline.fullPrompt(p, section: i)
        }.joined(separator: "\n\n"))
        notice = "All \(p.sections.count + 1) prompts copied."
    }

    func render() {
        guard let p = plan, let w = workDir else { return }
        stage = .rendering; phase = "Preparing frames"; progress = 0
        let q = quality
        Task {
            do {
                let out = Pipeline.videoURL(plan: p, work: w, config: config)
                try await VideoRenderer.render(plan: p, work: w, output: out, settings: VideoSettings(height: q), progress: handler)
                outputURL = out; stage = .done
            } catch { errorMessage = error.localizedDescription; stage = .plan }
        }
    }

    func reset() { stopPlayback(); stage = .setup; plan = nil; outputURL = nil; progress = 0; waveform = [] }

    // MARK: Projects
    func remember(_ folder: URL) {
        recents.removeAll { $0 == folder }; recents.insert(folder, at: 0); recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents.map(\.path), forKey: "recentProjects")
    }

    func openProject(_ folder: URL) {
        do {
            var p = try Pipeline.loadPlan(folder)
            // Heal pictures whose files were moved/deleted.
            for i in p.sections.indices { if let c = p.sections[i].selectedCandidate, let f = c.fullFile, !FileManager.default.fileExists(atPath: folder.appendingPathComponent(f).path) { p.sections[i].candidates = []; p.sections[i].selected = -1 } }
            plan = p; workDir = folder; title = p.title; subject = p.subject; lyrics = p.lines.map(\.text).joined(separator: "\n")
            stage = .plan; remember(folder); loadWaveform()
        } catch { errorMessage = "Couldn't open that project: \(error.localizedDescription)" }
    }

    func chooseProject() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = "Choose a project folder (it contains project.mvproj)"; p.directoryURL = outputRoot
        if p.runModal() == .OK, let u = p.url {
            if Pipeline.isProject(u) { openProject(u) }
            else if let sub = (try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil))?.first(where: Pipeline.isProject) { openProject(sub) }
            else { errorMessage = "That folder isn't a Music Video project." }
        }
    }

    @Published var resyncing = false
    /// Re-times the lyrics with exact word timestamps (older projects used approximate timing).
    func resync() {
        guard var p = plan, let w = workDir else { return }
        resyncing = true
        Task {
            do {
                let cov = try await Pipeline.resync(plan: &p, work: w, config: config)
                plan = p; notice = String(format: "Lyrics re-synced with exact word timing (%.0f%% of words matched).", cov * 100)
                refreshPreview(at: 1)
            } catch { errorMessage = error.localizedDescription }
            resyncing = false
        }
    }

    func revealProject() { if let w = workDir { NSWorkspace.shared.activateFileViewerSelecting([w]) } }

    // MARK: Shorts
    var audioFileURL: URL? { plan.flatMap { p in workDir.map { Pipeline.audioURL(p, work: $0) } } }

    func loadWaveform() {
        guard let u = audioFileURL else { return }
        Task { waveform = (try? await Transcriber.waveform(audioPath: u.path)) ?? [] }
    }

    var currentShort: ShortClip? { plan?.shorts.first { $0.id == selectedShort } }

    static let defaultShortLength = 30.0

    /// A new Short: `leadIn` seconds of music, then the first lyric, running 30 s in total (end snapped to a quiet gap).
    func newShort() {
        guard var p = plan else { return }
        let firstIdx = p.lines.firstIndex(where: { $0.start > 0 }) ?? 0
        let start = Pipeline.clip(plan: p, lines: firstIdx, to: firstIdx, lead: leadIn, tail: 0).start
        let end = min(p.songDuration, Pipeline.snap(start + Self.defaultShortLength, plan: p, maxDistance: 1.5))
        let c = ShortClip(name: "Short \(p.shorts.count + 1)", start: start, end: end)
        p.shorts.append(c); plan = p; selectedShort = c.id; persist(); refreshPreview(at: 1)
    }

    /// Local AI writes the opening title for a Short (3–6 words) from its lyrics.
    func writeHook(_ id: UUID) {
        guard let p = plan, let c = p.shorts.first(where: { $0.id == id }) else { return }
        hookBusy = true
        Task {
            if let h = await Pipeline.writeHook(plan: p, clip: c, config: config) { update(id) { $0.hook = h }; refreshPreview(at: 1.0) }
            hookBusy = false
        }
    }

    func shuffleLook(_ id: UUID) { update(id) { $0.styleSeed = UInt64.random(in: 1...UInt64(UInt32.max)) }; refreshPreview(at: 1.0) }

    /// The whole song as Shorts: one video if it fits in 3:00, otherwise split into the fewest parts that each do.
    func newWholeSong() {
        guard var p = plan else { return }
        let parts = Pipeline.wholeSongClips(plan: p)
        for c in parts where !p.shorts.contains(where: { $0.name == c.name }) { p.shorts.append(c) }
        plan = p; selectedShort = p.shorts.first(where: { $0.name == parts[0].name })?.id; persist(); refreshPreview(at: 1)
        if parts.count > 1 { notice = "The song is \(clock(p.songDuration)) — over the 3:00 Short limit — so it was split into \(parts.count) parts, cut at natural gaps in the lyrics. Render each part separately." }
    }

    func deleteShort(_ id: UUID) {
        plan?.shorts.removeAll { $0.id == id }; if selectedShort == id { selectedShort = plan?.shorts.first?.id }; persist()
    }

    func update(_ id: UUID, _ change: (inout ShortClip) -> Void) {
        guard var p = plan, let i = p.shorts.firstIndex(where: { $0.id == id }) else { return }
        var c = p.shorts[i]; change(&c)
        c.start = max(0, min(c.start, p.songDuration - 2)); c.end = min(p.songDuration, max(c.end, c.start + 2))
        if c.duration > ShortClip.maxDuration { c.end = c.start + ShortClip.maxDuration; capped = true }   // hard 3:00 limit
        p.shorts[i] = c; plan = p; persist()
    }

    /// Picks lyric lines for a Short. `from` = "In" (start here), `to` = "Out" (end here). The other end is kept if it still makes sense;
    /// otherwise it's chosen so the clip is about 30 s. Never exceeds the 3:00 limit.
    func setShortLines(_ id: UUID, from: Int? = nil, to: Int? = nil, fresh: Bool = false) {
        guard let p = plan, let c = p.shorts.first(where: { $0.id == id }), !p.lines.isEmpty else { return }
        let r = Pipeline.lineRange(plan: p, clip: c)
        var a: Int, b: Int
        if let f = from {
            a = f; b = fresh ? -1 : (r?.upperBound ?? f)       // a plain click starts a new ~30 s selection
            if b < a || p.lines[b].end - p.lines[a].start > ShortClip.maxDuration - 6 { b = Pipeline.lastLine(plan: p, from: a, within: 30) }
        } else if let t = to {
            b = t; a = r?.lowerBound ?? t
            if a > b || p.lines[b].end - p.lines[a].start > ShortClip.maxDuration - 6 { a = Pipeline.firstLine(plan: p, to: b, within: 30) }
        } else { return }
        let n = Pipeline.clip(plan: p, lines: a, to: b, lead: leadIn, tail: tailOut)
        update(id) { $0.start = n.start; $0.end = n.end }
    }

    func playRange(_ a: Double, _ b: Double) {
        guard let u = audioFileURL else { return }
        stopPlayback()
        guard let pl = try? AVAudioPlayer(contentsOf: u) else { return }
        audioPlayer = pl; pl.currentTime = max(0, a); pl.play(); playhead = a
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.audioPlayer else { return }
                self.playhead = p.currentTime
                if p.currentTime >= b || !p.isPlaying { self.stopPlayback() }
            }
        }
    }

    func stopPlayback() { playTimer?.invalidate(); playTimer = nil; audioPlayer?.stop(); audioPlayer = nil; playhead = nil }

    /// (Re)builds the live preview for the selected Short (debounced); `t` is the position to show afterwards.
    func refreshPreview(at t: Double) {
        guard let p = plan, let w = workDir, let audio = audioFileURL, let c = currentShort else { return }
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await live.load(plan: p, work: w, clip: c, audio: audio)
            live.seek(t)
        }
    }

    /// Preview of the full landscape video.
    func openFullPreview() {
        guard let p = plan, let w = workDir, let audio = audioFileURL else { return }
        showFullPreview = true
        Task { live.invalidate(); await live.load(plan: p, work: w, clip: nil, audio: audio); live.seek(min(live.time, 5)) }
    }

    func setCaptionY(_ v: Double?, shortID: UUID?) {
        if let id = shortID { update(id) { $0.captionY = v } } else { plan?.captionY = v; persist() }
    }

    /// Renders the Short — or, for A/B testing, 3 variants with different looks (same clip, different seeds).
    func renderShort(_ id: UUID, variants: Int = 1) {
        guard let p = plan, let w = workDir, let c = p.shorts.first(where: { $0.id == id }) else { return }
        stopPlayback(); shortProgress = 0; shortOutput = nil
        Task {
            do {
                for v in 0..<variants {
                    var cv = c; if v > 0 { cv.styleSeed = c.styleSeed &+ UInt64(v) &* 7919 }
                    let suffix = variants > 1 ? " (\(["A", "B", "C", "D", "E"][min(v, 4)]))" : ""
                    let base = Double(v) / Double(variants)
                    shortOutput = try await Pipeline.renderShort(plan: p, work: w, clip: cv, suffix: suffix, config: config) { [weak self] _, f in
                        Task { @MainActor in self?.shortProgress = base + f / Double(variants) }
                    }
                }
                if variants > 1 { shortOutput = Pipeline.shortsFolder(w) }
            } catch { errorMessage = error.localizedDescription }
            shortProgress = nil
        }
    }
}
