// App state and actions shared by every screen (planning, pictures, rendering, Shorts, folders, Dock).
import SwiftUI
import AVFoundation
import CryptoKit
import MVCore
#if NATIVE_MLX
import MVNative
#endif

@MainActor
final class AppModel: ObservableObject {
    enum Stage { case setup, working, plan, rendering, done, loop }

    @Published var stage: Stage = .setup
    @Published var audioURL: URL?
    @Published var audioDuration: Double = 0
    @Published var title = ""
    @Published var subject = ""
    @Published var songNotes = ""                 // "About the song": your own words; steers the description, setting ideas and YouTube text
    @Published var settingTheme = ""        // “Brightly lit colonial Philadelphia”: every picture prompt follows it
    @Published var lyrics = ""
    @Published var quality = 1080
    @Published var selectedStylePreset = StylePreset.autoID      // the id of the chosen picture style

    @Published var phase = ""
    @Published var progress = 0.0
    @Published var plan: Plan? {
        willSet {
            if plan != nil, newValue != nil, !restoringHistory, !skipNextPlanHistory, !timelineDragging,
               stage != .working, checkpointRevision != planRevision { checkpoint("Edit project", coalesce: true) }
            planRevision += 1; checkpointRevision = nil; skipNextPlanHistory = false
        }
    }
    @Published var workDir: URL?
    @Published var outputURL: URL?
    @Published var autoRenderShorts = true           // Shorts are made together with the video unless you untick it
    @Published var renderedShorts: [URL] = []
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var config = Config.load()

    @Published var draftSections: [PhotoSection]?
    @Published var draftShorts: [ShortClip] = []
    @Published var draftKey = ""
    @Published var timelineCursor = 0.0
    @Published var timelineZoom = 1.0
    @Published var timelineSnap = true
    @Published var snapDescription = ""
    @Published var saveStatus = ""
    @Published var editUndo: [TimelineSnapshot] = []
    @Published var editRedo: [TimelineSnapshot] = []
    var timelineDragging = false
    var restoringHistory = false
    var skipNextPlanHistory = false
    var planRevision = 0
    var checkpointRevision: Int?
    var listenTask: Task<Void, Never>?
    var lastEditAt = Date.distantPast
    var lastEditName = ""

    // Background task progress banner (shown whenever any background task runs)
    @Published var busy = false
    @Published var videoJob: VideoJob?
    @Published var youtubeFiles: (thumbnail: URL, description: URL)?      // made next to the finished video
    @Published var youtubeBusy = false
    // Looping long music video (its own workflow)
    @Published var loopProject: LoopProject?
    @Published var loopDir: URL?
    @Published var loopJob: LoopJob?
    var loopTask: Task<Void, Never>?
    var loopPreviewTask: Task<Void, Never>?
    var loopListenTask: Task<Void, Never>?
    @Published var loopListening: String?          // "Listening to the songs (3 of 17)…" while new songs are being measured
    @Published var showProjects = false
    var videoTask: Task<Void, Never>?
    @Published var workingSection: Int?            // the picture being drawn (or whose idea is being rewritten) right now: only it is locked while a task runs
    @Published var doneNote: DoneNote?
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
        if ProcessInfo.processInfo.environment["MV_EDITOR_SELFTEST"] != nil { return false }
        #if NATIVE_MLX
        return !NativeEngine.isInstalled
        #else
        return false
        #endif
    }

    // On-device models: what is installed, and live download progress for each (shown in Settings and on the first-run screen)
    @Published var speechProgress: Double?          // nil = not downloading
    @Published var llmProgress: Double?
    @Published var modelNote: String?               // last error / note, shown under the list
    @Published var modelTick = 0                    // bump to re-read what is on disk
    var speechReady: Bool { _ = modelTick; return modelState.speech }
    var llmReady: Bool { _ = modelTick; return modelState.llm }
    var speechSizeText: String { _ = modelTick; return modelState.speechText }
    var llmSizeText: String { _ = modelTick; return modelState.llmText }
    var llmName: String { _ = modelTick; return modelState.llmName }
    var downloadingModel: Bool { speechProgress != nil || llmProgress != nil }
    private var modelState: (speech: Bool, llm: Bool, speechText: String, llmText: String, llmName: String) {
        #if NATIVE_MLX
        func gb(_ b: Int) -> String { b >= 100_000_000 ? String(format: "%.1f GB", Double(b) / 1e9) : String(format: "%.0f MB", Double(b) / 1e6) }
        return (NativeEngine.speechInstalled, NativeEngine.llmInstalled, gb(NativeEngine.speechBytes), gb(NativeEngine.llmBytes), NativeEngine.llmName)
        #else
        return (true, true, "", "", "Language model")
        #endif
    }

    /// Downloads (or re-downloads) Parakeet Ultra. Progress appears on its row.
    func downloadSpeechModel(force: Bool = false) {
        #if NATIVE_MLX
        guard !downloadingModel else { return }
        speechProgress = 0; modelNote = nil
        Task {
            do { try await NativeEngine.installSpeech(force: force) { [weak self] p, f in Task { @MainActor in self?.speechProgress = f; self?.setupPhase = p } } }
            catch { modelNote = "Parakeet didn't finish downloading: \(error.localizedDescription)" }
            speechProgress = nil; modelTick += 1; objectWillChange.send()
        }
        #endif
    }

    /// Downloads (or re-downloads) the language model for the chosen size. Progress appears on its row.
    func downloadLanguageModel(force: Bool = false) {
        #if NATIVE_MLX
        guard !downloadingModel, let tier = NativeEngine.Tier(rawValue: nativeTier) else { return }
        llmProgress = 0; modelNote = nil
        Task {
            do { try await NativeEngine.installLanguageModel(tier: tier, force: force) { [weak self] p, f in Task { @MainActor in self?.llmProgress = f; self?.setupPhase = p } } }
            catch { modelNote = "The language model didn't finish downloading: \(error.localizedDescription)" }
            llmProgress = nil; modelTick += 1; objectWillChange.send()
        }
        #endif
    }

    /// First-run: download whatever is missing, speech first.
    func runNativeSetup() {
        #if NATIVE_MLX
        guard let tier = NativeEngine.Tier(rawValue: nativeTier), !downloadingModel else { return }
        settingUp = true; setupStarted = Date(); setupPhase = "Starting…"; setupProgress = 0; modelNote = nil
        Task {
            do {
                if !NativeEngine.speechInstalled {
                    speechProgress = 0
                    try await NativeEngine.installSpeech { [weak self] p, f in Task { @MainActor in self?.speechProgress = f; self?.setupPhase = p; self?.setupProgress = f * 0.2 } }
                    speechProgress = nil; modelTick += 1
                }
                if !NativeEngine.llmInstalled {
                    llmProgress = 0
                    try await NativeEngine.installLanguageModel(tier: tier) { [weak self] p, f in Task { @MainActor in self?.llmProgress = f; self?.setupPhase = p; self?.setupProgress = 0.2 + f * 0.8 } }
                    llmProgress = nil; modelTick += 1
                }
                settingUp = false; objectWillChange.send()
            } catch {
                settingUp = false; speechProgress = nil; llmProgress = nil; modelTick += 1
                errorMessage = "Setup didn't finish: \(error.localizedDescription)\n\nPress “Download & set up” again; it continues with what is still missing."
            }
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
    @Published var recents: [URL] = (UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []).map { URL(fileURLWithPath: $0) }.filter { Pipeline.isProject($0) || LoopVideo.isLoopProject($0) }

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
    @Published var requestRegenAll = false      // the key window asks the Pictures screen to confirm “make every picture again”

    var hasOpenRouterKey: Bool { !config.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var perImageCostUSD: Double { plan?.lastImageCostUSD ?? OpenRouter.defaultEstimatedCostPerImage }
    var missingImagesCostUSD: Double { Double(missing.count) * perImageCostUSD }
    var allImagesCostUSD: Double { Double(totalImages) * perImageCostUSD }

    init() {
        // Stop the hidden oMLX engine (if we started one) when the app quits.
        willQuit = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in OMLXServer.shared.shutdown() }
        // Test hooks: MV_DEMO_PLAN=<work folder> opens the plan screen; MV_DEMO_DONE=<mp4> opens the finished screen.
        let env = ProcessInfo.processInfo.environment
        if let root = env["MV_TEST_ROOT"], env["MV_EDITOR_SELFTEST"] != nil { config = Config(); config.projectsFolder = root; showGuide = false }
        if let w = env["MV_DEMO_PLAN"], let p = try? Pipeline.loadPlan(URL(fileURLWithPath: w)) {
            plan = p; workDir = URL(fileURLWithPath: w); title = p.title; lyrics = Self.lyricsText(of: p); audioURL = Pipeline.audioURL(p, work: URL(fileURLWithPath: w)); audioDuration = p.songDuration; stage = .plan
            if let m = env["MV_DEMO_DONE"] { outputURL = URL(fileURLWithPath: m); stage = .done }
        }
        if hasOpenRouterKey && env["MV_EDITOR_SELFTEST"] == nil { refreshOpenRouterCredits(silent: true) }
    }

    var canStart: Bool { !isRecording && !busy && audioURL != nil && !title.trimmingCharacters(in: .whitespaces).isEmpty && !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var estimatedImages: Int { previewSections.map { $0.count + 1 } ?? (audioDuration > 0 ? max(2, Int((audioDuration / 30).rounded()) + 1) : 0) }
    var missing: [Int] { plan.map(Pipeline.missing) ?? [] }
    var loadedCount: Int { plan.map { $0.sections.count + 1 - Pipeline.missing($0).count } ?? 0 }
    var totalImages: Int { plan.map { $0.sections.count + 1 } ?? 0 }

    /// Folder that holds projects (chosen in Settings; default ~/Movies/Music Videos).
    var outputRoot: URL { config.projectsRoot }

    /// A song's name for comparing files: no extension, no " (1)" / " copy" suffix, case and punctuation ignored.
    static func songKey(_ name: String) -> String {
        var t = (name as NSString).deletingPathExtension.lowercased()
        if let r = t.range(of: " (") { t = String(t[..<r.lowerBound]) }
        if t.hasSuffix(" copy") { t = String(t.dropLast(5)) }
        return t.filter { $0.isLetter || $0.isNumber }
    }
    static func titleFromFile(_ url: URL) -> String {
        var t = url.deletingPathExtension().lastPathComponent
        if let r = t.range(of: " (") { t = String(t[..<r.lowerBound]) }
        return t
    }
    private var autoTitle: String?          // the title the app filled in from a file name (so a different file can replace it)

    /// Loads a song. A song with a different name than the one you are working on starts a NEW project; the earlier one stays saved.
    func setAudio(_ url: URL) {
        let newKey = AppModel.songKey(url.lastPathComponent)
        if let p = plan, projectBaseline != nil, newKey != AppModel.songKey(p.title), newKey != AppModel.songKey(projectBaseline?.audioName ?? "") {
            let old = p.title
            detachProject()
            notice = "Started a new video for “\(AppModel.titleFromFile(url))”. “\(old)” is saved; open it again from “Projects” (Command-O)."
        } else if let prev = audioURL, plan == nil, AppModel.songKey(prev.lastPathComponent) != newKey, title == autoTitle || title.isEmpty {
            title = ""                                   // the old title came from the old file name
        }
        if audioURL != url { clearTimelineSession(); analysis = nil; listenTask?.cancel(); listening = false }
        audioURL = url
        trimSummary = nil
        if title.isEmpty { title = AppModel.titleFromFile(url); autoTitle = title }
        Task { audioDuration = (try? await MVCore.audioDuration(path: url.path)) ?? 0 }
    }

    // MARK: Moving between Song · Pictures · Video

    /// What the Song screen showed when it was opened from an existing project; used to tell whether you changed anything.
    @Published var projectBaseline: (title: String, subject: String, lyrics: String, audioName: String, setting: String)?
    var hasProject: Bool { plan != nil && workDir != nil }
    /// Where the finished video of the open project is, if it exists.
    var videoFile: URL? {
        guard let p = plan, let w = workDir else { return nil }
        let u = Pipeline.videoURL(plan: p, work: w, config: config)
        return FileManager.default.fileExists(atPath: u.path) ? u : (outputURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil })
    }
    var setupChanged: Bool {
        guard let b = projectBaseline else { return true }
        return title != b.title || subject != b.subject || settingTheme != b.setting || lyrics != b.lyrics || (audioURL?.lastPathComponent ?? "") != b.audioName
    }
    func canGoToStep(_ n: Int) -> Bool {
        if busy || stage == .working || stage == .rendering || videoJob != nil { return false }
        switch n { case 1: return true; case 2: return hasProject; case 3: return videoFile != nil; default: return false }
    }
    func goToStep(_ n: Int) {
        guard canGoToStep(n) else { return }
        stopPlayback()
        switch n {
        case 1:
            if let p = plan, let w = workDir {
                title = p.title; subject = p.subject; songNotes = p.songNotes; settingTheme = p.setting; lyrics = AppModel.lyricsText(of: p)
                let audio = w.appendingPathComponent(p.audioFile.isEmpty ? "audio.mp3" : p.audioFile)
                if FileManager.default.fileExists(atPath: audio.path) { audioURL = audio; audioDuration = p.songDuration }
                projectBaseline = (title, subject, lyrics, audioURL?.lastPathComponent ?? "", settingTheme)
            }
            stage = .setup
        case 2: stage = .plan
        default: outputURL = videoFile; stage = .done
        }
    }
    /// The lyrics as typed text: your own parts as `---` dividers, otherwise a blank line between the picture sections.
    static func lyricsText(of p: Plan) -> String {
        if let source = p.sourceLyrics, LyricText.rows(source).map(\.text) == p.lines.map(\.text) { return source }
        let texts = p.lines.map(\.text)
        if !p.partStarts.isEmpty && !p.partsFromVerses { return LyricText.text(lines: texts, partStarts: p.partStarts) }
        if p.partsFromVerses {
            let set = Set(p.partStarts); var out: [String] = []
            for (i, t) in texts.enumerated() { if set.contains(i) && i > 0 { out.append("") }; out.append(t) }
            return out.joined(separator: "\n")
        }
        let starts = p.sections.compactMap(\.lineIDs.first).filter { $0 > 0 }
        let set = Set(starts); var out: [String] = []
        for (i, t) in texts.enumerated() { if set.contains(i) { out.append("") }; out.append(t) }
        return out.joined(separator: "\n")
    }
    // MARK: the song on a timeline (words with their times, music breaks) and the pictures it will get
    struct SongAnalysis { var lines: [LyricLine]; var duration: Double; var key: String }
    @Published var analysis: SongAnalysis?
    @Published var listening = false
    @Published var listenPhase = ""
    @Published var listenFraction = 0.0

    /// Changes whenever the song or the words themselves change (but not when you only add or remove cuts).
    var analysisKey: String { (audioURL.map { Transcriber.fileStamp($0.path) } ?? "") + "|" + LyricText.rows(LyricText.clearDividers(lyrics)).map(\.text).joined(separator: "\n") }
    /// The lyric lines with their times: from "Listen to the song first", or from the planned project when it is the same words.
    var timelineLines: (lines: [LyricLine], duration: Double)? {
        if let a = analysis, a.key == analysisKey { return (a.lines, a.duration) }
        if let p = plan, hasProject, LyricText.rows(lyrics).isEmpty || p.lines.map(\.text) == LyricText.rows(LyricText.clearDividers(lyrics)).map(\.text) { return (p.lines, p.songDuration) }
        return nil
    }
    /// The pictures the song would get right now (one per verse and per music break), or nil until the song has been listened to.
    var previewSections: [PhotoSection]? {
        guard let t = timelineLines else { return nil }
        if let p = plan, p.lines.map(\.text) == t.lines.map(\.text) { return p.sections }
        if draftKey == analysisKey, let sections = draftSections { return sections }
        let parsed = LyricAligner.parse(lyrics)
        return Planner.structure(lines: t.lines, stanzaBreaks: parsed.stanzaBreaks, partBreaks: parsed.partBreaks, songDuration: t.duration)
    }
    var listenFolder: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicVideo/listen").appendingPathComponent(SHA256.hash(data: Data((audioURL.map { Transcriber.fileStamp($0.path) } ?? "none").utf8)).map { String(format: "%02x", $0) }.joined())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Listens to the song and matches the words to it (about a minute), without writing any picture ideas yet.
    func listenToSong() {
        guard let audio = audioURL, !listening, !LyricText.rows(lyrics).isEmpty else { return }
        config = Config.load()
        listening = true; listenPhase = "Starting…"; listenFraction = 0
        let key = analysisKey, l = lyrics, folder = listenFolder
        listenTask?.cancel()
        listenTask = Task {
            do {
                let h = try await Pipeline.listen(audioPath: audio.path, title: title, lyrics: l, work: folder, config: config) { ph, f in
                    Task { @MainActor in self.listenPhase = ph; self.listenFraction = f }
                }
                try Task.checkCancellation()
                guard key == analysisKey else { listening = false; return }
                analysis = SongAnalysis(lines: h.lines, duration: h.duration, key: key)
                loadDraft()                 // cuts you made before come back
                ensureDraftKey()
                waveform = (try? await Transcriber.waveform(audioPath: audio.path, work: folder)) ?? []
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
            listening = false
        }
    }

    func subdivide(section: PhotoSection, into parts: Int) {
        guard let t = timelineLines, parts >= 2 else { return }
        checkpoint("Split picture")
        var sections = previewSections ?? []
        for j in 1..<parts { sections = TimelineEditor.split(sections, at: section.start + section.duration * Double(j) / Double(parts), lines: t.lines) }
        commitPictures(sections)
    }
    func splitLongVerses() {
        if plan != nil, refuseWhileWorking() { return }
        guard let t = timelineLines, let sections = previewSections else { return }
        checkpoint("Split long sections")
        var result = sections
        for s in sections where s.duration > 30 {
            let count = Int(ceil(s.duration / 30))
            for j in 1..<count { result = TimelineEditor.split(result, at: s.start + s.duration * Double(j) / Double(count), lines: t.lines) }
        }
        commitPictures(result)
    }
    func toggleDivider(before i: Int) { if let t = timelineLines, t.lines.indices.contains(i) { splitPicture(at: t.lines[i].start) } }
    func clearDividers() { restoreAutomaticPictures() }
    func divideEvenly(_ n: Int) { if let t = timelineLines, n > 1 { checkpoint("Divide pictures"); commitPictures(TimelineEditor.applying((1..<n).map { t.duration * Double($0) / Double(n) }, to: previewSections ?? [], lines: t.lines, duration: t.duration)) } }
    func dividersFromVerses() {} // retained for older snapshot hooks; boundaries now live independently of lyrics.

    /// Forgets the open project (it stays saved on disk) so the Song screen starts empty.
    func detachProject() {
        clearTimelineSession(); stopPlayback(); plan = nil; workDir = nil; outputURL = nil; renderedShorts = []; waveform = []; projectBaseline = nil
        title = ""; subject = ""; songNotes = ""; settingTheme = ""; lyrics = ""; audioURL = nil; audioDuration = 0; autoTitle = nil
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
        let spentBefore = (plan?.totalGenerationCostUSD ?? 0) + (plan?.totalVideoCostUSD ?? 0), title = initialPhase
        backgroundTask = Task {
            do {
                try await work()
                if !Task.isCancelled {
                    let spent = (plan?.totalGenerationCostUSD ?? 0) + (plan?.totalVideoCostUSD ?? 0) - spentBefore
                    doneNote = DoneNote(text: "Done — " + title.replacingOccurrences(of: "…", with: "") + (spent > 0.0001 ? " · cost \(OpenRouter.formatUSD(spent))" : ""))
                }
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
        let t = title.trimmingCharacters(in: .whitespaces), s = subject, l = lyrics, every = 30.0, theme = settingTheme, notes = songNotes
        let boundaries = draftKey == analysisKey ? draftSections.map(TimelineEditor.boundaries) : nil
        let shorts = timelineShorts
        let presetPrompt = StylePreset.all.first(where: { $0.id == selectedStylePreset })?.prompt ?? ""
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
                // the listening done earlier (words and their times) is reused, so the song is not heard twice
                let cached = listenFolder.appendingPathComponent("transcript_words.json")
                if FileManager.default.fileExists(atPath: cached.path) { try? FileManager.default.copyItem(at: cached, to: work.appendingPathComponent("transcript_words.json")) }
                var made = try await Pipeline.plan(audioPath: audio.path, title: t, subject: s, lyrics: l, work: work, imageInterval: every, preferredStyle: presetPrompt, setting: theme, notes: notes, pictureBoundaries: boundaries, shorts: shorts, config: config, progress: handler)
                if made.shorts.isEmpty { made.shorts = Pipeline.autoShorts(plan: made); try? Pipeline.savePlan(made, work) }      // a new plan starts with suggested Shorts (drag, delete or add as you like)
                plan = made
                draftSections = nil; draftShorts = []; draftKey = ""; editUndo = []; editRedo = []
                projectBaseline = nil; outputURL = nil; renderedShorts = []
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
    func persist() {
        guard !timelineDragging, let p = plan, let w = workDir else { return }
        do { try Pipeline.savePlan(p, w); saveStatus = "Saved" }
        catch { saveStatus = "Not saved — try again"; errorMessage = "Your latest changes could not be saved. Keep this project open and try again. " + error.localizedDescription }
    }

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
        guard section == -1 || plan?.sections.indices.contains(section) == true else { return }
        let isReroll = (section < 0 ? plan?.intro.hasImage : plan?.sections[section].hasImage) == true
        let actionWord = isReroll ? "Rerolling" : "Generating"
        runBackground(initialPhase: "\(actionWord) \(label) with \(OpenRouter.imageModel)…") { [weak self] in
            guard let self, var p = self.plan else { return }
            let before = p
            self.workingSection = section; defer { self.workingSection = nil }
            self.busyHandler("\(actionWord) \(label) (16:9 Medium)…", 0.25)
            let gen = try await Pipeline.generateSectionImage(section: section, plan: &p, work: w, config: self.config)
            self.mergeTaskResult(p, startedFrom: before, section: section, artwork: true)
            if let rem = gen.creditsRemaining {
                self.openRouterCredits = rem
            } else {
                self.refreshOpenRouterCredits(silent: true)
            }
            self.live.invalidate()
            self.busyHandler("Done", 1.0)
        }
    }

    /// Makes this picture the style guide: every picture drawn from now on is matched to it.
    /// Opens the shared Pictures folder (every picture, named with its date, project and an increasing number).
    func showPicturesFolder(select name: String? = nil) {
        let dir = PictureLibrary.folder(config: config)
        if let n = name, FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path) { NSWorkspace.shared.activateFileViewerSelecting([dir.appendingPathComponent(n)]) }
        else { NSWorkspace.shared.open(dir) }
    }

    /// Copies the pictures and video clips of all earlier songs, and of the open song, into the Pictures folder.
    func backfillPictureLibrary() {
        let cfg = config, open = workDir
        runBackground(initialPhase: "Adding your earlier pictures and clips to the Pictures folder…") { [weak self] in
            guard let self else { return }
            let handler = self.busyHandler
            let r = await Task.detached(priority: .utility) { PictureLibrary.backfill(config: cfg, skipping: open, progress: handler) }.value
            var added = r.added, songs = r.songs
            if var p = self.plan, let w = open, self.workDir == w {            // the open song is done in memory, so nothing it holds is overwritten
                handler("Adding the open song's pictures and clips…", 0.95)
                let n = PictureLibrary.backfill(plan: &p, work: w, config: cfg)
                if n > 0 { self.plan = p; self.persist(); added += n; songs += 1 }
            }
            self.notice = added == 0 ? "Every earlier picture and clip is already in the Pictures folder." : "Added \(added) picture\(added == 1 ? "" : "s") and clip\(added == 1 ? "" : "s") from \(songs) song\(songs == 1 ? "" : "s") to the Pictures folder."
        }
    }

    func setStyleGuide(_ section: Int) {
        guard var p = plan else { return }
        checkpoint("Choose style guide picture")
        p.styleGuideSection = section == -1 ? nil : section; plan = p; persist()
    }
    var styleGuideSection: Int { plan?.styleGuideSection ?? -1 }

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

    private func generateSectionsList(_ targetsIn: [Int], work w: URL, titlePrefix: String, then: (@MainActor () async throws -> Void)? = nil) {
        // the style guide picture is made first, so every other picture can be drawn to match it
        var targets = targetsIn
        let guide = plan?.styleGuideSection ?? -1
        if let k = targets.firstIndex(of: guide), k > 0 { targets.remove(at: k); targets.insert(guide, at: 0) }
        runBackground(initialPhase: "\(titlePrefix) with \(OpenRouter.imageModel)…") { [weak self] in
            guard let self else { return }
            let total = targets.count
            var sessionSpent = 0.0
            var completed = 0
            var similar: [String] = []
            defer { self.workingSection = nil }
            for (idx, sec) in targets.enumerated() {
                try Task.checkCancellation()
                guard var p = self.plan else { break }
                let before = p
                self.workingSection = sec
                let label = sec < 0 ? "Title Card" : String(format: "Picture %02d", sec + 1)
                self.busyHandler("\(idx + 1)/\(total): Generating \(label) (16:9 Medium)…", Double(idx) / Double(total))
                let gen = try await Pipeline.generateSectionImage(section: sec, plan: &p, work: w, config: self.config)
                sessionSpent += gen.costUSD
                completed += 1
                if p.sections.indices.contains(sec) || sec < 0, (sec < 0 ? p.intro : p.sections[sec]).selectedCandidate?.looksLikePrevious(Pipeline.previousPictureFile(plan: p, for: sec)) == true { similar.append(label) }
                self.mergeTaskResult(p, startedFrom: before, section: sec, artwork: true)        // keeps any edits you made meanwhile; the selection is left alone
                if let rem = gen.creditsRemaining {
                    self.openRouterCredits = rem
                }
                self.live.invalidate()
                self.busyHandler("\(idx + 1)/\(total): Saved \(label) (\(OpenRouter.formatUSD(gen.costUSD)))", Double(idx + 1) / Double(total))
            }
            self.refreshOpenRouterCredits(silent: true)
            _ = (completed, sessionSpent)                                  // the green "Done" line at the top shows how many and what they cost
            if !similar.isEmpty { self.notice = "Heads-up: \(similar.joined(separator: ", ")) \(similar.count == 1 ? "has" : "have") almost the same framing as the picture before. Nothing was redrawn; look and press “Try another picture” if you want a different view." }
            try await then?()
        }
    }

    /// The picture before this section's (the title card for the first section).
    func previousPictureFile(section: Int) -> String? { plan.flatMap { Pipeline.previousPictureFile(plan: $0, for: section) } }

    func setPrompt(_ text: String, section: Int) {
        guard var p = plan, section == -1 || p.sections.indices.contains(section) else { return }
        checkpoint("Edit picture idea", coalesce: true)
        if section < 0 { p.intro.prompt = text; p.intro.promptManual = true; p.intro.logicNote = nil } else { p.sections[section].prompt = text; p.sections[section].promptManual = true; p.sections[section].logicNote = nil }
        plan = p; persist()
    }

    func setStyle(_ text: String) { plan?.style = text; persist() }
    /// Ten setting ideas from the lyrics (for the first screen or the open project).
    func fetchSettingIdeas(avoid: [String]) async throws -> [String] {
        let ls = plan.map { $0.lines.map(\.text) } ?? LyricAligner.parse(lyrics).lines
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        return try await PromptWriter(omlx: omlx).suggestSettings(title: plan?.title ?? title, lyrics: ls, description: plan?.description ?? "", notes: plan?.songNotes ?? songNotes, avoid: avoid)
    }
    func setSetting(_ text: String) { plan?.setting = text; persist() }
    func setDescription(_ text: String) { plan?.description = text; persist() }
    func setSongNotes(_ text: String) { plan?.songNotes = text; songNotes = text; persist() }

    var selectedStyleName: String { StylePreset.all.first(where: { $0.id == selectedStylePreset })?.name ?? StyleLibrary.auto.name }
    func applyStylePreset(_ id: String) {
        selectedStylePreset = id
        if let preset = StylePreset.all.first(where: { $0.id == id }), !preset.prompt.isEmpty {
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
        checkpoint("Load artwork")
        do {
            if let warn = try Pipeline.attach(imageAt: url, section: section, plan: &p, work: w) { notice = warn }
            plan = p; draftSections = nil; persist(); live.invalidate()
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
            self.plan = updated; self.persist(); self.live.invalidate()
            self.notice = "Loaded \(r.loaded.count) picture(s)." + (r.warnings.isEmpty ? "" : "\n" + r.warnings.joined(separator: "\n"))
        }
    }

    func removeImage(section: Int) {
        guard var p = plan, let w = workDir else { return }
        checkpoint("Remove artwork")
        Pipeline.removeImage(section: section, plan: &p, work: w); plan = p; draftSections = nil; persist(); live.invalidate()
    }

    /// Chooses which part of a video clip plays (seconds inside the clip); `end` nil = to the end of the clip.
    func setVideoTrim(section: Int, start: Double, end: Double?) {
        guard var p = plan else { return }
        checkpoint("Trim video", coalesce: true)
        func apply(_ s: inout PhotoSection) {
            guard s.candidates.indices.contains(s.selected) else { return }
            let length = max(0.001, s.candidates[s.selected].videoLength ?? end ?? start + 0.5)
            let from = min(max(0, start), max(0, length - min(0.5, length)))
            s.candidates[s.selected].videoStart = from
            s.candidates[s.selected].videoEnd = end.map { min(length, max(from + min(0.5, length - from), $0)) }
        }
        if section < 0 { apply(&p.intro) } else if p.sections.indices.contains(section) { apply(&p.sections[section]) }
        plan = p; persist(); live.invalidate()
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

    // MARK: camera move chosen by hand (start point → end point)
    func updateCandidate(section: Int, _ f: (inout ImageCandidate) -> Void) {
        guard var p = plan else { return }
        if section < 0 {
            if p.intro.candidates.indices.contains(p.intro.selected) { f(&p.intro.candidates[p.intro.selected]) }
        } else if p.sections.indices.contains(section), p.sections[section].candidates.indices.contains(p.sections[section].selected) {
            f(&p.sections[section].candidates[p.sections[section].selected])
        }
        plan = p; persist(); live.invalidate()
    }
    func chooseCameraMove(section: Int) {
        updateCandidate(section: section) { c in
            if c.cameraPath == nil { c.camStartX = 0.30; c.camStartY = 0.5; c.camEndX = 0.70; c.camEndY = 0.5; c.camZoom = 0 }
        }
    }
    func useAutomaticCamera(section: Int) { updateCandidate(section: section) { $0.camStartX = nil; $0.camStartY = nil; $0.camEndX = nil; $0.camEndY = nil } }
    func moveCameraPoint(section: Int, end: Bool, x: Double, y: Double) {
        let nx = min(0.97, max(0.03, x)), ny = min(0.97, max(0.03, y))
        updateCandidate(section: section) { c in if end { c.camEndX = nx; c.camEndY = ny } else { c.camStartX = nx; c.camStartY = ny } }
    }
    func setCameraZoom(section: Int, zoom: Int) { updateCandidate(section: section) { $0.camZoom = zoom } }
    func swapCameraPoints(section: Int) {
        updateCandidate(section: section) { c in
            swap(&c.camStartX, &c.camEndX); swap(&c.camStartY, &c.camEndY)
        }
    }

    func resetFocus(section: Int) {
        guard let p = plan, let w = workDir else { return }
        guard section == -1 || p.sections.indices.contains(section) else { return }
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
    @Published var clipJob: ClipJob?                // the video clip being made right now (or waiting for your decision)
    @Published var videoPricePerSecond = OpenRouterVideo.fallbackPricePerSecond
    var clipTask: Task<Void, Never>?
    var clipDecision: CheckedContinuation<ClipDecision, Never>?
    @Published var showReport = false        // the "Report a problem" window
    var reportPrefill = ""
    let reportCenter = ReportCenter()
    @Published var showHelp = false          // the Help window (ask a question / read the guide)
    var helpScreen = "Song screen (first screen)"
    /// Which screen is showing (told to the Help assistant).
    var screenName: String {
        if needsNativeSetup { return "First-time setup (downloading models)" }
        switch stage {
        case .setup: return hasProject ? "Song screen (opened from an existing video)" : "Song screen (first screen)"
        case .working: return "Planning the video (progress screen)"
        case .rendering: return "Making the video (progress screen)"
        case .plan: return "Pictures screen"
        case .done: return "Video screen (finished video)"
        case .loop: return "Looping long music video"
        }
    }

    func nudgeLine(_ lineIndex: Int, delta: Double) {
        guard var p = plan, let w = workDir else { return }
        Pipeline.shiftLine(plan: &p, lineIndex: lineIndex, delta: delta, work: w)
        plan = p; live.invalidate()
    }

    func reuse(section: Int, from source: Int) {
        guard let p = plan, let w = workDir, p.sections.indices.contains(source), let f = p.sections[source].selectedCandidate?.fullFile else { return }
        load(w.appendingPathComponent(f), section: section)
    }

    func rewritePrompt(section: Int) {
        guard var p = plan else { return }
        let before = p
        runBackground(initialPhase: "Writing another picture idea…") { [weak self] in
            guard let self else { return }
            self.workingSection = section; defer { self.workingSection = nil }
            try await Pipeline.rewritePrompt(plan: &p, section: section, config: self.config, progress: self.busyHandler)
            self.mergeTaskResult(p, startedFrom: before, section: section, idea: true)
        }
    }

    /// Long tasks work on a copy of the plan. This puts back only what the task changed (one picture's artwork, idea or clips, and the costs),
    /// so anything you edited meanwhile is kept.
    func mergeTaskResult(_ done: Plan, startedFrom before: Plan, section: Int, artwork: Bool = false, idea: Bool = false, clips: Bool = false) {
        guard var cur = plan else { return }
        let d: PhotoSection? = section < 0 ? done.intro : (done.sections.indices.contains(section) ? done.sections[section] : nil)
        func apply(_ s: inout PhotoSection) {
            guard let d else { return }
            if artwork { s.candidates = d.candidates; s.selected = d.selected }
            if idea { s.prompt = d.prompt; s.promptManual = d.promptManual; s.logicNote = d.logicNote; s.focal = d.focal }
            if clips { s.clips = d.clips; s.useClips = d.useClips; s.repeatClips = d.repeatClips }
        }
        if section < 0 { apply(&cur.intro) } else if cur.sections.indices.contains(section), cur.sections.count == done.sections.count { apply(&cur.sections[section]) }
        cur.totalGenerationCostUSD += done.totalGenerationCostUSD - before.totalGenerationCostUSD
        cur.imagesGeneratedCount += done.imagesGeneratedCount - before.imagesGeneratedCount
        cur.totalVideoCostUSD += done.totalVideoCostUSD - before.totalVideoCostUSD
        if done.lastImageCostUSD != before.lastImageCostUSD { cur.lastImageCostUSD = done.lastImageCostUSD }
        plan = cur; persist(); live.invalidate()
    }

    var canAddInstrumentalIntro: Bool { plan.map(Pipeline.needsInstrumentalIntro) ?? false }
    /// Older projects: gives the music before the first words its own picture slot and prompt.
    func addInstrumentalIntro() {
        guard var p = plan else { return }
        runBackground(initialPhase: "Adding a picture for the music before the words…") { [weak self] in
            guard let self else { return }
            try await Pipeline.addInstrumentalIntro(plan: &p, config: self.config, progress: self.busyHandler)
            self.plan = p; self.selectedSection = 0; self.persist(); self.live.invalidate()
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

    /// The video (and its Shorts) being made right now. It runs in the strip at the top; the rest of the app stays usable.
    struct VideoJob { var phase = "Preparing frames"; var progress = 0.0; var started = Date() }
    func render() {
        guard videoJob == nil, var p = plan, let w = workDir else { return }
        let q = quality
        let alsoShorts = autoRenderShorts
        if alsoShorts && p.shorts.isEmpty { p.shorts = Pipeline.autoShorts(plan: p); plan = p; persist() }      // no Shorts yet: cut the song into Shorts automatically
        videoJob = VideoJob(); renderedShorts = []
        videoTask?.cancel()
        videoTask = Task {
            do {
                let out = Pipeline.videoURL(plan: p, work: w, config: config)
                let mainWeight = alsoShorts && !p.shorts.isEmpty ? 0.50 : 1.0
                try await VideoRenderer.render(plan: p, work: w, output: out, settings: VideoSettings(height: q)) { [weak self] ph, f in
                    Task { @MainActor in
                        self?.videoJob?.phase = alsoShorts ? "Main video · \(ph)" : ph
                        self?.videoJob?.progress = f * mainWeight
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
                            videoJob?.phase = "Short \(i + 1) of \(count) · Writing the opening title…"; videoJob?.progress = base + span * 0.08
                            if let h = await Pipeline.writeHook(plan: p, clip: c, config: config), !h.isEmpty {
                                c.hook = h; p.shorts[i].hook = h
                                if let k = plan?.shorts.firstIndex(where: { $0.id == c.id }), plan?.shorts[k].hook.isEmpty == true { plan?.shorts[k].hook = h; persist() }   // only the title is put back; your other edits stay
                            }
                        }
                        try Task.checkCancellation()
                        let sOut = try await Pipeline.renderShort(plan: p, work: w, clip: c, config: config) { [weak self] ph, f in
                            Task { @MainActor in
                                self?.videoJob?.phase = "Short \(i + 1) of \(count) (\(c.name)) · \(ph)"
                                self?.videoJob?.progress = base + span * (0.10 + 0.90 * f)
                            }
                        }
                        shortURLs.append(sOut)
                    }
                }
                renderedShorts = shortURLs
                videoJob?.phase = "Writing the YouTube thumbnail and description…"; videoJob?.progress = 0.99
                await makeYouTubeFiles(plan: p, video: out)
                outputURL = out; videoJob = nil
                doneNote = DoneNote(text: "Your video is ready" + (shortURLs.isEmpty ? "" : " (and \(shortURLs.count) Short\(shortURLs.count == 1 ? "" : "s"))"), watch: true)
            } catch is CancellationError {
                videoJob = nil
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
                videoJob = nil
            }
            videoTask = nil
        }
    }
    /// The thumbnail (the title card picture with the song title) and the search-friendly description, next to the video.
    func makeYouTubeFiles(plan p: Plan, video: URL) async {
        guard let w = workDir, let pic = (p.intro.selectedCandidate?.fullFile ?? p.sections.lazy.compactMap { $0.selectedCandidate?.fullFile }.first).map({ w.appendingPathComponent($0) }) else { return }
        youtubeBusy = true; defer { youtubeBusy = false }
        let cfg = config
        let listing = await YouTubeKit.lyricListing(p, config: cfg)
        let sub = p.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = try? YouTubeKit.writeFiles(beside: video, picture: pic, thumbTitle: p.title, badge: "Lyric video", line: sub.isEmpty ? nil : sub, listing: listing) { youtubeFiles = f }
    }
    /// Where a Short's video is saved.
    func shortVideoURL(_ c: ShortClip) -> URL? { guard let p = plan, let w = workDir else { return nil }; return Pipeline.shortURL(plan: p, work: w, name: c.name, config: config) }
    /// Makes a Short's cover and YouTube description again (the Short must have been made).
    func remakeShortYouTube(_ c: ShortClip) {
        guard let p = plan, let w = workDir, let v = shortVideoURL(c) else { return }
        youtubeBusy = true
        Task { await YouTubeKit.writeShortFiles(p, work: w, clip: c, video: v, config: config); youtubeBusy = false; objectWillChange.send() }
    }
    /// The music video's thumbnail and description, made before the video (they go where the video will be saved).
    func makeYouTubeFilesNow() {
        guard let p = plan, let w = workDir else { return }
        let video = Pipeline.videoURL(plan: p, work: w, config: config)
        Task {
            await makeYouTubeFiles(plan: p, video: video)
            if let f = youtubeFiles { notice = "The YouTube thumbnail and description are saved next to where the video goes:\n\(f.thumbnail.lastPathComponent)\n\(f.description.lastPathComponent)"; NSWorkspace.shared.activateFileViewerSelecting([f.thumbnail, f.description]) }
        }
    }
    func remakeYouTubeFiles() {
        guard let p = plan, let v = outputURL else { return }
        Task { await makeYouTubeFiles(plan: p, video: v) }
    }

    func cancelVideo() { videoTask?.cancel(); videoTask = nil; videoJob = nil }

    /// "Make my video" with pictures still missing: draw them first, then make the video (stops, without a video, if a drawing fails).
    func drawMissingThenRender() {
        guard let p0 = plan, let w = workDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let targets = Pipeline.missing(p0)
        guard !targets.isEmpty else { render(); return }
        generateSectionsList(targets, work: w, titlePrefix: "Drawing \(targets.count) missing picture\(targets.count == 1 ? "" : "s"), then making the video") { [weak self] in self?.render() }
    }

    func reset() { clearTimelineSession(); stopPlayback(); cancelBackgroundTask(); stage = .setup; plan = nil; outputURL = nil; renderedShorts = []; progress = 0; waveform = []; projectBaseline = nil }

    // MARK: Projects
    func remember(_ folder: URL) {
        recents.removeAll { $0 == folder }; recents.insert(folder, at: 0); recents = Array(recents.prefix(8))
        UserDefaults.standard.set(recents.map(\.path), forKey: "recentProjects")
    }

    func openProject(_ folder: URL) {
        if LoopVideo.isLoopProject(folder) { openLoop(folder); return }
        clearTimelineSession()
        do {
            var p = try Pipeline.loadPlan(folder)
            // Heal pictures whose files were moved/deleted.
            for i in p.sections.indices { if let c = p.sections[i].selectedCandidate, let f = c.fullFile, !FileManager.default.fileExists(atPath: folder.appendingPathComponent(f).path) { p.sections[i].candidates = []; p.sections[i].selected = -1 } }

            plan = p; workDir = folder; title = p.title; subject = p.subject; songNotes = p.songNotes; settingTheme = p.setting; lyrics = AppModel.lyricsText(of: p)
            projectBaseline = nil; outputURL = nil; renderedShorts = []
            stage = .plan; remember(folder); loadWaveform(); refreshOpenRouterCredits(silent: true); recoverClips()
        } catch { errorMessage = "Couldn't open that project: \(error.localizedDescription)" }
    }

    func chooseProject() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = "Choose a project folder (it contains project.mvproj)"; p.directoryURL = outputRoot
        if p.runModal() == .OK, let u = p.url {
            if Pipeline.isProject(u) || LoopVideo.isLoopProject(u) { openProject(u) }
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
    var audioFileURL: URL? { plan.flatMap { p in workDir.map { Pipeline.audioURL(p, work: $0) } } ?? audioURL }

    func loadWaveform() {
        guard let u = audioFileURL else { return }
        let w = workDir
        let len = plan?.songDuration ?? 3600
        Task {
            let result = (try? await Transcriber.waveform(audioPath: u.path, work: w)) ?? []
            if audioFileURL == u { waveform = result }
        }
        Task {
            let result = await BeatDetector.beats(audioPath: u.path, start: 0, end: len, work: w)
            if audioFileURL == u { beats = result }
        }
    }

    var currentShort: ShortClip? { plan?.shorts.first { $0.id == selectedShort } }

    static let defaultShortLength = 30.0

    /// Automatically generates 4–7 ~30-second Shorts breaking at natural stanza and vocal pause boundaries.
    func autoMakeShorts(replaceExisting: Bool = false) {
        guard var p = plan else { return }
        checkpoint("Suggest Shorts")
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
                shortOutput = Pipeline.shortURL(plan: p, work: w, name: p.shorts.last?.name ?? "", config: config)
                notice = "Made all \(count) Shorts. They are in the same folder as your video."
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
        checkpoint("Add Short")
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
        checkpoint("Add whole song Shorts")
        let parts = Pipeline.wholeSongClips(plan: p)
        for c in parts where !p.shorts.contains(where: { $0.name == c.name }) { p.shorts.append(c) }
        plan = p; selectedShort = p.shorts.first(where: { $0.name == parts[0].name })?.id; persist(); refreshPreview(at: 1)
        if parts.count > 1 { notice = "The song is \(clock(p.songDuration)) — over the 3:00 Short limit — so it was split into \(parts.count) parts, cut at natural gaps in the lyrics. Render each part separately." }
    }

    func deleteShort(_ id: UUID) {
        checkpoint("Delete Short")
        plan?.shorts.removeAll { $0.id == id }; if selectedShort == id { selectedShort = plan?.shorts.first?.id }; persist()
    }

    func update(_ id: UUID, _ change: (inout ShortClip) -> Void) {
        guard var p = plan, let i = p.shorts.firstIndex(where: { $0.id == id }) else { return }
        checkpoint("Edit Short", coalesce: true)
        let old = p.shorts[i]
        var c = old; change(&c)
        let requested = c
        c = TimelineEditor.adjustedShort(c, from: old, duration: p.songDuration)
        if c.start != requested.start || c.end != requested.end { capped = true; snapDescription = "This Short must stay within the song and the 3-minute limit. The opposite edge is kept fixed." }
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

    @Published var looping = false
    @Published var beats: [Double] = []
    enum SnapMode: String, CaseIterable { case smart = "Smart", beats = "Beats", words = "Words", off = "Off" }
    @Published var snapMode: SnapMode = .smart

    /// Moves a time to a nearby musical or spoken landmark, depending on the Snap choice. `near` is the reach in seconds.
    /// Smart: word edges while words are sung, beats in the music-only stretches. Beats / Words: only those. Off: exactly where you point.
    func snap(_ t: Double, near: Double, edgeStart: Bool? = nil) -> Double {
        guard near > 0 else { return t }
        if snapMode != .off, snapMode != .beats, let start = edgeStart,
           let w = plan?.lines.flatMap(\.words).first(where: { t > $0.start && t < $0.end }) {
            snapDescription = "Aligned to \(start ? "beginning" : "end") of “\(w.text)”."
            return start ? w.start : w.end
        }
        func nearest(_ xs: [Double], reach: Double) -> Double? { xs.min { abs($0 - t) < abs($1 - t) }.flatMap { abs($0 - t) <= reach ? $0 : nil } }
        var edges: [Double] = []; var inWords = false
        for l in plan?.lines ?? [] { for w in l.words { edges.append(w.start); edges.append(w.end); if t >= w.start - 0.25 && t <= w.end + 0.25 { inWords = true } } }
        switch snapMode {
        case .off: return t
        case .words: return nearest(edges, reach: near) ?? t
        case .beats: return nearest(beats, reach: near * 1.5) ?? t
        case .smart: return (inWords ? nearest(edges, reach: near) : nil) ?? nearest(beats, reach: near * 1.5) ?? nearest(edges, reach: near) ?? t
        }
    }
    func nextBeat(after t: Double) -> Double? { beats.first { $0 > t + 0.02 } }
    func previousBeat(before t: Double) -> Double? { beats.last { $0 < t - 0.02 } }
    /// Plays the selection again and again (half a second of lead-in each time); press again to stop.
    func toggleLoop(_ a: Double, _ b: Double) {
        if looping { stopPlayback(); return }
        playRange(a, b, loop: true)
    }
    /// Snaps a time to the closest word or line edge when one is within `within` seconds (a word edge is where a word starts or ends).
    func snapToWordEdge(_ t: Double, within: Double) -> Double {
        guard let p = plan else { return t }
        var best = t, bestD = within
        func consider(_ x: Double) { let d = abs(x - t); if d < bestD { bestD = d; best = x } }
        for l in p.lines { consider(l.start); consider(l.end); for w in l.words { consider(w.start); consider(w.end) } }
        return best
    }
    /// Chooses lyric lines `a…b` for a Short (never past the 3:00 limit).
    func selectLines(_ id: UUID, _ a: Int, _ b: Int) {
        guard let p = plan, p.lines.indices.contains(a), p.lines.indices.contains(b) else { return }
        var hi = max(a, b)
        while hi > a && p.lines[hi].end - p.lines[a].start > ShortClip.maxDuration - leadIn - tailOut { hi -= 1 }
        let n = Pipeline.clip(plan: p, lines: a, to: hi, lead: leadIn, tail: tailOut)
        update(id) { $0.start = n.start; $0.end = n.end }
    }
    /// Keeps the start and adds lines until the clip is about `seconds` long.
    func extendSelection(_ id: UUID, seconds: Double) {
        guard let p = plan, let c = p.shorts.first(where: { $0.id == id }), let r = Pipeline.lineRange(plan: p, clip: c) else { return }
        selectLines(id, r.lowerBound, Pipeline.lastLine(plan: p, from: r.lowerBound, within: seconds))
    }
    /// Selects one part of the song (all its lyric lines, or the whole stretch of a music-only part).
    func selectSection(_ id: UUID, index: Int) {
        guard let p = plan, p.sections.indices.contains(index) else { return }
        let s = p.sections[index]
        if let f = s.lineIDs.first, let l = s.lineIDs.last { selectLines(id, f, l) }
        else { update(id) { $0.start = s.start; $0.end = s.end } }
    }

    func playRange(_ a: Double, _ b: Double, loop: Bool = false) {
        guard let u = audioFileURL else { return }
        stopPlayback()
        guard let pl = try? AVAudioPlayer(contentsOf: u) else { return }
        let begin = max(0, loop ? a - 0.5 : a)
        looping = loop
        audioPlayer = pl; pl.currentTime = begin; pl.play(); playhead = begin
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.audioPlayer else { return }
                self.playhead = p.currentTime
                if p.currentTime >= b || !p.isPlaying { if loop { p.currentTime = begin; p.play() } else { self.stopPlayback() } }
            }
        }
    }

    func stopPlayback() { playTimer?.invalidate(); playTimer = nil; audioPlayer?.stop(); audioPlayer = nil; playhead = nil; looping = false }

    /// (Re)builds the live preview for the selected Short (debounced); `t` is the position to show afterwards.
    func refreshPreview(at t: Double) {
        guard !timelineDragging, let p = plan, let w = workDir, let audio = audioFileURL, let c = currentShort else { return }
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
        previewTask?.cancel()
        previewTask = Task { live.invalidate(); await live.load(plan: p, work: w, clip: nil, audio: audio); live.seek(min(live.time, 5)) }
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
            } catch is CancellationError {
                shortOutput = nil
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            shortProgress = nil; shortPhase = ""; shortRenderTask = nil
        }
    }
}
