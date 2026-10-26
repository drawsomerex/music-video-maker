// Automatic mode and the director. Two ways in, for both kinds of video:
// - "Make it all automatically": one click. The director plans the video, the app draws everything (and, for a looping video, makes the
//   clips) and opens the preview. The price is on the button; pictures stay as bright as your Brightness setting (Bright unless you chose otherwise).
// - "Plan with the director": the director plans, then you see its choices in drop-downs (brightness, style, weather, time, quality, the picture
//   to base it on, the cast, the number of scenes) and approve or change them before anything is drawn. Darker moods only when you pick them.
import SwiftUI
import MVCore

/// The director's choices, as you approve them.
struct DirectorChoices {
    var style = ""
    var brightness: Brightness = .bright
    var suggested: Brightness = .bright           // what the director suggested (shown, never applied without you)
    var weather: LoopWeather = .any
    var time: LoopTimeOfDay = .any
    var shot: ShotType = .any
    var quality: PictureQuality = .high
    var reference = ""                            // words to search for a picture to base it on ("" = none)
    var keep: NextFocus = .place
    var cast = ""
    var scenes = 1
    var sceneTexts: [String] = []                 // a looping video's scenes, as you approve or rewrite them
}

/// The director at work: its steps, where it is, and whether you paused it.
struct DirectorRun: Equatable {
    var loop: Bool
    var steps: [String]
    var current = 0
    var detail = ""
    var paused = false                            // you pressed Pause: it stops at the next safe point
    var waiting = false                           // it has stopped there and waits for Continue
    var scenes: [String] = []                     // a looping video: the scenes it makes (the ones still to come can be rewritten while paused)
    var done = 0                                  // scenes finished
}

/// The director's plan waiting for your approval.
struct DirectorReview: Identifiable {
    let id = UUID()
    var logline: String
    var summary: String
    var song: Treatment?
    var loop: LoopTreatment?
    var choices: DirectorChoices
    var hasOwnSource: Bool                         // you already chose a picture to base it on (it is kept)
}

extension AppModel {
    // MARK: music video
    /// The price of doing everything automatically: every picture, and the cast sheet.
    var autoSongPrice: Double { Double((plan?.sections.count ?? 0) + 2) * perImageCostUSD }
    static let songSteps = ["Plan the video", "Picture to base it on", "Cast sheet", "Draw the pictures", "Preview"]

    /// One click: the director plans, everything is drawn, the preview opens.
    func autoDirect() { songDirector(review: false) }
    /// The director plans, then you approve its choices.
    func directorPlan() { songDirector(review: true) }

    private func songDirector(review: Bool) {
        guard plan != nil, let w = workDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let cfg = config
        directorRun = DirectorRun(loop: false, steps: review ? ["Plan the video", "Your approval"] : Self.songSteps)
        runBackground(initialPhase: "The director is planning the video…") { [weak self] in
            guard let self, let p0 = self.plan else { return }
            let bh = self.busyHandler
            try await self.directorStep(0, "Reading the song description and the lyrics")
            bh("The director is reading the song description and the lyrics, and planning the video…", 0.1)
            let (t, cost) = try await Director.musicVideo(p0, work: w, config: cfg)
            self.editSong { $0.totalGenerationCostUSD += cost }
            var c = DirectorChoices(style: t.style.isEmpty ? p0.style : t.style, brightness: p0.brightness, suggested: t.mood, weather: t.weather, time: t.timeOfDay, shot: t.shot,
                                    quality: p0.pictureQuality, reference: t.reference ?? "", keep: t.keep, cast: t.cast, scenes: 1)
            if p0.source != nil { c.reference = "" }
            if review {
                self.directorRun = nil
                self.directorReview = DirectorReview(logline: t.logline, summary: t.summary, song: t, choices: c, hasOwnSource: p0.source != nil)
            } else {
                try await self.songCarryOut(t, c, work: w, config: cfg)
            }
        }
    }

    /// Applies the director's plan with these choices, then draws every picture and opens the preview. Ideas you wrote yourself are kept.
    func carryOutSong(_ t: Treatment, _ c: DirectorChoices) {
        guard let w = workDir else { return }
        let cfg = config
        directorRun = DirectorRun(loop: false, steps: Self.songSteps, current: 1)
        runBackground(initialPhase: "Carrying out the director's plan…") { [weak self] in
            try await self?.songCarryOut(t, c, work: w, config: cfg)
        }
    }
    /// The director's ideas go into the parts you didn't write yourself (with whether each one shows the reference's place, building or subject).
    func applyIdeas(_ t: Treatment, to p: inout Plan) {
        func put(_ s: inout PhotoSection, _ i: Int) {
            guard !s.promptManual, let idea = t.pictures[i] else { return }
            s.prompt = idea; s.focal = []; s.logicNote = nil
            if let r = t.usesReference[i] { s.usesSource = r; s.usesSourceFor = idea } else { s.usesSource = nil; s.usesSourceFor = nil }
        }
        put(&p.intro, -1)
        for i in p.sections.indices { put(&p.sections[i], i) }
    }
    private func songCarryOut(_ t: Treatment, _ c: DirectorChoices, work w: URL, config cfg: Config) async throws {
        guard var p = plan else { return }
        let bh = busyHandler
        checkpoint("The director's plan")
        if !c.style.isEmpty { p.style = c.style }
        p.brightness = c.brightness; p.weather = c.weather; p.timeOfDay = c.time; p.shot = c.shot; p.pictureQuality = c.quality
        p.cast = c.cast.trimmingCharacters(in: .whitespacesAndNewlines); p.castSheet = nil
        applyIdeas(t, to: &p)
        p.treatment = t.summary + (p.cast.isEmpty ? "" : "\nCast: \(p.cast)")
        plan = p; persist()
        let words = c.reference.trimmingCharacters(in: .whitespaces)
        try await directorStep(1, p.source != nil ? "Your own picture is kept" : (words.isEmpty ? "None needed" : "Searching for “\(words)”"))
        guard var p = plan else { return }
        if p.source == nil, !words.isEmpty {
            bh("Finding a picture of \(words)…", 0.1)
            if let r = await Director.findReference(words, keep: c.keep, into: w, config: cfg) {
                // what is kept is what the photo really shows (a street photo is a place, never a "subject")
                p.source = r.file; p.nextFocus = r.keep; p.sourceNote = r.note; p.sourceNoteFocus = r.keep; p.totalGenerationCostUSD += r.cost
            } else {
                directorRun?.detail = "No photo really showed “\(words)”; the pictures follow their own words"
            }
            plan = p; persist()
        }
        try await directorStep(2, p.cast.isEmpty ? "Nothing recurs" : "Drawing the people and things that stay the same")
        guard var p = plan else { return }
        if !p.cast.isEmpty {
            bh("Drawing the cast sheet (the people and things every picture keeps the same)…", 0.15)
            _ = try? await Pipeline.makeCastSheet(plan: &p, work: w, config: cfg)
            plan = p; persist()
        }
        try await directorStep(3, "")
        try await drawLoop(Array(-1..<(plan?.sections.count ?? 0)), work: w)
        try await directorStep(4, "Opening the preview")
        directorRun = nil
        showFullPreview = true
        notice = "Everything is drawn. This is the preview of your video: watch it, change any picture you like, then press “Make my video”."
    }
    func drawThenPreview(_ targets: [Int], work: URL) {
        drawSections(targets, work: work, titlePrefix: "Drawing \(targets.count) picture\(targets.count == 1 ? "" : "s")") { [weak self] in
            self?.showFullPreview = true
            self?.notice = "Everything is drawn. This is the preview of your video: watch it, change any picture you like, then press “Make my video”."
        }
    }

    // MARK: pause, continue, stop
    /// Marks the step the director is on, then goes on (or waits while paused).
    func directorStep(_ i: Int, _ detail: String) async throws {
        directorRun?.current = i
        try await directorCheckpoint(detail)
    }
    /// A safe place to stop or wait: between steps and between pictures or scenes. While paused you can change the ideas and the picture options; they are used when you continue.
    func directorCheckpoint(_ detail: String, fraction: Double? = nil) async throws {
        guard directorRun != nil else { return }
        directorRun?.detail = detail
        while directorRun?.paused == true {
            directorRun?.waiting = true
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        directorRun?.waiting = false
        try Task.checkCancellation()
    }
    func pauseDirector() { directorRun?.paused = true }
    func continueDirector() { directorRun?.paused = false }
    /// Stops the director. Everything made so far is kept.
    func stopDirector() {
        guard let r = directorRun else { return }
        directorRun = nil
        if r.loop { cancelLoopJob() } else { cancelBackgroundTask() }
        notice = r.loop ? "Stopped. Everything made so far is kept. Change what you like, then make the next scene yourself or press “Make it all automatically” again."
                        : "Stopped. Everything drawn so far is kept. Change any picture idea or the picture options, then press “Make all missing pictures” to carry on."
    }

    /// "Fix it": redraws the picture with only the fault the check found changed.
    func fixPicture(_ section: Int) {
        guard let w = workDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let cfg = config
        runBackground(initialPhase: "Fixing the picture…") { [weak self] in
            guard let self, var p = self.plan else { return }
            let before = p
            self.workingSection = section
            defer { self.workingSection = nil }
            self.busyHandler("Fixing only that, keeping everything else…", 0.3)
            _ = try await Pipeline.fixSectionImage(section: section, plan: &p, work: w, config: cfg)
            self.mergeTaskResult(p, startedFrom: before, section: section, artwork: true)
            self.live.invalidate()
            self.notice = "Fixed. The earlier version is still there if you prefer it (the arrows under the picture)."
        }
    }

    /// "Make highest quality": redraws these pictures at High from themselves (more detail, sharper), one after another. Each earlier picture stays as a choice.
    func makeHighestQuality(_ sections: [Int]) {
        guard let w = workDir, !sections.isEmpty else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let cfg = config
        runBackground(initialPhase: "Making \(sections.count == 1 ? "the picture" : "\(sections.count) pictures") highest quality…") { [weak self] in
            guard let self else { return }
            for (k, sec) in sections.enumerated() {
                try Task.checkCancellation()
                guard var p = self.plan else { break }
                let before = p
                self.workingSection = sec
                self.busyHandler("\(k + 1)/\(sections.count): \(sec < 0 ? "Title card" : "Picture \(sec + 1)") — redrawing at the highest quality, then sharpening…", Double(k) / Double(sections.count))
                _ = try await Pipeline.highestQualitySectionImage(section: sec, plan: &p, work: w, config: cfg)
                self.mergeTaskResult(p, startedFrom: before, section: sec, artwork: true)
                self.live.invalidate()
            }
            self.workingSection = nil
            self.refreshOpenRouterCredits(silent: true)
            self.notice = (sections.count == 1 ? "Done: the picture is redrawn" : "Done: \(sections.count) pictures are redrawn") + " at the highest quality. The earlier version is still there if you prefer it (under the picture)."
        }
    }
    /// The parts whose picture can be made highest quality (a drawn or chosen picture, not a video clip, not done already).
    var highestQualityTargets: [Int] {
        guard let p = plan else { return [] }
        return (-1..<p.sections.count).filter { i in
            guard let c = (i < 0 ? p.intro : p.sections[i]).selectedCandidate else { return false }
            return c.videoFile == nil && c.fullFile != nil && !c.credit.hasPrefix("Highest quality")
        }
    }

    /// The director writes the picture ideas (the default for a new video when the OpenRouter key is set; about a cent). Nothing is drawn.
    /// Ideas you wrote yourself are kept; the style changes only when you left it on automatic.
    func directorIdeas(silent: Bool = false) {
        guard plan != nil, let w = workDir, hasOpenRouterKey else { return }
        let cfg = config, ownStyle = selectedStylePreset != StylePreset.autoID
        runBackground(initialPhase: "The director is writing the picture ideas…") { [weak self] in
            guard let self, let p0 = self.plan else { return }
            self.busyHandler("The director is reading the song description and the lyrics…", 0.2)
            let (t, cost) = try await Director.musicVideo(p0, work: w, config: cfg)
            guard var p = self.plan else { return }
            if !ownStyle, !t.style.isEmpty { p.style = t.style }
            self.applyIdeas(t, to: &p)
            if p.cast.isEmpty { p.cast = t.cast }
            p.treatment = t.summary + (p.cast.isEmpty ? "" : "\nCast: \(p.cast)")
            p.totalGenerationCostUSD += cost
            self.plan = p; self.persist()
            if !silent { self.notice = "The director wrote new picture ideas (ideas you wrote yourself were kept)." }
        }
    }

    // MARK: looping video
    /// What one scene costs (its picture and its clip).
    var loopScenePrice: Double { perImageCostUSD + loopClipPrice }
    /// How many scenes Automatic mode makes: the scene changes the long video has room for (up to three).
    var loopAutoScenes: Int {
        guard let p = loopProject else { return 1 }
        return max(1, min(3, loopPlan.map { LoopVideo.scenesWanted(p, plan: $0) } ?? 2))
    }
    var loopAutoPrice: Double { Double(loopAutoScenes) * loopScenePrice }

    /// One click: the director plans, the pictures and clips are made, the preview opens.
    func loopAutoAsk() {
        guard let p = loopProject else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let c = DirectorChoices(brightness: p.brightness, quality: p.pictureQuality, scenes: loopAutoScenes)
        loopAuto(c, treatment: nil)
    }
    static let loopSteps = ["Listen to the songs", "Plan the scenes", "Picture to base it on", "Make the scenes", "Preview"]
    /// The director plans the looping video, then you approve its choices.
    func loopDirectorPlan() {
        guard let p0 = loopProject, let d = loopDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        config = Config.load()
        let cfg = config, scenes = loopAutoScenes
        directorRun = DirectorRun(loop: true, steps: ["Listen to the songs", "Plan the scenes", "Your approval"])
        runLoop("The director is planning the video…") { [weak self] p, _ in
            var q = p
            try await self?.directorStep(0, "Hearing the words of the songs")
            await MainActor.run { self?.loopJob?.phase = "Listening to the words of the songs…" }
            await Director.listen(&q, dir: d, config: cfg)
            try await self?.directorStep(1, "Writing the scenes")
            await MainActor.run { self?.loopJob?.phase = "The director is planning the scenes…" }
            let (t, cost) = try await Director.looping(q, scenes: scenes, config: cfg)
            q.imagesUSD += cost
            let c = DirectorChoices(style: t.style.isEmpty ? q.style : t.style, brightness: p0.brightness, suggested: t.mood, weather: t.weather, time: t.timeOfDay, shot: t.shot,
                                    quality: p0.pictureQuality, reference: q.source == nil ? (t.reference ?? "") : "", keep: t.keep, cast: t.cast, scenes: max(1, min(t.scenes.count, scenes)), sceneTexts: t.scenes)
            await MainActor.run {
                self?.directorRun = nil
                self?.directorReview = DirectorReview(logline: t.logline, summary: t.logline, loop: t, choices: c, hasOwnSource: q.source != nil)
            }
            return q
        }
    }

    /// Makes the looping video with these choices: the director plans (unless its plan is given), then each scene's picture and clip, then the preview.
    /// Pause waits after the step in progress (a clip HeyGen is making is finished first); the scenes still to come can be rewritten while paused.
    func loopAuto(_ c: DirectorChoices, treatment: LoopTreatment?) {
        guard let d = loopDir else { return }
        config = Config.load()
        let cfg = config, scenes = c.scenes
        directorRun = DirectorRun(loop: true, steps: Self.loopSteps, current: treatment == nil ? 0 : 2)
        runLoop("Automatic: the director is planning the video…", estimate: Double(scenes) * 300) { [weak self] p, _ in
            func phase(_ s: String) async { await MainActor.run { self?.loopJob?.phase = s } }
            var q = p
            var t: LoopTreatment
            if let given = treatment { t = given } else {
                try await self?.directorStep(0, "Hearing the words of the songs")
                await phase("Automatic: listening to the words of the songs…")
                await Director.listen(&q, dir: d, config: cfg)
                try await self?.directorStep(1, "Writing the scenes")
                await phase("Automatic: the director is planning the video…")
                let (made, cost) = try await Director.looping(q, scenes: scenes, config: cfg)
                t = made; q.imagesUSD += cost
            }
            let scenesToMake = Array((c.sceneTexts.isEmpty ? t.scenes : c.sceneTexts).prefix(scenes))
            await MainActor.run { self?.directorRun?.scenes = scenesToMake }
            let style = treatment == nil ? t.style : c.style
            if !style.isEmpty { q.style = style }
            q.brightness = c.brightness; q.pictureQuality = c.quality
            q.weather = treatment == nil ? t.weather : c.weather; q.timeOfDay = treatment == nil ? t.timeOfDay : c.time; q.shot = treatment == nil ? t.shot : c.shot
            let words = treatment == nil ? (t.reference ?? "") : c.reference
            try await self?.directorStep(2, q.source != nil ? "Your own picture is kept" : (words.trimmingCharacters(in: .whitespaces).isEmpty ? "None needed" : "Searching for “\(words)”"))
            if q.source == nil, !words.trimmingCharacters(in: .whitespaces).isEmpty {
                await phase("Automatic: finding a picture of \(words)…")
                if let r = await Director.findReference(words, keep: treatment == nil ? t.keep : c.keep, into: d, config: cfg) { q.source = r.file; q.nextFocus = r.keep; q.imagesUSD += r.cost }
            }
            // the cast: the recurring animals, objects and landmarks, drawn once on a sheet every picture matches
            q.cast = (treatment == nil ? t.cast : c.cast).trimmingCharacters(in: .whitespacesAndNewlines); q.castSheet = nil
            if !q.cast.isEmpty {
                await phase("Automatic: drawing the cast sheet…")
                _ = try? await LoopVideo.makeCastSheet(&q, dir: d, config: cfg)
            }
            var made: [String] = []
            for k in scenesToMake.indices {
                let n = "scene \(k + 1) of \(scenesToMake.count)"
                try await self?.directorStep(3, "Scene \(k + 1) of \(scenesToMake.count): the picture")
                // what you changed while paused: the scene's words and the picture options
                let now = await MainActor.run { (self?.directorRun?.scenes, self?.loopProject) }
                if let edited = now.0, edited.indices.contains(k) { q.scene = edited[k] } else { q.scene = scenesToMake[k] }
                if let cur = now.1 { q.style = cur.style; q.brightness = cur.brightness; q.pictureQuality = cur.pictureQuality; q.weather = cur.weather; q.timeOfDay = cur.timeOfDay; q.shot = cur.shot }
                await phase("Automatic: drawing the picture for \(n)…")
                if k == 0 { try await LoopVideo.makePicture(&q, dir: d, config: cfg) } else { q.sceneDrawn = nil; try await LoopVideo.makeNextPicture(&q, dir: d, config: cfg) }
                await phase("Automatic: looking at what should move in \(n)…")
                await LoopVideo.refreshMotion(&q, dir: d, config: cfg)
                try await self?.directorCheckpoint("Scene \(k + 1) of \(scenesToMake.count): the loop clip (HeyGen, a few minutes)")
                await phase("Automatic: HeyGen is making the clip for \(n) (a few minutes)…")
                try await LoopVideo.makeClip(&q, dir: d, config: cfg) { ph in Task { @MainActor in self?.loopJob?.phase = "Automatic, \(n): " + ph } }
                if let c = q.clip { made.append(c) }
                LoopVideo.save(q, d)
                await MainActor.run { self?.directorRun?.done = k + 1 }
            }
            try await self?.directorStep(4, "Making the loop preview")
            if let first = made.first {
                q.clip = first; q.sceneClips = made
                if made.count > 1 && q.sceneChange == .never { q.sceneChange = .both }
                LoopVideo.save(q, d)
                await phase("Automatic: making the loop preview…")
                try await LoopVideo.makePreview(clip: d.appendingPathComponent(first), output: d.appendingPathComponent("preview-" + (first as NSString).deletingPathExtension + ".mp4"), trim: q.trims[first] ?? ClipTrim())
            }
            await MainActor.run { self?.directorRun = nil; self?.loopAutoFinished = true }
            return q
        }
    }

    /// You approved the director's choices: carry them out.
    func approveDirector(_ r: DirectorReview) {
        directorReview = nil
        if let t = r.song { carryOutSong(t, r.choices) }
        else if let t = r.loop { loopAuto(r.choices, treatment: t) }
    }
}

/// The director's choices in drop-downs, to approve or change before anything is drawn.
struct DirectorSheet: View {
    @EnvironmentObject var model: AppModel
    @State var review: DirectorReview
    private var c: Binding<DirectorChoices> { $review.choices }
    private var isLoop: Bool { review.loop != nil }
    private var price: Double {
        isLoop ? Double(review.choices.scenes) * model.loopScenePrice + (review.choices.cast.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : review.choices.quality.estimate)
               : Double((model.plan?.sections.count ?? 0) + 1 + (review.choices.cast.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)) * (review.choices.quality.estimate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The director's plan").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(review.logline).font(.title3).fixedSize(horizontal: false, vertical: true)
                    if let t = review.song { Text(t.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if review.loop != nil {
                        ForEach(0..<min(review.choices.scenes, review.choices.sceneTexts.count), id: \.self) { k in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scene \(k + 1)").font(.callout.weight(.semibold))
                                TextField("Scene \(k + 1)", text: $review.choices.sceneTexts[k], axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    Text("Check the choices below and change any of them. Nothing is drawn until you press the blue button.").font(.callout).foregroundStyle(.secondary)
                    Form {
                        Picker("Brightness", selection: c.brightness) { ForEach(Brightness.allCases, id: \.self) { Text($0.name).tag($0) } }
                        if review.choices.suggested != .bright && review.choices.suggested != review.choices.brightness {
                            Text("The director suggests “\(review.choices.suggested.name)”. Pictures stay \(review.choices.brightness.name.lowercased()) unless you choose it above.").font(.callout).foregroundStyle(.orange)
                        }
                        Picker("Style", selection: c.style) {
                            Text("The director's style").tag(review.song?.style ?? review.loop?.style ?? "")
                            ForEach(StylePreset.all.filter { !$0.prompt.isEmpty && $0.prompt != (review.song?.style ?? review.loop?.style) }) { Text($0.name).tag($0.prompt) }
                        }
                        TextField("The style in words", text: c.style, axis: .vertical).lineLimit(2...4)
                        Picker("Weather", selection: c.weather) { ForEach(LoopWeather.allCases, id: \.self) { Text($0.name).tag($0) } }
                        Picker("Time of day", selection: c.time) { ForEach(LoopTimeOfDay.allCases, id: \.self) { Text($0.name).tag($0) } }
                        Picker("Type of shot", selection: c.shot) { ForEach(ShotType.allCases, id: \.self) { Text($0.name).tag($0) } }
                        Picker("Picture quality", selection: c.quality) { ForEach(PictureQuality.allCases, id: \.self) { Text($0.name).tag($0) } }
                        if review.hasOwnSource {
                            Text("Picture to base it on: your own picture (kept).").foregroundStyle(.secondary)
                        } else {
                            TextField("Picture to base it on (search words, empty = none)", text: c.reference)
                            if !review.choices.reference.trimmingCharacters(in: .whitespaces).isEmpty {
                                Picker("Keep from that picture", selection: c.keep) { ForEach(NextFocus.allCases, id: \.self) { Text($0.name).tag($0) } }
                            }
                        }
                        TextField(isLoop ? "The animals, objects and landmarks that stay the same (empty = none)" : "The people and things that stay the same (empty = none)", text: c.cast, axis: .vertical).lineLimit(2...5)
                        if let t = review.loop, t.scenes.count > 1 {
                            Picker("Scenes", selection: c.scenes) { ForEach(1...t.scenes.count, id: \.self) { Text("\($0)").tag($0) } }
                        }
                    }.formStyle(.grouped)
                }
            }
            HStack {
                Button("Not now", role: .cancel) { model.directorReview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("About \(OpenRouter.formatUSD(price))\(model.openRouterCredits.map { " · your credit \(OpenRouter.formatCredits($0))" } ?? "")").foregroundStyle(.secondary)
                Button { model.approveDirector(review) } label: { Label(isLoop ? "Approve and make it" : "Approve and draw everything", systemImage: "checkmark.circle.fill").font(.headline) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(minWidth: 620, idealWidth: 720, minHeight: 560, idealHeight: 720)
    }
}

/// Shows the director's plan for approval.
struct AutoAskModifier: ViewModifier {
    @EnvironmentObject var model: AppModel
    func body(content: Content) -> some View {
        content.sheet(item: $model.directorReview) { r in DirectorSheet(review: r).environmentObject(model) }
    }
}
