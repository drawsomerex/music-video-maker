// Choosing which part of a video clip plays.
//
//   [ preview picture ]   a strip of pictures from the clip with a green START and a red END marker
//   [ Play this part ]    (drag the markers, or click the strip to look at a moment, then press "Start here" / "End here")
//   ┌ Start of the clip ───────┐  ┌ End of the clip ─────────┐
//   │ 0:03.0  ◀ ▶ nudge buttons │  │ 0:06.5  ◀ ▶ nudge buttons │
//   └──────────────────────────┘  └──────────────────────────┘
//
// The layout adapts: wide windows put the preview beside the strip and the two cards side by side; narrow windows stack everything.
import SwiftUI
import AVFoundation
import MVCore
import AppKit

struct VideoTrimView: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    let file: String?                // the clip, relative to the project folder
    let knownLength: Double?
    let initialStart: Double
    let initialEnd: Double?
    let clipID: String?              // a generated clip's id; nil = the video dragged into the picture slot
    let partLength: Double
    var fileURL: URL? = nil          // a clip outside the song's folder (the looping video's clip)
    var onCommit: ((Double, Double?) -> Void)? = nil     // where the chosen part goes (the looping video); nil = the song's plan
    var heading = "Video clip", subheading = "Choose which part of the clip is used."

    init(fileURL: URL, length: Double?, start: Double, end: Double?, heading: String, subheading: String, onCommit: @escaping (Double, Double?) -> Void) {
        section = 0; file = fileURL.lastPathComponent; knownLength = length; initialStart = start; initialEnd = end; clipID = nil; partLength = 0
        self.fileURL = fileURL; self.onCommit = onCommit; self.heading = heading; self.subheading = subheading
    }

    init(section: Int, candidate: ImageCandidate, partLength: Double) {
        self.section = section; file = candidate.videoFile; knownLength = candidate.videoLength
        initialStart = candidate.videoStart; initialEnd = candidate.videoEnd; clipID = nil; self.partLength = partLength
    }
    init(section: Int, clip: SectionClip, partLength: Double) {
        self.section = section; file = clip.file; knownLength = clip.seconds
        initialStart = clip.trimStart; initialEnd = clip.trimEnd; clipID = clip.id; self.partLength = partLength
    }
    /// Whether the clip repeats (with a crossfade) in this part of the song, read from the plan.
    private var repeats: Bool {
        guard let p = model.plan else { return false }
        let s = section < 0 ? p.intro : (p.sections.indices.contains(section) ? p.sections[section] : nil)
        guard let s else { return false }
        return clipID != nil ? s.repeatClips : (s.selectedCandidate?.videoRepeat ?? false)
    }
    private var canRepeat: Bool {
        if onCommit != nil { return false }                 // the looping video always repeats
        guard clipID != nil, let p = model.plan else { return true }
        let s = section < 0 ? p.intro : (p.sections.indices.contains(section) ? p.sections[section] : nil)
        return (s?.clips.count ?? 0) == 1
    }

    @State private var length = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var look = 0.0                  // the moment shown in the preview (and marked on the strip)
    static var preload: (strip: [NSImage], frame: NSImage?)? = nil         // screenshots only
    @State private var strip: [NSImage] = VideoTrimView.preload?.strip ?? []
    @State private var shown: NSImage? = VideoTrimView.preload?.frame
    @State private var playing = false
    @State private var playTask: Task<Void, Never>?
    @State private var grab: CGFloat?              // where the handle was when this drag began
    private var minLen: Double { min(0.5, max(0.001, length)) }

    private var url: URL? { fileURL ?? file.flatMap { model.workDir?.appendingPathComponent($0) } }
    private var playsFor: Double { max(0, end - start) }
    private var isWhole: Bool { start <= 0.01 && end >= length - 0.01 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { previewBox.frame(width: 260); VStack(alignment: .leading, spacing: 12) { filmstrip; cards } }
                VStack(alignment: .leading, spacing: 12) { HStack(alignment: .top, spacing: 14) { previewBox.frame(width: 240); Spacer(minLength: 0) }; filmstrip; cards }
            }
            if canRepeat {
                Toggle(isOn: Binding(get: { repeats }, set: { model.setClipRepeat(section: section, on: $0) })) { Text("Repeat the clip until this part of the song ends (with a smooth crossfade)") }
                    .toggleStyle(.switch)
                    .help("Off (the default): the clip plays once, then the last picture holds while the camera moves from one feature to another. On: the clip starts again each time it ends, blending into its own beginning.")
            }
            Text(summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .task(id: file) { await load() }
        .onDisappear { stopPlay() }
    }

    // MARK: pieces
    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Label(heading, systemImage: "film").font(.headline)
                Text(subheading).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { reset() } label: { Label("Use the whole clip", systemImage: "arrow.counterclockwise") }
                .disabled(isWhole).help("Puts the start and end back to the very beginning and very end of the clip.")
        }
    }

    var previewBox: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black)
                if let img = shown { Image(nsImage: img).resizable().scaledToFit() }
                else { ProgressView().controlSize(.small) }
            }
            .aspectRatio(16.0 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(playing ? "Playing — \(clock(look))" : "Looking at \(clock(look))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button { playing ? stopPlay() : play() } label: { Label(playing ? "Stop" : "Play this part", systemImage: playing ? "stop.fill" : "play.fill").frame(maxWidth: .infinity).padding(.vertical, 3) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .help("Plays the part between the green and red markers (no sound here — your song plays in the finished video).")
        }
    }

    var filmstrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let w = max(1, geo.size.width), h: CGFloat = 70, top: CGFloat = 26
                let sx = CGFloat(length > 0 ? start / length : 0) * w, ex = CGFloat(length > 0 ? end / length : 1) * w
                let lx = CGFloat(length > 0 ? look / length : 0) * w
                ZStack(alignment: .topLeading) {
                    // the pictures
                    HStack(spacing: 0) {
                        ForEach(Array(strip.enumerated()), id: \.offset) { _, img in
                            Image(nsImage: img).resizable().scaledToFill().frame(width: w / CGFloat(max(1, strip.count)), height: h).clipped()
                        }
                    }
                    .frame(width: w, height: h).background(Color.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 8)).offset(y: top)
                    // dimmed = not used
                    Rectangle().fill(.black.opacity(0.62)).frame(width: max(0, sx), height: h).offset(y: top)
                    Rectangle().fill(.black.opacity(0.62)).frame(width: max(0, w - ex), height: h).offset(x: ex, y: top)
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white, lineWidth: 2).frame(width: max(3, ex - sx), height: h).offset(x: sx, y: top)
                    // where the preview is looking
                    Rectangle().fill(.white).frame(width: 2, height: h + 6).shadow(radius: 2).offset(x: lx - 1, y: top - 3)
                    // markers: the bars sit on the strip; START's time label is above it, END's is below, so they never collide
                    bar(.green).accessibilityLabel("Clip start marker").accessibilityValue(clock(start)).accessibilityAdjustableAction { d in move(start: true, to: start + (d == .increment ? 0.1 : -0.1)); commit() }.offset(x: min(max(0, sx - 11), w - 22), y: top - 3).zIndex(2)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("strip")).onChanged { g in dragHandle(isStart: true, g, from: sx, width: w) }.onEnded { _ in grab = nil; commit() })
                    bar(.red).accessibilityLabel("Clip end marker").accessibilityValue(clock(end)).accessibilityAdjustableAction { d in move(start: false, to: end + (d == .increment ? 0.1 : -0.1)); commit() }.offset(x: min(max(0, ex - 11), w - 22), y: top - 3).zIndex(2)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("strip")).onChanged { g in dragHandle(isStart: false, g, from: ex, width: w) }.onEnded { _ in grab = nil; commit() })
                    pill("START \(clock(start))", .green).offset(x: min(max(0, sx - 55), max(0, w - 110)), y: 0)
                    pill("END \(clock(end))", .red).offset(x: min(max(0, ex - 55), max(0, w - 110)), y: top + h + 6)
                }
                .frame(width: w, height: top + h + 34, alignment: .topLeading)
                .coordinateSpace(name: "strip")
                .contentShape(Rectangle())
                .onTapGesture { p in if p.y > top { stopPlay(); showFrame(at: Double(max(0, min(1, p.x / w))) * length) } }
                .help("The whole clip from beginning to end. The bright part between the markers is what is used. Click a picture to look at that moment.")
            }
            .frame(height: 130)
            HStack {
                Text("0:00.0").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer()
                Text("Drag the green and red markers — or click a picture to look at it").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(clock(length)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
    }

    func bar(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(color).frame(width: 22, height: 76)
            .overlay(VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(.white.opacity(0.9)).frame(width: 10, height: 2) } })
            .shadow(radius: 2).contentShape(Rectangle())
            .help(color == .green ? "Drag to choose where the clip starts playing." : "Drag to choose where the clip stops.")
    }
    func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(color)).frame(width: 110, alignment: .center).fixedSize()
    }

    var cards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { card(isStart: true); card(isStart: false) }
            VStack(spacing: 12) { card(isStart: true); card(isStart: false) }
        }
    }

    func card(isStart: Bool) -> some View {
        let color: Color = isStart ? .green : .red, t = isStart ? start : end
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 12, height: 12)
                Text(isStart ? "Start of the clip" : "End of the clip").font(.callout.weight(.semibold))
                Spacer()
                TextField("Seconds", value: Binding(get: { t }, set: { value in move(start: isStart, to: value); commit() }), format: .number.precision(.fractionLength(0...3)))
                    .textFieldStyle(.roundedBorder).frame(width: 95)
                    .accessibilityLabel(isStart ? "Clip start in seconds" : "Clip end in seconds")
                    .help("Type an exact time in seconds, then press Return.")
            }
            Button { move(start: isStart, to: look); commit() } label: { Label(isStart ? "Start here (at \(clock(look)))" : "End here (at \(clock(look)))", systemImage: "scope").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.regular)
                .help(isStart ? "Makes the clip start at the moment you are looking at in the preview. Click a picture in the strip first to choose the moment." : "Makes the clip stop at the moment you are looking at in the preview. Click a picture in the strip first to choose the moment.")
            HStack(spacing: 6) {
                Text(isStart ? "Start" : "End").font(.caption).foregroundStyle(.secondary)
                nudge(-0.5, isStart); nudge(-0.1, isStart); nudge(0.1, isStart); nudge(0.5, isStart)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.5), lineWidth: 1.5))
    }

    func nudge(_ d: Double, _ isStart: Bool) -> some View {
        Button { move(start: isStart, to: (isStart ? start : end) + d); commit() } label: {
            Text(String(format: "%@%g s", d < 0 ? "−" : "+", abs(d))).font(.callout.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .help(isStart ? (d < 0 ? "Start the clip \(abs(d)) seconds earlier." : "Start the clip \(abs(d)) seconds later.")
                      : (d < 0 ? "Stop the clip \(abs(d)) seconds earlier." : "Stop the clip \(abs(d)) seconds later."))
    }

    var summary: String {
        var s = isWhole ? "The whole clip is used (\(String(format: "%.1f", playsFor)) seconds)." : "Using \(String(format: "%.1f", playsFor)) seconds of the \(String(format: "%.1f", length))-second clip: from \(clock(start)) to \(clock(end))."
        if onCommit != nil { s += " This part repeats for the whole video. Its end overlaps its beginning with a blend that fits the selected range." }
        if partLength > 0 {
            if playsFor + 0.3 < partLength { s += repeats && canRepeat ? " This part of the song lasts \(Int(partLength.rounded())) seconds, so the clip repeats." : " This part of the song lasts \(Int(partLength.rounded())) seconds: the clip plays once, then the last picture holds and the camera moves between its main features." }
            else if playsFor > partLength + 0.3 { s += " This part of the song lasts \(Int(partLength.rounded())) seconds, so the end of the clip is not reached." }
        }
        return s
    }

    // MARK: behaviour
    func clock(_ t: Double) -> String { String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }

    /// The handle follows the mouse: its position when the drag began plus how far the mouse has travelled (measured on the strip, which does not move).
    func dragHandle(isStart: Bool, _ g: DragGesture.Value, from x0: CGFloat, width w: CGFloat) {
        if grab == nil { grab = x0 }
        let x = (grab ?? x0) + (g.location.x - g.startLocation.x)
        move(start: isStart, to: Double(min(max(0, x), w) / w) * length)
    }

    func move(start isStart: Bool, to raw: Double) {
        stopPlay()
        let t = (min(max(0, raw), length) * 10).rounded() / 10
        if isStart { start = max(0, min(t, end - minLen)); showFrame(at: start) }
        else { end = min(length, max(t, start + minLen)); showFrame(at: max(start, end - 0.05)) }
    }
    func commit() {
        let e: Double? = end >= length - 0.01 ? nil : end
        if let f = onCommit { f(start, e); return }
        if let id = clipID { model.setClipTrim(section: section, clip: id, start: start, end: e) } else { model.setVideoTrim(section: section, start: start, end: e) }
    }
    func reset() { stopPlay(); start = 0; end = length; commit(); showFrame(at: 0) }

    func generator(max px: CGFloat = 640) -> AVAssetImageGenerator? {
        guard let u = url else { return nil }
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: u)); g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: px, height: px)
        g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        return g
    }
    func showFrame(at t: Double) {
        look = min(max(0, t), length)
        guard let g = generator() else { return }
        let at = look
        Task { if let r = try? await g.image(at: CMTime(seconds: min(at, max(0, length - 0.05)), preferredTimescale: 600)) { shown = NSImage(cgImage: r.image, size: .zero) } }
    }
    func play() {
        playing = true
        playTask = Task {
            guard let g = generator(max: 480) else { playing = false; return }
            var t = start
            while !Task.isCancelled && t < end {
                look = t
                if let r = try? await g.image(at: CMTime(seconds: t, preferredTimescale: 600)) { shown = NSImage(cgImage: r.image, size: .zero) }
                try? await Task.sleep(nanoseconds: 100_000_000); t += 0.1
            }
            playing = false
            if !Task.isCancelled { showFrame(at: start) }
        }
    }
    func stopPlay() { playTask?.cancel(); playTask = nil; playing = false }

    func load() async {
        guard let u = url else { return }
        let asset = AVURLAsset(url: u)
        var len = knownLength ?? 0
        if len <= 0, let d = try? await asset.load(.duration) { len = CMTimeGetSeconds(d) }
        length = max(0.001, len.isFinite ? len : 0.001)
        start = min(initialStart, length - minLen); end = min(initialEnd ?? length, length)
        if end <= start { end = length }
        showFrame(at: start)
        guard let g = generator(max: 240) else { return }
        var imgs: [NSImage] = []
        let n = 14
        for i in 0..<n {
            let t = length * (Double(i) + 0.5) / Double(n)
            if let r = try? await g.image(at: CMTime(seconds: t, preferredTimescale: 600)) { imgs.append(NSImage(cgImage: r.image, size: .zero)) }
        }
        strip = imgs
    }
}
