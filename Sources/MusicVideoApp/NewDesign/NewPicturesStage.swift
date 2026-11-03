// Stage 2 · Pictures. Design 2d: the list, the picture and an inspector (default). 2e is the same stage as a storyboard and 2f as a board of
// every picture; the layout switch in the toolbar changes between them. Every per-picture option lives in the inspector (3a, 3b).
import SwiftUI
import UniformTypeIdentifiers
import MVCore

struct NewPicturesStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    @AppStorage("picturesLayout") private var layout = "list"            // list (2d), storyboard (2e), board (2f)
    @AppStorage("picturesTimeline") private var timelineOpen = false
    @State private var showLook = false
    @State private var confirmMissing = false
    @State private var confirmClips = false
    @State private var boardInspector = false

    var plan: Plan? { model.plan }
    var body: some View {
        if model.stage == .loop { NewScenesStage() }
        else if let plan, model.workDir != nil {
            VStack(spacing: 0) {
                toolbar(plan)
                Hairline()
                if timelineOpen { ScaledTimeline().padding(.horizontal, 20).padding(.vertical, 6); Hairline() }
                Group {
                    switch layout {
                    case "storyboard": NewStoryboardLayout()
                    case "board": NewBoardLayout(openInspector: $boardInspector)
                    default: NewListLayout()
                    }
                }
                NewPicturesFooter()
            }
            .sheet(isPresented: $showLook) { NewLookPanel().environmentObject(model) }
            .sheet(isPresented: $model.showFullPreview, onDismiss: { model.live.pause() }) { PreviewSheet(title: plan.title).environmentObject(model) }
            .onChange(of: model.requestRegenAll) { _, v in if v { model.requestRegenAll = false } }
            .sheet(isPresented: $model.showOpenRouterKeySheet) { OpenRouterKeySheet().environmentObject(model) }
            .alert("Notice", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.notice ?? "") }
            .confirmationDialog("Draw the \(model.missing.count) missing picture\(model.missing.count == 1 ? "" : "s")?", isPresented: $confirmMissing, titleVisibility: .visible) {
                Button("Draw \(model.missing.count) (≈ \(OpenRouter.formatUSD(model.missingImagesCostUSD)))") { model.generateAllMissingImages() }
                Button("Not now", role: .cancel) {}
            } message: { Text("About \(OpenRouter.formatUSD(model.missingImagesCostUSD)) in total." + (model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? "")) }
            .confirmationDialog("Make a video clip for every picture?", isPresented: $confirmClips, titleVisibility: .visible) {
                Button("Make \(model.clipTargets.count) clip\(model.clipTargets.count == 1 ? "" : "s") (≈ \(OpenRouter.formatUSD(model.allClipsPriceUSD)))") { model.startAllClips() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("One clip (5–15 s) for each picture that has none, at the list price of \(OpenRouter.formatUSD(model.videoPricePerSecond)) per second. Each clip plays once, then the camera moves over its last picture. You see the price before anything is made.") }
            .task { model.refreshVideoPrice() }
        } else { NewMusicSongStage() }
    }

    func toolbar(_ plan: Plan) -> some View {
        HStack(spacing: 10) {
            Button { showLook = true } label: { HStack(spacing: 5) { Image(systemName: "paintpalette").font(.system(size: 11)); Text("Look") } }.buttonStyle(.classicalSmall)
                .help("Art style, setting, quality, brightness, weather, time of day and shot: everything that affects every picture.")
            Menu {
                Button("Direct the rest (≈ \(OpenRouter.formatUSD(model.autoSongPrice)))") { model.autoDirect() }
                Button("Plan with the director, then I approve…") { model.directorPlan() }
                if let t = plan.treatment { Button("The director's plan…") { model.notice = t } }
            } label: { HStack(spacing: 5) { Image(systemName: "wand.and.stars").font(.system(size: 11)); Text("Director…") } }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().font(Classical.body(12)).padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.neutral300, lineWidth: 1))
                .help("A director plans the story and the pictures. Direct the rest does it in one click; the other choice lets you approve its plan first.")
            Spacer(minLength: 6)
            layoutSwitch
            CLink(title: timelineOpen ? "Fold timeline" : "Expand timeline") { withAnimation { timelineOpen.toggle() } }.help("The whole song to scale: drag picture borders and Shorts.")
            Button("Clips for all…") { confirmClips = true }.buttonStyle(.classicalSmall).disabled(model.clipTargets.isEmpty || model.busy || model.clipJob != nil)
                .help("Makes one video clip for every picture that has none. You see the price first.")
            Button { model.hasOpenRouterKey ? (confirmMissing = true) : (model.showOpenRouterKeySheet = true) } label: {
                Text(model.missing.isEmpty ? "All drawn" : "Draw \(model.missing.count) missing  \(OpenRouter.formatUSD(model.missingImagesCostUSD))")
            }.buttonStyle(.classicalPrimary).disabled(model.missing.isEmpty || model.busy)
                .help("Draws a picture for every part that has none. You see the price first, and can cancel at any time.")
        }.padding(.horizontal, 20).padding(.vertical, 9).background(Classical.bg)
    }

    var layoutSwitch: some View {
        HStack(spacing: 0) {
            ForEach([("list", "sidebar.left", "List, picture and inspector"), ("storyboard", "rectangle.split.1x2", "Storyboard: the timeline as one long page"), ("board", "square.grid.3x3", "Board of every picture")], id: \.0) { id, icon, tip in
                Button { layout = id } label: { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(layout == id ? Classical.accent700 : Classical.neutral600).padding(.horizontal, 9).padding(.vertical, 6).background(layout == id ? Classical.accent100 : .clear) }.buttonStyle(.plain).help(tip)
            }
        }.overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
    }
}

/// The finished-video preview (same as the original design's).
struct PreviewSheet: View {
    @EnvironmentObject var model: AppModel
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("Preview — \(title)").font(.headline); Spacer(); Button("Done") { model.showFullPreview = false }.keyboardShortcut(.defaultAction) }
            LivePreviewPane(live: model.live, defaultCaption: 0.075) { v in model.setCaptionY(v, shortID: nil) }
            CaptionTimingBar().environmentObject(model)
            Text("This is exactly what the finished video will look like. Drag the words up or down to move them.").font(.callout).foregroundStyle(.secondary)
        }.padding(20).frame(minWidth: 620, idealWidth: 800, minHeight: 460, idealHeight: 620)
    }
}

struct NewPicturesFooter: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    var body: some View {
        CFooter {
            HStack(spacing: 12) {
                Button { model.openFullPreview() } label: { HStack(spacing: 5) { Image(systemName: "play").font(.system(size: 10)); Text("Preview") } }.buttonStyle(.classical).disabled(model.loadedCount == 0)
                    .help(model.loadedCount == 0 ? "Add at least one picture first." : "Watch the video before it is made. Nothing is saved or changed.")
                Text("\(model.loadedCount) of \(model.totalImages) pictures ready").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
                if let p = model.plan, p.timing != "exact" {
                    Text("·").foregroundStyle(Classical.neutral500)
                    Text("Word timing is rough —").font(Classical.body(12)).foregroundStyle(Classical.accent800)
                    CLink(title: model.resyncing ? "working…" : "fix it") { model.resync() }.disabled(model.resyncing)
                        .help("Listens to the song again to line every word up exactly. Takes about a minute. Your pictures are not touched.")
                }
            }
        } right: {
            Button("Continue to Shorts →") { nd.route = .shorts }.buttonStyle(.classicalPrimary).keyboardShortcut(.return, modifiers: .command)
        }
    }
}

// MARK: 2d · list, picture, inspector

struct NewListLayout: View {
    @EnvironmentObject var model: AppModel
    @State private var showAim = true
    @State private var dropSection: Int?
    var plan: Plan { model.plan! }
    var sel: Int { model.selectedSection }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 238)
            VHairline()
            ScrollView { canvas.padding(20) }.frame(maxWidth: .infinity)
            VHairline()
            NewInspector(section: sel).frame(width: 330)
        }
    }

    var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                if model.canAddInstrumentalIntro, let first = plan.lines.first?.start {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Music before the first words (0:00–\(timeString(first))) has no picture.").font(Classical.body(12)).foregroundStyle(Classical.accent800)
                        CLink(title: "Add a picture for it") { model.addInstrumentalIntro() }.disabled(model.busy)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.accent300, lineWidth: 1)).padding(10)
                }
                NewListRow(index: -1, selected: sel == -1).onTapGesture { model.selectedSection = -1 }
                ForEach(plan.sections.indices, id: \.self) { i in
                    NewListRow(index: i, selected: sel == i).onTapGesture { model.selectedSection = i }
                        .onDrag { NSItemProvider(object: "mv-picture:\(i)" as NSString) }
                        .onDrop(of: [UTType.text], isTargeted: Binding(get: { dropSection == i }, set: { dropSection = $0 ? i : nil })) { providers in
                            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
                            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                                guard let value = value as? String, value.hasPrefix("mv-picture:"), let source = Int(value.dropFirst(11)), source != i else { return }
                                Task { @MainActor in dropSection = nil; model.reassignPicture(from: source, to: i) }
                            }
                            return true
                        }
                        .overlay(alignment: .bottom) { if dropSection == i { Text(plan.sections[i].selectedCandidate == nil ? "Move here" : "Swap pictures").font(Classical.body(11, weight: .semibold)).padding(4).background(Classical.accent100) } }
                        .help("Drag this picture onto another to move it there or swap their artwork. Undo reverses the action.")
                }
            }
        }.background(Classical.bg)
    }

    var canvas: some View {
        let sec = sel < 0 ? plan.intro : plan.sections[min(max(sel, 0), plan.sections.count - 1)]
        return VStack(alignment: .leading, spacing: 12) {
            if model.lyricsMismatch {
                Text("Only \(Int(plan.alignmentCoverage * 100))% of the lyrics were heard in this song. Is it the right MP3?").font(Classical.body(12, weight: .semibold)).foregroundStyle(Classical.warn)
            }
            DropWell(section: sel, maxPictureHeight: 560, pictureOnly: true, aim: $showAim).disabled(model.workingSection == sel)
            HStack(spacing: 14) {
                if let f = sec.selectedCandidate?.fullFile, let w = model.workDir {
                    CLink(title: "View larger") { FullScreenPlayer.showImage(w.appendingPathComponent(f), title: "Picture") }.help("See this picture full screen and zoom in on any part (Esc closes).")
                }
                Button { showAim.toggle() } label: { HStack(spacing: 5) { Image(systemName: showAim ? "checkmark.square" : "square").font(.system(size: 11)); Text("Show the aim and the Shorts crop") }.font(Classical.body(12)) }.buttonStyle(.plain).foregroundStyle(Classical.neutral800)
                Spacer()
                Text("Drag the dot to aim the camera · drop a file to replace").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            }
            words(sec)
        }
    }

    @ViewBuilder func words(_ sec: PhotoSection) -> some View {
        if !sec.lineIDs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sec.lineIDs.filter { plan.lines.indices.contains($0) }, id: \.self) { li in
                    let line = plan.lines[li]
                    HStack(spacing: 8) {
                        Button { model.playRange(max(0, line.start - 0.15), line.end + 0.25) } label: { Image(systemName: "play").font(.system(size: 9)) }.buttonStyle(.plain).foregroundStyle(Classical.accent700).help("Listen to this line of the song.")
                        Text(preciseClock(line.start)).font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600).frame(width: 44, alignment: .leading)
                        Text(line.text).font(Classical.italic(13)).lineLimit(1).foregroundStyle(Classical.text)
                        Spacer(minLength: 6)
                        HStack(spacing: 3) { ForEach([("−0.5", -0.5), ("−0.1", -0.1), ("+0.1", 0.1), ("+0.5", 0.5)], id: \.1) { t, d in Button(t) { model.nudgeLine(li, delta: d) }.buttonStyle(.classicalSmall) } }
                            .help("Moves just this line earlier (−) or later (+) in the video. 0.1 s is a tiny nudge.")
                    }.padding(.vertical, 5)
                    Hairline()
                }
            }
        }
    }
}

struct NewListRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int; let selected: Bool
    var body: some View {
        let plan = model.plan!
        let s = index < 0 ? plan.intro : plan.sections[index]
        let c = s.selectedCandidate
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                Rectangle().fill(Color(hex: 0xE4E2E2))
                if let t = c?.thumbFile, let w = model.workDir { Thumb(file: w.appendingPathComponent(t)) } else { Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(Classical.neutral500) }
            }.frame(width: 52, height: 30).clipped().overlay(Rectangle().stroke(Classical.divider, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(String(format: "%02d", index + 1)).font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
                    if c?.checkNote != nil { Text("⚠").font(.system(size: 10)).foregroundStyle(Classical.warn) }
                    if s.useClips && !s.clips.isEmpty { Text("▶ clip").font(Classical.body(10)).foregroundStyle(Classical.accent700) }
                    if s.repeatOf != nil { Text("↺").font(.system(size: 10)).foregroundStyle(Classical.accent700) }
                    Spacer()
                    if index >= 0 { Text(timeString(s.start)).font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600) }
                }
                Text(index < 0 ? plan.title : (s.lineIDs.first.flatMap { plan.lines.indices.contains($0) ? plan.lines[$0].text : nil } ?? "♪ music")).font(Classical.body(12)).lineLimit(2).foregroundStyle(Classical.text)
                if let r = s.repeatOf { Text("same lyrics as \(r + 1)").font(Classical.body(10)).foregroundStyle(Classical.neutral600) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Classical.accent100 : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(selected ? Classical.accent : .clear).frame(width: 2) }
        .contentShape(Rectangle())
    }
}
