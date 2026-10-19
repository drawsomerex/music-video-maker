// Live preview that renders the real composition, with draggable captions and safe zones.
import SwiftUI
import AVFoundation
import MVCore
import CryptoKit

/// Real-time preview of the *actual* composition: the same FrameComposer the final render uses, drawn at preview size
/// next to the song's audio. Dragging the captions changes a live parameter, so there's no rebuild.
@MainActor
final class LivePreview: ObservableObject {
    @Published var image: NSImage?
    @Published var time = 0.0
    @Published var playing = false
    @Published var duration = 1.0
    @Published var preparing = false
    @Published var preparingPhase = "Building preview…"
    @Published var preparingProgress = 0.0
    @Published var captionY: Double?

    private var composer: FrameComposer?
    private var key = ""
    private var loadID = UUID()
    private var frameGeneration = UUID()
    private var clockAnchor: Date?
    private var clockStart = 0.0
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var busy = false
    private var pending: Double?
    private var audioStart = 0.0
    private var fadeIn = false
    private let queue = DispatchQueue(label: "mv.live", qos: .userInitiated)
    @Published private(set) var vertical = true

    /// Builds (or reuses) the composer for this plan/clip. Cheap when nothing changed.
    func load(plan: Plan, work: URL, clip: ShortClip?, audio: URL) async {
        guard !Task.isCancelled else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var bytes = (try? encoder.encode(plan)) ?? Data()
        bytes.append((try? encoder.encode(clip)) ?? Data())
        bytes.append(Data((work.path + Transcriber.fileStamp(audio.path)).utf8))
        for section in [plan.intro] + plan.sections {
            if let c = section.selectedCandidate {
                for file in [c.fullFile, c.videoFile].compactMap({ $0 }) { bytes.append(Data(Transcriber.fileStamp(work.appendingPathComponent(file).path).utf8)) }
            }
        }
        let sig = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let request = UUID(); loadID = request
        defer { if loadID == request { preparing = false } }
        vertical = clip != nil
        duration = clip.map(\.duration) ?? (plan.songDuration + plan.audioOffset)
        audioStart = clip?.start ?? -plan.audioOffset
        fadeIn = clip?.dynamic ?? false
        if sig == key, composer != nil { return }
        pause()
        preparing = true; preparingPhase = "Analyzing beats & timing…"; preparingProgress = 0.15
        let cap = clip?.captionY ?? plan.captionY
        let owner = self
        let build = Task.detached(priority: .userInitiated) { () -> FrameComposer in
            var s = clip != nil ? VideoSettings(height: 960) : VideoSettings(height: 540)
            if clip != nil { s.width = 540 }
            var beats: [Double] = []
            if let c = clip, c.dynamic {
                let st = ShortStyle.make(seed: c.styleSeed, clip: c)
                if st.pulse > 0 || !st.calm { beats = await BeatDetector.beats(audioPath: audio.path, start: c.start, end: c.end, work: work) }
            }
            await MainActor.run { if owner.loadID == request { owner.preparingPhase = "Composing lyric & scene layers…"; owner.preparingProgress = 0.6 } }
            let comp = FrameComposer(plan: plan, work: work, settings: s, short: clip, beats: beats)
            comp.captionBottom = cap
            return comp
        }
        let built = await withTaskCancellationHandler { await build.value } onCancel: { build.cancel() }
        guard !Task.isCancelled, loadID == request else { return }
        frameGeneration = UUID()
        preparingPhase = "Rendering first frame…"; preparingProgress = 0.9
        composer = built; key = sig; captionY = cap
        if let p = try? AVAudioPlayer(contentsOf: audio) { player = p; p.prepareToPlay() }
        render(at: min(time, max(0, duration - 0.1)))
        preparingProgress = 1.0; preparing = false
    }

    func invalidate() { key = ""; loadID = UUID(); frameGeneration = UUID(); preparing = false }
    /// Screenshots only: show a ready-made picture instead of building the preview.
    func setStill(_ img: NSImage, vertical v: Bool) { image = img; vertical = v; preparing = false }

    // MARK: frames
    func render(at t: Double) {
        guard let comp = composer else { return }
        if busy { pending = t; return }
        busy = true
        let tt = min(max(0, t), max(0, comp.totalDuration - 0.02))
        let generation = frameGeneration
        queue.async { [weak self] in
            let cg = comp.still(at: tt)
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            DispatchQueue.main.async {
                guard let self else { return }
                if self.frameGeneration == generation { self.image = img }; self.busy = false
                if let p = self.pending { self.pending = nil; self.render(at: p) }
            }
        }
    }

    func seek(_ t: Double) {
        let wasPlaying = playing
        if wasPlaying { pause() }
        time = min(max(0, t), duration)
        if wasPlaying { toggle() }
        render(at: time)
    }

    func setCaption(_ v: Double?) {
        captionY = v
        if let comp = composer { queue.async { comp.captionBottom = v } }
        render(at: time)
    }

    // MARK: playback
    func toggle() {
        if playing { pause(); return }
        guard let p = player else { return }
        if time >= duration - 0.05 { time = 0 }
        let audioTime = audioStart + time
        p.currentTime = max(0, audioTime)
        p.volume = fadeIn && time < 0.1 ? 0 : 1
        if audioTime < 0 { p.play(atTime: p.deviceCurrentTime - audioTime) } else { p.play() }
        if fadeIn && time < 0.1 { p.setVolume(1, fadeDuration: 1.8) }
        clockAnchor = Date(); clockStart = time; playing = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let anchor = self.clockAnchor else { return }
                self.time = min(self.duration, self.clockStart + Date().timeIntervalSince(anchor))
                self.render(at: self.time)
                if self.time >= self.duration - 0.01 { self.pause() }
            }
        }
    }

    func pause() { timer?.invalidate(); timer = nil; player?.pause(); playing = false; clockAnchor = nil }
}

/// The preview with draggable captions, a safe-zone overlay and transport controls.
struct LivePreviewPane: View {
    @ObservedObject var live: LivePreview
    let defaultCaption: Double
    let onCaptionCommit: (Double?) -> Void
    @State private var safeZones = true       // Shorts: show where YouTube's own buttons and text cover the picture
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
                } else {
                    VStack(spacing: 10) {
                        ProgressView(value: live.preparingProgress).progressViewStyle(.linear).frame(width: 180)
                        Text(live.preparingPhase).font(.caption).foregroundStyle(.white.opacity(0.85))
                    }.padding(16)
                }
                if live.preparing && live.image != nil {
                    VStack(spacing: 6) {
                        ProgressView(value: live.preparingProgress).progressViewStyle(.linear).frame(width: 160)
                        Text(live.preparingPhase).font(.caption2).foregroundStyle(.primary)
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .aspectRatio(live.vertical ? 9.0 / 16 : 16.0 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(radius: 8, y: 3)

            HStack(spacing: 8) {
                Button { live.toggle() } label: { Image(systemName: live.playing ? "pause.fill" : "play.fill").frame(width: 18) }.buttonStyle(.borderedProminent).controlSize(.large).help(live.playing ? "Pause the preview." : "Play the preview with your song.")
                Slider(value: Binding(get: { live.time }, set: { live.seek($0) }), in: 0...max(1, live.duration)).help("Choose where to watch the preview.")
                Text("\(clock(live.time))").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble").foregroundStyle(.secondary)
                Slider(value: Binding(get: { live.captionY ?? defaultCaption }, set: { live.setCaption($0) }), in: 0.04...0.86) { editing in if !editing { onCaptionCommit(live.captionY) } }
                    .help("Move the lyrics higher or lower in the picture.")
                Button("Reset") { live.setCaption(nil); onCaptionCommit(nil) }.controlSize(.mini).disabled(live.captionY == nil).help("Put the words back in their usual place.")
            }
            HStack {
                Text("Drag the captions in the preview, or use the slider").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if live.vertical { Toggle("Safe zones", isOn: $safeZones).toggleStyle(.checkbox).controlSize(.mini).help("Red areas are covered by YouTube's own buttons and title. Keep the words out of them.") }
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
