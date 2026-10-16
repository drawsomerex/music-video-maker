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
            list.frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
            Group {
                if let c = model.currentShort { ShortEditor(clip: c).id(c.id) }
                else { empty }
            }.frame(minWidth: 620)
        }
        .onAppear { if model.selectedShort == nil { model.selectedShort = model.plan?.shorts.first?.id } }
    }

    var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.portrait.on.rectangle.portrait").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Make a YouTube Short").font(.title2.bold())
            Text("Pick the lyrics you want, fine-tune where the music starts and stops, and render a vertical 1080×1920 clip using your pictures.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button { model.newShort() } label: { Label("New Short (30 s)", systemImage: "plus").padding(.horizontal, 8) }.buttonStyle(.borderedProminent).controlSize(.large)
                Button { model.newWholeSong() } label: { Label("Whole song", systemImage: "music.note.list").padding(.horizontal, 8) }.controlSize(.large)
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
            HStack {
                Menu {
                    Button("New Short (30 s from the lyrics)") { model.newShort() }
                    Button("Whole song (split into parts if over 3:00)") { model.newWholeSong() }
                } label: { Label("New", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                if let id = model.selectedShort { Button(role: .destructive) { model.deleteShort(id) } label: { Image(systemName: "trash") } }
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

    var plan: Plan { model.plan! }
    var c: ShortClip { model.currentShort ?? clip }
    var range: ClosedRange<Int>? { Pipeline.lineRange(plan: plan, clip: c) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        TextField("Name", text: Binding(get: { c.name }, set: { n in model.update(clip.id) { $0.name = n } })).textFieldStyle(.roundedBorder).font(.title3.bold())
                    }
                    summary
                    Text("1 · Pick the lyrics").font(.headline)
                    lyricPicker
                    Text("2 · Look").font(.headline)
                    styleBox
                    Text("3 · Line up the music").font(.headline)
                    Text("Drag the handles on the waveform, or nudge. Use ▶ First/Last 4 s to hear exactly how the cut sounds.").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Picker("Zoom on", selection: $zoomFocus) { Text("Whole clip").tag(0); Text("Start").tag(1); Text("End").tag(2) }.pickerStyle(.segmented).frame(width: 240).labelsHidden()
                        if zoomFocus != 0 {
                            Button { zoomSpan = min(40, zoomSpan * 1.6) } label: { Image(systemName: "minus.magnifyingglass") }.controlSize(.small)
                            Slider(value: Binding(get: { log(zoomSpan) }, set: { zoomSpan = exp($0) }), in: log(1.5)...log(40)).frame(width: 130)
                            Button { zoomSpan = max(1.5, zoomSpan / 1.6) } label: { Image(systemName: "plus.magnifyingglass") }.controlSize(.small)
                            Text(String(format: "%.1f s across", zoomSpan)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    WaveformEditor(clip: c, id: clip.id, zoomFocus: zoomFocus, zoomSpan: zoomSpan)
                    HStack(alignment: .top, spacing: 24) { edge("Start", isStart: true); edge("End", isStart: false) }
                    transport
                }.padding(20)
            }
            Divider()
            previewPane.frame(width: 340)
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

    var summary: some View {
        HStack(spacing: 12) {
            Label("\(clock(c.start)) → \(clock(c.end))", systemImage: "scissors").monospacedDigit()
            Text(String(format: "%.1f s", c.duration)).monospacedDigit().padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(c.duration >= ShortClip.maxDuration - 0.05 ? Color.orange.opacity(0.25) : c.duration <= 60 ? Color.green.opacity(0.18) : Color.orange.opacity(0.18)))
            Text(c.duration >= ShortClip.maxDuration - 0.05 ? "At the 3:00 Short limit" : c.duration <= 60 ? "Under a minute" : "Over a minute").font(.caption)
                .foregroundStyle(c.duration >= ShortClip.maxDuration - 0.05 ? .orange : .secondary)
            if let m = musicAround {
                Text(String(format: "♪ %.1f s before the words · %.1f s after", m.before, m.after)).font(.caption).monospacedDigit()
                    .foregroundStyle(m.before < 1.5 || m.after < 1.5 ? .orange : .secondary)
                    .help("Music-only time at the start and end. Short because the neighbouring lyric line is right next to it — move the handle into the gap, or accept it.")
            }
        }.font(.callout)
    }

    // MARK: lyrics
    var lyricPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Stepper(value: $model.leadIn, in: 0...12, step: 0.5) { Text("Music before the words: \(String(format: "%.1f", model.leadIn)) s").font(.caption).monospacedDigit() }
                Stepper(value: $model.tailOut, in: 0...12, step: 0.5) { Text("after: \(String(format: "%.1f", model.tailOut)) s").font(.caption).monospacedDigit() }
                Text("(applied when you pick lines)").font(.caption2).foregroundStyle(.tertiary)
            }.padding(.bottom, 4)
            Text("Click a line to start there · Shift-click a line to end there · or use In / Out").font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(plan.lines.indices, id: \.self) { i in
                            let l = plan.lines[i]; let inside = range.map { $0.contains(i) } ?? false
                            HStack(spacing: 8) {
                                Text(String(format: "%2d", i + 1)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 20, alignment: .trailing)
                                Text(clock(l.start)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 46, alignment: .leading)
                                Text(l.text).font(.callout).foregroundStyle(inside ? .primary : .secondary).lineLimit(1)
                                Spacer(minLength: 4)
                                if range?.lowerBound == i { Text("START").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(.green)) }
                                if range?.upperBound == i { Text("END").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(.red)) }
                                Button("In") { model.setShortLines(clip.id, from: i) }.buttonStyle(.bordered).controlSize(.mini)
                                Button("Out") { model.setShortLines(clip.id, to: i) }.buttonStyle(.bordered).controlSize(.mini)
                            }
                            .padding(.horizontal, 8).frame(height: 26)
                            .background(inside ? Color.accentColor.opacity(0.16) : .clear).id(i)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Click = start here; Shift-click = end here.
                                if NSEvent.modifierFlags.contains(.shift) { model.setShortLines(clip.id, to: i) } else { model.setShortLines(clip.id, from: i, fresh: true) }
                            }
                        }
                    }
                }
                .frame(height: 190).background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .onAppear { if let r = range { proxy.scrollTo(max(0, r.lowerBound - 1), anchor: .top) } }
            }
            if let r = range { Text("Lines \(r.lowerBound + 1)–\(r.upperBound + 1) · “\(plan.lines[r.lowerBound].text)” … “\(plan.lines[r.upperBound].text)”").font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.top, 4) }
        }
    }

    // MARK: look
    var styleBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Dynamic style — opening title, word-by-word lyrics, quick cuts, loop ending", isOn: Binding(get: { c.dynamic }, set: { v in model.update(clip.id) { $0.dynamic = v }; model.refreshPreview(at: previewT) })).toggleStyle(.switch)
            if c.dynamic {
                HStack {
                    Text("Opening title").frame(width: 98, alignment: .leading)
                    TextField("blank = the song title (\(plan.title))", text: Binding(get: { c.hook }, set: { v in model.update(clip.id) { $0.hook = v }; model.refreshPreview(at: previewT) })).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Closing text").frame(width: 98, alignment: .leading)
                    TextField("optional, e.g. Full song on YouTube ▶", text: Binding(get: { c.cta }, set: { v in model.update(clip.id) { $0.cta = v } })).textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 14) {
                    Picker("Motion", selection: Binding(get: { c.motion }, set: { v in model.update(clip.id) { $0.motion = v }; model.refreshPreview(at: previewT) })) {
                        Text("Calm").tag("calm"); Text("Punchy").tag("punchy") }.pickerStyle(.segmented).frame(width: 190)
                    Picker("Lyrics", selection: Binding(get: { c.textStyle }, set: { v in model.update(clip.id) { $0.textStyle = v }; model.refreshPreview(at: previewT) })) {
                        Text("Pill").tag("pill"); Text("Pop").tag("pop"); Text("Big").tag("stack"); Text("Sweep").tag("sweep"); Text("Surprise me").tag("auto") }.frame(width: 190)
                }
                HStack(spacing: 14) {
                    Picker("Colour", selection: Binding(get: { c.accent }, set: { v in model.update(clip.id) { $0.accent = v }; model.refreshPreview(at: previewT) })) {
                        ForEach(ShortStyle.paletteNames, id: \.self) { Text($0).tag($0) }; Text("Auto").tag("Auto") }.frame(width: 190)
                    Toggle("Beat pulse", isOn: Binding(get: { c.pulse }, set: { v in model.update(clip.id) { $0.pulse = v } })).controlSize(.small)
                    Toggle("Loop ending", isOn: Binding(get: { c.loop }, set: { v in model.update(clip.id) { $0.loop = v } })).controlSize(.small)
                }
                HStack(spacing: 8) {
                    Label(ShortStyle.make(seed: c.styleSeed, clip: c).summary, systemImage: "paintpalette").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { model.shuffleLook(clip.id) } label: { Label("Shuffle title & cuts", systemImage: "dice") }.controlSize(.small)
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
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                nudge("−1", -1) { set(value + $0) }; nudge("−.1", -0.1) { set(value + $0) }
                TextField("", text: Binding(get: { clock(value) }, set: { if let v = parseClock($0) { set(v) } })).textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 74).multilineTextAlignment(.center)
                nudge("+.1", 0.1) { set(value + $0) }; nudge("+1", 1) { set(value + $0) }
            }
            HStack(spacing: 6) {
                Button("Snap to word gap") { set(Pipeline.snap(value, plan: plan, maxDistance: 1.2)) }.controlSize(.small)
                Button { isStart ? model.playRange(c.start, c.start + 4) : model.playRange(max(c.start, c.end - 4), c.end + 0.3) } label: { Label(isStart ? "First 4 s" : "Last 4 s", systemImage: "play.fill") }.controlSize(.small)
            }
        }
    }
    func nudge(_ label: String, _ d: Double, _ f: @escaping (Double) -> Void) -> some View {
        Button(label) { f(d) }
            .buttonStyle(.bordered).controlSize(.small).font(.caption.monospacedDigit())
    }

    var transport: some View {
        HStack(spacing: 10) {
            Button { model.playhead == nil ? model.playRange(c.start, c.end) : model.stopPlayback() } label: {
                Label(model.playhead == nil ? "Play whole clip" : "Stop", systemImage: model.playhead == nil ? "play.fill" : "stop.fill")
            }.controlSize(.large)
            Spacer()
            if let p = model.shortProgress {
                ProgressView(value: p).frame(width: 180); Text("Rendering \(Int(p * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            } else if let out = model.shortOutput {
                Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: { Label("Show in Finder", systemImage: "folder") }
                ShareLink(item: out) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            if c.dynamic {
                Button { model.renderShort(clip.id, variants: 3) } label: { Label("3 variants to A/B test", systemImage: "square.stack.3d.up") }
                    .controlSize(.large).disabled(model.shortProgress != nil)
                    .help("Renders the same clip with three different looks so you can compare retention in YouTube Studio")
            }
            Button { model.renderShort(clip.id) } label: { Label("Render Short", systemImage: "film").font(.headline).padding(.horizontal, 6) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.shortProgress != nil)
        }
    }

    // MARK: preview
    var previewPane: some View {
        VStack(spacing: 8) {
            HStack { Text("Live preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer()
                if model.live.preparing { ProgressView().controlSize(.mini) } }.padding(.top, 14).padding(.horizontal, 20)
            LivePreviewPane(live: model.live, defaultCaption: 0.20) { v in model.setCaptionY(v, shortID: clip.id) }
                .padding(.horizontal, 20)
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
    @State private var dragging: Int? = nil   // 0 = start, 1 = end
    @State private var frozen: ClosedRange<Double>? = nil   // keeps the window still while a handle is dragged

    var c: ShortClip { model.currentShort ?? clip }

    var body: some View {
        VStack(spacing: 6) {
            strip(visible: 0...(model.plan?.songDuration ?? 1), height: 46, editable: false)
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

    func strip(visible: ClosedRange<Double>, height: CGFloat, editable: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = max(0.1, visible.upperBound - visible.lowerBound)
            let x: (Double) -> CGFloat = { t in CGFloat((t - visible.lowerBound) / span) * w }
            let time: (CGFloat) -> Double = { px in visible.lowerBound + Double(px / w) * span }
            Canvas { ctx, size in
                let peaks = model.waveform
                // selection
                let a = x(c.start), b = x(c.end)
                ctx.fill(Path(CGRect(x: max(0, a), y: 0, width: max(0, min(size.width, b) - max(0, a)), height: size.height)), with: .color(.accentColor.opacity(0.18)))
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
                    if dragging == nil { dragging = abs(g.startLocation.x - x(c.start)) <= abs(g.startLocation.x - x(c.end)) ? 0 : 1; frozen = visible }
                    let t = time(min(max(0, g.location.x), w))
                    model.update(id) { if dragging == 0 { $0.start = min(t, $0.end - 2) } else { $0.end = max(t, $0.start + 2) } }
                }
                .onEnded { _ in
                    let which = dragging; dragging = nil; frozen = nil
                    // Audition the edge you just moved: 2.5 s from the start, or the last 2.5 s up to the end.
                    if which == 0 { model.playRange(c.start, c.start + 2.5) } else if which == 1 { model.playRange(max(c.start, c.end - 2.5), c.end + 0.3) }
                } : nil)
            .overlay(alignment: .topLeading) {
                if editable { Text(clock(visible.lowerBound)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary).padding(3) }
            }
            .overlay(alignment: .topTrailing) {
                if editable { Text(clock(visible.upperBound)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary).padding(3) }
            }
        }.frame(height: height)
    }
}
