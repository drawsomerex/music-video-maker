// Shorts editor: lyric picker, waveform fine-tuning, style options and live preview.
import SwiftUI
import MVCore

func clock(_ s: Double) -> String { String(format: "%d:%04.1f", Int(s) / 60, s - Double(Int(s) / 60 * 60)) }
func parseClock(_ s: String) -> Double? {
    let p = s.split(separator: ":").map(String.init)
    if p.count == 2, let m = Double(p[0]), let x = Double(p[1]) { return m * 60 + x }
    return Double(s)
}

/// YouTube Shorts: pick lyrics, fine-tune the cut against the waveform, audition it, render a 1080×1920 clip.
struct ShortsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HSplitView {
            list.frame(minWidth: 170, idealWidth: 220, maxWidth: 300)
            Group {
                if let c = model.currentShort { ShortEditor(clip: c).id(c.id) }
                else { empty }
            }.frame(minWidth: 520)
        }
        .onAppear { if model.selectedShort == nil { model.selectedShort = model.plan?.shorts.first?.id } }
    }

    var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.portrait.on.rectangle.portrait").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Make short clips for YouTube Shorts").font(.title2.bold())
            Text("Short vertical clips for phones, up to 3 minutes each. Let the app cut your song into 4 to 7 clips of about 30 seconds, or choose the exact lines yourself.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button { model.autoMakeShorts() } label: { Label("Cut my song into clips for me", systemImage: "sparkles").padding(.horizontal, 8) }.buttonStyle(.borderedProminent).controlSize(.large)
                    .help("The app picks 4 to 7 clips of about 30 seconds, cut at natural pauses between verses. You can still change each one.")
                Button { model.newShort() } label: { Label("Choose the lines myself", systemImage: "plus").padding(.horizontal, 8) }.controlSize(.large)
                    .help("Starts one clip of about 30 seconds that you shape by picking lyric lines.")
                Button { model.newWholeSong() } label: { Label("Whole song", systemImage: "music.note.list").padding(.horizontal, 8) }.controlSize(.large)
                    .help("Turns the whole song into one vertical video. Songs over 3 minutes are split into the fewest equal parts, because Shorts can be at most 3 minutes.")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var list: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.selectedShort }, set: { model.selectedShort = $0; model.stopPlayback(); model.refreshPreview(at: 1) })) {
                ForEach(model.plan?.shorts ?? []) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("\(clock(c.start)) – \(clock(c.end)) · \(Int(c.duration)) s").font(.caption).foregroundStyle(.secondary)
                    }.tag(c.id).contextMenu { Button("Delete", role: .destructive) { model.deleteShort(c.id) } }
                }
            }.listStyle(.sidebar)
            Divider()
            VStack(spacing: 8) {
                HStack {
                    Menu {
                        Button("Auto-make 4–7 Shorts (~30 s at stanza breaks)") { model.autoMakeShorts(replaceExisting: true) }
                        Button("New Short (30 s from the lyrics)") { model.newShort() }
                        Button("Whole song (split into parts if over 3:00)") { model.newWholeSong() }
                    } label: { Label("Add a clip", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                    .help("Add another clip: cut the song automatically, choose lines yourself, or use the whole song.")
                    Spacer()
                    if let id = model.selectedShort { Button(role: .destructive) { model.deleteShort(id) } label: { Image(systemName: "trash") }
                        .help("Deletes the selected clip from this list. Videos you already made are kept.") }
                }
                if let shorts = model.plan?.shorts, shorts.count > 1 {
                    Button {
                        model.renderAllShorts()
                    } label: {
                        Label("Make all \(shorts.count) clips", systemImage: "film.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Creates every clip in the list, one after another.")
                    .disabled(model.shortProgress != nil)
                }
            }.padding(10)
        }
    }
}

struct ShortEditor: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    @State private var previewT = 1.0
    @State private var zoomFocus = 0        // 0 = whole clip, 1 = around the start, 2 = around the end
    @State private var zoomSpan = 8.0       // seconds visible when zoomed on an edge
    @State private var anchor: Int?         // the lyric line where a drag across the list began

    var plan: Plan { model.plan! }
    var c: ShortClip { model.currentShort ?? clip }
    var range: ClosedRange<Int>? { Pipeline.lineRange(plan: plan, clip: c) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TextField("Name", text: Binding(get: { c.name }, set: { n in model.update(clip.id) { $0.name = n } })).textFieldStyle(.roundedBorder).font(.title3.bold())
                            .help("A name for this clip. It becomes the file name.")
                    }
                    selectionHeader
                    Text("Choose your hook").font(.headline)
                    Text("The song is shown below with its parts on top. The bright box is your Short; everything outside it is dimmed. Drag the box to move it, drag its edges to change where it starts and ends (they snap to the nearest word; hold Shift to turn snapping off), or choose lyric lines in the list further down.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Picker("Zoom on", selection: $zoomFocus) { Text("Whole clip").tag(0); Text("Start").tag(1); Text("End").tag(2) }.pickerStyle(.segmented).frame(minWidth: 170, maxWidth: 240).labelsHidden()
                            .help("The lower picture is a close-up. Show the whole clip, or zoom in on its start or end to place the cut precisely. Every word is labelled when you are zoomed in.")
                        if zoomFocus != 0 {
                            Button { zoomSpan = min(40, zoomSpan * 1.6) } label: { Image(systemName: "minus.magnifyingglass") }.controlSize(.small)
                            Slider(value: Binding(get: { log(zoomSpan) }, set: { zoomSpan = exp($0) }), in: log(1.5)...log(40)).frame(minWidth: 70, maxWidth: 130)
                            Button { zoomSpan = max(1.5, zoomSpan / 1.6) } label: { Image(systemName: "plus.magnifyingglass") }.controlSize(.small)
                            Text(String(format: "%.1f s across", zoomSpan)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    WaveformEditor(clip: c, id: clip.id, zoomFocus: zoomFocus, zoomSpan: zoomSpan)
                    lyricPicker
                    Text("Fine-tune").font(.headline)
                    HStack(alignment: .top, spacing: 24) { edge("Start", isStart: true); edge("End", isStart: false) }
                    Text("Choose the look").font(.headline)
                    styleBox
                    transport
                }.padding(20)
            }
            Divider()
            previewPane.frame(minWidth: 230, idealWidth: 300, maxWidth: 340)
        }
        .onChange(of: c.start) { model.refreshPreview(at: previewT) }
        .onChange(of: c.end) { model.refreshPreview(at: previewT) }
        .onAppear { model.refreshPreview(at: previewT) }
        .onDisappear { model.stopPlayback() }
    }

    /// Seconds of music before the first sung word and after the last one.
    var musicAround: (before: Double, after: Double)? {
        guard let r = range else { return nil }
        let first = plan.lines[r.lowerBound].start, last = plan.lines[r.upperBound].end
        return (max(0, first - c.start), max(0, c.end - last))
    }

    // MARK: length guardrails + loop preview
    var selectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("\(clock(c.start)) → \(clock(c.end))", systemImage: "scissors").monospacedDigit()
                LengthBadge(duration: c.duration)
                Text(ShortLength.message(c.duration)).font(.callout.weight(.medium)).foregroundStyle(ShortLength.color(c.duration))
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button { model.toggleLoop(c.start, c.end) } label: { Label(model.looping ? "Stop" : "Loop preview", systemImage: model.looping ? "stop.fill" : "repeat") }
                    .keyboardShortcut("l", modifiers: [])
                    .help("Plays just this selection again and again, starting half a second early, so you can hear whether the cut sounds clean. Keyboard: press L (or the space bar) to start and stop.")
                Button("") { model.toggleLoop(c.start, c.end) }.keyboardShortcut(.space, modifiers: []).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                Button { model.extendSelection(clip.id, seconds: 30) } label: { Label("Make it about 30 seconds", systemImage: "arrow.left.and.right") }
                    .help("Keeps where it starts and adds lyric lines until the clip is about 30 seconds long.")
                if let m = musicAround {
                    Text(String(format: "♪ %.1f s before the words · %.1f s after", m.before, m.after)).font(.caption).monospacedDigit()
                        .foregroundStyle(m.before < 1.5 || m.after < 1.5 ? .orange : .secondary)
                        .help("Music-only time at the start and end. Short because the neighbouring lyric line is right next to it. Move the handle into the gap, or accept it.")
                }
            }
        }.font(.callout)
    }

    // MARK: lyrics, grouped by the song's parts. Click a line, or drag across several lines, and the selection snaps to them.
    enum LyricRow { case header(String, Int); case line(Int) }
    var lyricRows: [LyricRow] {
        var out: [LyricRow] = []
        for (i, sec) in plan.sections.enumerated() {
            let title = sec.lineIDs.isEmpty ? "Music only" : "Part \(i + (plan.sections.first?.lineIDs.isEmpty == true ? 0 : 1))"
            if sec.lineIDs.isEmpty && sec.end - sec.start < 4 { continue }
            out.append(.header(title, i)); for l in sec.lineIDs where plan.lines.indices.contains(l) { out.append(.line(l)) }
        }
        return out
    }
    static let rowH: CGFloat = 28

    func lineAt(_ y: CGFloat, _ rows: [LyricRow]) -> Int? {
        guard !rows.isEmpty else { return nil }
        var i = min(rows.count - 1, max(0, Int(y / ShortEditor.rowH)))
        while i < rows.count { if case .line(let l) = rows[i] { return l }; i += 1 }          // a part's heading means its first line
        i = rows.count - 1; while i >= 0 { if case .line(let l) = rows[i] { return l }; i -= 1 }
        return nil
    }

    var lyricPicker: some View {
        let rows = lyricRows
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Stepper(value: $model.leadIn, in: 0...12, step: 0.5) { Text("Music before the words: \(String(format: "%.1f", model.leadIn)) s").font(.callout).monospacedDigit() }
                    .help("How many seconds of music play before the first sung word. Applied when you choose lines.")
                Stepper(value: $model.tailOut, in: 0...12, step: 0.5) { Text("after: \(String(format: "%.1f", model.tailOut)) s").font(.callout).monospacedDigit() }
                    .help("How many seconds of music play after the last sung word.")
            }
            Text("Click a line to choose it, or press and drag across several lines. Hold Shift and click to stretch the clip to another line. The box on the timeline above follows you.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { n, row in
                            switch row {
                            case .header(let t, let si):
                                HStack {
                                    Text(t).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Use this whole part") { model.selectSection(clip.id, index: si) }.buttonStyle(.borderless).font(.caption)
                                        .help("Selects every line of this part as one clip.")
                                }.padding(.horizontal, 8).frame(height: ShortEditor.rowH).background(Color.secondary.opacity(0.10))
                            case .line(let i):
                                let l = plan.lines[i]; let inside = range.map { $0.contains(i) } ?? false
                                HStack(spacing: 8) {
                                    Text(clock(l.start)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 46, alignment: .leading)
                                    Text(l.text).font(.callout).foregroundStyle(inside ? .primary : .secondary).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if range?.lowerBound == i { Text("START").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(.green)) }
                                    if range?.upperBound == i { Text("END").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(.red)) }
                                }
                                .padding(.horizontal, 8).frame(height: ShortEditor.rowH)
                                .background(inside ? ShortLength.color(c.duration).opacity(0.16) : .clear).id(i)
                            }
                        }
                    }
                    .coordinateSpace(name: "lyrics")
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("lyrics"))
                        .onChanged { g in
                            guard let cur = lineAt(g.location.y, rows) else { return }
                            if anchor == nil {
                                if NSEvent.modifierFlags.contains(.shift), let r = range { anchor = cur < r.lowerBound ? r.upperBound : r.lowerBound }
                                else { anchor = lineAt(g.startLocation.y, rows) ?? cur }
                            }
                            if let a = anchor { model.selectLines(clip.id, min(a, cur), max(a, cur)) }
                        }
                        .onEnded { _ in anchor = nil })
                }
                .frame(height: 220).background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .onAppear { if let r = range { proxy.scrollTo(max(0, r.lowerBound - 1), anchor: .top) } }
            }
            if let r = range { Text("Lines \(r.lowerBound + 1)–\(r.upperBound + 1) · “\(plan.lines[r.lowerBound].text)” … “\(plan.lines[r.upperBound].text)”").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    // MARK: look
    var styleBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Lively style — opening title, word-by-word words, smooth cuts, looping end", isOn: Binding(get: { c.dynamic }, set: { v in model.update(clip.id) { $0.dynamic = v }; model.refreshPreview(at: previewT) })).toggleStyle(.switch)
                .help("Adds the opening title, a highlight that follows each word, and smooth picture changes. Turn it off for a simple look.")
            if c.dynamic {
                HStack {
                    Text("Opening title").frame(width: 98, alignment: .leading)
                        .help("The big words shown during the first two seconds. Leave empty to use your song title.")
                    TextField("blank = the song title (\(plan.title))", text: Binding(get: { c.hook }, set: { v in model.update(clip.id) { $0.hook = v }; model.refreshPreview(at: previewT) })).textFieldStyle(.roundedBorder)
                    Button {
                        model.writeHook(clip.id)
                    } label: {
                        Label("Suggest one", systemImage: "sparkles")
                    }
                    .disabled(model.hookBusy || model.busy)
                    .help("The AI reads this clip's words and suggests a short, catchy opening title.")
                }
                HStack {
                    Text("Closing text").frame(width: 98, alignment: .leading)
                        .help("Optional words shown at the very end, such as “Full song on YouTube”.")
                    TextField("optional, e.g. Full song on YouTube ▶", text: Binding(get: { c.cta }, set: { v in model.update(clip.id) { $0.cta = v } })).textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 14) {
                    Picker("Motion", selection: Binding(get: { c.motion }, set: { v in model.update(clip.id) { $0.motion = v }; model.refreshPreview(at: previewT) })) {
                        Text("Calm").tag("calm"); Text("Punchy").tag("punchy") }.pickerStyle(.segmented).frame(minWidth: 130, maxWidth: 190)
                        .help("Calm: slow, smooth camera moves. Punchy: faster cuts and a little shake on the beat.")
                    Picker("Lyrics", selection: Binding(get: { c.textStyle }, set: { v in model.update(clip.id) { $0.textStyle = v }; model.refreshPreview(at: previewT) })) {
                        Text("Pill").tag("pill"); Text("Pop").tag("pop"); Text("Big").tag("stack"); Text("Sweep").tag("sweep"); Text("Surprise me").tag("auto") }.frame(minWidth: 130, maxWidth: 190)
                        .help("How the words are drawn. Pill: a coloured bar follows the word being sung. Pop: words pop in. Big: large words. Sweep: a colour sweeps across each line.")
                }
                HStack(spacing: 14) {
                    Picker("Colour", selection: Binding(get: { c.accent }, set: { v in model.update(clip.id) { $0.accent = v }; model.refreshPreview(at: previewT) })) {
                        ForEach(ShortStyle.paletteNames, id: \.self) { Text($0).tag($0) }; Text("Auto").tag("Auto") }.frame(minWidth: 130, maxWidth: 190)
                        .help("The highlight colour for the words.")
                    Toggle("Beat pulse", isOn: Binding(get: { c.pulse }, set: { v in model.update(clip.id) { $0.pulse = v } }))
                        .help("A gentle throb on the beat of the music.")
                    Toggle("Loop ending", isOn: Binding(get: { c.loop }, set: { v in model.update(clip.id) { $0.loop = v } }))
                        .help("Makes the end flow back into the start so the clip repeats smoothly on phones.")
                }
                HStack(spacing: 8) {
                    Label(ShortStyle.make(seed: c.styleSeed, clip: c).summary, systemImage: "paintpalette").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { model.shuffleLook(clip.id) } label: { Label("Try a different look", systemImage: "dice") }
                        .help("Picks a new random title animation and set of cuts. Press it until you like what you see in the preview.")
                }
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
    }

    // MARK: start / end controls
    func edge(_ title: String, isStart: Bool) -> some View {
        let value = isStart ? c.start : c.end
        func set(_ v: Double) { model.update(clip.id) { if isStart { $0.start = v } else { $0.end = v } } }
        return VStack(alignment: .leading, spacing: 6) {
            Text(isStart ? "Clip starts at" : "Clip ends at").font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                nudge("−1", -1) { set(value + $0) }; nudge("−.1", -0.1) { set(value + $0) }
                TextField("", text: Binding(get: { clock(value) }, set: { if let v = parseClock($0) { set(v) } })).textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 74).multilineTextAlignment(.center)
                nudge("+.1", 0.1) { set(value + $0) }; nudge("+1", 1) { set(value + $0) }
            }
            HStack(spacing: 6) {
                Button("Move to the nearest pause") { set(Pipeline.snap(value, plan: plan, maxDistance: 1.2)) }
                    .help("Moves this edge to the closest quiet gap between words so the cut does not slice through a word.")
                Button { isStart ? model.playRange(c.start, c.start + 4) : model.playRange(max(c.start, c.end - 4), c.end + 0.3) } label: { Label(isStart ? "Hear the start" : "Hear the end", systemImage: "play.fill") }
                    .help(isStart ? "Plays the first 4 seconds of the clip." : "Plays the last 4 seconds of the clip.")
            }
        }
    }
    func nudge(_ label: String, _ d: Double, _ f: @escaping (Double) -> Void) -> some View {
        Button(label) { f(d) }
            .buttonStyle(.bordered).controlSize(.small).font(.caption.monospacedDigit())
            .help(d < 0 ? "Moves this edge earlier by \(abs(d) == 1 ? "1 second" : "a tenth of a second")." : "Moves this edge later by \(d == 1 ? "1 second" : "a tenth of a second").")
    }

    var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { model.playhead == nil ? model.playRange(c.start, c.end) : model.stopPlayback() } label: {
                    Label(model.playhead == nil ? "Play the clip" : "Stop", systemImage: model.playhead == nil ? "play.fill" : "stop.fill")
                }.controlSize(.large).help("Plays the music for this clip.")
                Spacer(minLength: 8)
                if let p = model.shortProgress {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(model.shortPhase.isEmpty ? "Rendering" : model.shortPhase) (\(Int(p * 100))%)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        ProgressView(value: p).frame(minWidth: 120, maxWidth: 210)
                    }
                    Button("Cancel") { model.cancelShortRender() }
                        .buttonStyle(.bordered).help("Stops making this clip.")
                } else if let out = model.shortOutput {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: { Label("Show in Finder", systemImage: "folder") }.help("Opens the folder with this clip.")
                    ShareLink(item: out) { Label("Share", systemImage: "square.and.arrow.up") }.help("Send the clip by Messages, Mail or AirDrop.")
                }
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if c.dynamic {
                    Button { model.renderShort(clip.id, variants: 3) } label: { Label("Make 3 versions", systemImage: "square.stack.3d.up") }
                        .controlSize(.large).disabled(model.shortProgress != nil)
                        .help("Makes the same clip three times with different looks, so you can see which one people watch longest on YouTube.")
                }
                Button { model.renderShort(clip.id) } label: { Label("Make this clip", systemImage: "film").font(.headline).padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.shortProgress != nil)
                    .help("Creates the finished vertical video for this clip.")
            }
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

/// Overview + zoomed waveform with draggable In/Out handles, lyric ticks and the playhead.
struct WaveformEditor: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    let id: UUID
    let zoomFocus: Int
    let zoomSpan: Double
    enum DragMode { case start, end, move(grab: Double) }
    @State private var mode: DragMode? = nil
    @State private var dragging: Int? = nil   // 0 = start, 1 = end (for the audition on release)
    @State private var frozen: ClosedRange<Double>? = nil   // keeps the window still while a handle is dragged

    var c: ShortClip { model.currentShort ?? clip }

    var body: some View {
        VStack(spacing: 6) {
            sectionsStrip
            strip(visible: 0...(model.plan?.songDuration ?? 1), height: 64, editable: true, overview: true)
            strip(visible: frozen ?? detailRange, height: zoomFocus == 0 ? 90 : 120, editable: true)
        }
    }

    var detailRange: ClosedRange<Double> {
        let dur = model.plan?.songDuration ?? 1
        switch zoomFocus {
        case 1, 2:
            let center = zoomFocus == 1 ? c.start : c.end
            var lo = center - zoomSpan / 2, hi = center + zoomSpan / 2
            if lo < 0 { hi -= lo; lo = 0 }; if hi > dur { lo -= hi - dur; hi = dur }
            return max(0, lo)...hi
        default: return max(0, c.start - 6)...min(dur, c.end + 6)
        }
    }

    /// The song's parts (the pictures) as coloured blocks above the waveform, so you can see where the verses and choruses are. Press one to select all of it.
    var sectionsStrip: some View {
        GeometryReader { geo in
            let dur = max(1, model.plan?.songDuration ?? 1), w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array((model.plan?.sections ?? []).enumerated()), id: \.offset) { i, sec in
                    let x0 = CGFloat(sec.start / dur) * w, x1 = CGFloat(sec.end / dur) * w
                    let music = sec.lineIDs.isEmpty
                    Button { model.selectSection(clip.id, index: i) } label: {
                        Text(x1 - x0 > 54 ? (music ? "Music" : "Part \(i + (model.plan!.sections.first?.lineIDs.isEmpty == true ? 0 : 1))") : "")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            .frame(width: max(2, x1 - x0 - 2), height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(music ? Color.gray.opacity(0.55) : [Color.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown][i % 8].opacity(0.75)))
                    }
                    .buttonStyle(.plain).offset(x: x0 + 1)
                    .help(music ? "A part with only music. Press to select it as a Short." : "Part \(i + 1) of the song. Press to select all of it as a Short.")
                }
            }
        }.frame(height: 20)
    }

    func strip(visible: ClosedRange<Double>, height: CGFloat, editable: Bool, overview: Bool = false) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = max(0.1, visible.upperBound - visible.lowerBound)
            let x: (Double) -> CGFloat = { t in CGFloat((t - visible.lowerBound) / span) * w }
            let time: (CGFloat) -> Double = { px in visible.lowerBound + Double(px / w) * span }
            Canvas { ctx, size in
                let peaks = model.waveform
                // selection
                let a = x(c.start), b = x(c.end)
                ctx.fill(Path(CGRect(x: max(0, a), y: 0, width: max(0, min(size.width, b) - max(0, a)), height: size.height)), with: .color(.white.opacity(0.10)))
                // waveform (max over each pixel column)
                if !peaks.isEmpty {
                    let mid = size.height / 2
                    var path = Path()
                    for px in stride(from: 0, to: Int(size.width), by: 2) {
                        let t0 = time(CGFloat(px)), t1 = time(CGFloat(px + 2))
                        let i0 = max(0, Int(t0 * 100)), i1 = min(peaks.count, max(i0 + 1, Int(t1 * 100)))
                        if i0 >= peaks.count { break }
                        let m = peaks[i0..<i1].max() ?? 0
                        let h = max(1, CGFloat(m) * (size.height * 0.46))
                        path.addRect(CGRect(x: CGFloat(px), y: mid - h, width: 1.4, height: h * 2))
                    }
                    ctx.fill(path, with: .color(.secondary.opacity(0.75)))
                }
                // lyric line ticks; when zoomed in, every word with its text so the cut can be matched to the singing
                if let p = model.plan {
                    for l in p.lines where visible.contains(l.start) { ctx.fill(Path(CGRect(x: x(l.start), y: 0, width: 1, height: size.height * (editable ? 0.28 : 0.18))), with: .color(.orange.opacity(0.9))) }
                    if editable && span <= 16 {
                        var row = 0
                        for l in p.lines { for w in l.words where visible.contains(w.start) {
                            let px = x(w.start)
                            ctx.fill(Path(CGRect(x: px, y: size.height - 16 - CGFloat(row % 2) * 11, width: 1, height: 16 + CGFloat(row % 2) * 11)), with: .color(.orange.opacity(0.55)))
                            ctx.draw(Text(w.text).font(.system(size: 9, weight: .medium)).foregroundColor(.orange), at: CGPoint(x: px + 2, y: size.height - 8 - CGFloat(row % 2) * 11), anchor: .leading)
                            row += 1
                        } }
                    }
                }
                // everything outside the Short is dimmed; the Short itself is outlined in the colour of its length (orange too short, green ideal, red long)
                ctx.fill(Path(CGRect(x: 0, y: 0, width: max(0, min(size.width, a)), height: size.height)), with: .color(.black.opacity(0.42)))
                ctx.fill(Path(CGRect(x: max(0, b), y: 0, width: max(0, size.width - max(0, b)), height: size.height)), with: .color(.black.opacity(0.42)))
                ctx.stroke(Path(CGRect(x: max(1, a), y: 1, width: max(2, min(size.width - 1, b) - max(1, a)), height: size.height - 2)), with: .color(ShortLength.color(c.duration)), lineWidth: 2.5)
                // handles
                for (t, col) in [(c.start, Color.green), (c.end, Color.red)] where visible.contains(t) {
                    ctx.fill(Path(CGRect(x: x(t) - 1, y: 0, width: 2, height: size.height)), with: .color(col))
                    if editable { ctx.fill(Path(roundedRect: CGRect(x: x(t) - 6, y: size.height / 2 - 14, width: 12, height: 28), cornerRadius: 4), with: .color(col)) }
                }
                if let ph = model.playhead, visible.contains(ph) { ctx.fill(Path(CGRect(x: x(ph) - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(.white)) }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            .gesture(editable ? DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let dur = model.plan?.songDuration ?? 1
                    let t = time(min(max(0, g.location.x), w))
                    if mode == nil {
                        frozen = overview ? nil : visible
                        let xs = x(c.start), xe = x(c.end), px = g.startLocation.x
                        if abs(px - xs) <= 12 { mode = .start; dragging = 0 }
                        else if abs(px - xe) <= 12 { mode = .end; dragging = 1 }
                        else if px > xs && px < xe { mode = .move(grab: time(px) - c.start) }
                        else { mode = .move(grab: c.duration / 2) }          // pressing outside the window moves it there
                    }
                    let near = 8 * (visible.upperBound - visible.lowerBound) / Double(max(1, w))      // snapping reach: 8 pixels
                    let free = NSEvent.modifierFlags.contains(.shift)                                   // Shift = no snapping
                    @MainActor func snapped(_ v: Double) -> Double { free ? v : model.snapToWordEdge(v, within: near) }
                    switch mode {
                    case .start: let v = snapped(t); model.update(id) { $0.start = min(v, $0.end - 2) }
                    case .end: let v = snapped(t); model.update(id) { $0.end = max(v, $0.start + 2) }
                    case .move(let grab)?:
                        let d = c.duration
                        var s0 = min(max(0, t - grab), max(0, dur - d))
                        let s1 = snapped(s0), e1 = snapped(s0 + d)
                        if abs(s1 - s0) <= abs(e1 - (s0 + d)) { s0 = min(max(0, s1), max(0, dur - d)) } else { s0 = min(max(0, e1 - d), max(0, dur - d)) }
                        model.update(id) { $0.start = s0; $0.end = s0 + d }
                    case nil: break
                    }
                }
                .onEnded { _ in
                    let which = dragging; dragging = nil; frozen = nil; mode = nil
                    // Audition the edge you just moved: 2.5 s from the start, or the last 2.5 s up to the end.
                    if which == 0 { model.playRange(c.start, c.start + 2.5) } else if which == 1 { model.playRange(max(c.start, c.end - 2.5), c.end + 0.3) }
                } : nil)
            .overlay {
                // the length badge sits on the selected window of the overview
                if overview {
                    let a = max(0, x(c.start)), b = min(w, x(c.end))
                    if b - a > 70 { LengthBadge(duration: c.duration).position(x: (a + b) / 2, y: height - 14).allowsHitTesting(false) }
                }
            }
            .overlay(alignment: .topLeading) {
                if editable { Text(clock(visible.lowerBound)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary).padding(3) }
            }
            .overlay(alignment: .topTrailing) {
                if editable { Text(clock(visible.upperBound)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary).padding(3) }
            }
        }.frame(height: height)
    }
}


/// Colours and words for how long a Short is: orange too short, green ideal, red long.
enum ShortLength {
    static func color(_ d: Double) -> Color {
        if d < 5 { return .orange }
        if d < 15 { return .secondary }
        if d <= 60 { return .green }
        return Color(red: 0.86, green: 0.11, blue: 0.2)
    }
    static func message(_ d: Double) -> String {
        if d >= ShortClip.maxDuration - 0.05 { return "At the 3:00 limit for a Short." }
        if d < 5 { return "Too short for a compelling Short." }
        if d < 15 { return "A little short. 15 to 60 seconds works best." }
        if d <= 60 { return "Ideal length for a Short." }
        return "Longer than 60 seconds. YouTube allows up to 3 minutes for some uploads."
    }
}

/// "34.2 s / 60 s" pill shown on the selection.
struct LengthBadge: View {
    let duration: Double
    var body: some View {
        Text(String(format: "%.1f s / 60 s", duration)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(ShortLength.color(duration).opacity(0.92)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .help("The length of this Short. Green is the ideal range, orange is too short, red is longer than 60 seconds.")
    }
}
