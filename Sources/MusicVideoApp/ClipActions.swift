// Video clips for a section: make one clip, or the whole section as back-to-back clips, watching each one as it arrives.
import SwiftUI
import MVCore

enum ClipDecision { case next, redo, stop, use, discard }

struct ClipJob {
    var id = UUID()
    var preview: SectionClip? = nil
    var section: Int
    var chain: Bool
    var secondsList: [Int]            // the clips still to make, in order (including the one in progress)
    var index = 0                     // the clip being made or waiting for a decision
    var phase = "Starting…"
    var waiting = false               // a clip has just arrived: watch it, then choose
    var autoContinue = false          // back-to-back: make the rest without asking
    var failed: String?
    var noWait = false                // bulk run: use each clip as soon as it arrives
    var bulk: (n: Int, of: Int)? = nil
    var started = Date()              // when the clip being made now was ordered
    /// HeyGen does not report progress, so the bar is an estimate: it fills toward about 95 % over the typical time for this clip length, then jumps to 100 % when the clip arrives.
    func estimatedFraction(now: Date) -> Double {
        let seconds = Double(secondsList.indices.contains(index) ? secondsList[index] : 10)
        let typical = 60 + 12 * seconds
        return 0.95 * (1 - exp(-1.8 * max(0, now.timeIntervalSince(started)) / typical))
    }
}

@MainActor
extension AppModel {
    /// Clip lengths for a section. One clip: the section length (5–15 s). Whole section: clips of up to 15 s that add up to the section.
    func clipSeconds(section: Int, chain: Bool) -> [Int] {
        guard let p = plan else { return [] }
        let dur = section < 0 ? p.introDuration : (p.sections.indices.contains(section) ? p.sections[section].duration : 0)
        guard dur > 0 else { return [] }
        if !chain { return [(section < 0 ? p.intro : p.sections[section]).clipOptions.generatedSeconds(section: dur)] }
        let have = (section < 0 ? p.intro : p.sections[section]).clips.reduce(0) { $0 + $1.playSeconds }
        var out: [Int] = []; var left = Int(ceil(dur - have - 0.001))
        while left > 0 { let s = min(OpenRouterVideo.maxSeconds, max(OpenRouterVideo.minSeconds, left)); out.append(s); left -= s }
        return out
    }
    func clipPriceUSD(_ seconds: [Int], sharp: Bool = false) -> Double { Double(seconds.reduce(0, +)) * (sharp ? 0.10 : videoPricePerSecond) }
    func setClipOptions(section: Int, seconds: Int?, sharp: Bool, repeatClip: Bool) {
        checkpoint("Change clip options"); edit(section) { $0.clipOptions = ClipOptions(seconds: seconds, sharp: sharp); $0.repeatClips = repeatClip }
    }
    func useSavedClip(section: Int, clip: SectionClip) {
        checkpoint("Use saved clip"); edit(section) { $0.clips = [clip]; $0.useClips = true; $0.mediaParts = nil; $0.playbackOffset = 0 }
    }
    func refreshVideoPrice() { Task { videoPricePerSecond = await OpenRouterVideo.pricePerSecond() } }

    private func sectionRef(_ i: Int) -> PhotoSection? { guard let p = plan else { return nil }; return i < 0 ? p.intro : (p.sections.indices.contains(i) ? p.sections[i] : nil) }
    private func edit(_ i: Int, _ f: (inout PhotoSection) -> Void) {
        guard var p = plan else { return }
        if i < 0 { f(&p.intro) } else if p.sections.indices.contains(i) { f(&p.sections[i]) }
        plan = p; persist(); live.invalidate()
    }

    /// Chooses which part of one generated clip plays; the clips after it slide up so there is no gap.
    func setClipTrim(section: Int, clip id: String, start: Double, end: Double?) {
        checkpoint("Trim video", coalesce: true)
        edit(section) { s in
            guard let i = s.clips.firstIndex(where: { $0.id == id }) else { return }
            let len = max(0.5, s.clips[i].seconds), from = min(max(0, start), max(0, len - 0.5))
            s.clips[i].trimStart = from
            s.clips[i].trimEnd = end.map { min(len, max(from + 0.5, $0)) }
            var t = s.clips.first?.offset ?? 0
            for k in s.clips.indices { s.clips[k].offset = t; t += s.clips[k].playSeconds }
        }
    }

    /// Repeat the clip (with a crossfade) instead of holding its last frame. Generated: only a single clip repeats; imported: the picture slot's clip.
    func setClipRepeat(section: Int, on: Bool) {
        checkpoint("Change repeat")
        guard let s = sectionRef(section) else { return }
        if s.useClips && !s.clips.isEmpty { edit(section) { $0.repeatClips = on && $0.clips.count == 1 } }
        else { updateCandidate(section: section) { $0.videoRepeat = on } }
    }

    func setClipMode(section: Int, use: Bool) { checkpoint("Change motion"); edit(section) { $0.mediaParts = nil; $0.playbackOffset = 0; $0.useClips = use && !$0.clips.isEmpty } }

    func deleteClips(section: Int) {
        guard workDir != nil, sectionRef(section) != nil else { return }
        checkpoint("Delete video clips")
        // Remove the assignment, not the paid media. Undo/history and other sections may still reference these files.
        edit(section) { $0.retainedClips = TimelineEditor.uniqueClips($0.retainedClips + $0.clips); $0.clips = []; $0.mediaParts = nil; $0.useClips = false }
    }

    /// Makes the clip(s). Single: one clip from the picture. Chain: clips back to back, each starting on the last frame of the one before.
    func startClips(section: Int, chain: Bool) {
        guard clipJob == nil, plan != nil, let w = workDir, let sec = sectionRef(section) else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        guard sec.selectedCandidate?.fullFile != nil else { errorMessage = "Make or add this picture first. The clip starts from it."; return }
        let secs = clipSeconds(section: section, chain: chain)
        guard !secs.isEmpty else { return }
        config = Config.load()
        let spentBefore = plan?.totalVideoCostUSD ?? 0
        clipTaskID = UUID(); let owner = clipTaskID
        clipJob = ClipJob(section: section, chain: chain, secondsList: secs)
        clipTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.runClips(section: section, chain: chain, work: w) }
            catch is CancellationError { }
            catch { if self.clipTaskID == owner { self.clipJob?.failed = error.localizedDescription } }
            guard self.clipTaskID == owner else { return }
            if self.clipJob?.failed == nil {
                self.clipJob = nil
                let spent = (self.plan?.totalVideoCostUSD ?? 0) - spentBefore
                if spent > 0.0001 { self.doneNote = DoneNote(text: "Done — the video clip\(chain ? "s are" : " is") ready · cost \(OpenRouter.formatUSD(spent))") }
            }
            self.clipTask = nil
        }
    }

    private func runClips(section: Int, chain: Bool, work w: URL) async throws {
        guard let job = clipJob, let sec0 = sectionRef(section), let p0 = plan else { return }
        // the credit must cover the whole job, so it can never run dry halfway
        let price = clipPriceUSD(job.secondsList, sharp: sec0.clipOptions.sharp)
        if let rem = try? await OpenRouter.fetchCredits(apiKey: config.openRouterKey).remaining {
            openRouterCredits = rem
            if rem < price { throw MVError("This needs about \(OpenRouter.formatUSD(price)) of OpenRouter credit but only \(OpenRouter.formatCredits(rem)) is left. Add credit and try again.") }
        }
        // story prompts for the clips from the local model (one call)
        try Task.checkCancellation()
        clipJob?.phase = "Writing the clip prompts…"
        let lines = p0.lines
        let ids = sec0.lineIDs.sorted()
        let perClip: [String] = {
            var out: [String] = []; var t0 = sec0.start + sec0.clips.reduce(0) { $0 + $1.seconds }
            for s in job.secondsList { let t1 = t0 + Double(s); out.append(ids.filter { lines.indices.contains($0) && lines[$0].start >= t0 && lines[$0].start < t1 }.map { lines[$0].text }.joined(separator: " / ")); t0 = t1 }
            return out
        }()
        let omlx = OMLX(config: config); try? await omlx.ensureReady()
        let shots = await PromptWriter(omlx: omlx).clipShots(idea: sec0.prompt, lyricsPerClip: perClip, title: p0.title, subject: p0.description, setting: p0.setting, focal: sec0.selectedCandidate?.focalNames.count == 2 ? sec0.selectedCandidate!.focalNames : sec0.focal)
        try Task.checkCancellation()
        var base = sec0.clips                                  // clips already in the section stay when the whole section is continued
        if !chain { base = []; checkpoint("Make video clip") } else { checkpoint("Make video clips") }
        var made: [SectionClip] = []
        var k = 0
        while k < job.secondsList.count {
            try Task.checkCancellation()
            clipJob?.index = k; clipJob?.waiting = false; clipJob?.started = Date()
            let all = base + made
            let offset = all.reduce(0) { $0 + $1.playSeconds }
            let firstFrame = all.last?.lastFrame ?? sec0.selectedCandidate?.fullFile ?? ""
            let prompt = (k < shots.count ? shots[k] : sec0.prompt) + " Bright, well lit, smooth natural motion that obeys real-world physics, no text."
            guard var p = plan else { return }
            let before = p
            var clip = try await Pipeline.makeClip(plan: &p, section: section, seconds: job.secondsList[k], prompt: prompt, firstFrame: firstFrame, offset: offset, work: w, config: config,
                                                   onPhase: { ph in Task { @MainActor in if self.clipJob?.id == job.id { self.clipJob?.phase = ph } } }, options: chain ? ClipOptions(sharp: sec0.clipOptions.sharp) : sec0.clipOptions)
            if config.videoRealismCheck && !Task.isCancelled {
                clipJob?.phase = "Checking the clip looks physically believable…"
                let r = await Pipeline.realismWarning(clipFile: w.appendingPathComponent(clip.file), idea: sec0.prompt, config: config)
                clip.warning = r.warning; p.totalVideoCostUSD += r.costUSD
            }
            // keep the new clip with the section (not yet used until you accept it)
            let shown = base + made + [clip]
            // The paid original is already durable in retainedClips. Approval controls the visible assignment.
            if clipJob?.id == job.id { clipJob?.preview = clip }
            mergeTaskResult(p, startedFrom: before, work: w, section: section)          // edits you made while it was being made are kept
            refreshOpenRouterCredits(silent: true)
            try Task.checkCancellation()
            func accept() { edit(section) { $0.clips = shown; $0.useClips = true; $0.mediaParts = nil; $0.playbackOffset = 0 } }
            let last = k == job.secondsList.count - 1
            if clipJob?.noWait == true { made.append(clip); accept(); k += 1; continue }
            if chain && !last && clipJob?.autoContinue == true { made.append(clip); accept(); k += 1; continue }
            // watch it, then decide
            clipJob?.waiting = true; clipJob?.phase = ""
            let decision = await withCheckedContinuation { (c: CheckedContinuation<ClipDecision, Never>) in clipDecision = c }
            clipDecision = nil
            try Task.checkCancellation()
            switch decision {
            case .redo:
                // Redo leaves this paid original in Earlier clips; it never changes the current assignment.
                continue
            case .discard: return
            case .stop:
                made.append(clip); accept(); return
            case .use, .next:
                made.append(clip); accept()
                k += 1
            }
        }
    }

    /// Collects clips that were ordered (and paid for) but not saved because the app was closed while they were being made.
    func recoverClips() {
        guard hasOpenRouterKey, plan != nil, let w = workDir, !Pipeline.pendingClipJobs(work: w).isEmpty else { return }
        config = Config.load()
        Task {
            var p = plan!
            let before = p.totalVideoCostUSD
            let notes = await Pipeline.recoverPendingClips(plan: &p, work: w, config: config)
            guard !notes.isEmpty, var cur = plan, workDir == w else { return }
            for c in p.intro.clips where !cur.intro.clips.contains(where: { $0.id == c.id }) { cur.intro.clips.append(c) }
            for i in p.sections.indices where cur.sections.indices.contains(i) { for c in p.sections[i].clips where !cur.sections[i].clips.contains(where: { $0.id == c.id }) { cur.sections[i].clips.append(c) } }
            cur.totalVideoCostUSD += p.totalVideoCostUSD - before
            plan = cur; persist(); live.invalidate(); notice = notes.joined(separator: "\n")
        }
    }

    /// Sections (the opening included) that have a picture but no video clip yet and no imported video.
    var clipTargets: [Int] {
        guard let p = plan else { return [] }
        var out: [Int] = []
        if p.intro.selectedCandidate?.fullFile != nil, p.intro.selectedCandidate?.videoFile == nil, p.intro.clips.isEmpty, p.introDuration > 0 { out.append(-1) }
        for (i, s) in p.sections.enumerated() where s.selectedCandidate?.fullFile != nil && s.selectedCandidate?.videoFile == nil && s.clips.isEmpty && s.duration > 0 { out.append(i) }
        return out
    }
    var allClipsPriceUSD: Double { clipTargets.reduce(0) { $0 + clipPriceUSD(clipSeconds(section: $1, chain: false), sharp: sectionRef($1)?.clipOptions.sharp ?? false) } }

    /// One clip per picture that has none, one after the other, each used as soon as it arrives (you can still redo or trim any of them afterwards).
    func startAllClips() {
        guard clipJob == nil, plan != nil, let w = workDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let targets = clipTargets
        guard !targets.isEmpty else { return }
        config = Config.load()
        clipTaskID = UUID(); let owner = clipTaskID
        let spentBefore = plan?.totalVideoCostUSD ?? 0, price = allClipsPriceUSD
        clipTask = Task { [weak self] in
            guard let self else { return }
            if let rem = try? await OpenRouter.fetchCredits(apiKey: self.config.openRouterKey).remaining {
                self.openRouterCredits = rem
                if rem < price { self.errorMessage = "Making every clip needs about \(OpenRouter.formatUSD(price)) of OpenRouter credit but only \(OpenRouter.formatCredits(rem)) is left. Add credit and try again."; self.clipTask = nil; return }
            }
            guard self.clipTaskID == owner, !Task.isCancelled else { return }
            var made = 0
            for (n, s) in targets.enumerated() {
                if Task.isCancelled { break }
                var j = ClipJob(section: s, chain: false, secondsList: self.clipSeconds(section: s, chain: false)); j.noWait = true; j.bulk = (n + 1, targets.count)
                guard !j.secondsList.isEmpty else { continue }
                self.clipJob = j
                do { try await self.runClips(section: s, chain: false, work: w); made += 1 }
                catch is CancellationError { break }
                catch { if self.clipTaskID == owner { self.clipJob?.failed = error.localizedDescription; self.clipTask = nil }; return }
            }
            guard self.clipTaskID == owner else { return }
            self.clipJob = nil; self.clipTask = nil
            let spent = (self.plan?.totalVideoCostUSD ?? 0) - spentBefore
            if made > 0 { self.doneNote = DoneNote(text: "Done — \(made) video clip\(made == 1 ? "" : "s") made · cost \(OpenRouter.formatUSD(spent))") }
        }
    }

    func decideClip(_ d: ClipDecision) { clipDecision?.resume(returning: d); clipDecision = nil }
    func cancelClipJob() { clipTaskID = UUID(); clipDecision?.resume(returning: .stop); clipDecision = nil; clipTask?.cancel(); clipJob = nil }
    func dismissClipError() { clipJob = nil }
}
