// Looping long music video: what the buttons on its screen do. Every long step runs in the strip at the top with a bar and Cancel.
import SwiftUI
import AVFoundation
import MVCore

struct LoopJob {
    var title: String
    var phase = ""
    var progress: Double? = nil
    var estimatedSeconds: Double? = nil        // HeyGen and the picture maker report no progress: the bar is an estimate
    var started = Date()
    func fraction(now: Date) -> Double? {
        if let p = progress { return p }
        guard let e = estimatedSeconds else { return nil }
        return 0.95 * (1 - exp(-1.8 * max(0, now.timeIntervalSince(started)) / e))
    }
}

@MainActor
extension AppModel {
    // MARK: projects
    /// A new looping project for a song (its own folder), then its screen.
    func startLoopProject(songs: [URL], title: String) {
        config = Config.load()
        Task {
            do {
                let (p, dir) = try await LoopVideo.create(songs: songs, title: title, config: config)
                loopProject = p; loopDir = dir; stage = .loop; remember(dir)
                loopListen()
            } catch { errorMessage = "Couldn't start the looping video: \(error.localizedDescription)" }
        }
    }

    // MARK: the music
    /// The exact plan of the music (once every song has been listened to).
    var loopPlan: LoopAudio.Plan? { loopProject.flatMap { LoopVideo.plan($0) } }

    /// Adds songs (from a file dialog when none are given), then listens to them.
    func loopAddSongs(_ given: [URL]? = nil) {
        var files = given ?? []
        if given == nil {
            let o = NSOpenPanel(); o.allowedContentTypes = [.audio]; o.allowsMultipleSelection = true; o.message = "Choose one or more songs"
            guard o.runModal() == .OK else { return }
            files = o.urls
        }
        guard !files.isEmpty, var p = loopProject, let d = loopDir else { return }
        Task {
            do { try await LoopVideo.addTracks(&p, dir: d, files: files) } catch { errorMessage = error.localizedDescription }
            if var cur = loopProject, cur.id == p.id { cur.tracks = p.tracks; cur.songFile = p.songFile; cur.songSeconds = p.songSeconds; loopProject = cur; LoopVideo.save(cur, d) }
            loopListen()
        }
    }
    func loopRemoveSong(_ id: String) { editLoop { p in if p.tracks.count > 1 { p.tracks.removeAll { $0.id == id } } } }

    /// Listens to every song not listened to yet, a song at a time, without holding up anything else on the screen.
    func loopListen() {
        guard let p = loopProject, let d = loopDir else { return }
        let todo = p.tracks.filter { (p.analysis[$0.file]?.version ?? 0) < TrackAnalysis.currentVersion }
        guard !todo.isEmpty else { return }
        loopListenTask?.cancel()
        loopListenTask = Task { [weak self] in
            for (k, t) in todo.enumerated() {
                if Task.isCancelled { break }
                self?.loopListening = "Listening to the songs (\(k + 1) of \(todo.count))…"
                let url = d.appendingPathComponent(t.file)
                guard let a = try? await Task.detached(priority: .utility, operation: { try LoopAudio.analyze(url) }).value else { continue }
                guard let self, self.loopDir == d else { break }
                self.editLoop { $0.analysis[t.file] = a }
            }
            self?.loopListening = nil
        }
    }

    func openLoop(_ dir: URL) {
        do {
            let p = try LoopVideo.load(dir)
            loopProject = p; loopDir = dir; stage = .loop; remember(dir)
            for t in p.tracks where t.seconds <= 0 {                      // older or hand-made projects: work out each song's length
                Task { let s = (try? await AVURLAsset(url: dir.appendingPathComponent(t.file)).load(.duration)).map(CMTimeGetSeconds) ?? 0
                       if s > 0 { editLoop { q in if let i = q.tracks.firstIndex(where: { $0.id == t.id }) { q.tracks[i].seconds = s } } } }
            }
            refreshOpenRouterCredits(silent: true)
            if p.pendingJob != nil { recoverLoopClip() }
            loopListen()
            var q = p                                                   // clips made before the mirror/cut check existed are checked once now
            if LoopVideo.checkIfNeeded(&q, dir: dir) { loopProject = q; if q.clipWarning != nil, let c = q.clip { loopMakePreview(c) } }
        } catch { errorMessage = "Couldn't open that looping video: \(error.localizedDescription)" }
    }

    func closeLoop() { cancelLoopJob(); loopProject = nil; loopDir = nil; stage = .setup }

    /// Changes the open loop project (and saves it).
    func editLoop(_ f: (inout LoopProject) -> Void) {
        guard var p = loopProject, let d = loopDir else { return }
        f(&p); loopProject = p; LoopVideo.save(p, d)
    }

    func loopFile(_ name: String?) -> URL? { name.flatMap { n in loopDir?.appendingPathComponent(n) } }
    func loopPreviewURL(for clip: String) -> URL? { loopDir?.appendingPathComponent("preview-" + (clip as NSString).deletingPathExtension + ".mp4") }

    /// Runs one long step of the loop workflow in the top strip. `work` gets a copy of the project and returns it changed; only what it changed
    /// (pictures, clips, costs, pending job) is put back, so edits made meanwhile (title, scene, hours) are kept.
    private func runLoop(_ title: String, estimate: Double? = nil, _ work: @escaping (LoopProject, URL) async throws -> LoopProject) {
        guard loopJob == nil, let p0 = loopProject, let d = loopDir else { return }
        loopJob = LoopJob(title: title, estimatedSeconds: estimate)
        let spentBefore = p0.imagesUSD + p0.videoUSD
        loopTask = Task {
            do {
                let done = try await work(p0, d)
                if var cur = loopProject, cur.id == done.id {
                    cur.pictures = done.pictures; cur.picture = done.picture; cur.clips = done.clips; cur.clip = done.clip
                    if done.motion != p0.motion { cur.motion = done.motion }       // a new description from the picture (your own edits made meanwhile are otherwise kept)
                    cur.thumbnail = done.thumbnail; cur.listing = done.listing; cur.clipWarning = done.clipWarning; cur.loopScores = done.loopScores
                    for (k, v) in done.trims where cur.trims[k] == nil || p0.trims[k] != v { cur.trims[k] = v }      // a new clip's check; your own trims made meanwhile stay
                    cur.imagesUSD = done.imagesUSD; cur.videoUSD = done.videoUSD; cur.pictureCount = done.pictureCount; cur.pendingJob = done.pendingJob; cur.output = done.output
                    loopProject = cur; LoopVideo.save(cur, d)
                }
                let spent = done.imagesUSD + done.videoUSD - spentBefore
                if done.output == p0.output { doneNote = DoneNote(text: "Done — " + title.replacingOccurrences(of: "…", with: "") + (spent > 0.0001 ? " · cost \(OpenRouter.formatUSD(spent))" : "")) }   // a finished long video has its own note
                refreshOpenRouterCredits(silent: true)
            } catch is CancellationError {
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
            loopJob = nil; loopTask = nil
        }
    }
    func cancelLoopJob() { loopTask?.cancel(); loopTask = nil; loopJob = nil }

    // MARK: the picture
    func loopSuggestScenes(avoid: [String]) async throws -> [String] {
        guard let p = loopProject else { return [] }
        return try await LoopVideo.suggestScenes(title: p.title, style: p.style, about: p.about, avoid: avoid, config: config)
    }

    func loopMakePicture() {
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        config = Config.load()
        let cfg = config
        runLoop("Drawing the picture…", estimate: 50) { [weak self] p, d in
            var q = p; try await LoopVideo.makePicture(&q, dir: d, config: cfg)
            await MainActor.run { self?.loopJob?.phase = "Looking at what should move…" }
            await LoopVideo.refreshMotion(&q, dir: d, config: cfg); return q
        }
    }
    func loopUsePicture(_ url: URL) {
        guard var p = loopProject, let d = loopDir else { return }
        do { try LoopVideo.addPicture(&p, dir: d, file: url, config: config); loopProject = p } catch { errorMessage = error.localizedDescription; return }
        loopDescribeMotion()
    }
    /// Writes "what moves" from the picture in use (a fraction of a cent).
    func loopDescribeMotion() {
        guard hasOpenRouterKey, loopProject?.picture != nil else { return }
        let cfg = Config.load()
        runLoop("Looking at what should move…", estimate: 8) { p, d in var q = p; await LoopVideo.refreshMotion(&q, dir: d, config: cfg); return q }
    }
    func loopChoosePicture() {
        let o = NSOpenPanel(); o.allowedContentTypes = [.image]; o.message = "Choose the picture the loop clip starts from"
        if o.runModal() == .OK, let u = o.url { loopUsePicture(u) }
    }

    // MARK: the clip
    var loopClipPrice: Double { LoopVideo.clipPrice(sharp: loopProject?.sharpClip ?? false, perSecond768: videoPricePerSecond) }

    func loopMakeClip() {
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        config = Config.load()
        let cfg = config, price = loopClipPrice
        runLoop("Making the 15-second loop clip…", estimate: 240) { [weak self] p, d in
            if let rem = try? await OpenRouter.fetchCredits(apiKey: cfg.openRouterKey).remaining, rem < price {
                throw MVError("The clip costs about \(OpenRouter.formatUSD(price)) but your OpenRouter credit is \(OpenRouter.formatCredits(rem)). Add credit and try again.")
            }
            var q = p
            try await LoopVideo.makeClip(&q, dir: d, config: cfg) { ph in Task { @MainActor in self?.loopJob?.phase = ph } }
            if let c = q.clip { await MainActor.run { self?.loopJob?.phase = "Checking the clip and making the loop preview…" }; try await LoopVideo.makePreview(clip: d.appendingPathComponent(c), output: d.appendingPathComponent("preview-" + (c as NSString).deletingPathExtension + ".mp4"), trim: q.trim) }
            return q
        }
    }
    func loopUseClip(_ url: URL) {
        guard var p = loopProject, let d = loopDir else { return }
        do {
            try LoopVideo.addClip(&p, dir: d, file: url, config: config); loopProject = p
            if let c = p.clip { loopMakePreview(c) }
        } catch { errorMessage = error.localizedDescription }
    }
    func loopChooseClip() {
        let o = NSOpenPanel(); o.allowedContentTypes = [.movie]; o.message = "Choose a video clip to loop"
        if o.runModal() == .OK, let u = o.url { loopUseClip(u) }
    }
    /// Makes (or makes again) the in-app preview of a clip's loop (with the part chosen to loop).
    func loopMakePreview(_ clip: String) {
        guard let d = loopDir else { return }
        runLoop("Making the loop preview…") { p, _ in
            try await LoopVideo.makePreview(clip: d.appendingPathComponent(clip), output: d.appendingPathComponent("preview-" + (clip as NSString).deletingPathExtension + ".mp4"), trim: p.trims[clip] ?? ClipTrim()); return p
        }
    }
    /// The part of the clip in use that loops. The preview is made again a moment after you stop moving the markers.
    /// Searches the clip again for its best loop (the markers are moved there).
    func loopFindBestLoop() {
        guard let c = loopProject?.clip else { return }
        runLoop("Finding the best loop…") { p, d in var q = p; LoopVideo.applyBestLoop(&q, clip: c, dir: d); LoopVideo.save(q, d)
            try await LoopVideo.makePreview(clip: d.appendingPathComponent(c), output: d.appendingPathComponent("preview-" + (c as NSString).deletingPathExtension + ".mp4"), trim: q.trim); return q }
    }
    func loopSetTrim(start: Double, end: Double?) {
        guard let c = loopProject?.clip else { return }
        editLoop { $0.trims[c] = ClipTrim(start: start, end: end, blend: $0.trims[c]?.blend) }
        loopPreviewTask?.cancel()
        loopPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self else { return }
            while self.loopJob != nil { try? await Task.sleep(nanoseconds: 300_000_000); if Task.isCancelled { return } }
            self.loopMakePreview(c)
        }
    }
    func recoverLoopClip() {
        guard var p = loopProject, let d = loopDir else { return }
        let cfg = Config.load()
        Task {
            if let note = await LoopVideo.recoverClip(&p, dir: d, config: cfg) {
                if loopDir == d { loopProject = p }
                notice = note
                if let c = p.clip, let u = loopPreviewURL(for: c), !FileManager.default.fileExists(atPath: u.path) { loopMakePreview(c) }
            }
        }
    }

    // MARK: the long video
    func loopOutputURL(_ p: LoopProject) -> URL {
        let folder = config.outputFolder.isEmpty ? (loopDir ?? config.projectsRoot) : URL(fileURLWithPath: (config.outputFolder as NSString).expandingTildeInPath)
        if p.playOnce { return folder.appendingPathComponent("\(p.title.replacingOccurrences(of: "/", with: "-")).mp4") }     // each song once: just the name
        let h = p.hours == p.hours.rounded() ? "\(Int(p.hours)) hour\(p.hours == 1 ? "" : "s")" : String(format: "%.1f hours", p.hours)
        return folder.appendingPathComponent("\(p.title.replacingOccurrences(of: "/", with: "-")) – \(h).mp4")      // YouTube suggests the file name as the title: nothing about looping
    }
    /// Makes (or makes again) the YouTube thumbnail and description, before or after the long video.
    func loopMakeYouTube() {
        guard let p = loopProject else { return }
        let out = loopOutputURL(p), cfg = Config.load()
        runLoop("Writing the YouTube thumbnail and description…", estimate: 25) { p, d in var q = p; try await LoopVideo.makeYouTubeFiles(&q, dir: d, video: out, config: cfg); return q }
    }
    /// Changes what the looping video's thumbnail says and draws it again a moment later.
    func setLoopThumbText(_ t: ThumbnailText) {
        editLoop { $0.thumbText = t }
        thumbRedrawTask?.cancel()
        thumbRedrawTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self, let p = self.loopProject, let d = self.loopDir else { return }
            try? LoopVideo.redrawThumbnail(p, dir: d)
            self.thumbRevision += 1
        }
    }
    /// A short preview of the long video, with sound: the start, a song change, or the end. Plays as soon as it is made.
    enum PreviewPart { case start, change, end }
    func loopPreview(_ part: PreviewPart) {
        guard let p = loopProject, let d = loopDir else { return }
        let out = d.appendingPathComponent("sample-\(Int(Date().timeIntervalSince1970)).mp4")
        for f in (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? [] where f.hasPrefix("sample-") { try? FileManager.default.removeItem(at: d.appendingPathComponent(f)) }
        runLoop("Making a preview…") { [weak self] p, d in
            var q = p; try LoopVideo.ensureAnalysis(&q, dir: d)
            guard let s = LoopVideo.previewStarts(q) else { throw MVError("Add a song and the loop clip first.") }
            let from: Double, seconds: Double
            switch part { case .start: from = s.start; seconds = 45; case .change: from = s.change ?? s.start; seconds = 40; case .end: from = s.end; seconds = 40 }
            try await LoopVideo.renderPreview(q, dir: d, output: out, from: from, seconds: seconds) { f in Task { @MainActor in self?.loopJob?.progress = f } }
            await MainActor.run { self?.loopSample = out }
            return q
        }
        _ = p
    }
    func loopRender() {
        guard let p = loopProject else { return }
        let out = loopOutputURL(p)
        runLoop(p.playOnce ? "Making the video (each song once)…" : "Making the \(p.hours == p.hours.rounded() ? "\(Int(p.hours))-hour" : String(format: "%.1f-hour", p.hours)) looping video…") { [weak self] p, d in
            try await LoopVideo.render(p, dir: d, output: out) { ph, f in Task { @MainActor in self?.loopJob?.phase = ph; self?.loopJob?.progress = f } }
            var q = p; q.output = out.path
            await MainActor.run { self?.loopJob?.phase = "Writing the YouTube thumbnail and description…"; self?.loopJob?.progress = 0.99 }
            try? await LoopVideo.makeYouTubeFiles(&q, dir: d, video: out, config: Config.load())
            await MainActor.run { self?.doneNote = DoneNote(text: "Your looping video is ready (\(out.lastPathComponent)), with its YouTube thumbnail and description", reveal: out) }
            return q
        }
    }
}
