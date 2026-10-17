// The Shorts editor: one screen, no scrolling.
//   Left:  the clip's name and length, the whole-song map, ONE close-up of the end you are working on (Start / End switch),
//          the nudge buttons, how it finishes, and the play buttons.
//   Right: the vertical preview, the look, and "Make this clip".
import SwiftUI
import MVCore

enum ShortEdge: String { case start = "Start", end = "End" }

struct ShortEditor: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    @State private var previewT = 1.0
    @State private var cursor: Double?
    @State private var edge: ShortEdge = .start
    @State private var showMore = false
    @State private var showWords = false
    var snapshot = false                      // layout pictures only
    init(clip: ShortClip, snapshot: Bool = false, edge: ShortEdge = .start) { self.clip = clip; self.snapshot = snapshot; _edge = State(initialValue: edge) }

    var plan: Plan { model.plan! }
    var c: ShortClip { model.currentShort ?? clip }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                Group {
                    if snapshot { mainColumn.frame(width: geo.size.width - 400) }
                    else { ScrollView { mainColumn.frame(minHeight: geo.size.height - 4, alignment: .top) } }
                }
                Divider()
                sideColumn.frame(minWidth: 300, idealWidth: 380, maxWidth: 420)
            }
        }
        .onChange(of: c.start) { model.refreshPreview(at: previewT) }
        .onChange(of: c.end) { model.refreshPreview(at: previewT) }
        .onAppear { model.refreshPreview(at: previewT) }
        .onDisappear { model.stopPlayback() }
        .sheet(isPresented: $showMore) { ShortMoreOptions(clipID: clip.id).environmentObject(model) }
        .sheet(isPresented: $showWords) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("All the words of the song").font(.title2.bold()); Spacer(); Button("Done") { showWords = false }.help("Close the list of words.").keyboardShortcut(.defaultAction) }
                WordTimeline(clip: clip, cursor: $cursor)
            }.padding(20).frame(minWidth: 760, idealWidth: 900)
        }
    }

    // MARK: left
    var mainColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            SongMap(clip: clip, cursor: $cursor)
            edgePanel
            transport
        }.padding(.horizontal, 20).padding(.vertical, 16)
    }

    var header: some View {
        HStack(spacing: 12) {
            TextField("Name", text: Binding(get: { c.name }, set: { n in model.update(clip.id) { $0.name = n } }))
                .textFieldStyle(.roundedBorder).font(.title3.bold()).frame(maxWidth: 240).help("A name for this clip. It becomes the file name.")
            LengthBadge(duration: c.duration)
            Text(ShortLength.message(c.duration)).font(.callout.weight(.medium)).foregroundStyle(ShortLength.color(c.duration)).lineLimit(1)
            Spacer(minLength: 6)
            Text("\(clock(c.start)) → \(clock(c.end))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    /// The Start / End switch and the close-up of the chosen end.
    var edgePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach([ShortEdge.start, ShortEdge.end], id: \.self) { e in
                    let on = edge == e
                    Button { edge = e } label: {
                        HStack(spacing: 8) {
                            Circle().fill(e == .start ? Color.green : Color.red).frame(width: 10, height: 10)
                            Text(e == .start ? "Where it starts" : "Where it ends").font(.callout.weight(on ? .bold : .regular))
                            Text(clock(e == .start ? c.start : c.end)).font(.callout.monospacedDigit().weight(.bold))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color.primary.opacity(0.10) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? (e == .start ? Color.green : Color.red) : Color.secondary.opacity(0.3), lineWidth: on ? 2 : 1))
                    }.buttonStyle(.plain).help(e == .start ? "Work on where the Short starts." : "Work on where the Short ends, including an instrumental ending.")
                }
                Spacer()
            }
            EdgeCard(clip: clip, isStart: edge == .start)
        }
    }

    var transport: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { playButtons; Spacer(minLength: 6); snapChoice }
            VStack(alignment: .leading, spacing: 8) { HStack(spacing: 10) { playButtons }; snapChoice }
        }
    }
    @ViewBuilder var playButtons: some View {
        Button { playShort() } label: { Label(model.playhead == nil ? "Play the Short" : "Stop", systemImage: model.playhead == nil ? "play.fill" : "stop.fill").frame(minWidth: 110) }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.space, modifiers: [])
            .help("Plays the Short from its start to its end. The space bar does the same; press it again to stop.")
        Button { model.toggleLoop(c.start, c.end) } label: { Label(model.looping ? "Stop repeating" : "Repeat", systemImage: "repeat") }
            .controlSize(.large).keyboardShortcut("l", modifiers: [])
            .help("Plays the Short over and over, starting half a second early, so you can hear whether the ends sound right. Keyboard: L.")
        Button { showWords = true } label: { Label("Browse the words", systemImage: "text.word.spacing") }.controlSize(.large)
            .help("Shows every word of the song along a timeline. Click a word to hear the song from there and start or end the Short at it.")
        Button { model.extendSelection(clip.id, seconds: 30) } label: { Label("Make it ~30 s", systemImage: "arrow.left.and.right") }.controlSize(.large)
            .help("Keeps where it starts and adds lyric lines until the Short is about 30 seconds long.")
    }
    var snapChoice: some View {
        HStack(spacing: 8) {
            Text("Sticks to").font(.callout.weight(.semibold))
            Picker("", selection: $model.snapMode) { ForEach(AppModel.SnapMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 250)
                .help("Smart: sticks to a word edge while words are sung and to the beat in music-only parts. Beats: only the beat. Words: only word edges. Off: stays exactly where you put it. Holding Shift while dragging also turns it off.")
        }
    }
    func playShort() { if model.playhead != nil { model.stopPlayback() } else { model.playRange(c.start, c.end) } }

    // MARK: right
    var sideColumn: some View {
        VStack(spacing: 10) {
            HStack { Text("Preview").font(.callout.weight(.semibold)).foregroundStyle(.secondary); Spacer(); if model.live.preparing { ProgressView().controlSize(.mini) } }
            LivePreviewPane(live: model.live, defaultCaption: 0.20) { v in model.setCaptionY(v, shortID: clip.id) }
            CaptionTimingBar().environmentObject(model).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            lookBox
            Spacer(minLength: 4)
            makeRow
        }.padding(16)
    }

    var lookBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Look").font(.callout.weight(.semibold)).frame(width: 64, alignment: .leading)
                choice("Lively", on: c.dynamic, help: "Adds an opening title, a highlight that follows each word, and smooth picture changes.") { set { $0.dynamic = true } }
                choice("Simple", on: !c.dynamic, help: "Plain pictures with the words at the bottom. No opening title.") { set { $0.dynamic = false } }
                Spacer()
                Button { showMore = true } label: { Label("More", systemImage: "slider.horizontal.3") }
                    .help("Calm or punchy motion, beat pulse, closing text, a new random look and three versions.")
            }
            Group {
                HStack(spacing: 8) {
                    Text("Title").font(.callout.weight(.semibold)).frame(width: 64, alignment: .leading)
                    TextField("blank = \(plan.title)", text: Binding(get: { c.hook }, set: { v in set { $0.hook = v; if !v.isEmpty { $0.dynamic = true } } })).textFieldStyle(.roundedBorder)
                        .help("The big words shown during the first two seconds. Leave empty to use your song title.")
                    Button { model.writeHook(clip.id) } label: { Image(systemName: "sparkles") }.disabled(model.hookBusy || model.busy)
                        .help("Suggest one: the AI reads this clip's words and suggests a short, catchy opening title.")
                }
                HStack(spacing: 6) {
                    Text("Words").font(.callout.weight(.semibold)).frame(width: 64, alignment: .leading)
                    ForEach([("pill", "Pill"), ("pop", "Pop"), ("stack", "Big"), ("sweep", "Sweep"), ("auto", "Surprise")], id: \.0) { k in
                        choice(k.1, on: c.textStyle == k.0, help: wordsHelp(k.0)) { set { $0.textStyle = k.0; $0.dynamic = true } }
                    }
                }
                HStack(spacing: 8) {
                    Text("Colour").font(.callout.weight(.semibold)).frame(width: 64, alignment: .leading)
                    ForEach(ShortStyle.swatches, id: \.name) { s in
                        Button { set { $0.accent = s.name; $0.dynamic = true } } label: {
                            Circle().fill(Color(red: s.r, green: s.g, blue: s.b)).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(c.accent == s.name ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: c.accent == s.name ? 3 : 1))
                        }.buttonStyle(.plain).help(s.name)
                    }
                    choice("Auto", on: c.accent == "Auto", help: "The app picks a colour for you.") { set { $0.accent = "Auto"; $0.dynamic = true } }
                }
            }
        }.font(.callout)
    }
    func set(_ f: @escaping (inout ShortClip) -> Void) { model.update(clip.id, f); model.refreshPreview(at: previewT) }
    func wordsHelp(_ k: String) -> String {
        switch k {
        case "pill": return "A coloured bar follows the word being sung."
        case "pop": return "Each word pops in as it is sung."
        case "stack": return "Large words, a few at a time."
        case "sweep": return "A colour sweeps across each line."
        default: return "The app picks a style for you."
        }
    }
    func choice(_ title: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).lineLimit(1) }
            .buttonStyle(.bordered).tint(on ? .accentColor : nil)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
            .help(help)
    }

    var makeRow: some View {
        VStack(spacing: 8) {
            if let p = model.shortProgress {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.shortPhase.isEmpty ? "Making the clip" : model.shortPhase) (\(Int(p * 100))%)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    HStack { ProgressView(value: p); Button("Cancel") { model.cancelShortRender() }.buttonStyle(.bordered).help("Stops making this clip.") }
                }
            } else if let out = model.shortOutput {
                HStack {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: { Label("Show in Finder", systemImage: "folder") }.help("Opens the folder with this clip.")
                    ShareLink(item: out) { Label("Share", systemImage: "square.and.arrow.up") }.help("Send the clip by Messages, Mail or AirDrop.")
                    Spacer()
                }
            }
            Button { model.renderShort(clip.id) } label: { Label("Make this clip", systemImage: "film").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.shortProgress != nil)
                .help("Creates the finished vertical video for this clip.")
        }
    }
}

struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.title; configuration.icon } }
}

/// The less common choices.
struct ShortMoreOptions: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let clipID: UUID
    var c: ShortClip { model.plan?.shorts.first { $0.id == clipID } ?? ShortClip(name: "", start: 0, end: 10) }
    func set(_ f: @escaping (inout ShortClip) -> Void) { model.update(clipID, f); model.refreshPreview(at: 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("More options").font(.title2.bold())
            HStack(spacing: 8) {
                Text("Motion").frame(width: 130, alignment: .leading)
                opt("Calm", c.motion != "punchy", "Slow, smooth camera moves.") { set { $0.motion = "calm" } }
                opt("Punchy", c.motion == "punchy", "Faster cuts and a little shake on the beat.") { set { $0.motion = "punchy" } }
            }
            HStack(spacing: 8) {
                Text("Beat pulse").frame(width: 130, alignment: .leading)
                opt("On", c.pulse, "A gentle throb on the beat of the music.") { set { $0.pulse = true } }
                opt("Off", !c.pulse, "No throb.") { set { $0.pulse = false } }
            }
            HStack(spacing: 8) {
                Text("Closing text").frame(width: 130, alignment: .leading)
                TextField("optional, e.g. Full song on YouTube ▶", text: Binding(get: { c.cta }, set: { v in model.update(clipID) { $0.cta = v } })).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 10) {
                Button { model.shuffleLook(clipID) } label: { Label("Try a different look", systemImage: "dice") }
                    .help("Picks a new random title animation and set of cuts. Press it until you like what you see in the preview.")
                Button { dismiss(); model.renderShort(clipID, variants: 3) } label: { Label("Make 3 versions", systemImage: "square.stack.3d.up") }
                    .help("Makes the same clip three times with different looks, so you can see which one people watch longest on YouTube.")
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.font(.callout).padding(22).frame(width: 560)
    }
    func opt(_ t: String, _ on: Bool, _ help: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t) }.buttonStyle(.bordered).tint(on ? .accentColor : nil)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2)).help(help)
    }
}
