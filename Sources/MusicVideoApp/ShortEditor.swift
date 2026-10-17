// The Shorts editor. One idea: you SEE the song with its words, you HEAR it, and you set where the Short starts and ends.
//   • The song map (top) shows the whole song; the bright box is your Short.
//   • The word timeline (middle) shows the waveform and every word at a readable size; drag the green and red markers, or click a word.
//   • Big buttons play it, mark "start here / end here" at the moment you hear, and nudge each edge earlier or later (you hear every change).
import SwiftUI
import MVCore

struct ShortEditor: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    @State private var previewT = 1.0
    @State private var cursor: Double?               // the spot you last clicked on the timeline
    @State private var showMore = false
    var snapshot = false                      // layout pictures only

    var plan: Plan { model.plan! }
    var c: ShortClip { model.currentShort ?? clip }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group { if snapshot { editorColumn } else { ScrollView { editorColumn } } }
            Divider()
            previewPane.frame(minWidth: 230, idealWidth: 290, maxWidth: 330)
        }
        .onChange(of: c.start) { model.refreshPreview(at: previewT) }
        .onChange(of: c.end) { model.refreshPreview(at: previewT) }
        .onAppear { model.refreshPreview(at: previewT) }
        .onDisappear { model.stopPlayback() }
        .sheet(isPresented: $showMore) { ShortMoreOptions(clipID: clip.id).environmentObject(model) }
    }

    var editorColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            SongMap(clip: clip, cursor: $cursor)
            WordTimeline(clip: clip, cursor: $cursor, snapshot: snapshot)
            snapRow
            playRow
            EdgeCard(clip: clip, isStart: true)
            EdgeCard(clip: clip, isStart: false)
            lookBox
            makeRow
        }.padding(18)
    }

    // MARK: how things stick to words and beats
    var snapRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Markers stick to:").font(.callout.weight(.semibold))
                Picker("", selection: $model.snapMode) { ForEach(AppModel.SnapMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                    .help("Smart: sticks to word edges while words are being sung, and to the beat in the music-only parts. Beats: only the beat. Words: only word edges. Off: stays exactly where you put it. Holding Shift while dragging also turns it off.")
            }
            Text({ switch model.snapMode {
                case .smart: return "Smart: near words the marker sticks to the edge of a word; in music-only parts it sticks to the beat."
                case .beats: return "Beats: the marker always sticks to the nearest beat of the music."
                case .words: return "Words: the marker sticks to the nearest edge of a word."
                case .off: return "Off: the marker stays exactly where you put it." } }()).font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: play
    var playRow: some View {
        HStack(spacing: 10) {
            Button { playShort() } label: { Label(model.playhead == nil ? "Play the Short" : "Stop", systemImage: model.playhead == nil ? "play.fill" : "stop.fill").frame(minWidth: 120) }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.space, modifiers: [])
                .help("Plays the Short from its start to its end. The space bar does the same; press it again to stop.")
            Button { model.toggleLoop(c.start, c.end) } label: { Label(model.looping ? "Stop repeating" : "Play again and again", systemImage: "repeat") }
                .controlSize(.large).keyboardShortcut("l", modifiers: [])
                .help("Plays the Short over and over, starting half a second early, so you can hear whether the ends sound right. Keyboard: L.")
            Spacer(minLength: 6)
            Button { model.extendSelection(clip.id, seconds: 30) } label: { Label("Make it about 30 seconds", systemImage: "arrow.left.and.right") }
                .controlSize(.large).help("Keeps where it starts and adds lyric lines until the Short is about 30 seconds long.")
        }
    }
    func playShort() { if model.playhead != nil { model.stopPlayback() } else { model.playRange(c.start, c.end) } }

    // MARK: top: name, length, advice
    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TextField("Name", text: Binding(get: { c.name }, set: { n in model.update(clip.id) { $0.name = n } }))
                    .textFieldStyle(.roundedBorder).font(.title3.bold()).help("A name for this clip. It becomes the file name.")
                LengthBadge(duration: c.duration)
            }
            Text("\(clock(c.start)) → \(clock(c.end))  ·  " + ShortLength.message(c.duration)).font(.callout.weight(.medium)).foregroundStyle(ShortLength.color(c.duration)).monospacedDigit()
        }
    }

    // MARK: look (the few choices that matter; the rest is under "More options")
    var lookBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the look").font(.headline)
            HStack(spacing: 8) {
                choice("Lively", on: c.dynamic, help: "Adds an opening title, a highlight that follows each word, and smooth picture changes.") { set { $0.dynamic = true } }
                choice("Simple", on: !c.dynamic, help: "Plain pictures with the words at the bottom. No opening title.") { set { $0.dynamic = false } }
            }
            if c.dynamic {
                HStack(spacing: 8) {
                    Text("Opening title").frame(width: 100, alignment: .leading).help("The big words shown during the first two seconds. Leave empty to use your song title.")
                    TextField("blank = the song title (\(plan.title))", text: Binding(get: { c.hook }, set: { v in set { $0.hook = v } })).textFieldStyle(.roundedBorder)
                    Button { model.writeHook(clip.id) } label: { Label("Suggest one", systemImage: "sparkles") }.disabled(model.hookBusy || model.busy)
                        .help("The AI reads this clip's words and suggests a short, catchy opening title.")
                }
                HStack(spacing: 8) {
                    Text("The words").frame(width: 100, alignment: .leading)
                    ForEach([("pill", "Pill"), ("pop", "Pop"), ("stack", "Big"), ("sweep", "Sweep"), ("auto", "Surprise me")], id: \.0) { k in
                        choice(k.1, on: c.textStyle == k.0, help: wordsHelp(k.0)) { set { $0.textStyle = k.0 } }
                    }
                }
                HStack(spacing: 8) {
                    Text("Colour").frame(width: 100, alignment: .leading)
                    ForEach(ShortStyle.paletteNames + ["Auto"], id: \.self) { n in choice(n, on: c.accent == n, help: "The highlight colour for the words.") { set { $0.accent = n } } }
                }
                HStack { Spacer(); Button { showMore = true } label: { Label("More options…", systemImage: "slider.horizontal.3") }
                    .help("Calm or punchy motion, beat pulse, looping end, closing text, and a new random look.") }
            }
        }
        .font(.callout)
        .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.35)))
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

    // MARK: make it
    var makeRow: some View {
        HStack(spacing: 10) {
            if let p = model.shortProgress {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(model.shortPhase.isEmpty ? "Making the clip" : model.shortPhase) (\(Int(p * 100))%)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    ProgressView(value: p).frame(minWidth: 120, maxWidth: 260)
                }
                Button("Cancel") { model.cancelShortRender() }.buttonStyle(.bordered).help("Stops making this clip.")
            } else if let out = model.shortOutput {
                Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: { Label("Show in Finder", systemImage: "folder") }.help("Opens the folder with this clip.")
                ShareLink(item: out) { Label("Share", systemImage: "square.and.arrow.up") }.help("Send the clip by Messages, Mail or AirDrop.")
            }
            Spacer(minLength: 8)
            Button { model.renderShort(clip.id) } label: { Label("Make this clip", systemImage: "film").font(.headline).padding(.horizontal, 8).padding(.vertical, 3) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.shortProgress != nil)
                .help("Creates the finished vertical video for this clip.")
        }
    }

    // MARK: preview
    var previewPane: some View {
        VStack(spacing: 8) {
            HStack { Text("Preview").font(.callout.weight(.semibold)).foregroundStyle(.secondary); Spacer()
                if model.live.preparing { ProgressView().controlSize(.mini) } }.padding(.top, 14).padding(.horizontal, 20)
            LivePreviewPane(live: model.live, defaultCaption: 0.20) { v in model.setCaptionY(v, shortID: clip.id) }
                .padding(.horizontal, 20)
            CaptionTimingBar().environmentObject(model).padding(.horizontal, 14).scaleEffect(0.92)
            Spacer()
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
