// App state and actions shared by every screen (planning, pictures, rendering, Shorts, folders, Dock).
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
    @Published var selectedStylePreset = StylePreset.all[0].name

    @Published var phase = ""
    @Published var progress = 0.0
    @Published var plan: Plan?
    @Published var workDir: URL?
    @Published var outputURL: URL?
    @Published var autoRenderShorts = true
    @Published var renderedShorts: [URL] = []
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var config = Config.load()

    // Background task progress banner (shown whenever any background task runs)
    @Published var busy = false
    @Published var busyPhase = ""
    @Published var busyProgress = 0.0
    var busyStarted = Date()
    var mainTask: Task<Void, Never>?
    var backgroundTask: Task<Void, Never>?
    var shortRenderTask: Task<Void, Never>?

    // Live Song Recording & Real-Time Transcription
    @Published var audioInputMode = 0   // 0 = Drop MP3/WAV, 1 = Record Song Playing
    @Published var recordSource: LiveSongRecorder.Source = .systemAudio
    @Published var isRecording = false
    @Published var recordingSeconds = 0.0
    @Published var recordingLevel: Float = 0
    @Published var recordingHistory: [Float] = []
    @Published var liveTranscribing = false
    @Published var trimSummary: String?
    private let recorder = LiveSongRecorder()
    private var recordTimer: Timer?
    private var lastLiveTranscribeTime = 0.0

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
    @Published var shortPhase = ""
    var shortStarted = Date()
    @Published var shortOutput: URL?
    @Published var hookBusy = false
    @Published var capped = false   // flashes a note when an edit hit the 3:00 limit
    @Published var leadIn = 3.0     // seconds of music before the first picked word
    @Published var tailOut = 3.0    // seconds of music after the last picked word
    var audioPlayer: AVAudioPlayer?
    var playTimer: Timer?
    var previewTask: Task<Void, Never>?
    var willQuit: NSObjectProtocol?

    // OpenRouter image generation & credits
    @Published var selectedSection = -1
    @Published var openRouterCredits: Double? = nil
    @Published var checkingCredits = false
    @Published var openRouterCreditError: String? = nil
    @Published var showOpenRouterKeySheet = false

    var hasOpenRouterKey: Bool { !config.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var perImageCostUSD: Double { plan?.lastImageCostUSD ?? OpenRouter.defaultEstimatedCostPerImage }
    var missingImagesCostUSD: Double { Double(missing.count) * perImageCostUSD }
    var allImagesCostUSD: Double { Double(totalImages) * perImageCostUSD }

    init() {
        // Stop the hidden oMLX engine (if we started one) when the app quits.
        willQuit = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in OMLXServer.shared.shutdown() }
        // Test hooks: MV_DEMO_PLAN=<work folder> opens the plan screen; MV_DEMO_DONE=<mp4> opens the finished screen.
        let env = ProcessInfo.processInfo.environment
        if let w = env["MV_DEMO_PLAN"], let p = try? Pipeline.loadPlan(URL(fileURLWithPath: w)) {
            plan = p; workDir = URL(fileURLWithPath: w); title = p.title; stage = .plan
            if let m = env["MV_DEMO_DONE"] { outputURL = URL(fileURLWithPath: m); stage = .done }
        }
        if hasOpenRouterKey { refreshOpenRouterCredits(silent: true) }
    }

    var canStart: Bool { !isRecording && !busy && audioURL != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty && !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var estimatedImages: Int { audioDuration > 0 ? max(2, Int((audioDuration / imageInterval).rounded()) + 1) : 0 }
    var missing: [Int] { plan.map(Pipeline.missing) ?? [] }
    var loadedCount: Int { plan.map { $0.sections.count + 1 - Pipeline.missing($0).count } ?? 0 }
    var totalImages: Int { plan.map { $0.sections.count + 1 } ?? 0 }

    /// Folder that holds projects (chosen in Settings; default ~/Movies/Music Videos).
    var outputRoot: URL { config.projectsRoot }

    func setAudio(_ url: URL) {
        audioURL = url
        trimSummary = nil
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

    private var busyHandler: ProgressHandler {
        { [weak self] phase, p in Task { @MainActor in self?.busyPhase = phase; self?.busyProgress = p } }
    }

    private func runBackground(initialPhase: String, work: @escaping () async throws -> Void) {
        backgroundTask?.cancel()
        busy = true; busyStarted = Date(); busyPhase = initialPhase; busyProgress = 0.05
        backgroundTask = Task {
            do {
                try await work()
            } catch is CancellationError {
                // User cancelled
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            busy = false; busyProgress = 0; backgroundTask = nil
        }
    }

    func cancelBackgroundTask() {
        backgroundTask?.cancel()
        backgroundTask = nil
        busy = false
        resyncing = false
        hookBusy = false
    }

    func cancelMainTask() {
        let wasPlanning = (stage == .working)
        mainTask?.cancel()
        mainTask = nil
        stage = wasPlanning ? .setup : .plan
    }

    func cancelShortRender() {
        shortRenderTask?.cancel()
        shortRenderTask = nil
        shortProgress = nil
        shortPhase = ""
    }

    // MARK: Live Song Recording & Real-Time Transcription

    func startRecording() {
        guard !isRecording else { return }
        stopPlayback()
        recordingSeconds = 0
        recordingLevel = 0
        recordingHistory = []
        lastLiveTranscribeTime = 0
        trimSummary = nil
        let src = recordSource
        Task {
            do {
                try await recorder.start(source: src)
                isRecording = true
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    let df = DateFormatter(); df.dateFormat = "MMM d h-mm a"
                    title = "Recorded Song (\(df.string(from: Date())))"
                }
                recordTimer?.invalidate()
                recordTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tickRecording() }
                }
            } catch is RecordingPermissionError {
                showRecordingFix = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    @Published var showRecordingFix = false

    private func tickRecording() {
        guard isRecording else { return }
        recordingSeconds = recorder.recordedDuration
        let lvl = recorder.level
        recordingLevel = lvl
        recordingHistory.append(lvl)
        if recordingHistory.count > 32 { recordingHistory.removeFirst(recordingHistory.count - 32) }

        // Real-time transcription every ~4.5 seconds of recorded audio
        if !liveTranscribing && recordingSeconds - lastLiveTranscribeTime >= 4.5 {
            let maxRecent = recordingHistory.suffix(24).max() ?? 0
            guard maxRecent > 0.008 else { return }
            lastLiveTranscribeTime = recordingSeconds
            liveTranscribing = true
            let pcm = recorder.snapshotMono16k()
            let cfg = config
            Task {
                if let text = try? await LiveSongRecorder.transcribePCM16k(pcm, config: cfg), !text.isEmpty {
                    if self.isRecording { self.lyrics = text }
                }
                self.liveTranscribing = false
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recordTimer?.invalidate(); recordTimer = nil
        isRecording = false; recordingLevel = 0
        let outDir = outputRoot.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let safeTitle = (title.trimmingCharacters(in: .whitespaces).isEmpty ? "Recorded Song" : title).replacingOccurrences(of: "/", with: "-")
        let wavURL = outDir.appendingPathComponent("\(safeTitle)_\(Int(Date().timeIntervalSince1970)).wav")
        let cfg = config
        runBackground(initialPhase: "Stopping recording & trimming silence…") { [weak self] in
            guard let self else { return }
            let bh = self.busyHandler
            let res = try await self.recorder.stopAndTrim(outputURL: wavURL) { p, f in
                bh(p, f * 0.45)
            }
            self.audioURL = res.url
            self.audioDuration = res.duration
            self.trimSummary = String(format: "Auto-trimmed %.1fs silence at start & %.1fs at end · Final length: %@", res.trimmedStart, res.trimmedEnd, timeString(res.duration))
            bh("Transcribing full trimmed song with Parakeet…", 0.55)
            if let text = try? await LiveSongRecorder.transcribeAudioFile(url: res.url, config: cfg), !text.isEmpty {
                self.lyrics = text
            }
            bh("Done", 1.0)
        }
    }

    func pasteOverLyrics() {
        if let s = NSPasteboard.general.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lyrics = s
        }
    }

    /// Transcribes whatever audio file is currently loaded into the Lyrics editor.
    func transcribeLoadedAudio() {
        guard let u = audioURL else { return }
        let cfg = config
        runBackground(initialPhase: "Transcribing lyrics from audio with Parakeet…") { [weak self] in
            guard let self else { return }
            self.busyHandler("Listening to song with Parakeet Ultra…", 0.25)
            let text = try await LiveSongRecorder.transcribeAudioFile(url: u, config: cfg)
            guard !text.isEmpty else { throw MVError("The speech model didn't detect any sung words in that audio file.") }
            self.lyrics = text
            self.busyHandler("Done", 1.0)
        }
    }

    /// Trims leading and trailing silence from the currently loaded audio file.
    func trimLoadedAudioSilence() {
        guard let u = audioURL else { return }
        let outDir = outputRoot.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let dst = outDir.appendingPathComponent(u.deletingPathExtension().lastPathComponent + "_trimmed.wav")
        runBackground(initialPhase: "Trimming silence from start and end…") { [weak self] in
            guard let self else { return }
            let res = try await LiveSongRecorder.trimAudioFile(at: u, outputURL: dst, progress: self.busyHandler)
            self.audioURL = res.url
            self.audioDuration = res.duration
            self.trimSummary = String(format: "Auto-trimmed %.1fs silence at start & %.1fs at end · Final length: %@", res.trimmedStart, res.trimmedEnd, timeString(res.duration))
        }
    }

    // MARK: Step 1
    func start() {
        guard let audio = audioURL else { return }
        config = Config.load()
        stage = .working; phase = "Starting…"; progress = 0
        let t = title.trimmingCharacters(in: .whitespaces), s = subject, l = lyrics, every = imageInterval
        let presetPrompt = StylePreset.all.first(where: { $0.name == selectedStylePreset })?.prompt ?? ""
        mainTask?.cancel()
        mainTask = Task {
            do {
                // Never overwrite an existing project: a second song/plan with the same title gets "Title 2", "Title 3"…
                let base = t.replacingOccurrences(of: "/", with: "-")
                var folder = outputRoot.appendingPathComponent(base); var n = 2
                while Pipeline.isProject(Pipeline.workDir(output: folder, title: t)) { folder = outputRoot.appendingPathComponent("\(base) \(n)"); n += 1 }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let work = Pipeline.workDir(output: folder, title: t)
                workDir = work
                plan = try await Pipeline.plan(audioPath: audio.path, title: t, subject: s, lyrics: l, work: work, imageInterval: every, preferredStyle: presetPrompt, config: config, progress: handler)
                stage = .plan; remember(work); loadWaveform(); refreshOpenRouterCredits(silent: true)
            } catch is CancellationError {
                stage = .setup
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
                stage = .setup
            }
            mainTask = nil
        }
    }

    // MARK: Step 2
    func persist() { if let p = plan, let w = workDir { try? Pipeline.savePlan(p, w) } }

    // MARK: OpenRouter Image Generation & Credits
    func refreshOpenRouterCredits(silent: Bool = true) {
        let key = config.effectiveOpenRouterKey
        guard !key.isEmpty else {
            openRouterCredits = nil
            openRouterCreditError = nil
            return
        }
        checkingCredits = true
        openRouterCreditError = nil
        Task {
            do {
                let info = try await OpenRouter.fetchCredits(apiKey: key)
                self.openRouterCredits = info.remaining
            } catch {
                if !silent {
                    self.openRouterCreditError = error.localizedDescription
                }
            }
            self.checkingCredits = false
        }
    }

    func saveOpenRouterKey(_ key: String) {
        config.openRouterKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try? config.save()
        refreshOpenRouterCredits(silent: false)
    }

    func generateImage(section: Int) {
        guard plan != nil, let w = workDir else { return }
        guard hasOpenRouterKey else {
            showOpenRouterKeySheet = true
            return
        }
        let label = section < 0 ? "Title Card" : String(format: "Picture %02d", section + 1)
        let isReroll = (section < 0 ? plan?.intro.hasImage : plan?.sections[section].hasImage) == true
        let actionWord = isReroll ? "Rerolling" : "Generating"
        runBackground(initialPhase: "\(actionWord) \(label) with \(OpenRouter.imageModel)…") { [weak self] in
            guard let self, var p = self.plan else { return }
            self.busyHandler("\(actionWord) \(label) (16:9 Medium)…", 0.25)
            let gen = try await Pipeline.generateSectionImage(section: section, plan: &p, work: w, config: self.config)
            self.plan = p
            if let rem = gen.creditsRemaining {
                self.openRouterCredits = rem
            } else {
                self.refreshOpenRouterCredits(silent: true)
            }
            self.live.invalidate()
            self.busyHandler("Done", 1.0)
        }
    }

    func generateAllMissingImages() {
        guard let p0 = plan, let w = workDir else { return }
        guard hasOpenRouterKey else {
            showOpenRouterKeySheet = true
            return
        }
        let targets = Pipeline.missing(p0)
        guard !targets.isEmpty else { return }
        generateSectionsList(targets, work: w, titlePrefix: "Generating \(targets.count) missing picture(s)")
    }

    func regenerateAllImages() {
        guard let p0 = plan, let w = workDir else { return }
        guard hasOpenRouterKey else {
            showOpenRouterKeySheet = true
            return
        }
        let targets = Array(-1..<p0.sections.count)
        generateSectionsList(targets, work: w, titlePrefix: "Generating all \(targets.count) picture(s)")
    }

    private func generateSectionsList(_ targets: [Int], work w: URL, titlePrefix: String) {
        runBackground(initialPhase: "\(titlePrefix) with \(OpenRouter.imageModel)…") { [weak self] in
            guard let self else { return }
            let total = targets.count
            var sessionSpent = 0.0
            var completed = 0
            for (idx, sec) in targets.enumerated() {
                try Task.checkCancellation()
                guard var p = self.plan else { break }
                let label = sec < 0 ? "Title Card" : String(format: "Picture %02d", sec + 1)
                self.busyHandler("\(idx + 1)/\(total): Generating \(label) (16:9 Medium)…", Double(idx) / Double(total))
                let gen = try await Pipeline.generateSectionImage(section: sec, plan: &p, work: w, config: self.config)
                sessionSpent += gen.costUSD
                completed += 1
                self.plan = p
                self.selectedSection = sec
                if let rem = gen.creditsRemaining {
                    self.openRouterCredits = rem
                }
                self.live.invalidate()
                self.busyHandler("\(idx + 1)/\(total): Saved \(label) (\(OpenRouter.formatUSD(gen.costUSD)))", Double(idx + 1) / Double(total))
            }
            self.refreshOpenRouterCredits(silent: true)
            if let totalSong = self.plan?.totalGenerationCostUSD {
                self.notice = "Generated \(completed) picture(s) for \(OpenRouter.formatUSD(sessionSpent)) · Song total: \(OpenRouter.formatUSD(totalSong))."
            }
        }
    }

    func setPrompt(_ text: String, section: Int) {
        guard var p = plan else { return }
        if section < 0 { p.intro.prompt = text } else { p.sections[section].prompt = text }
        plan = p; persist()
    }

    func setStyle(_ text: String) { plan?.style = text; persist() }
    func setDescription(_ text: String) { plan?.description = text; persist() }

    func applyStylePreset(_ name: String) {
        selectedStylePreset = name
        if let preset = StylePreset.all.first(where: { $0.name == name }), !preset.prompt.isEmpty {
            plan?.style = preset.prompt
            persist()
        }
    }

    func regeneratePrompts(keepStyle: Bool = true) {
        guard var p = plan else { return }
        runBackground(initialPhase: "Writing image prompts from description…") { [weak self] in
            guard let self else { return }
            try await Pipeline.regeneratePrompts(plan: &p, keepStyle: keepStyle, config: self.config, progress: self.busyHandler)
            self.plan = p; self.persist(); self.notice = "Prompts rewritten from the description."
        }
    }

    func redescribe() {
        guard var p = plan else { return }
        runBackground(initialPhase: "Rewriting song description & image prompts…") { [weak self] in
            guard let self else { return }
            let bh = self.busyHandler
            try await Pipeline.redescribe(plan: &p, config: self.config) { ph, f in bh(ph, f * 0.35) }
            try await Pipeline.regeneratePrompts(plan: &p, keepStyle: true, config: self.config) { ph, f in bh(ph, 0.35 + f * 0.65) }
            self.plan = p; self.persist()
        }
    }

    func load(_ url: URL, section: Int) {
        guard var p = plan, let w = workDir else { return }
        do {
            if let warn = try Pipeline.attach(imageAt: url, section: section, plan: &p, work: w) { notice = warn }
            plan = p; live.invalidate()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadFolder(_ url: URL) {
        guard let p0 = plan, let w = workDir else { return }
        runBackground(initialPhase: "Loading folder of pictures…") { [weak self] in
            guard let self else { return }
            let handler = self.busyHandler
            let (updated, r) = await Task.detached(priority: .userInitiated) {
                var p = p0
                let res = Pipeline.attachFolder(url, plan: &p, work: w, progress: handler)
                return (p, res)
            }.value
            self.plan = updated; self.live.invalidate()
            self.notice = "Loaded \(r.loaded.count) picture(s)." + (r.warnings.isEmpty ? "" : "\n" + r.warnings.joined(separator: "\n"))
        }
    }

    func removeImage(section: Int) {
        guard var p = plan, let w = workDir else { return }
        Pipeline.removeImage(section: section, plan: &p, work: w); plan = p; live.invalidate()
    }

    func setFocus(x: Double, y: Double, section: Int) {
        guard var p = plan else { return }
        let cx = min(0.95, max(0.05, x)), cy = min(0.95, max(0.05, y))
        if section < 0 {
            if p.intro.candidates.indices.contains(p.intro.selected) {
                p.intro.candidates[p.intro.selected].focusX = cx
                p.intro.candidates[p.intro.selected].focusY = cy
            }
        } else if p.sections.indices.contains(section), p.sections[section].candidates.indices.contains(p.sections[section].selected) {
            p.sections[section].candidates[p.sections[section].selected].focusX = cx
            p.sections[section].candidates[p.sections[section].selected].focusY = cy
        }
        plan = p; persist(); live.invalidate()
    }

    func resetFocus(section: Int) {
        guard let p = plan, let w = workDir else { return }
        let sec = section < 0 ? p.intro : p.sections[section]
        guard let thumb = sec.selectedCandidate?.thumbFile,
              let a = ImageScorer.analyze(fileURL: w.appendingPathComponent(thumb)) else {
            setFocus(x: 0.5, y: 0.5, section: section); return
        }
        setFocus(x: Double(a.focus.x), y: Double(a.focus.y), section: section)
    }

    /// Moves every caption of this song earlier (negative) or later (positive); the preview and the finished video both follow it.
    func nudgeCaptions(by delta: Double) {
        guard var p = plan else { return }
        p.captionShift = max(-0.5, min(0.5, ((p.captionShift + delta) * 100).rounded() / 100))
        plan = p; persist(); live.invalidate()
    }
    func resetCaptionTiming() { guard var p = plan else { return }; p.captionShift = Plan.defaultCaptionShift; plan = p; persist(); live.invalidate() }
    var captionShiftText: String {
        let v = plan?.captionShift ?? Plan.defaultCaptionShift
        if abs(v) < 0.005 { return "exactly with the voice" }
        return String(format: "%.2f s %@", abs(v), v < 0 ? "early" : "late")
    }
    @Published var showGuide = QuickGuideView.shouldShowFirst

    func nudgeLine(_ lineIndex: Int, delta: Double) {
        guard var p = plan, let w = workDir else { return }
        Pipeline.shiftLine(plan: &p, lineIndex: lineIndex, delta: delta, work: w)
        plan = p; live.invalidate()
    }

    func reuse(section: Int, from source: Int) {
        guard let p = plan, let w = workDir, let f = p.sections[source].selectedCandidate?.fullFile else { return }
        load(w.appendingPathComponent(f), section: section)
    }

    func rewritePrompt(section: Int) {
        guard var p = plan else { return }
        runBackground(initialPhase: "Writing another prompt take…") { [weak self] in
            guard let self else { return }
            try await Pipeline.rewritePrompt(plan: &p, section: section, config: self.config, progress: self.busyHandler)
            self.plan = p; self.persist()
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
        guard var p = plan, let w = workDir else { return }
        stage = .rendering; phase = "Preparing frames"; progress = 0; renderedShorts = []
        let q = quality
        let alsoShorts = autoRenderShorts
        if alsoShorts && p.shorts.isEmpty {
            p.shorts = Pipeline.autoShorts(plan: p)
            plan = p; persist()
        }
        mainTask?.cancel()
        mainTask = Task {
            do {
                let out = Pipeline.videoURL(plan: p, work: w, config: config)
                let mainWeight = alsoShorts && !p.shorts.isEmpty ? 0.50 : 1.0
                try await VideoRenderer.render(plan: p, work: w, output: out, settings: VideoSettings(height: q)) { [weak self] ph, f in
                    Task { @MainActor in
                        self?.phase = alsoShorts ? "Main video · \(ph)" : ph
                        self?.progress = f * mainWeight
                    }
                }
                var shortURLs: [URL] = []
                if alsoShorts && !p.shorts.isEmpty {
                    let count = p.shorts.count
                    for i in 0..<count {
                        try Task.checkCancellation()
                        var c = p.shorts[i]
                        let base = mainWeight + (1.0 - mainWeight) * (Double(i) / Double(count))
                        let span = (1.0 - mainWeight) / Double(count)
                        if c.hook.isEmpty {
                            await MainActor.run {
                                self.phase = "Short \(i + 1) of \(count) · Writing hook title…"
                                self.progress = base + span * 0.08
                            }
                            if let h = await Pipeline.writeHook(plan: p, clip: c, config: config), !h.isEmpty {
                                c.hook = h
                                p.shorts[i].hook = h
                                await MainActor.run { self.plan = p; self.persist() }
                            }
                        }
                        try Task.checkCancellation()
                        let sOut = try await Pipeline.renderShort(plan: p, work: w, clip: c, config: config) { [weak self] ph, f in
                            Task { @MainActor in
                                self?.phase = "Short \(i + 1) of \(count) (\(c.name)) · \(ph)"
                                self?.progress = base + span * (0.10 + 0.90 * f)
                            }
                        }
                        shortURLs.append(sOut)
                    }
                }
                renderedShorts = shortURLs
                outputURL = out; stage = .done
            } catch is CancellationError {
                stage = .plan
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
                stage = .plan
            }
            mainTask = nil
        }
    }

    func reset() { stopPlayback(); cancelBackgroundTask(); stage = .setup; plan = nil; outputURL = nil; renderedShorts = []; progress = 0; waveform = [] }

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
            if p.shorts.isEmpty && !p.lines.isEmpty {
                p.shorts = Pipeline.autoShorts(plan: p)
                try? Pipeline.savePlan(p, folder)
            }
            plan = p; workDir = folder; title = p.title; subject = p.subject; lyrics = p.lines.map(\.text).joined(separator: "\n")
            stage = .plan; remember(folder); loadWaveform(); refreshOpenRouterCredits(silent: true)
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
        runBackground(initialPhase: "Re-syncing lyrics with Parakeet…") { [weak self] in
            guard let self else { return }
            defer { self.resyncing = false }
            let cov = try await Pipeline.resync(plan: &p, work: w, config: self.config, progress: self.busyHandler)
            self.plan = p; self.notice = String(format: "Lyrics re-synced with exact word timing (%.0f%% of words matched).", cov * 100)
            self.refreshPreview(at: 1)
        }
    }

    func revealProject() { if let w = workDir { NSWorkspace.shared.activateFileViewerSelecting([w]) } }

    // MARK: Shorts
    var audioFileURL: URL? { plan.flatMap { p in workDir.map { Pipeline.audioURL(p, work: $0) } } }

    func loadWaveform() {
        guard let u = audioFileURL else { return }
        let w = workDir
        Task { waveform = (try? await Transcriber.waveform(audioPath: u.path, work: w)) ?? [] }
    }

    var currentShort: ShortClip? { plan?.shorts.first { $0.id == selectedShort } }

    static let defaultShortLength = 30.0

    /// Automatically generates 4–7 ~30-second Shorts breaking at natural stanza and vocal pause boundaries.
    func autoMakeShorts(replaceExisting: Bool = true) {
        guard var p = plan else { return }
        let generated = Pipeline.autoShorts(plan: p)
        if replaceExisting {
            p.shorts = generated
        } else {
            p.shorts.append(contentsOf: generated)
        }
        plan = p; selectedShort = p.shorts.first?.id; persist(); refreshPreview(at: 1)
        notice = "Created \(generated.count) Shorts (~30s each) cut at natural stanza & lyric boundaries."
    }

    /// Renders all Shorts in `plan.shorts` sequentially with progress and AI hooks.
    func renderAllShorts() {
        guard var p = plan, let w = workDir, !p.shorts.isEmpty else { return }
        stopPlayback(); shortProgress = 0; shortPhase = "Preparing \(p.shorts.count) Shorts…"; shortStarted = Date(); shortOutput = nil
        shortRenderTask?.cancel()
        shortRenderTask = Task {
            do {
                let count = p.shorts.count
                for i in 0..<count {
                    try Task.checkCancellation()
                    var c = p.shorts[i]
                    let base = Double(i) / Double(count)
                    let span = 1.0 / Double(count)
                    if c.hook.isEmpty {
                        shortPhase = "Short \(i + 1)/\(count): Writing hook…"
                        shortProgress = base + span * 0.08
                        if let h = await Pipeline.writeHook(plan: p, clip: c, config: config), !h.isEmpty {
                            c.hook = h; p.shorts[i].hook = h; plan = p; persist()
                        }
                    }
                    try Task.checkCancellation()
                    _ = try await Pipeline.renderShort(plan: p, work: w, clip: c, config: config) { [weak self] ph, f in
                        Task { @MainActor in
                            self?.shortPhase = "Short \(i + 1)/\(count) (\(c.name)): \(ph)"
                            self?.shortProgress = base + span * (0.10 + 0.90 * f)
                        }
                    }
                }
                shortOutput = Pipeline.shortsFolder(w)
                notice = "Rendered all \(count) Shorts to \(Pipeline.shortsFolder(w).lastPathComponent)/."
            } catch is CancellationError {
                shortOutput = nil
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            shortProgress = nil; shortPhase = ""; shortRenderTask = nil
        }
    }

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
        runBackground(initialPhase: "Writing opening hook title with local AI…") { [weak self] in
            guard let self else { return }
            defer { self.hookBusy = false }
            self.busyHandler("Generating punchy hook from Short lyrics…", 0.4)
            if let h = await Pipeline.writeHook(plan: p, clip: c, config: self.config) {
                self.update(id) { $0.hook = h }
                self.refreshPreview(at: 1.0)
            }
            self.busyHandler("Done", 1.0)
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
        stopPlayback(); shortProgress = 0; shortPhase = "Preparing Short…"; shortStarted = Date(); shortOutput = nil
        shortRenderTask?.cancel()
        shortRenderTask = Task {
            do {
                for v in 0..<variants {
                    try Task.checkCancellation()
                    var cv = c; if v > 0 { cv.styleSeed = c.styleSeed &+ UInt64(v) &* 7919 }
                    let label = variants > 1 ? "Variant \(["A", "B", "C", "D", "E"][min(v, 4)]) (\(v + 1)/\(variants)): " : ""
                    let suffix = variants > 1 ? " (\(["A", "B", "C", "D", "E"][min(v, 4)]))" : ""
                    let base = Double(v) / Double(variants)
                    shortOutput = try await Pipeline.renderShort(plan: p, work: w, clip: cv, suffix: suffix, config: config) { [weak self] ph, f in
                        Task { @MainActor in
                            self?.shortPhase = label + ph
                            self?.shortProgress = base + f / Double(variants)
                        }
                    }
                }
                if variants > 1 { shortOutput = Pipeline.shortsFolder(w) }
            } catch is CancellationError {
                shortOutput = nil
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            shortProgress = nil; shortPhase = ""; shortRenderTask = nil
        }
    }
}
