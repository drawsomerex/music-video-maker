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
    @State private var step = 0.1                    // seconds moved by one press of Earlier / Later
    @State private var cursor: Double?               // the spot you last clicked on the timeline
    @State private var showMore = false
    var snapshot = false                      // layout pictures only

    var plan: Plan { model.plan! }
    var c: ShortClip { model.currentShort ?? clip }
    var here: Double? { model.playhead ?? cursor }

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
            controls
            lookBox
            makeRow
        }.padding(18)
    }

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

    // MARK: play, mark, nudge
    var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listen and set the ends").font(.headline)
            HStack(spacing: 10) {
                Button { playShort() } label: { Label(model.playhead == nil ? "Play the Short" : "Stop", systemImage: model.playhead == nil ? "play.fill" : "stop.fill").frame(minWidth: 120) }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.space, modifiers: [])
                    .help("Plays just the Short, from its start to its end. The space bar does the same; press it again to stop.")
                Button { model.toggleLoop(c.start, c.end) } label: { Label(model.looping ? "Stop looping" : "Loop it", systemImage: "repeat") }
                    .controlSize(.large).keyboardShortcut("l", modifiers: [])
                    .help("Plays the Short again and again, starting half a second early, so you can hear whether the ends sound clean. Keyboard: L.")
                Button { model.playRange(cursor ?? c.start, plan.songDuration) } label: { Label("Play from the cursor", systemImage: "play.circle") }
                    .controlSize(.large).disabled(cursor == nil)
                    .help("Plays the song from the spot you clicked on the timeline, past the end of the Short, so you can listen for the right place to end it.")
            }
            HStack(spacing: 10) {
                Button { markStart() } label: { Label("Start here", systemImage: "flag.fill") }.controlSize(.large).tint(.green).buttonStyle(.bordered)
                    .disabled(here == nil).help("Makes the Short start at the spot you are listening to or clicked on (it moves to the nearest word edge).")
                Button { markEnd() } label: { Label("End here", systemImage: "flag.checkered") }.controlSize(.large).tint(.red).buttonStyle(.bordered)
                    .disabled(here == nil).help("Makes the Short end at the spot you are listening to or clicked on (it moves to the nearest word edge).")
                Text(here.map { "Cursor at \(clock($0))" } ?? "Click the timeline, or press Play, to set a cursor.").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 14) {
                edgeCard("Starts at", c.start, .green, earlier: { nudgeStart(-step) }, later: { nudgeStart(step) }, hear: { model.playRange(c.start, c.start + 3) })
                edgeCard("Ends at", c.end, .red, earlier: { nudgeEnd(-step) }, later: { nudgeEnd(step) }, hear: { model.playRange(max(c.start, c.end - 3), c.end + 0.3) })
            }
            HStack(spacing: 10) {
                Text("Each press moves by").font(.callout)
                Picker("", selection: $step) { Text("0.1 s").tag(0.1); Text("0.5 s").tag(0.5); Text("1 s").tag(1.0) }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    .help("How far Earlier and Later move an end. A small step is for precise cuts; a big step gets you close quickly.")
                Spacer()
                Button { model.extendSelection(clip.id, seconds: 30) } label: { Label("Make it about 30 seconds", systemImage: "arrow.left.and.right") }
                    .help("Keeps the start and adds lyric lines until the Short is about 30 seconds long.")
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.35)))
    }

    func edgeCard(_ title: String, _ t: Double, _ color: Color, earlier: @escaping () -> Void, later: @escaping () -> Void, hear: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Circle().fill(color).frame(width: 10, height: 10); Text(title).font(.subheadline.weight(.semibold)); Text(clock(t)).font(.title3.monospacedDigit().weight(.bold)) }
            HStack(spacing: 8) {
                Button(action: earlier) { Label("Earlier", systemImage: "chevron.left") }.help("Moves this end earlier and plays it so you can hear the change.")
                Button(action: later) { Label("Later", systemImage: "chevron.right").labelStyle(TrailingIcon()) }.help("Moves this end later and plays it so you can hear the change.")
                Button(action: hear) { Label("Hear it", systemImage: "speaker.wave.2") }.help("Plays this end of the Short again.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.6), lineWidth: 1.5))
    }

    func playShort() { if model.playhead != nil { model.stopPlayback() } else { model.playRange(c.start, c.end) } }
    func markStart() { guard let t = here else { return }; let v = model.snapToWordEdge(t, within: 0.4); model.update(clip.id) { $0.start = min(v, $0.end - 2) }; model.playRange(v, v + 3) }
    func markEnd() { guard let t = here else { return }; let v = model.snapToWordEdge(t, within: 0.4); model.update(clip.id) { $0.end = max(v, $0.start + 2) }; model.playRange(max(c.start, v - 3), v + 0.3) }
    func nudgeStart(_ d: Double) { let v = max(0, c.start + d); model.update(clip.id) { $0.start = min(v, $0.end - 2) }; model.playRange(v, v + 3) }
    func nudgeEnd(_ d: Double) { let v = c.end + d; model.update(clip.id) { $0.end = max(v, $0.start + 2) }; model.playRange(max(c.start, v - 3), v + 0.3) }

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
                Text("Looping end").frame(width: 130, alignment: .leading)
                opt("On", c.loop, "Makes the end flow back into the start so the clip repeats smoothly on phones.") { set { $0.loop = true } }
                opt("Off", !c.loop, "A normal ending.") { set { $0.loop = false } }
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
