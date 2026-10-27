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
    func startLoopProject(songs: [URL], title: String, automatic: Bool = false) {
        guard mayLeaveProject() else { return }
        config = Config.load()
        Task {
            do {
                let (p, dir) = try await LoopVideo.create(songs: songs, title: title, config: config)
                editUndo = []; editRedo = []; loopProject = p; loopDir = dir; stage = .loop; remember(dir)
                loopListen()
                if automatic { loopAutoAsk() }
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
        guard mayLeaveProject() else { return }
        editUndo = []; editRedo = []
        do {
            let p = try LoopVideo.load(dir)
            loopProject = p; loopDir = dir; stage = .loop; remember(dir)
            for t in p.tracks where t.seconds <= 0 {                      // older or hand-made projects: work out each song's length
                Task { let s = (try? await AVURLAsset(url: dir.appendingPathComponent(t.file)).load(.duration)).map(CMTimeGetSeconds) ?? 0
                       if s > 0 { editLoop { q in if let i = q.tracks.firstIndex(where: { $0.id == t.id }) { q.tracks[i].seconds = s } } } }
            }
            refreshOpenRouterCredits(silent: true)
            if p.pendingJob != nil || !LoopVideo.pendingLoopJobs(dir).isEmpty { recoverLoopClip() }
            loopListen()
            // clips made before the checks, or rated before the slow dissolve and the colour lock, are checked once now (in the background)
            let check = Task.detached(priority: .userInitiated) { () -> LoopProject? in var q = p; return LoopVideo.checkIfNeeded(&q, dir: dir) ? q : nil }
            Task { [weak self] in
                guard let q = await check.value, let self, self.loopDir == dir, let c = q.clip else { return }
                self.editLoop { cur in
                    guard cur.clip == c else { return }
                    if cur.trims[c] == p.trims[c] { cur.trims[c] = q.trims[c] }           // unless you moved the markers meanwhile
                    cur.loopScores[c] = q.loopScores[c]; cur.loopDrift[c] = q.loopDrift[c]; cur.clipWarning = q.clipWarning
                }
                self.loopMakePreview(c)                                    // the preview as the loop now looks (full size)
            }
        } catch { errorMessage = "Couldn't open that looping video: \(error.localizedDescription)" }
    }

    func closeLoop() { guard mayLeaveProject() else { return }; cancelLoopJob(); loopProject = nil; loopDir = nil; stage = .setup }

    /// Changes the open loop project (and saves it).
    func editLoop(_ f: (inout LoopProject) -> Void) {
        guard var p = loopProject, loopDir != nil else { return }
        checkpoint("Edit looping video", coalesce: true)
        f(&p); loopProject = p; planRevision += 1; checkpointRevision = nil; persistLoop()
    }
    func persistLoop() {
        guard let p = loopProject, let d = loopDir else { return }
        do { try LoopVideo.saveChecked(p, d); saveStatus = "Saved" }
        catch { saveStatus = "Not saved — try again"; errorMessage = "Your looping-video changes could not be saved. Keep this project open and try again. " + error.localizedDescription }
    }

    func loopFile(_ name: String?) -> URL? { name.flatMap { n in loopDir?.appendingPathComponent(n) } }
    func loopPreviewURL(for clip: String) -> URL? { loopDir?.appendingPathComponent("preview-" + (clip as NSString).deletingPathExtension + ".mp4") }

    /// Runs one long step of the loop workflow in the top strip. `work` gets a copy of the project and returns it changed; only what it changed
    /// (pictures, clips, costs, pending job) is put back, so edits made meanwhile (title, scene, hours) are kept.
    func runLoop(_ title: String, estimate: Double? = nil, _ work: @escaping (LoopProject, URL) async throws -> LoopProject) {
        guard loopJob == nil, let p0 = loopProject, let d = loopDir else { return }
        checkpoint(title)
        let owner = UUID(); loopJobID = owner
        loopJob = LoopJob(title: title, estimatedSeconds: estimate)
        let spentBefore = p0.imagesUSD + p0.videoUSD
        loopTask = Task {
            do {
                let done = try await work(p0, d)
                guard loopDir == d, loopProject?.id == p0.id else { return }
                if loopJobID != owner || Task.isCancelled {
                    // A completed paid original still belongs to this project after local Stop. Retain it without changing the visible scene.
                    if var cur = loopProject {
                        for file in done.pictures where !p0.pictures.contains(file) && !cur.pictures.contains(file) { cur.pictures.append(file) }
                        for file in done.clips where !p0.clips.contains(file) && !cur.clips.contains(file) { cur.clips.append(file) }
                        cur.imagesUSD += max(0, done.imagesUSD - p0.imagesUSD); cur.videoUSD += max(0, done.videoUSD - p0.videoUSD)
                        cur.pictureCount += max(0, done.pictureCount - p0.pictureCount)
                        cur.versionCosts.merge(done.versionCosts) { _, new in new }; cur.versionQualities.merge(done.versionQualities) { _, new in new }
                    cur.motionByPicture.merge(done.motionByPicture) { old, _ in old }
                        loopProject = cur; persistLoop()
                    }
                    return
                }
                if var cur = loopProject, cur.id == done.id {
                    for file in done.pictures where !cur.pictures.contains(file) { cur.pictures.append(file) }
                    for file in done.clips where !cur.clips.contains(file) { cur.clips.append(file) }
                    if cur.picture == p0.picture { cur.picture = done.picture }
                    if cur.clip == p0.clip { cur.clip = done.clip }
                    if done.scene != p0.scene && cur.scene == p0.scene { cur.scene = done.scene }   // the next scene's description, unless you typed meanwhile
                    cur.sceneDrawn = done.sceneDrawn
                    cur.sceneChanges = done.sceneChanges; cur.subjectClose = done.subjectClose
                    if done.sceneClips != p0.sceneClips { cur.sceneClips = done.sceneClips; cur.sceneChange = done.sceneChange }
                    cur.versionCosts.merge(done.versionCosts) { _, new in new }; cur.versionQualities.merge(done.versionQualities) { _, new in new }
                    cur.motionByPicture.merge(done.motionByPicture) { _, new in new }
                    cur.motion = done.motion != p0.motion ? done.motion : cur.motion
                    if done.style != p0.style && cur.style == p0.style { cur.style = done.style }
                    if cur.nextFocus == p0.nextFocus { cur.nextFocus = done.nextFocus }
                    if cur.source == p0.source { cur.source = done.source }
                    if cur.brightness == p0.brightness { cur.brightness = done.brightness }
                    if cur.shot == p0.shot { cur.shot = done.shot }
                    cur.checks = done.checks; cur.enhanced = done.enhanced; cur.enlarged = done.enlarged; cur.castSheet = done.castSheet
                    if cur.cast == p0.cast { cur.cast = done.cast }
                    if cur.pictureQuality == p0.pictureQuality { cur.pictureQuality = done.pictureQuality }
                    if cur.weather == p0.weather { cur.weather = done.weather }
                    if cur.timeOfDay == p0.timeOfDay { cur.timeOfDay = done.timeOfDay }
                    for k in cur.tracks.indices where cur.tracks[k].lyrics == nil { if let t = done.tracks.first(where: { $0.id == cur.tracks[k].id }) { cur.tracks[k].lyrics = t.lyrics } }
                    if done.motion != p0.motion { cur.motion = done.motion }       // a new description from the picture (your own edits made meanwhile are otherwise kept)
                    cur.thumbnail = done.thumbnail; cur.listing = done.listing; cur.clipWarning = done.clipWarning; cur.loopScores = done.loopScores; cur.loopDrift = done.loopDrift
                    for (k, v) in done.trims where cur.trims[k] == nil || p0.trims[k] != v { cur.trims[k] = v }      // a new clip's check; your own trims made meanwhile stay
                    cur.imagesUSD += max(0, done.imagesUSD - p0.imagesUSD); cur.videoUSD += max(0, done.videoUSD - p0.videoUSD); cur.pictureCount += max(0, done.pictureCount - p0.pictureCount); cur.pendingJob = done.pendingJob; cur.pendingOptions = done.pendingOptions; cur.output = done.output
                    loopProject = cur; planRevision += 1; checkpointRevision = nil
                    try LoopVideo.saveChecked(cur, d); try LoopVideo.acknowledgeLoopJobs(cur, dir: d); saveStatus = "Saved"
                }
                let spent = done.imagesUSD + done.videoUSD - spentBefore
                if done.output == p0.output { doneNote = DoneNote(text: "Done — " + title.replacingOccurrences(of: "…", with: "") + (spent > 0.0001 ? " · cost \(OpenRouter.formatUSD(spent))" : "")) }   // a finished long video has its own note
                refreshOpenRouterCredits(silent: true)
            } catch is CancellationError {
            } catch { if !Task.isCancelled, loopJobID == owner { errorMessage = error.localizedDescription } }
            if loopJobID == owner {
                loopJob = nil; loopTask = nil
                if directorRun?.loop == true { directorRun = nil }
            }
        }
    }
    func cancelLoopJob() { loopJobID = UUID(); loopTask?.cancel(); loopTask = nil; loopJob = nil; if directorRun?.loop == true { directorRun = nil } }

    // MARK: the picture
    func loopSuggestScenes(avoid: [String]) async throws -> [String] {
        guard let p = loopProject else { return [] }
        // with a picture (or a subject photo): ideas from it, keeping what "Next picture keeps" says; without one: ideas from the title (on this Mac)
        if hasOpenRouterKey, let d = loopDir, let pic = p.source ?? p.picture ?? p.subject {
            return try await LoopVideo.suggestScenes(picture: d.appendingPathComponent(pic), focus: LoopVideo.nextFocus(p, dir: d), about: p.about, avoid: avoid, config: config)
        }
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
    /// "Fix it": the picture in use, redrawn with only the fault the check found changed.
    func loopFixPicture() {
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        guard let pic = loopProject?.picture else { return }
        config = Config.load()
        let cfg = config
        runLoop("Fixing the picture…", estimate: 50) { [weak self] p, d in
            var q = p; try await LoopVideo.fixPicture(&q, dir: d, picture: pic, config: cfg)
            await MainActor.run { self?.loopJob?.phase = "Looking at what should move…" }
            await LoopVideo.refreshMotion(&q, dir: d, config: cfg); return q
        }
    }
    /// "Make highest quality": the picture in use, redrawn from itself at the very highest level, then sharpened. The old one stays in the list.
    func loopHighestQuality() {
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        guard let pic = loopProject?.picture else { return }
        config = Config.load()
        let cfg = config
        runLoop("Making the picture highest quality…", estimate: 55) { p, d in
            var q = p; try await LoopVideo.highestQuality(&q, dir: d, picture: pic, config: cfg); return q
        }
    }
    /// The next scene: the same place, one major change, a slightly different angle (from the picture in use).
    func loopMakeNextPicture() {
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        config = Config.load()
        let cfg = config
        let what = loopProject.flatMap { p in loopDir.map { LoopVideo.nextFocus(p, dir: $0) } } ?? .place
        runLoop(what.action.replacingOccurrences(of: "Next scene: ", with: "Drawing the next scene (") + ")…", estimate: 60) { [weak self] p, d in
            var q = p; try await LoopVideo.makeNextPicture(&q, dir: d, config: cfg)
            await MainActor.run { self?.loopJob?.phase = "Looking at what should move…" }
            await LoopVideo.refreshMotion(&q, dir: d, config: cfg); return q
        }
    }
    /// A picture of your own as the source image for next scenes (shaped to widescreen first if needed).
    /// One click for another scene: the next picture (based on the picture the video is based on), what moves in it, its loop clip, and it joins
    /// the scenes the video changes between. The scene the video starts with stays the same.
    var loopAddScenePrice: Double { perImageCostUSD + loopClipPrice }
    func loopAddScene() {
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        config = Config.load()
        let cfg = config
        runLoop("Adding another scene: drawing its picture…", estimate: 300) { [weak self] p, d in
            var q = p
            let first = q.clip
            try await LoopVideo.makeNextPicture(&q, dir: d, config: cfg)
            await MainActor.run { self?.loopJob?.phase = "Adding another scene: looking at what should move…" }
            await LoopVideo.refreshMotion(&q, dir: d, config: cfg)
            await MainActor.run { self?.loopJob?.phase = "Adding another scene: HeyGen is making its clip (a few minutes)…" }
            try await LoopVideo.makeClip(&q, dir: d, config: cfg) { ph in Task { @MainActor in self?.loopJob?.phase = "Adding another scene: " + ph } }
            if let new = q.clip {
                var list = LoopVideo.sceneClips(p)
                if !list.contains(new) { list.append(new) }
                q.sceneClips = list
                if q.sceneChange == .never { q.sceneChange = .both }
                if let f = first { q.clip = f }                      // the video still starts with the first scene
                LoopVideo.save(q, d)
                try await LoopVideo.makePreview(clip: d.appendingPathComponent(new), output: d.appendingPathComponent("preview-" + (new as NSString).deletingPathExtension + ".mp4"), trim: q.trims[new] ?? ClipTrim())
            }
            return q
        }
    }
    func loopChooseSource() {
        let o = NSOpenPanel(); o.allowedContentTypes = [.image]; o.message = "Choose the picture to base the pictures on"
        if o.runModal() == .OK, let u = o.url { loopSetReference(u) }
    }
    /// A picture to base the looping video's pictures on (yours or found online), shaped to widescreen first if needed.
    func loopSetReference(_ u: URL) {
        fitThen(u, scene: loopProject?.scene ?? "", addCost: { [weak self] c in self?.editLoop { $0.imagesUSD += c } }) { [weak self] f in
            guard let self, var p = self.loopProject, let d = self.loopDir else { return }
            do { try LoopVideo.setSource(&p, dir: d, file: f); p.nextFocus = nil; LoopVideo.save(p, d); self.loopProject = p } catch { self.errorMessage = error.localizedDescription }
        }
    }
    func loopUsePicture(_ url: URL) {
        fitThen(url, scene: loopProject?.scene ?? "", addCost: { [weak self] c in self?.editLoop { $0.imagesUSD += c } }) { [weak self] u in self?.loopUsePictureNow(u) }
    }
    private func loopUsePictureNow(_ url: URL) {
        guard var p = loopProject, let d = loopDir else { return }
        do { try LoopVideo.addPicture(&p, dir: d, file: url, config: config); loopProject = p } catch { errorMessage = error.localizedDescription; return }
        loopDescribeMotion()
    }
    /// Writes "what moves" from the picture in use (a fraction of a cent).
    func loopDescribeMotion(force: Bool = false) {
        if force, let pic = loopProject?.picture { editLoop { $0.motionByPicture[pic] = nil } }
        guard hasOpenRouterKey, loopProject?.picture != nil else { return }
        let cfg = Config.load()
        runLoop("Looking at what should move…", estimate: 8) { p, d in var q = p; await LoopVideo.refreshMotion(&q, dir: d, config: cfg); return q }
    }
    func loopSelectPicture(_ file: String) {
        editLoop { project in
            if let old = project.picture, !project.motion.isEmpty { project.motionByPicture[old] = project.motion }
            project.picture = file; project.motion = project.motionByPicture[file] ?? ""
        }
    }
    func loopChoosePicture() {
        let o = NSOpenPanel(); o.allowedContentTypes = [.image]; o.message = "Choose the picture the loop clip starts from"
        if o.runModal() == .OK, let u = o.url { loopUsePicture(u) }
    }

    // MARK: the clip
    var loopClipPrice: Double { LoopVideo.clipPrice(sharp: loopProject?.sharpClip ?? false, perSecond768: videoPricePerSecond, seconds: loopProject?.clipLength) }

    func loopMakeClip() {
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        config = Config.load()
        let cfg = config, price = loopClipPrice
        runLoop("Making the loop clip…", estimate: 240) { [weak self] p, d in
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
        guard loopProject != nil else { return }
        let cfg = config
        runLoop("Checking the clip and making the loop preview…", estimate: 20) { p, d in
            let q = try await Task.detached(priority: .userInitiated) { var q = p; try LoopVideo.addClip(&q, dir: d, file: url, config: cfg); return q }.value
            if let c = q.clip { try await LoopVideo.makePreview(clip: d.appendingPathComponent(c), output: d.appendingPathComponent("preview-" + (c as NSString).deletingPathExtension + ".mp4"), trim: q.trim) }
            return q
        }
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
        runLoop("Finding the best loop…") { p, d in
            let q = await Task.detached(priority: .userInitiated) { var q = p; LoopVideo.applyBestLoop(&q, clip: c, dir: d); LoopVideo.save(q, d); return q }.value
            try await LoopVideo.makePreview(clip: d.appendingPathComponent(c), output: d.appendingPathComponent("preview-" + (c as NSString).deletingPathExtension + ".mp4"), trim: q.trim); return q }
    }
    func loopSetTrim(start: Double, end: Double?) {
        guard let c = loopProject?.clip else { return }
        editLoop { $0.trims[c] = ClipTrim(start: start, end: end, blend: $0.trims[c]?.blend, clean: $0.trims[c]?.clean) }
        loopPreviewTask?.cancel()
        loopPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self, let p = self.loopProject, let d = self.loopDir else { return }
            // the rating for the part you chose
            let rated = await Task.detached(priority: .userInitiated) { var q = p; LoopVideo.rateLoop(&q, clip: c, dir: d); return q }.value
            guard !Task.isCancelled else { return }
            self.editLoop { $0.loopScores[c] = rated.loopScores[c]; $0.loopDrift[c] = rated.loopDrift[c] }
            while self.loopJob != nil { try? await Task.sleep(nanoseconds: 300_000_000); if Task.isCancelled { return } }
            self.loopMakePreview(c)
        }
    }
    func recoverLoopClip() {
        guard !recoveringLoop, var p = loopProject, let d = loopDir else { return }
        let cfg = Config.load(); recoveringLoop = true
        Task {
            defer { recoveringLoop = false }
            if let note = await LoopVideo.recoverClip(&p, dir: d, config: cfg) {
                if loopDir == d, loopProject?.id == p.id { loopProject = (try? LoopVideo.load(d)) ?? p; if let saved = loopProject { try? LoopVideo.acknowledgeLoopJobs(saved, dir: d) } }
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
    /// Where a looping video's Shorts go: a folder beside the long video.
    func loopShortsFolder(_ p: LoopProject) -> URL { loopOutputURL(p).deletingLastPathComponent().appendingPathComponent("\(p.title.replacingOccurrences(of: "/", with: "-")) – Shorts") }
    func setLoopShortFraming(clip: String, x: Double, y: Double) {
        guard !clip.isEmpty, var p = loopProject else { return }
        if !timelineDragging { checkpoint("Frame looping Short", coalesce: true) }
        p.shortOptions.framing[clip] = ShortFraming(x: min(1, max(0, x)), y: min(1, max(0, y)))
        loopProject = p; planRevision += 1; checkpointRevision = nil
        if !timelineDragging { persistLoop() }
    }
    func loopPreviewShort() {
        guard let dir = loopDir else { return }
        let output = dir.appendingPathComponent("short-preview.mp4")
        runLoop("Making a Short preview…") { [weak self] project, work in
            try await LoopVideo.makeShortPreview(project, dir: work, output: output)
            await MainActor.run { if self?.loopDir == work && self?.loopProject?.id == project.id { self?.loopSample = output } }
            return project
        }
    }
    /// One YouTube Short per song (its liveliest 45 seconds, with its scene).
    func loopMakeShorts() {
        guard let p0 = loopProject else { return }
        let folder = loopShortsFolder(p0)
        runLoop("Making the Shorts…", estimate: Double(max(1, p0.tracks.count)) * 30) { [weak self] p, d in
            let made = try await LoopVideo.makeShorts(p, dir: d, folder: folder) { ph, f in Task { @MainActor in self?.loopJob?.phase = ph; self?.loopJob?.progress = f } }
            await MainActor.run { self?.notice = "Made \(made.count) Short\(made.count == 1 ? "" : "s") in “\(folder.lastPathComponent)”, each with a YouTube title, description and tags beside it."; NSWorkspace.shared.open(folder) }
            return p
        }
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
