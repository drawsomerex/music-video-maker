// Video clips for a section: make one clip, or the whole section as back-to-back clips, watching each one as it arrives.
import SwiftUI
import MVCore

enum ClipDecision { case next, redo, stop, use, discard }

struct ClipJob: Equatable {
    var section: Int
    var chain: Bool
    var secondsList: [Int]            // the clips still to make, in order (including the one in progress)
    var index = 0                     // the clip being made or waiting for a decision
    var phase = "Starting…"
    var waiting = false               // a clip has just arrived: watch it, then choose
    var autoContinue = false          // back-to-back: make the rest without asking
    var failed: String?
}

@MainActor
extension AppModel {
    /// Clip lengths for a section. One clip: the section length (5–15 s). Whole section: clips of up to 15 s that add up to the section.
    func clipSeconds(section: Int, chain: Bool) -> [Int] {
        guard let p = plan else { return [] }
        let dur = section < 0 ? p.introDuration : (p.sections.indices.contains(section) ? p.sections[section].duration : 0)
        guard dur > 0 else { return [] }
        if !chain { return [OpenRouterVideo.clipSeconds(forSectionSeconds: dur)] }
        let have = (section < 0 ? p.intro : p.sections[section]).clips.reduce(0) { $0 + $1.seconds }
        var out: [Int] = []; var left = Int(ceil(dur - have - 0.001))
        while left > 0 { let s = min(OpenRouterVideo.maxSeconds, max(OpenRouterVideo.minSeconds, left)); out.append(s); left -= s }
        return out
    }
    func clipPriceUSD(_ seconds: [Int]) -> Double { Double(seconds.reduce(0, +)) * videoPricePerSecond }
    func refreshVideoPrice() { Task { videoPricePerSecond = await OpenRouterVideo.pricePerSecond() } }

    private func sectionRef(_ i: Int) -> PhotoSection? { guard let p = plan else { return nil }; return i < 0 ? p.intro : (p.sections.indices.contains(i) ? p.sections[i] : nil) }
    private func edit(_ i: Int, _ f: (inout PhotoSection) -> Void) {
        guard var p = plan else { return }
        if i < 0 { f(&p.intro) } else if p.sections.indices.contains(i) { f(&p.sections[i]) }
        plan = p; persist(); live.invalidate()
    }

    func setClipMode(section: Int, use: Bool) { checkpoint("Change motion"); edit(section) { $0.useClips = use && !$0.clips.isEmpty } }

    func deleteClips(section: Int) {
        guard let w = workDir, let s = sectionRef(section) else { return }
        checkpoint("Delete video clips")
        for c in s.clips { try? FileManager.default.removeItem(at: w.appendingPathComponent(c.file)); try? FileManager.default.removeItem(at: w.appendingPathComponent(c.lastFrame)) }
        edit(section) { $0.clips = []; $0.useClips = false }
    }

    /// Makes the clip(s). Single: one clip from the picture. Chain: clips back to back, each starting on the last frame of the one before.
    func startClips(section: Int, chain: Bool) {
        guard clipJob == nil, plan != nil, let w = workDir, let sec = sectionRef(section) else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        guard sec.selectedCandidate?.fullFile != nil else { errorMessage = "Make or add this picture first. The clip starts from it."; return }
        let secs = clipSeconds(section: section, chain: chain)
        guard !secs.isEmpty else { return }
        config = Config.load()
        clipJob = ClipJob(section: section, chain: chain, secondsList: secs)
        clipTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.runClips(section: section, chain: chain, work: w) }
            catch is CancellationError { }
            catch { self.clipJob?.failed = error.localizedDescription }
            if self.clipJob?.failed == nil { self.clipJob = nil }
            self.clipTask = nil
        }
    }

    private func runClips(section: Int, chain: Bool, work w: URL) async throws {
        guard let job = clipJob, let sec0 = sectionRef(section), let p0 = plan else { return }
        // the credit must cover the whole job, so it can never run dry halfway
        let price = clipPriceUSD(job.secondsList)
        if let rem = try? await OpenRouter.fetchCredits(apiKey: config.openRouterKey).remaining {
            openRouterCredits = rem
            if rem < price { throw MVError("This needs about \(OpenRouter.formatUSD(price)) of OpenRouter credit but only \(OpenRouter.formatCredits(rem)) is left. Add credit and try again.") }
        }
        // story prompts for the clips from the local model (one call)
        clipJob?.phase = "Writing the clip prompts…"
        let lines = p0.lines
        let ids = sec0.lineIDs.sorted()
        let perClip: [String] = {
            var out: [String] = []; var t0 = sec0.start + sec0.clips.reduce(0) { $0 + $1.seconds }
            for s in job.secondsList { let t1 = t0 + Double(s); out.append(ids.filter { lines.indices.contains($0) && lines[$0].start >= t0 && lines[$0].start < t1 }.map { lines[$0].text }.joined(separator: " / ")); t0 = t1 }
            return out
        }()
        let omlx = OMLX(config: config); try? await omlx.ensureReady()
        let shots = await PromptWriter(omlx: omlx).clipShots(idea: sec0.prompt, lyricsPerClip: perClip, title: p0.title, subject: p0.description, setting: p0.setting)
        let wasUsing = sec0.useClips
        var base = sec0.clips                                  // clips already in the section stay when the whole section is continued
        if !chain { base = []; checkpoint("Make video clip") } else { checkpoint("Make video clips") }
        var made: [SectionClip] = []
        var k = 0
        while k < job.secondsList.count {
            try Task.checkCancellation()
            clipJob?.index = k; clipJob?.waiting = false
            let all = base + made
            let offset = all.reduce(0) { $0 + $1.seconds }
            let firstFrame = all.last?.lastFrame ?? sec0.selectedCandidate?.fullFile ?? ""
            let prompt = (k < shots.count ? shots[k] : sec0.prompt) + " Bright, well lit, smooth natural motion that obeys real-world physics, no text."
            guard var p = plan else { return }
            var clip = try await Pipeline.makeClip(plan: &p, section: section, seconds: job.secondsList[k], prompt: prompt, firstFrame: firstFrame, offset: offset, work: w, config: config,
                                                   onPhase: { ph in Task { @MainActor in self.clipJob?.phase = ph } })
            if config.videoRealismCheck {
                clipJob?.phase = "Checking the clip looks physically believable…"
                let r = await Pipeline.realismWarning(clipFile: w.appendingPathComponent(clip.file), idea: sec0.prompt, config: config)
                clip.warning = r.warning; p.totalVideoCostUSD += r.costUSD
            }
            // keep the new clip with the section (not yet used until you accept it)
            let shown = base + made + [clip]
            if section < 0 { p.intro.clips = shown; p.intro.useClips = true } else { p.sections[section].clips = shown; p.sections[section].useClips = true }      // a new clip is in use straight away
            plan = p; persist(); live.invalidate()
            refreshOpenRouterCredits(silent: true)
            let last = k == job.secondsList.count - 1
            if chain && !last && clipJob?.autoContinue == true { made.append(clip); k += 1; continue }
            // watch it, then decide
            clipJob?.waiting = true; clipJob?.phase = ""
            let decision = await withCheckedContinuation { (c: CheckedContinuation<ClipDecision, Never>) in clipDecision = c }
            clipDecision = nil
            switch decision {
            case .redo:                                      // the clip is paid for already; make another from the same first frame
                let wasting = clip
                var q = plan!; let drop = { (s: inout PhotoSection) in s.clips.removeAll { $0.id == wasting.id } }
                if section < 0 { drop(&q.intro) } else { drop(&q.sections[section]) }
                plan = q; persist(); continue
            case .discard:
                var q = plan!; let drop = { (s: inout PhotoSection) in s.clips = Array(s.clips.prefix(base.count + made.count)); s.useClips = !s.clips.isEmpty && (wasUsing || !made.isEmpty) }
                if section < 0 { drop(&q.intro) } else { drop(&q.sections[section]) }
                plan = q; persist(); live.invalidate(); return
            case .stop:
                made.append(clip); edit(section) { $0.useClips = true }; return
            case .use, .next:
                made.append(clip); edit(section) { $0.useClips = true }
                k += 1
            }
        }
    }

    func decideClip(_ d: ClipDecision) { clipDecision?.resume(returning: d); clipDecision = nil }
    func cancelClipJob() { clipDecision?.resume(returning: .stop); clipDecision = nil; clipTask?.cancel(); clipJob = nil }
    func dismissClipError() { clipJob = nil }
}
