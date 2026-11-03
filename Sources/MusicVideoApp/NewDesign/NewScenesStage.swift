// Stage 2 · Scenes for a looping video (design 2g): a scene list, the scene on a canvas, and the same kind of inspector as a music video's pictures.
// A scene is one loop clip. Nothing about how a looping project is saved changes: the list, the songs under each scene and the order
// are the project's existing clips, sceneClips and each song's clip.
import SwiftUI
import MVCore

struct NewScenesStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    @AppStorage("sceneTab") private var tab = "idea"
    @State private var showLook = false
    @State private var confirmAdd = false
    @State private var confirmRemove: String?
    var p: LoopProject { model.loopProject ?? LoopProject() }
    var working: Bool { model.loopJob != nil }
    var shown: String? { p.clip ?? p.clips.first }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Hairline()
            HStack(spacing: 0) {
                sceneList.frame(width: 290)
                VHairline()
                canvas.frame(maxWidth: .infinity)
                VHairline()
                inspector.frame(width: 400)
            }
            footer
        }
        .sheet(isPresented: $showLook) {
            VStack(spacing: 0) {
                LoopView(part: .look)
                CFooter { Text("Same Look panel, versions and picture check as music videos.").font(Classical.body(11)).foregroundStyle(Classical.neutral600) } right: { Button("Done") { showLook = false }.buttonStyle(.classicalPrimary).keyboardShortcut(.defaultAction) }
            }.frame(width: 640, height: 720).background(Classical.bg).environment(\.colorScheme, .light).environmentObject(model)
        }
        .confirmationDialog("Add another scene?", isPresented: $confirmAdd, titleVisibility: .visible) {
            Button("Add it (≈ \(OpenRouter.formatUSD(model.loopAddScenePrice)))") { model.loopAddScene() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app draws the next picture (about \(OpenRouter.formatUSD(model.perImageCostUSD))), then HeyGen makes its clip (about \(OpenRouter.formatUSD(model.loopClipPrice)) at list price). It takes a few minutes; you can keep working. The new scene joins the video automatically.")
        }
        .confirmationDialog("Remove this scene?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button("Remove it", role: .destructive) { if let c = confirmRemove { removeScene(c) } }
            Button("Keep it", role: .cancel) {}
        } message: { Text("Its songs go back to Auto. The clip file stays on disk, and Undo brings the scene back.") }
    }

    // MARK: toolbar
    var toolbar: some View {
        HStack(spacing: 10) {
            Button { showLook = true } label: { HStack(spacing: 5) { Image(systemName: "paintpalette").font(.system(size: 11)); Text("Look") } }.buttonStyle(.classicalSmall)
                .help("Art style, quality, brightness, weather, time of day, shot, the picture to base it on, cloudless sky and what moves.")
            Menu {
                Button("Direct the rest (≈ \(OpenRouter.formatUSD(model.loopAutoPrice)))") { model.loopAutoAsk() }
                Button("Plan with the director, then I approve…") { model.loopDirectorPlan() }
            } label: { HStack(spacing: 5) { Image(systemName: "wand.and.stars").font(.system(size: 11)); Text("Director…") } }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().font(Classical.body(12)).padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.neutral300, lineWidth: 1)).disabled(working || p.tracks.isEmpty)
            Rectangle().fill(Classical.divider).frame(width: 1, height: 18)
            Text("Scenes change").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
            Menu {
                ForEach(LoopSceneChange.allCases, id: \.self) { c in Button(c.name) { model.editLoop { $0.sceneChange = c } } }
            } label: { Text(p.sceneChange.name).font(Classical.body(12, weight: .semibold)) }
                .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                .help("One clip: the clip shown plays all through. At each song change: each song has its own scene. Every few minutes: the scenes play in the order shown. Changes are a slow cross-fade; the music never changes because of them.")
            if p.sceneChange == .time {
                Stepper("every \(Int(p.sceneMinutes)) min", value: Binding(get: { p.sceneMinutes }, set: { v in model.editLoop { $0.sceneMinutes = v } }), in: 1...60, step: 1).fixedSize().font(Classical.body(12))
            }
            Spacer()
            Button { confirmAdd = true } label: { Text("+ Add a scene  ≈ \(OpenRouter.formatUSD(model.loopAddScenePrice))") }.buttonStyle(.classicalSmall)
                .disabled(working || p.picture == nil || p.clip == nil).help(p.clip == nil ? "Make the first scene's clip first." : "Draws the next picture (the same place, building or subject, something new), makes its clip, and adds it to the video. You see the price first.")
        }.padding(.horizontal, 20).padding(.vertical, 9).background(Classical.bg)
    }

    // MARK: the scene list
    var sceneList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if p.clips.isEmpty { emptyRow }
                    ForEach(Array(p.clips.enumerated()), id: \.element) { i, c in row(i, c); Hairline() }
                }
            }
            if let hint = changeHint {
                Hairline()
                Text(hint).font(Classical.body(11)).foregroundStyle(Classical.accent800).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Classical.accent100)
            }
        }.background(Classical.bg)
    }
    var emptyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scene 1").font(Classical.heading(18))
            Text("No clip yet. Describe the scene, draw its picture, then make its clip (right).").font(Classical.body(11)).foregroundStyle(Classical.neutral700)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Classical.accent100)
            .overlay(alignment: .leading) { Rectangle().fill(Classical.accent).frame(width: 3) }
    }
    func row(_ i: Int, _ c: String) -> some View {
        let selected = c == shown
        let order = LoopVideo.sceneClips(p), inVideo = order.contains(c)
        return Button { select(c) } label: {
            HStack(spacing: 10) {
                ZStack { Color.black; if let d = model.loopDir, let t = LoopVideo.clipThumbnail(c, dir: d) { Thumb(file: t) } }
                    .frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(LoopVideo.sceneName(p, c)).font(Classical.heading(18))
                    Text(subtitle(c, inVideo: inVideo, order: order)).font(Classical.body(11)).foregroundStyle(inVideo || p.sceneChange == .never ? Classical.neutral700 : Classical.neutral500).lineLimit(2)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(working)
            .background(selected ? Classical.accent100 : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(selected ? Classical.accent : .clear).frame(width: 3) }
            .help("Look at this scene.")
    }
    /// "songs 1–3", "plays 2nd", or "not used".
    func subtitle(_ c: String, inVideo: Bool, order: [String]) -> String {
        switch p.sceneChange {
        case .songs:
            let n = zip(p.tracks.indices, LoopVideo.songClips(p)).filter { $0.1.clip == c }.map { $0.0 + 1 }
            return n.isEmpty ? "no song · Auto may use it" : "under " + Self.songWords(n)
        case .time:
            guard let k = order.firstIndex(of: c) else { return "not in the order" }
            return "plays \(Self.ordinal(k + 1)) of \(order.count)"
        case .never: return c == p.clip ? "the clip the video uses" : "not used"
        }
    }
    static func ordinal(_ n: Int) -> String { n == 1 ? "1st" : n == 2 ? "2nd" : n == 3 ? "3rd" : "\(n)th" }
    /// [1, 2, 3, 5] → "songs 1–3, 5"
    static func songWords(_ n: [Int]) -> String {
        var parts: [String] = [], k = 0
        while k < n.count {
            var j = k; while j + 1 < n.count && n[j + 1] == n[j] + 1 { j += 1 }
            parts.append(j > k ? (j == k + 1 ? "\(n[k]), \(n[j])" : "\(n[k])–\(n[j])") : "\(n[k])"); k = j + 1
        }
        return (n.count == 1 ? "song " : "songs ") + parts.joined(separator: ", ")
    }
    var changeHint: String? {
        guard p.sceneChange != .never, p.clip != nil, let plan = model.loopPlan else { return nil }
        let have = Set(LoopVideo.sceneStarts(p, plan: plan).map(\.clip)).count, wanted = LoopVideo.scenesWanted(p, plan: plan)
        let changes = LoopVideo.sceneChangeTimes(p, plan: plan).count
        if changes == 0 { return "No scene changes at this length." }
        if have < wanted { return have <= 1 ? "This video changes scene \(changes) time\(changes == 1 ? "" : "s") but has one scene, so it stays the same picture. Add another scene." : "This video changes scene \(changes) times and has \(have) scenes. \(wanted) would look best." }
        return nil
    }

    func select(_ c: String) {
        model.editLoop { q in
            // looking at another scene must not change what plays: a video with no list yet plays the clip that was in use, so keep it in the list
            if q.sceneChange != .never, q.sceneClips.isEmpty, let cur = q.clip { q.sceneClips = [cur] }
            q.clip = c
        }
        if let u = model.loopPreviewURL(for: c), !FileManager.default.fileExists(atPath: u.path) { model.loopMakePreview(c) }
    }
    func removeScene(_ c: String) {
        model.editLoop { q in
            q.clips.removeAll { $0 == c }; q.sceneClips.removeAll { $0 == c }
            for k in q.tracks.indices where q.tracks[k].clip == c { q.tracks[k].clip = nil }
            if q.clip == c { q.clip = q.clips.first }
        }
    }

    // MARK: canvas
    var canvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shown.map { LoopVideo.sceneName(p, $0) } ?? "Scene 1").font(Classical.heading(26))
                    if let c = shown { Text(subtitle(c, inVideo: LoopVideo.sceneClips(p).contains(c), order: LoopVideo.sceneClips(p))).font(Classical.body(12)).foregroundStyle(Classical.neutral600) }
                    Spacer()
                    if let c = shown, p.clips.contains(c) { CLink(title: "Remove scene") { confirmRemove = c }.disabled(working) }
                }
                player
                Text(p.clip != nil ? "loop clip · plays seamlessly" : (p.picture != nil ? "picture · the clip starts from it" : "")).font(Classical.italic(11)).foregroundStyle(Classical.neutral600)
                HStack(spacing: 8) {
                    Button { model.loopPreview(.start) } label: { Text("▷ Watch the start").fixedSize() }.buttonStyle(.classicalSmall)
                    Button { model.loopPreview(.change) } label: { Text("▷ The change").fixedSize() }.buttonStyle(.classicalSmall)
                    Button { model.loopPreview(.end) } label: { Text("▷ The end").fixedSize() }.buttonStyle(.classicalSmall)
                    Spacer()
                }.disabled(working || p.clip == nil || p.tracks.isEmpty)
                if let c = shown, p.clips.contains(c) { placement(c) }
            }.padding(20)
        }.background(Classical.bg)
    }
    @ViewBuilder var player: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.85))
            if let c = p.clip, let u = model.loopPreviewURL(for: c), FileManager.default.fileExists(atPath: u.path) {
                LoopingPlayer(url: u)
                Color.clear.contentShape(Rectangle()).onTapGesture { FullScreenPlayer.show(u, title: "The loop – \(p.title)", loop: true, muted: true) }.help("Click to watch it full screen and zoom in on any part.")
            } else if p.clip != nil {
                VStack(spacing: 6) { ProgressView().controlSize(.small); Text("Preparing the preview…").font(Classical.body(11)).foregroundStyle(.white.opacity(0.8)) }
            } else if let u = model.loopFile(p.picture) {
                Thumb(file: u).onTapGesture { FullScreenPlayer.showImage(u, title: "Picture") }.help("Click to see the picture full screen and zoom in.")
            } else {
                Text("Describe the scene on the right, then draw its picture.").font(Classical.body(12)).foregroundStyle(.white.opacity(0.7))
            }
        }.aspectRatio(16.0 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 3)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Classical.divider, lineWidth: 1))
    }
    /// Where this scene plays: the songs under it, or its place in the order.
    @ViewBuilder func placement(_ c: String) -> some View {
        let order = LoopVideo.sceneClips(p), k = order.firstIndex(of: c)
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            switch p.sceneChange {
            case .songs:
                Text("Plays under").font(Classical.body(12, weight: .semibold)).foregroundStyle(Classical.neutral800)
                if p.tracks.isEmpty { Text("Add songs on the Music stage.").font(Classical.body(11)).foregroundStyle(Classical.neutral600) }
                else {
                    let tied = LoopVideo.songClips(p)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(Array(p.tracks.enumerated()), id: \.element.id) { n, t in
                            let mine = tied.indices.contains(n) && tied[n].clip == c, auto = tied.indices.contains(n) && tied[n].auto
                            Button { assign(n, to: c, on: !mine) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mine ? "checkmark.square.fill" : "square").foregroundStyle(mine ? Classical.accent : Classical.neutral500)
                                    Text("\(n + 1)  \(t.title)").font(Classical.body(11)).lineLimit(1).truncationMode(.tail)
                                    if !mine, !auto, tied.indices.contains(n), let other = tied[n].clip { Text(LoopVideo.sceneName(p, other)).font(Classical.body(10)).foregroundStyle(Classical.neutral500) }
                                }.padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(mine ? Classical.accent : Classical.divider, lineWidth: 1))
                            }.buttonStyle(.plain).disabled(working)
                                .help(mine ? "Click to take this song off the scene (it goes back to Auto)." : "Show this scene under “\(t.title)”.")
                        }
                    }
                }
            case .time:
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(get: { k != nil }, set: { v in setInOrder(c, v) })) { Text("In the order").font(Classical.body(12)) }.toggleStyle(.checkbox)
                        .disabled(working || (k != nil && order.count <= 1))
                    if let k {
                        CLink(title: "Move earlier") { moveScene(c, to: k - 1) }.disabled(k == 0 || working)
                        CLink(title: "Move later") { moveScene(c, to: k + 1) }.disabled(k >= order.count - 1 || working)
                    }
                }
            case .never:
                Text(c == p.clip ? "This is the clip the whole video uses." : "Pick this scene to use it for the whole video.").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            }
        }
    }
    func assign(_ n: Int, to c: String, on: Bool) {
        model.editLoop { q in
            LoopVideo.pinSongClips(&q)
            guard q.tracks.indices.contains(n) else { return }
            q.tracks[n].clip = on ? c : nil
            if on { var l = LoopVideo.sceneClips(q); if !l.contains(c) { l.append(c); q.sceneClips = l } }
        }
    }
    func setInOrder(_ c: String, _ on: Bool) {
        model.editLoop { q in
            var l = LoopVideo.sceneClips(q)
            if on { if !l.contains(c) { l.append(c) } } else if l.count > 1 { l.removeAll { $0 == c } }
            q.sceneClips = l
        }
    }
    func moveScene(_ c: String, to k: Int) {
        model.editLoop { q in var l = LoopVideo.sceneClips(q); l.removeAll { $0 == c }; l.insert(c, at: max(0, min(k, l.count))); q.sceneClips = l }
    }

    // MARK: inspector
    var inspector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ForEach([("idea", "Idea"), ("clip", "Clip"), ("versions", "Versions\(p.pictures.count > 1 ? " \(p.pictures.count)" : "")")], id: \.0) { id, t in
                    Button { tab = id } label: {
                        Text(t).font(Classical.body(13, weight: tab == id ? .semibold : .regular)).foregroundStyle(tab == id ? Classical.text : Classical.neutral600)
                            .padding(.bottom, 4).overlay(alignment: .bottom) { Rectangle().fill(tab == id ? Classical.accent : .clear).frame(height: 2) }
                    }.buttonStyle(.plain)
                }
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 14).overlay(alignment: .bottom) { Hairline().offset(y: 1) }
            LoopView(part: tab == "clip" ? .sceneClip : (tab == "versions" ? .sceneVersions : .sceneIdea)).id(tab).padding(.horizontal, 16)
        }.background(Classical.bg)
    }

    // MARK: footer
    var footer: some View {
        CFooter {
            let n = p.clips.count
            Text(n == 0 ? "No scene has a clip yet" : "\(n) scene\(n == 1 ? "" : "s") with a clip").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
        } right: {
            Button { model.loopPreview(.start) } label: { Text("▷ Preview") }.buttonStyle(.classical).disabled(working || p.clip == nil || p.tracks.isEmpty)
            Button("Continue to Shorts →") { nd.route = .shorts }.buttonStyle(.classicalPrimary)
        }
    }
}
