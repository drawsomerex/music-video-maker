// Choosing which part of a video clip plays: a strip of pictures from the clip with a green START and a red END marker.
// Drag the markers (or use the small buttons); the picture on the left always shows the frame at the marker you moved,
// and "Play this part" runs through the chosen stretch. Everything outside the markers is dimmed and is not used.
import SwiftUI
import AVFoundation
import MVCore
import AppKit

struct VideoTrimView: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    let candidate: ImageCandidate
    let partLength: Double

    @State private var length = 0.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var strip: [NSImage] = []
    @State private var shown: NSImage?
    @State private var shownLabel = ""
    @State private var playing = false
    @State private var playTask: Task<Void, Never>?
    @State private var dragging = false
    private let minLen = 0.5

    private var url: URL? { candidate.videoFile.flatMap { model.workDir?.appendingPathComponent($0) } }
    private var playsFor: Double { max(0, end - start) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Which part of the video clip to use").font(.headline)
                Spacer()
                Button { reset() } label: { Label("Use the whole clip", systemImage: "arrow.counterclockwise") }
                    .disabled(start <= 0.01 && end >= length - 0.01).help("Puts the start and end back to the very beginning and very end of the clip.")
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(.black)
                        if let img = shown { Image(nsImage: img).resizable().scaledToFit() }
                    }.frame(width: 190, height: 107).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(shownLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button { playing ? stopPlay() : play() } label: { Label(playing ? "Stop" : "Play this part", systemImage: playing ? "stop.fill" : "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                        .help("Plays the part between the green and red markers (without sound — your song plays in the finished video).")
                }
                VStack(alignment: .leading, spacing: 8) {
                    filmstrip.frame(height: 62)
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 10, height: 10)
                        Text("Starts at").font(.callout.weight(.semibold)); Text(clock(start)).font(.callout.monospacedDigit())
                        nudge(-0.5, isStart: true); nudge(-0.1, isStart: true); nudge(0.1, isStart: true); nudge(0.5, isStart: true)
                        Spacer(minLength: 8)
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("Ends at").font(.callout.weight(.semibold)); Text(clock(end)).font(.callout.monospacedDigit())
                        nudge(-0.5, isStart: false); nudge(-0.1, isStart: false); nudge(0.1, isStart: false); nudge(0.5, isStart: false)
                    }
                    Text(summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .task(id: candidate.videoFile) { await load() }
        .onDisappear { stopPlay() }
    }

    var summary: String {
        let whole = start <= 0.01 && end >= length - 0.01
        var s = whole ? "The whole clip plays (\(String(format: "%.1f", playsFor)) s)." : "Only this part of the clip plays: \(String(format: "%.1f", playsFor)) s of \(String(format: "%.1f", length)) s."
        if partLength > 0 { s += playsFor + 0.3 < partLength ? " This part of the song lasts \(Int(partLength.rounded())) s, so the clip repeats." : (playsFor > partLength + 0.3 ? " This part of the song lasts \(Int(partLength.rounded())) s, so the end of the clip is not reached." : "") }
        return s + " Drag the green and red markers, or click a picture in the strip."
    }

    // MARK: the strip
    var filmstrip: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let sx = CGFloat(length > 0 ? start / length : 0) * w, ex = CGFloat(length > 0 ? end / length : 1) * w
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(strip.enumerated()), id: \.offset) { _, img in
                        Image(nsImage: img).resizable().scaledToFill().frame(width: w / CGFloat(max(1, strip.count)), height: h).clipped()
                    }
                }.frame(width: w, height: h).background(Color.black.opacity(0.15))
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, sx), height: h)                       // before the start: not used
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, w - ex), height: h).offset(x: ex)     // after the end: not used
                Rectangle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2).frame(width: max(2, ex - sx), height: h).offset(x: sx)
                marker(.green, label: "START").offset(x: sx - 7)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in move(start: true, to: Double((sx + g.translation.width + 7) / w) * length) }.onEnded { _ in commit() })
                marker(.red, label: "END").offset(x: ex - 7)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in move(start: false, to: Double((ex + g.translation.width + 7) / w) * length) }.onEnded { _ in commit() })
            }
            .contentShape(Rectangle())
            .onTapGesture { location in showFrame(at: Double(location.x / w) * length, label: "Frame at \(clock(Double(location.x / w) * length))") }
            .help("The clip from beginning to end. The bright part between the markers is what plays. Click anywhere to look at that moment.")
        }
    }

    func marker(_ color: Color, label: String) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 4).background(color)
            Rectangle().fill(color).frame(width: 14)
        }.frame(width: 14).contentShape(Rectangle())
            .help(label == "START" ? "Drag to choose where the clip starts playing." : "Drag to choose where the clip stops.")
    }

    func nudge(_ d: Double, isStart: Bool) -> some View {
        Button { move(start: isStart, to: (isStart ? start : end) + d); commit() } label: { Text((d > 0 ? "+" : "−") + String(format: "%g", abs(d))).font(.caption.monospacedDigit()) }
            .buttonStyle(.bordered).controlSize(.small)
            .help(isStart ? (d < 0 ? "Start the clip \(abs(d)) s earlier." : "Start the clip \(abs(d)) s later.") : (d < 0 ? "Stop the clip \(abs(d)) s earlier." : "Stop the clip \(abs(d)) s later."))
    }

    // MARK: behaviour
    func clock(_ t: Double) -> String { String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) }

    func move(start isStart: Bool, to raw: Double) {
        stopPlay(); dragging = true
        let t = (min(max(0, raw), length) * 10).rounded() / 10
        if isStart { start = min(t, end - minLen); start = max(0, start); showFrame(at: start, label: "Starts here: \(clock(start))") }
        else { end = max(t, start + minLen); end = min(length, end); showFrame(at: max(start, end - 0.05), label: "Ends here: \(clock(end))") }
    }
    func commit() { dragging = false; model.setVideoTrim(section: section, start: start, end: end >= length - 0.01 ? nil : end) }
    func reset() { stopPlay(); start = 0; end = length; commit(); showFrame(at: 0, label: "Starts here: \(clock(0))") }

    func generator() -> AVAssetImageGenerator? {
        guard let u = url else { return nil }
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: u)); g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 480, height: 480)
        g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        return g
    }
    func showFrame(at t: Double, label: String) {
        shownLabel = label
        guard let g = generator() else { return }
        Task { if let r = try? await g.image(at: CMTime(seconds: min(max(0, t), max(0, length - 0.05)), preferredTimescale: 600)) { shown = NSImage(cgImage: r.image, size: .zero) } }
    }
    func play() {
        playing = true
        playTask = Task {
            guard let g = generator() else { playing = false; return }
            var t = start
            while !Task.isCancelled && t < end {
                if let r = try? await g.image(at: CMTime(seconds: t, preferredTimescale: 600)) { shown = NSImage(cgImage: r.image, size: .zero); shownLabel = "Playing: \(clock(t))" }
                try? await Task.sleep(nanoseconds: 120_000_000); t += 0.12
            }
            playing = false; showFrame(at: start, label: "Starts here: \(clock(start))")
        }
    }
    func stopPlay() { playTask?.cancel(); playTask = nil; playing = false }

    func load() async {
        guard let u = url else { return }
        let asset = AVURLAsset(url: u)
        var len = candidate.videoLength ?? 0
        if len <= 0, let d = try? await asset.load(.duration) { len = CMTimeGetSeconds(d) }
        length = max(0.5, len)
        start = min(candidate.videoStart, length - minLen); end = min(candidate.videoEnd ?? length, length)
        if end <= start { end = length }
        showFrame(at: start, label: "Starts here: \(clock(start))")
        guard let g = generator() else { return }
        g.maximumSize = CGSize(width: 240, height: 140)
        var imgs: [NSImage] = []
        let n = 12
        for i in 0..<n {
            let t = length * (Double(i) + 0.5) / Double(n)
            if let r = try? await g.image(at: CMTime(seconds: t, preferredTimescale: 600)) { imgs.append(NSImage(cgImage: r.image, size: .zero)) }
        }
        strip = imgs
    }
}
