// Stage 2 · Scenes for a looping video (design 2g): a scene list, the scene on a canvas, and the same kind of inspector as a music video's pictures.
// The list is the scenes in playing order (see LoopSlots.swift): one per song at each song change, as many as you add every few minutes, one for a single clip.
// A scene that has no picture or clip yet is a blank window. The selected scene's idea, picture and clip are the project's own, so every button works on it.
import SwiftUI
import MVCore

struct NewScenesStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    @AppStorage("sceneTab") private var tab = "idea"
    @State private var showLook = false
    @State private var confirmRemove: String?
    @State private var confirmClear: String?
    var p: LoopProject { model.loopProject ?? LoopProject() }
    var working: Bool { model.loopJob != nil }
    var slots: [LoopSlot] { LoopVideo.slots(p) }
    var selected: LoopSlot? { slots.first { $0.id == model.loopSlot } ?? slots.first }
    var selectedIndex: Int { slots.firstIndex { $0.id == selected?.id } ?? 0 }

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
        .onAppear { model.slotSync(adopt: true) }
        .onChange(of: model.loopProject) { _, _ in model.slotSync() }
        .onDisappear { model.slotLeave() }
        .confirmationDialog("Take this scene out?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button("Take it out", role: .destructive) { if let id = confirmRemove { model.slotEdit { LoopVideo.removeSlot(&$0, id: id, focus: $1) } } }
            Button("Keep it", role: .cancel) {}
        } message: { Text("The scenes after it move up. Its picture and clip stay in the project folder, and Undo brings the scene back.") }
        .confirmationDialog("Make this scene blank again?", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } }), titleVisibility: .visible) {
            Button("Make it blank", role: .destructive) { if let id = confirmClear { model.slotEdit { LoopVideo.clearSlot(&$0, id: id, focus: $1) } } }
            Button("Keep it", role: .cancel) {}
        } message: { Text("Its songs borrow the other scenes. The picture and clip stay in the project folder, and Undo brings them back.") }
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
                ForEach(LoopSceneChange.allCases, id: \.self) { c in Button(c.name) { model.slotEdit { q, f in LoopVideo.syncSlots(&q, focus: f); q.sceneChange = c } } }
            } label: { Text(p.sceneChange.name).font(Classical.body(12, weight: .semibold)) }
                .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize().disabled(working)
                .help("At each song change: one scene for each song, in the songs' order. Every few minutes: the scenes you add, played in this order and then again. One clip: a single scene. Changes are a slow cross-fade; the music never changes because of them.")
            if p.sceneChange == .time {
                Stepper("every \(Int(p.sceneMinutes)) min", value: Binding(get: { p.sceneMinutes }, set: { v in model.editLoop { $0.sceneMinutes = v } }), in: 1...60, step: 1).fixedSize().font(Classical.body(12))
            }
            Spacer()
            switch p.sceneChange {
            case .time:
                Text("\(slots.count) scene\(slots.count == 1 ? "" : "s")").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
                Button { if let s = selected { confirmRemove = s.id } } label: { Text("− Take out") }.buttonStyle(.classicalSmall).disabled(working || slots.count <= 1 || selected == nil)
                    .help("Takes the selected scene out of the list.")
                Button { model.slotEdit { LoopVideo.addSlot(&$0, focus: $1) } } label: { Text("+ Add a scene") }.buttonStyle(.classicalSmall).disabled(working)
                    .help("Adds a blank scene at the end. It is free; you draw its picture and make its clip on the right.")
            case .songs: Text("One scene for each of the \(p.tracks.count) song\(p.tracks.count == 1 ? "" : "s")").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
            case .never: EmptyView()
            }
        }.padding(.horizontal, 20).padding(.vertical, 9).background(Classical.bg)
    }

    // MARK: the scene list
    var sceneList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { i, s in row(i, s); Hairline() }
            }
        }.background(Classical.bg)
    }
    func row(_ i: Int, _ s: LoopSlot) -> some View {
        let isSel = s.id == selected?.id
        return Button { model.slotSelect(s.id) } label: {
            HStack(spacing: 10) {
                thumb(s).frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scene \(i + 1)").font(Classical.heading(18))
                    Text(subtitle(i, s)).font(Classical.body(11)).foregroundStyle(s.clip == nil ? Classical.neutral500 : Classical.neutral700).lineLimit(2)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(working)
            .background(isSel ? Classical.accent100 : Color.clear)
            .overlay(alignment: .leading) { Rectangle().fill(isSel ? Classical.accent : .clear).frame(width: 3) }
            .help("Select this scene. Drag it to move it\(p.sceneChange == .songs ? " (its songs move with it)" : "").")
            .draggable(s.id)
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first, id != s.id, !working else { return false }
                model.slotEdit { LoopVideo.moveSlot(&$0, id: id, to: i, focus: $1) }; return true
            }
    }
    /// The scene's clip, else its picture, else a blank window.
    @ViewBuilder func thumb(_ s: LoopSlot) -> some View {
        if let c = s.clip, let d = model.loopDir, let t = LoopVideo.clipThumbnail(c, dir: d) { Thumb(file: t) }
        else if let pic = s.picture, let u = model.loopFile(pic) { Thumb(file: u) }
        else { ZStack { Classical.surface; Image(systemName: "photo").font(.system(size: 14)).foregroundStyle(Classical.neutral500) }.overlay(Rectangle().strokeBorder(Classical.neutral300, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))) }
    }
    /// "song 3 · Title", "songs 2–3", "2nd of 5", or "blank".
    func subtitle(_ i: Int, _ s: LoopSlot) -> String {
        let what = s.clip != nil ? "" : (s.picture != nil ? " · picture only" : " · blank")
        switch p.sceneChange {
        case .songs:
            let n = s.songs.compactMap { id in p.tracks.firstIndex { $0.id == id } }.map { $0 + 1 }.sorted()
            if n.count == 1, let t = p.tracks.first(where: { $0.id == s.songs.first }) { return "song \(n[0]) · \(t.title)" + what }
            return Self.songWords(n) + what
        case .time: return "\(Self.ordinal(i + 1)) of \(slots.count)" + what
        case .never: return "plays all through" + what
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

    // MARK: canvas
    var canvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Scene \(selectedIndex + 1)").font(Classical.heading(26))
                    if let s = selected { Text(subtitle(selectedIndex, s)).font(Classical.body(12)).foregroundStyle(Classical.neutral600) }
                    Spacer()
                    if let s = selected, !s.isBlank { CLink(title: "Make blank") { confirmClear = s.id }.disabled(working) }
                }
                player
                Text(p.clip != nil ? "loop clip · plays seamlessly" : (p.picture != nil ? "picture · make its clip on the right" : "a blank scene · describe it on the right, then draw its picture")).font(Classical.italic(11)).foregroundStyle(Classical.neutral600)
                HStack(spacing: 8) {
                    Button { model.loopPreview(.start) } label: { Text("▷ Watch the start").fixedSize() }.buttonStyle(.classicalSmall)
                    Button { model.loopPreview(.change) } label: { Text("▷ The change").fixedSize() }.buttonStyle(.classicalSmall)
                    Button { model.loopPreview(.end) } label: { Text("▷ The end").fixedSize() }.buttonStyle(.classicalSmall)
                    Spacer()
                }.disabled(working || !slots.contains { $0.clip != nil } || p.tracks.isEmpty)
                if p.picture == nil, selectedIndex > 0, slots[..<selectedIndex].contains(where: { $0.picture != nil }) {
                    CLink(title: "Draw it as the next scene of the one before  ≈ \(OpenRouter.formatUSD(model.perImageCostUSD))") { model.slotDrawFromPrevious() }.disabled(working || !model.hasOpenRouterKey)
                        .help("Keeps the same place, building or subject as the scene before and changes one thing, with a slightly different angle.")
                }
                if let s = selected { placement(s) }
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
                VStack(spacing: 6) { Image(systemName: "photo.badge.plus").font(.system(size: 26)); Text("Blank scene").font(Classical.body(12)) }.foregroundStyle(.white.opacity(0.6))
            }
        }.aspectRatio(16.0 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 3)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Classical.divider, lineWidth: 1))
    }
    /// Where this scene plays and how to move it.
    @ViewBuilder func placement(_ s: LoopSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            switch p.sceneChange {
            case .songs:
                Text(s.songs.count > 1 ? "Plays under these songs" : "Plays under").font(Classical.body(12, weight: .semibold)).foregroundStyle(Classical.neutral800)
                ForEach(s.songs, id: \.self) { id in
                    if let k = p.tracks.firstIndex(where: { $0.id == id }) { Text("\(k + 1)  \(p.tracks[k].title)").font(Classical.body(12)).foregroundStyle(Classical.neutral700) }
                }
                HStack(spacing: 14) {
                    CLink(title: "Move earlier (with its song)") { model.slotEdit { LoopVideo.moveSlot(&$0, id: s.id, to: selectedIndex - 1, focus: $1) } }.disabled(selectedIndex == 0 || working)
                    CLink(title: "Move later") { model.slotEdit { LoopVideo.moveSlot(&$0, id: s.id, to: selectedIndex + 1, focus: $1) } }.disabled(selectedIndex >= slots.count - 1 || working)
                    if s.songs.count > 1 { CLink(title: "Give each song its own scene") { model.slotEdit { LoopVideo.separateSlot(&$0, id: s.id, focus: $1) } }.disabled(working) }
                }
                Text("The scene and its song are tied together, so moving one moves the other. A blank scene borrows the other scenes, taking turns, until you fill it.").font(Classical.body(11)).foregroundStyle(Classical.neutral600).fixedSize(horizontal: false, vertical: true)
            case .time:
                HStack(spacing: 14) {
                    CLink(title: "Move earlier") { model.slotEdit { LoopVideo.moveSlot(&$0, id: s.id, to: selectedIndex - 1, focus: $1) } }.disabled(selectedIndex == 0 || working)
                    CLink(title: "Move later") { model.slotEdit { LoopVideo.moveSlot(&$0, id: s.id, to: selectedIndex + 1, focus: $1) } }.disabled(selectedIndex >= slots.count - 1 || working)
                }
                Text("The scenes play in this order, then start again. A blank scene is skipped until you fill it.").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            case .never:
                Text("This is the clip the whole video uses.").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            }
        }
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
            let b = LoopVideo.blankSlots(p)
            Text(b.blank == 0 ? "\(b.total) scene\(b.total == 1 ? "" : "s"), every one has a clip" : "\(b.blank) of \(b.total) scene\(b.total == 1 ? " has" : "s have") no clip yet").font(Classical.body(12)).foregroundStyle(b.blank == 0 ? Classical.neutral700 : Classical.accent800)
        } right: {
            Button { model.loopPreview(.start) } label: { Text("▷ Preview") }.buttonStyle(.classical).disabled(working || !slots.contains { $0.clip != nil } || p.tracks.isEmpty)
            Button("Continue to Shorts →") { nd.route = .shorts }.buttonStyle(.classicalPrimary)
        }
    }
}
