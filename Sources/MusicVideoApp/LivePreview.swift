// Live preview that renders the real composition, with draggable captions and safe zones.
import SwiftUI
import AVFoundation
import MVCore

/// Real-time preview of the *actual* composition: the same FrameComposer the final render uses, drawn at preview size
/// next to the song's audio. Dragging the captions changes a live parameter, so there's no rebuild.
@MainActor
final class LivePreview: ObservableObject {
    @Published var image: NSImage?
    @Published var time = 0.0
    @Published var playing = false
    @Published var duration = 1.0
    @Published var preparing = false
    @Published var captionY: Double?

    private var composer: FrameComposer?
    private var key = ""
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var busy = false
    private var pending: Double?
    private var audioStart = 0.0
    private var fadeIn = false
    private let queue = DispatchQueue(label: "mv.live", qos: .userInitiated)
    private(set) var vertical = true

    /// Builds (or reuses) the composer for this plan/clip. Cheap when nothing changed.
    func load(plan: Plan, work: URL, clip: ShortClip?, audio: URL) async {
        let sig = [clip.map { "\($0.id)|\($0.start)|\($0.end)|\($0.dynamic)|\($0.styleSeed)|\($0.hook)|\($0.cta)|\($0.motion)|\($0.textStyle)|\($0.accent)|\($0.pulse)|\($0.loop)" } ?? "full",
                   plan.sections.map { $0.selectedCandidate?.fullFile ?? "-" }.joined(separator: ","), "\(plan.lines.count)|\(plan.lines.first?.start ?? 0)|\(plan.title)"].joined(separator: "#")
        vertical = clip != nil
        duration = clip.map(\.duration) ?? (plan.songDuration + plan.audioOffset)
        audioStart = clip?.start ?? 0
        fadeIn = clip?.dynamic ?? false
        if sig == key, composer != nil { return }
        pause()
        preparing = true
        let cap = clip?.captionY ?? plan.captionY
        let built: FrameComposer = await Task.detached(priority: .userInitiated) {
            var s = clip != nil ? VideoSettings(height: 960) : VideoSettings(height: 540)
            if clip != nil { s.width = 540 }
            var beats: [Double] = []
            if let c = clip, c.dynamic, ShortStyle.make(seed: c.styleSeed, clip: c).pulse > 0 { beats = await BeatDetector.beats(audioPath: audio.path, start: c.start, end: c.end) }
            let comp = FrameComposer(plan: plan, work: work, settings: s, short: clip, beats: beats)
            comp.captionBottom = cap
            return comp
        }.value
        composer = built; key = sig; captionY = cap; preparing = false
        if let p = try? AVAudioPlayer(contentsOf: audio) { player = p; p.prepareToPlay() }
        render(at: min(time, max(0, duration - 0.1)))
    }

    func invalidate() { key = "" }

    // MARK: frames
    func render(at t: Double) {
        guard let comp = composer else { return }
        if busy { pending = t; return }
        busy = true
        let tt = min(max(0.02, t), comp.totalDuration - 0.02)
        queue.async { [weak self] in
            let cg = comp.still(at: tt)
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            DispatchQueue.main.async {
                guard let self else { return }
                self.image = img; self.busy = false
                if let p = self.pending { self.pending = nil; self.render(at: p) }
            }
        }
    }

    func seek(_ t: Double) {
        time = min(max(0, t), duration)
        if playing { player?.currentTime = audioStart + time }
        render(at: time)
    }

    func setCaption(_ v: Double?) {
        captionY = v; composer?.captionBottom = v
        render(at: time)
    }

    // MARK: playback
    func toggle() { playing ? pause() : play() }

    func play() {
        guard let p = player, composer != nil else { return }
        if time >= duration - 0.2 { time = 0 }
        p.currentTime = audioStart + time
        if fadeIn && time < 0.1 { p.volume = 0; p.play(); p.setVolume(1, fadeDuration: 1.8) } else { p.volume = 1; p.play() }
        playing = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.time = max(0, p.currentTime - self.audioStart)
                self.render(at: self.time)
                if self.time >= self.duration - 0.05 || !p.isPlaying { self.pause() }
            }
        }
    }

    func pause() { timer?.invalidate(); timer = nil; player?.pause(); playing = false }
}

/// The preview with draggable captions, a safe-zone overlay and transport controls.
struct LivePreviewPane: View {
    @ObservedObject var live: LivePreview
    let defaultCaption: Double
    let onCaptionCommit: (Double?) -> Void
    @State private var safeZones = false
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.black)
                if let img = live.image {
                    GeometryReader { geo in
                        Image(nsImage: img).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                            .overlay { overlays(geo.size) }
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    dragging = true
                                    live.setCaption(min(0.86, max(0.04, 1 - g.location.y / geo.size.height)))
                                }
                                .onEnded { _ in dragging = false; onCaptionCommit(live.captionY) })
                    }
                } else { ProgressView(live.preparing ? "Building preview…" : "") }
            }
            .aspectRatio(live.vertical ? 9.0 / 16 : 16.0 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(radius: 8, y: 3)

            HStack(spacing: 8) {
                Button { live.toggle() } label: { Image(systemName: live.playing ? "pause.fill" : "play.fill").frame(width: 18) }.buttonStyle(.borderedProminent).controlSize(.small)
                Slider(value: Binding(get: { live.time }, set: { live.seek($0) }), in: 0...max(1, live.duration))
                Text("\(clock(live.time))").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble").foregroundStyle(.secondary)
                Slider(value: Binding(get: { live.captionY ?? defaultCaption }, set: { live.setCaption($0) }), in: 0.04...0.86) { editing in if !editing { onCaptionCommit(live.captionY) } }
                Button("Reset") { live.setCaption(nil); onCaptionCommit(nil) }.controlSize(.mini).disabled(live.captionY == nil)
            }
            HStack {
                Text("Drag the captions in the preview, or use the slider").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if live.vertical { Toggle("Safe zones", isOn: $safeZones).toggleStyle(.checkbox).controlSize(.mini) }
            }
        }
    }

    @ViewBuilder func overlays(_ size: CGSize) -> some View {
        let y = size.height * (1 - (live.captionY ?? defaultCaption))
        ZStack {
            if dragging { Rectangle().fill(.white.opacity(0.8)).frame(height: 1).position(x: size.width / 2, y: y) }
            if safeZones && live.vertical {
                // Where YouTube's own UI sits: title/description along the bottom, buttons down the right, search/channel up top.
                Color.red.opacity(0.18).frame(height: size.height * 0.20).position(x: size.width / 2, y: size.height * 0.90)
                Color.red.opacity(0.18).frame(width: size.width * 0.16, height: size.height * 0.45).position(x: size.width * 0.92, y: size.height * 0.62)
                Color.red.opacity(0.18).frame(height: size.height * 0.08).position(x: size.width / 2, y: size.height * 0.04)
            }
        }.allowsHitTesting(false)
    }
}
