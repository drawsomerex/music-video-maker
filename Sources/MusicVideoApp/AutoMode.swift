// Automatic mode: the director plans the whole video (the story, the style, a reference picture if one helps, every picture idea), you see the price,
// and the app draws everything and opens the preview. For a looping video it also makes the clips.
import SwiftUI
import MVCore

/// A price to agree to before Automatic mode spends anything more.
struct AutoAsk: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let choices: [(label: String, run: () -> Void)]
}

extension AppModel {
    // MARK: music video
    /// Plans the open song with the director, then asks before drawing the pictures. Ideas you wrote yourself are kept.
    func autoDirect() {
        guard plan != nil, let w = workDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let cfg = config
        runBackground(initialPhase: "The director is planning the video…") { [weak self] in
            guard let self, let p0 = self.plan else { return }
            let bh = self.busyHandler
            bh("The director is planning the video (the story, the style and every picture)…", 0.2)
            let (t, cost) = try await Director.musicVideo(p0, config: cfg)
            guard var p = self.plan else { return }
            if !t.style.isEmpty { p.style = t.style }
            if let idea = t.pictures[-1], !p.intro.promptManual { p.intro.prompt = idea; p.intro.focal = []; p.intro.logicNote = nil }
            for i in p.sections.indices where !p.sections[i].promptManual { if let idea = t.pictures[i] { p.sections[i].prompt = idea; p.sections[i].focal = []; p.sections[i].logicNote = nil } }
            p.treatment = t.summary; p.totalGenerationCostUSD += cost
            if let words = t.reference {
                bh("Finding a picture of \(words)…", 0.7)
                if let name = await Director.findReference(words, into: w) {
                    p.source = name; p.nextFocus = t.keep
                    if let r = try? await Pipeline.describeSource(w.appendingPathComponent(name), focus: t.keep, config: cfg) { p.sourceNote = r.text; p.sourceNoteFocus = t.keep; p.totalGenerationCostUSD += r.cost }
                }
            }
            self.plan = p; self.persist()
            bh("Done", 1)
            self.askToDrawAll()
        }
    }

    /// The price, then the pictures, then the preview.
    func askToDrawAll() {
        guard let p = plan, let w = workDir else { return }
        let missing = Pipeline.missing(p), all = Array(-1..<p.sections.count)
        let each = perImageCostUSD
        var choices: [(String, () -> Void)] = []
        if !missing.isEmpty { choices.append(("Draw the \(missing.count) missing picture\(missing.count == 1 ? "" : "s") (≈ \(OpenRouter.formatUSD(Double(missing.count) * each)))", { [weak self] in self?.drawThenPreview(missing, work: w) })) }
        if missing.count < all.count { choices.append(("Draw all \(all.count) pictures again (≈ \(OpenRouter.formatUSD(Double(all.count) * each)))", { [weak self] in self?.drawThenPreview(all, work: w) })) }
        autoAsk = AutoAsk(title: "The director's plan is ready",
                          message: (p.treatment.map { $0 + "\n\n" } ?? "") + "Next the pictures are drawn, about \(OpenRouter.formatUSD(each)) each" + (openRouterCredits.map { " (your credit: \(OpenRouter.formatCredits($0)))" } ?? "") + ". Then the preview of the video opens.",
                          choices: choices)
    }
    func drawThenPreview(_ targets: [Int], work: URL) {
        drawSections(targets, work: work, titlePrefix: "Drawing \(targets.count) picture\(targets.count == 1 ? "" : "s")") { [weak self] in
            self?.showFullPreview = true
            self?.notice = "Everything is drawn. This is the preview of your video: watch it, change any picture you like, then press “Make my video”."
        }
    }

    // MARK: looping video
    /// What one scene costs (its picture and its clip).
    var loopScenePrice: Double { perImageCostUSD + loopClipPrice }
    /// Asks how many scenes, with the price, before anything is spent.
    func loopAutoAsk() {
        guard let p = loopProject else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let wanted = max(1, min(3, loopPlan.map { LoopVideo.scenesWanted(p, plan: $0) } ?? 1))
        var choices: [(String, () -> Void)] = [("1 scene (≈ \(OpenRouter.formatUSD(loopScenePrice)))", { [weak self] in self?.loopAuto(scenes: 1) })]
        if wanted > 1 { choices.insert(("\(wanted) scenes (≈ \(OpenRouter.formatUSD(Double(wanted) * loopScenePrice)))", { [weak self] in self?.loopAuto(scenes: wanted) }), at: 0) }
        autoAsk = AutoAsk(title: "Make it all automatically?",
                          message: "The director plans the video (the scenes, the style and, if it helps, a reference photo). Then for each scene the app draws a picture (about \(OpenRouter.formatUSD(perImageCostUSD))) and HeyGen makes its 15-second loop clip (about \(OpenRouter.formatUSD(loopClipPrice)) at list price). It takes a few minutes per scene; then a preview of the video opens." + (openRouterCredits.map { " Your credit: \(OpenRouter.formatCredits($0))." } ?? ""),
                          choices: choices)
    }
    func loopAuto(scenes: Int) {
        config = Config.load()
        let cfg = config
        runLoop("Automatic: the director is planning the video…", estimate: Double(scenes) * 300) { [weak self] p, d in
            func phase(_ s: String) async { await MainActor.run { self?.loopJob?.phase = s } }
            var q = p
            let (t, cost) = try await Director.looping(q, scenes: scenes, config: cfg)
            q.imagesUSD += cost
            if !t.style.isEmpty { q.style = t.style }
            if let words = t.reference {
                await phase("Automatic: finding a picture of \(words)…")
                if let name = await Director.findReference(words, into: d) { q.source = name; q.nextFocus = t.keep }
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
}

/// The price question, with one button per choice.
struct AutoAskModifier: ViewModifier {
    @EnvironmentObject var model: AppModel
    func body(content: Content) -> some View {
        content.confirmationDialog(model.autoAsk?.title ?? "", isPresented: Binding(get: { model.autoAsk != nil }, set: { if !$0 { model.autoAsk = nil } }), titleVisibility: .visible, presenting: model.autoAsk) { a in
            ForEach(Array(a.choices.enumerated()), id: \.offset) { _, c in Button(c.label) { model.autoAsk = nil; c.run() } }
            Button("Not now", role: .cancel) {}
        } message: { a in Text(a.message) }
    }
}
