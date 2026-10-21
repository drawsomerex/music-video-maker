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
    func startLoopProject(song: URL, title: String) {
        config = Config.load()
        Task {
            do {
                let (p, dir) = try await LoopVideo.create(song: song, title: title, config: config)
                loopProject = p; loopDir = dir; stage = .loop; remember(dir)
            } catch { errorMessage = "Couldn't start the looping video: \(error.localizedDescription)" }
        }
    }

    func openLoop(_ dir: URL) {
        do {
            let p = try LoopVideo.load(dir)
            loopProject = p; loopDir = dir; stage = .loop; remember(dir)
            if p.songSeconds <= 0, !p.songFile.isEmpty {              // older or hand-made projects: work out the song's length
                Task { let s = (try? await AVURLAsset(url: dir.appendingPathComponent(p.songFile)).load(.duration)).map(CMTimeGetSeconds) ?? 0; if s > 0 { editLoop { $0.songSeconds = s } } }
            }
            refreshOpenRouterCredits(silent: true)
            if p.pendingJob != nil { recoverLoopClip() }
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
        return try await LoopVideo.suggestScenes(title: p.title, style: p.style, avoid: avoid, config: config)
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
            if let c = q.clip { await MainActor.run { self?.loopJob?.phase = "Making the loop preview…" }; try await LoopVideo.makePreview(clip: d.appendingPathComponent(c), output: d.appendingPathComponent("preview-" + (c as NSString).deletingPathExtension + ".mp4")) }
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
    /// Makes (or makes again) the in-app preview of a clip's loop.
    func loopMakePreview(_ clip: String) {
        guard let d = loopDir else { return }
        runLoop("Making the loop preview…") { p, _ in
            try await LoopVideo.makePreview(clip: d.appendingPathComponent(clip), output: d.appendingPathComponent("preview-" + (clip as NSString).deletingPathExtension + ".mp4")); return p
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
        let h = p.hours == p.hours.rounded() ? "\(Int(p.hours)) hour\(p.hours == 1 ? "" : "s")" : String(format: "%.1f hours", p.hours)
        return folder.appendingPathComponent("\(p.title.replacingOccurrences(of: "/", with: "-")) – \(h) (looping).mp4")
    }
    func loopRender() {
        guard let p = loopProject else { return }
        let out = loopOutputURL(p)
        runLoop("Making the \(p.hours == p.hours.rounded() ? "\(Int(p.hours))-hour" : String(format: "%.1f-hour", p.hours)) looping video…") { [weak self] p, d in
            try await LoopVideo.render(p, dir: d, output: out) { ph, f in Task { @MainActor in self?.loopJob?.phase = ph; self?.loopJob?.progress = f } }
            var q = p; q.output = out.path
            await MainActor.run { self?.doneNote = DoneNote(text: "Your looping video is ready (\(out.lastPathComponent))", reveal: out) }
            return q
        }
    }
}
