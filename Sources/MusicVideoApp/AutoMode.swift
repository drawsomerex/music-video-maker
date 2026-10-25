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
    var quality: PictureQuality = .high
    var reference = ""                            // words to search for a picture to base it on ("" = none)
    var keep: NextFocus = .place
    var cast = ""
    var scenes = 1
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

    /// One click: the director plans, everything is drawn, the preview opens.
    func autoDirect() { songDirector(review: false) }
    /// The director plans, then you approve its choices.
    func directorPlan() { songDirector(review: true) }

    private func songDirector(review: Bool) {
        guard plan != nil, let w = workDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let cfg = config
        runBackground(initialPhase: "The director is planning the video…") { [weak self] in
            guard let self, let p0 = self.plan else { return }
            let bh = self.busyHandler
            bh("The director is reading the song description and the lyrics, and planning the video…", 0.2)
            let (t, cost) = try await Director.musicVideo(p0, work: w, config: cfg)
            self.editSong { $0.totalGenerationCostUSD += cost }
            var c = DirectorChoices(style: t.style.isEmpty ? p0.style : t.style, brightness: p0.brightness, suggested: t.mood, weather: t.weather, time: t.timeOfDay,
                                    quality: p0.pictureQuality, reference: t.reference ?? "", keep: t.keep, cast: t.cast, scenes: 1)
            if p0.source != nil { c.reference = "" }
            bh("Done", 1)
            if review {
                self.directorReview = DirectorReview(logline: t.logline, summary: t.summary, song: t, choices: c, hasOwnSource: p0.source != nil)
            } else {
                self.carryOutSong(t, c)
            }
        }
    }

    /// Applies the director's plan with these choices, then draws every picture and opens the preview. Ideas you wrote yourself are kept.
    func carryOutSong(_ t: Treatment, _ c: DirectorChoices) {
        guard let w = workDir else { return }
        let cfg = config
        runBackground(initialPhase: "Setting up the director's plan…") { [weak self] in
            guard let self, var p = self.plan else { return }
            let bh = self.busyHandler
            self.checkpoint("The director's plan")
            if !c.style.isEmpty { p.style = c.style }
            p.brightness = c.brightness; p.weather = c.weather; p.timeOfDay = c.time; p.pictureQuality = c.quality
            p.cast = c.cast.trimmingCharacters(in: .whitespacesAndNewlines); p.castSheet = nil
            if let idea = t.pictures[-1], !p.intro.promptManual { p.intro.prompt = idea; p.intro.focal = []; p.intro.logicNote = nil }
            for i in p.sections.indices where !p.sections[i].promptManual { if let idea = t.pictures[i] { p.sections[i].prompt = idea; p.sections[i].focal = []; p.sections[i].logicNote = nil } }
            p.treatment = t.summary + (p.cast.isEmpty ? "" : "\nCast: \(p.cast)")
            let words = c.reference.trimmingCharacters(in: .whitespaces)
            if p.source == nil, !words.isEmpty {
                bh("Finding a picture of \(words)…", 0.3)
                if let name = await Director.findReference(words, into: w) {
                    p.source = name; p.nextFocus = c.keep
                    if let r = try? await Pipeline.describeSource(w.appendingPathComponent(name), focus: c.keep, config: cfg) { p.sourceNote = r.text; p.sourceNoteFocus = c.keep; p.totalGenerationCostUSD += r.cost }
                }
            }
            if !p.cast.isEmpty {
                bh("Drawing the cast sheet (the people and things every picture keeps the same)…", 0.6)
                _ = try? await Pipeline.makeCastSheet(plan: &p, work: w, config: cfg)
            }
            self.plan = p; self.persist()
            bh("Done", 1)
            let all = Array(-1..<p.sections.count)
            self.drawThenPreview(all, work: w)
        }
    }
    func drawThenPreview(_ targets: [Int], work: URL) {
        drawSections(targets, work: work, titlePrefix: "Drawing \(targets.count) picture\(targets.count == 1 ? "" : "s")") { [weak self] in
            self?.showFullPreview = true
            self?.notice = "Everything is drawn. This is the preview of your video: watch it, change any picture you like, then press “Make my video”."
        }
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
            if let idea = t.pictures[-1], !p.intro.promptManual { p.intro.prompt = idea; p.intro.focal = []; p.intro.logicNote = nil }
            for i in p.sections.indices where !p.sections[i].promptManual { if let idea = t.pictures[i] { p.sections[i].prompt = idea; p.sections[i].focal = []; p.sections[i].logicNote = nil } }
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
    /// The director plans the looping video, then you approve its choices.
    func loopDirectorPlan() {
        guard let p0 = loopProject, let d = loopDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        config = Config.load()
        let cfg = config, scenes = loopAutoScenes
        runLoop("The director is planning the video…") { [weak self] p, _ in
            var q = p
            await MainActor.run { self?.loopJob?.phase = "Listening to the words of the songs…" }
            await Director.listen(&q, dir: d, config: cfg)
            await MainActor.run { self?.loopJob?.phase = "The director is planning the scenes…" }
            let (t, cost) = try await Director.looping(q, scenes: scenes, config: cfg)
            q.imagesUSD += cost
            let c = DirectorChoices(style: t.style.isEmpty ? q.style : t.style, brightness: p0.brightness, suggested: t.mood, weather: t.weather, time: t.timeOfDay,
                                    quality: p0.pictureQuality, reference: q.source == nil ? (t.reference ?? "") : "", keep: t.keep, scenes: max(1, min(t.scenes.count, scenes)))
            await MainActor.run { self?.directorReview = DirectorReview(logline: t.logline, summary: t.logline, loop: t, choices: c, hasOwnSource: q.source != nil) }
            return q
        }
    }

    /// Makes the looping video with these choices: the director plans (unless its plan is given), then each scene's picture and clip, then the preview.
    func loopAuto(_ c: DirectorChoices, treatment: LoopTreatment?) {
        guard let d = loopDir else { return }
        config = Config.load()
        let cfg = config, scenes = c.scenes
        runLoop("Automatic: the director is planning the video…", estimate: Double(scenes) * 300) { [weak self] p, _ in
            func phase(_ s: String) async { await MainActor.run { self?.loopJob?.phase = s } }
            var q = p
            var t: LoopTreatment
            if let given = treatment { t = given } else {
                await phase("Automatic: listening to the words of the songs…")
                await Director.listen(&q, dir: d, config: cfg)
                await phase("Automatic: the director is planning the video…")
                let (made, cost) = try await Director.looping(q, scenes: scenes, config: cfg)
                t = made; q.imagesUSD += cost
            }
            var style = c.style
            if treatment == nil { style = t.style }
            if !style.isEmpty { q.style = style }
            q.brightness = c.brightness; q.pictureQuality = c.quality
            q.weather = treatment == nil ? t.weather : c.weather; q.timeOfDay = treatment == nil ? t.timeOfDay : c.time
            let words = treatment == nil ? (t.reference ?? "") : c.reference
            if q.source == nil, !words.trimmingCharacters(in: .whitespaces).isEmpty {
                await phase("Automatic: finding a picture of \(words)…")
                if let name = await Director.findReference(words, into: d) { q.source = name; q.nextFocus = treatment == nil ? t.keep : c.keep }
            }
            var made: [String] = []
            for (k, scene) in t.scenes.prefix(scenes).enumerated() {
                let n = "scene \(k + 1) of \(min(scenes, t.scenes.count))"
                q.scene = scene
                await phase("Automatic: drawing the picture for \(n)…")
                if k == 0 { try await LoopVideo.makePicture(&q, dir: d, config: cfg) } else { q.sceneDrawn = nil; try await LoopVideo.makeNextPicture(&q, dir: d, config: cfg) }
                await phase("Automatic: looking at what should move in \(n)…")
                await LoopVideo.refreshMotion(&q, dir: d, config: cfg)
                await phase("Automatic: HeyGen is making the clip for \(n) (a few minutes)…")
                try await LoopVideo.makeClip(&q, dir: d, config: cfg) { ph in Task { @MainActor in self?.loopJob?.phase = "Automatic, \(n): " + ph } }
                if let c = q.clip { made.append(c) }
                LoopVideo.save(q, d)
            }
            if let first = made.first {
                q.clip = first; q.sceneClips = made
                if made.count > 1 && q.sceneChange == .never { q.sceneChange = .both }
                LoopVideo.save(q, d)
                await phase("Automatic: making the loop preview…")
                try await LoopVideo.makePreview(clip: d.appendingPathComponent(first), output: d.appendingPathComponent("preview-" + (first as NSString).deletingPathExtension + ".mp4"), trim: q.trims[first] ?? ClipTrim())
            }
            await MainActor.run { self?.loopAutoFinished = true }
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
        isLoop ? Double(review.choices.scenes) * model.loopScenePrice
               : Double((model.plan?.sections.count ?? 0) + 1 + (review.choices.cast.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)) * (review.choices.quality.estimate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The director's plan").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(review.logline).font(.title3).fixedSize(horizontal: false, vertical: true)
                    if let t = review.song { Text(t.summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if let t = review.loop {
                        ForEach(Array(t.scenes.prefix(review.choices.scenes).enumerated()), id: \.offset) { k, s in Text("Scene \(k + 1): \(s)").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
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
                        Picker("Picture quality", selection: c.quality) { ForEach(PictureQuality.allCases, id: \.self) { Text($0.name).tag($0) } }
                        if review.hasOwnSource {
                            Text("Picture to base it on: your own picture (kept).").foregroundStyle(.secondary)
                        } else {
                            TextField("Picture to base it on (search words, empty = none)", text: c.reference)
                            if !review.choices.reference.trimmingCharacters(in: .whitespaces).isEmpty {
                                Picker("Keep from that picture", selection: c.keep) { ForEach(NextFocus.allCases, id: \.self) { Text($0.name).tag($0) } }
                            }
                        }
                        if !isLoop {
                            TextField("The people and things that stay the same (empty = none)", text: c.cast, axis: .vertical).lineLimit(2...5)
                        } else if let t = review.loop, t.scenes.count > 1 {
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
