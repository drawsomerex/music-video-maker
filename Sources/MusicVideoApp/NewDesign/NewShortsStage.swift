// Stage 3 · Shorts (design 3e): its own stage in the same shell. The list of Shorts on the left, one editor for the chosen Short, and its
// preview and look on the right. Shorts are made with the video in Export (or one at a time here, free, on this Mac).
import SwiftUI
import MVCore

struct NewShortsStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    var body: some View {
        if model.stage == .loop { NewLoopShortsStage() }
        else if model.plan == nil { NewMusicSongStage() }
        else {
            VStack(spacing: 0) {
                if model.plan?.shorts.isEmpty ?? true { empty } else {
                    HStack(spacing: 0) {
                        rail.frame(width: 190)
                        VHairline()
                        if let c = model.currentShort { NewShortEditor(clip: c).id(c.id) } else { Color.clear }
                    }
                }
                CFooter {
                    let n = model.plan?.shorts.count ?? 0
                    Text("\(n) Short\(n == 1 ? "" : "s") · made with the video in Export · 3:00 limit each").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                } right: {
                    Button("Skip Shorts") { model.autoRenderShorts = false; nd.route = .export }.buttonStyle(.classical).help("Go straight to Export without making Shorts.")
                    Button("Continue to Export →") { nd.route = .export }.buttonStyle(.classicalPrimary).keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear { if model.selectedShort == nil { model.selectedShort = model.plan?.shorts.first?.id } }
        }
    }

    var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array((model.plan?.shorts ?? []).enumerated()), id: \.element.id) { i, c in
                        let on = c.id == model.selectedShort
                        Button { model.selectedShort = c.id; model.stopPlayback(); model.refreshPreview(at: 1) } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(i + 1)").font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
                                Text(c.name).font(Classical.body(12)).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 2)
                                Text("\(Int(c.duration)) s").font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
                            }.padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(on ? Classical.accent100 : .clear).overlay(alignment: .leading) { Rectangle().fill(on ? Classical.accent : .clear).frame(width: 2) }
                        }.buttonStyle(.plain).help("\(c.name): \(clock(c.start)) to \(clock(c.end))")
                            .contextMenu { Button("Delete this Short", role: .destructive) { model.deleteShort(c.id) } }
                    }
                }
            }
            Hairline()
            Menu {
                Button("Cut for me (4–7 of about 30 s)") { model.autoMakeShorts(replaceExisting: true) }
                Button("Choose lines (about 30 s from the first words)") { model.newShort() }
                Button("Whole song (split into parts if over 3:00)") { model.newWholeSong() }
            } label: { Text("+ Add a Short ⌄").font(Classical.body(12)).foregroundStyle(Classical.accent700) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).padding(12).help("Add another Short: cut the song automatically, start one yourself, or use the whole song.")
            if let n = model.plan?.shorts.count, n > 1 {
                Button("Make all \(n) now") { model.renderAllShorts() }.buttonStyle(.classicalSmall).padding(.horizontal, 12).padding(.bottom, 12).disabled(model.shortProgress != nil)
                    .help("Makes every Short in the list, one after another. Free, on this Mac.")
            }
        }.background(Classical.bg)
    }

    var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            ClassicalHeading(text: "Make YouTube Shorts", size: 30)
            Text("Short vertical videos for phones, up to 3 minutes each. Let the app cut your song into 4 to 7 Shorts of about 30 seconds, or choose the exact lines yourself. You can skip this stage.")
                .font(Classical.body(13)).foregroundStyle(Classical.neutral700).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button("Cut my song into Shorts for me") { model.autoMakeShorts() }.buttonStyle(.classicalPrimary).help("The app picks 4 to 7 Shorts of about 30 seconds, cut at natural pauses between verses. You can still change each one.")
                Button("Choose the lines myself") { model.newShort() }.buttonStyle(.classical)
                Button("Whole song") { model.newWholeSong() }.buttonStyle(.classical)
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }
}

struct NewShortEditor: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    @State private var previewT = 1.0
    @State private var cursor: Double?
    @State private var edge: ShortEdge = .start
    @State private var showWords = false
    var plan: Plan { model.plan! }
    var c: ShortClip { model.currentShort ?? clip }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView { main.padding(22) }.frame(maxWidth: .infinity)
            VHairline()
            ScrollView { side.padding(18) }.frame(width: 350)
        }
        .onChange(of: c.start) { model.refreshPreview(at: previewT) }
        .onChange(of: c.end) { model.refreshPreview(at: previewT) }
        .onAppear { model.refreshPreview(at: previewT) }
        .onDisappear { model.stopPlayback() }
        .sheet(isPresented: $showWords) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("All the words of the song").font(.title2.bold()); Spacer(); Button("Done") { showWords = false }.keyboardShortcut(.defaultAction) }
                WordTimeline(clip: clip, cursor: $cursor)
            }.padding(20).frame(minWidth: 760, idealWidth: 900)
        }
    }

    // MARK: left
    var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("Name", text: Binding(get: { c.name }, set: { n in model.update(clip.id) { $0.name = n } })).textFieldStyle(.plain).font(Classical.heading(24)).frame(maxWidth: 280)
                    .help("A name for this Short. It becomes the file name.")
                Text(String(format: "%.1f s", c.duration)).font(Classical.body(12).monospacedDigit().weight(.semibold)).foregroundStyle(Classical.accent700)
                Text(ShortLength.message(c.duration)).font(Classical.body(11)).foregroundStyle(Classical.neutral600).lineLimit(1)
                Spacer()
                Text("\(clock(c.start)) → \(clock(c.end))").font(Classical.body(12).monospacedDigit()).foregroundStyle(Classical.neutral600)
            }
            SongMap(clip: clip, cursor: $cursor)
            HStack(spacing: 18) {
                edgeTab(.start, "Where it starts", c.start); edgeTab(.end, "Where it ends", c.end)
                Spacer()
            }
            EdgeCard(clip: clip, isStart: edge == .start)
            HStack(spacing: 10) {
                Button { if model.playhead != nil { model.stopPlayback() } else { model.playRange(c.start, c.end) } } label: { HStack(spacing: 5) { Image(systemName: model.playhead == nil ? "play" : "stop").font(.system(size: 10)); Text(model.playhead == nil ? "Play the Short" : "Stop") } }
                    .buttonStyle(.classicalPrimary).keyboardShortcut(.space, modifiers: []).help("Plays the Short from its start to its end. The space bar does the same.")
                Button(model.looping ? "Stop repeating" : "Repeat") { model.toggleLoop(c.start, c.end) }.buttonStyle(.classical).keyboardShortcut("l", modifiers: []).help("Plays the Short over and over so you can hear whether the ends sound right. Keyboard: L.")
                Button("Browse the words") { showWords = true }.buttonStyle(.classical).help("Every word of the song along a timeline. Click a word to hear from there and start or end the Short at it.")
                Button("Make it ~30 s") { model.extendSelection(clip.id, seconds: 30) }.buttonStyle(.classical).help("Keeps where it starts and adds lyric lines until the Short is about 30 seconds long.")
                Spacer()
                Text("Sticks to").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
                HStack(spacing: 0) { ForEach(AppModel.SnapMode.allCases, id: \.self) { m in
                    Button { model.snapMode = m } label: { Text(m.rawValue).font(Classical.body(11)).foregroundStyle(model.snapMode == m ? Classical.accent700 : Classical.neutral700).padding(.horizontal, 8).padding(.vertical, 5).background(model.snapMode == m ? Classical.accent100 : .clear) }.buttonStyle(.plain)
                } }.overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                    .help("Smart: sticks to a word edge while words are sung and to the beat in music-only parts. Beats, Words, or Off.")
            }
        }
    }
    func edgeTab(_ e: ShortEdge, _ t: String, _ v: Double) -> some View {
        Button { edge = e } label: {
            HStack(spacing: 6) { Text(t).font(Classical.body(13, weight: edge == e ? .semibold : .regular)); Text(clock(v)).font(Classical.body(13).monospacedDigit()) }
                .foregroundStyle(edge == e ? Classical.text : Classical.neutral600).padding(.bottom, 4).overlay(alignment: .bottom) { Rectangle().fill(edge == e ? Classical.accent : .clear).frame(height: 2) }
        }.buttonStyle(.plain)
    }

    // MARK: right
    var side: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(plan.title).font(Classical.italic(12)).foregroundStyle(Classical.neutral600).lineLimit(1); Spacer(); if model.live.preparing { ProgressView().controlSize(.mini) } }
            LivePreviewPane(live: model.live, defaultCaption: 0.20) { v in model.setCaptionY(v, shortID: clip.id) }
            Text("Live preview. Drag the words up or down.").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            CaptionTimingBar().environmentObject(model)
            Hairline()
            row("Look") { chip("Lively", c.dynamic) { set { $0.dynamic = true } }; chip("Simple", !c.dynamic) { set { $0.dynamic = false } } }
            HStack(spacing: 8) {
                Text("Title").font(Classical.body(12, weight: .semibold)).frame(width: 60, alignment: .leading)
                TextField("blank = song title", text: Binding(get: { c.hook }, set: { v in set { $0.hook = v; if !v.isEmpty { $0.dynamic = true } } })).textFieldStyle(.plain).font(Classical.body(12))
                    .padding(6).background(Classical.paper).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                CLink(title: "Suggest") { model.writeHook(clip.id) }.disabled(model.hookBusy || model.busy).help("The AI reads this Short's words and suggests a short, catchy opening title.")
            }
            row("Words") { ForEach([("pill", "Pill"), ("pop", "Pop"), ("stack", "Big"), ("sweep", "Sweep"), ("auto", "Surprise")], id: \.0) { k in chip(k.1, c.textStyle == k.0) { set { $0.textStyle = k.0; $0.dynamic = true } } } }
            HStack(spacing: 8) {
                Text("Colour").font(Classical.body(12, weight: .semibold)).frame(width: 60, alignment: .leading)
                ForEach(ShortStyle.swatches, id: \.name) { s in
                    Button { set { $0.accent = s.name; $0.dynamic = true } } label: { Circle().fill(Color(red: s.r, green: s.g, blue: s.b)).frame(width: 18, height: 18).overlay(Circle().stroke(c.accent == s.name ? Classical.accent : Classical.neutral300, lineWidth: c.accent == s.name ? 2 : 1)) }.buttonStyle(.plain).help(s.name)
                }
                chip("Auto", c.accent == "Auto") { set { $0.accent = "Auto"; $0.dynamic = true } }
            }
            row("Motion") { chip("Calm", c.motion != "punchy") { set { $0.motion = "calm" } }; chip("Punchy", c.motion == "punchy") { set { $0.motion = "punchy" } } }
            row("Beat pulse") { chip("On", c.pulse) { set { $0.pulse = true } }; chip("Off", !c.pulse) { set { $0.pulse = false } } }
            VStack(alignment: .leading, spacing: 4) {
                Text("Ending").font(Classical.body(12, weight: .semibold))
                TextField("Closing text, e.g. Full song on YouTube ▶", text: Binding(get: { c.cta }, set: { v in model.update(clip.id) { $0.cta = v } })).textFieldStyle(.plain).font(Classical.body(12))
                    .padding(6).background(Classical.paper).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
            }
            HStack(spacing: 14) {
                CLink(title: "Try a different look") { model.shuffleLook(clip.id) }.help("Picks a new random title animation and set of cuts.")
                CLink(title: "Make 3 versions") { model.renderShort(clip.id, variants: 3) }.help("Makes the same Short three times with different looks, so you can see which one people watch longest.")
            }
            Hairline()
            make
        }
    }
    func row<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 6) { Text(t).font(Classical.body(12, weight: .semibold)).frame(width: 60, alignment: .leading); c(); Spacer(minLength: 0) }
    }
    func chip(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(Classical.body(11)).foregroundStyle(on ? Classical.accent700 : Classical.neutral800).padding(.horizontal, 8).padding(.vertical, 4).background(on ? Classical.accent100 : .clear)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Classical.accent : Classical.neutral300, lineWidth: 1)) }.buttonStyle(.plain)
    }
    func set(_ f: @escaping (inout ShortClip) -> Void) { model.update(clip.id, f); model.refreshPreview(at: previewT) }

    @ViewBuilder var make: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.shortProgress == nil, let out = model.shortOutput {
                HStack(spacing: 12) { CLink(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([out]) }; ShareLink(item: out) { Text("Share").font(Classical.body(12)).foregroundStyle(Classical.accent700) } }
            }
            if model.shortProgress == nil, let v = model.shortVideoURL(clip), FileManager.default.fileExists(atPath: v.path) {
                YouTubeFilesRow(files: YouTubeKit.shortFiles(video: v), busy: model.youtubeBusy, vertical: true) { model.remakeShortYouTube(clip) }
            }
            Button { model.renderShort(clip.id) } label: { HStack { Text("Make just this Short"); Spacer(); Text("free · on this Mac").font(Classical.body(11)) }.frame(maxWidth: .infinity) }
                .buttonStyle(.classicalPrimary).disabled(model.shortProgress != nil).help("Creates the finished vertical video for this clip.")
        }
    }
}

struct NewLoopShortsStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    var body: some View {
        VStack(spacing: 0) {
            LoopView(part: .shorts)
            CFooter { Text("One Short per song · 3:00 limit each").font(Classical.body(12)).foregroundStyle(Classical.neutral600) } right: {
                Button("Skip Shorts") { nd.route = .export }.buttonStyle(.classical)
                Button("Continue to Export →") { nd.route = .export }.buttonStyle(.classicalPrimary)
            }
        }
    }
}
