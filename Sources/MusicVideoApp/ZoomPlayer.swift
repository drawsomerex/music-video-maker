// Watching a video full screen and zoomed in on any part: for checking a loop closely, and for anyone who needs to see it bigger.
// Pinch, the scroll wheel or the + and − buttons zoom where the pointer is; drag (or the arrow keys) moves around; double-click zooms in or back out;
// Esc closes. The controls are large and high-contrast.
import SwiftUI
import AVKit
import AppKit

/// The video, zoomable and movable inside the screen.
final class ZoomVideoView: NSView {
    let playerLayer = AVPlayerLayer()
    private var picture: CALayer?                          // a still picture instead of a video
    private var pictureSize: CGSize?
    static let maxScale: CGFloat = 8
    private(set) var scale: CGFloat = 1
    private var centre = CGPoint(x: 0.5, y: 0.5)          // the point of the video in the middle of the screen (0…1 from the top left)
    var onChange: ((CGFloat) -> Void)?
    var onClose: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onToggleControls: (() -> Void)?

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer(); layer?.backgroundColor = NSColor.black.cgColor; layer?.masksToBounds = true
        playerLayer.player = player; playerLayer.videoGravity = .resize
        layer?.addSublayer(playerLayer)
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("The video, zoomable")
    }
    /// A still picture, zoomable the same way.
    init(image: NSImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer(); layer?.backgroundColor = NSColor.black.cgColor; layer?.masksToBounds = true
        let l = CALayer(); l.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil); l.contentsGravity = .resize; l.magnificationFilter = .trilinear
        layer?.addSublayer(l); picture = l; pictureSize = image.size
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("The picture, zoomable")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var aspect: CGFloat {
        let s = pictureSize ?? playerLayer.player?.currentItem?.presentationSize ?? .zero
        return s.width > 0 && s.height > 0 ? s.width / s.height : 16.0 / 9
    }
    /// The whole video fitted to the screen.
    private var fitted: CGRect {
        let b = bounds; guard b.width > 0, b.height > 0 else { return b }
        let w = min(b.width, b.height * aspect), h = w / aspect
        return CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
    }
    /// Where the video is drawn now.
    private var shown: CGRect {
        let f = fitted, size = CGSize(width: f.width * scale, height: f.height * scale)
        var o = CGPoint(x: bounds.midX - centre.x * size.width, y: bounds.midY - centre.y * size.height)
        // never leave a gap at an edge while zoomed in; smaller than the screen: centred
        o.x = size.width > bounds.width ? min(0, max(bounds.width - size.width, o.x)) : (bounds.width - size.width) / 2
        o.y = size.height > bounds.height ? min(0, max(bounds.height - size.height, o.y)) : (bounds.height - size.height) / 2
        return CGRect(origin: o, size: size)
    }
    private func place() {
        let r = shown
        centre = CGPoint(x: (bounds.midX - r.minX) / r.width, y: (bounds.midY - r.minY) / r.height)
        CATransaction.begin(); CATransaction.setDisableActions(true); playerLayer.frame = r; picture?.frame = r; CATransaction.commit()
        onChange?(scale)
        window?.invalidateCursorRects(for: self)
    }
    override func layout() { super.layout(); place() }

    /// Zooms by `factor`, keeping the point under `at` (the pointer, or the middle of the screen) where it is.
    func zoom(by factor: CGFloat, at: CGPoint? = nil) {
        let p = at ?? CGPoint(x: bounds.midX, y: bounds.midY), old = shown
        let u = CGPoint(x: (p.x - old.minX) / old.width, y: (p.y - old.minY) / old.height)
        scale = min(Self.maxScale, max(1, scale * factor))
        let f = fitted, size = CGSize(width: f.width * scale, height: f.height * scale)
        let origin = CGPoint(x: p.x - u.x * size.width, y: p.y - u.y * size.height)
        centre = CGPoint(x: (bounds.midX - origin.x) / size.width, y: (bounds.midY - origin.y) / size.height)
        place()
    }
    func fit() { scale = 1; centre = CGPoint(x: 0.5, y: 0.5); place() }
    func move(dx: CGFloat, dy: CGFloat) {
        let r = shown
        centre = CGPoint(x: centre.x - dx / r.width, y: centre.y - dy / r.height); place()
    }

    override func magnify(with e: NSEvent) { zoom(by: 1 + e.magnification, at: convert(e.locationInWindow, from: nil)) }
    override func scrollWheel(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if e.hasPreciseScrollingDeltas && !e.modifierFlags.contains(.command) {     // a trackpad: two fingers move around (pinch zooms)
            if scale > 1 { move(dx: e.scrollingDeltaX, dy: e.scrollingDeltaY) }
        } else {                                                                      // a mouse wheel (or ⌘ + trackpad): zoom where the pointer is
            let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 120 : e.scrollingDeltaY / 6
            zoom(by: pow(1.25, d), at: p)
        }
    }
    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        if e.clickCount == 2 { scale > 1.01 ? fit() : zoom(by: 2.5, at: convert(e.locationInWindow, from: nil)) }
    }
    override func mouseDragged(with e: NSEvent) { if scale > 1 { move(dx: e.deltaX, dy: e.deltaY) } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: scale > 1 ? .openHand : .arrow) }
    override func keyDown(with e: NSEvent) {
        let step = bounds.width * 0.08
        switch e.keyCode {
        case 53: onClose?()                                       // Esc
        case 49: onPlayPause?()                                   // space
        case 123: move(dx: step, dy: 0); case 124: move(dx: -step, dy: 0)
        case 125: move(dx: 0, dy: -step); case 126: move(dx: 0, dy: step)
        default:
            switch e.charactersIgnoringModifiers {
            case "+", "=": zoom(by: 1.5); case "-", "_": zoom(by: 1 / 1.5); case "0": fit()
            case "h", "H": onToggleControls?()
            default: super.keyDown(with: e)
            }
        }
    }
}

final class ZoomModel: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var playing = true
    @Published var showControls = true
    let player: AVPlayer
    var image: NSImage?                                    // a still picture instead of a video
    var looper: AVPlayerLooper?
    weak var view: ZoomVideoView?
    init(player: AVPlayer, looper: AVPlayerLooper?) { self.player = player; self.looper = looper }
    func playPause() { if playing { player.pause() } else { player.play() }; playing.toggle() }
}

struct ZoomVideo: NSViewRepresentable {
    let model: ZoomModel
    let close: () -> Void
    func makeNSView(context: Context) -> ZoomVideoView {
        let v = model.image.map { ZoomVideoView(image: $0) } ?? ZoomVideoView(player: model.player)
        v.onChange = { s in DispatchQueue.main.async { if model.scale != s { model.scale = s } } }
        v.onClose = close
        v.onPlayPause = { model.playPause() }
        v.onToggleControls = { model.showControls.toggle() }
        model.view = v
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ v: ZoomVideoView, context: Context) {}
}

/// The full-screen screen: the video and a bar of large controls.
struct ZoomPlayerScreen: View {
    @ObservedObject var model: ZoomModel
    let title: String
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            ZoomVideo(model: model, close: close)
            if model.showControls { controls } else {
                Button { model.showControls = true } label: { Label("Show controls (H)", systemImage: "slider.horizontal.3").font(.system(size: 18, weight: .semibold)).padding(10) }
                    .buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(Color.black.opacity(0.6))).padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
    }

    var controls: some View {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    big("minus.magnifyingglass", "Zoom out") { model.view?.zoom(by: 1 / 1.5) }.disabled(model.scale <= 1.001)
                    Text("\(Int((model.scale * 100).rounded()))%").font(.system(size: 24, weight: .bold).monospacedDigit()).frame(minWidth: 86)
                        .accessibilityLabel("Zoom \(Int((model.scale * 100).rounded())) percent")
                    big("plus.magnifyingglass", "Zoom in") { model.view?.zoom(by: 1.5) }.disabled(model.scale >= ZoomVideoView.maxScale - 0.001)
                    big("arrow.down.right.and.arrow.up.left", "Fit") { model.view?.fit() }.disabled(model.scale <= 1.001)
                    if model.image == nil { big(model.playing ? "pause.fill" : "play.fill", model.playing ? "Pause" : "Play") { model.playPause() } }
                    big("eye.slash", "Hide controls") { model.showControls = false }
                    Spacer(minLength: 12)
                    big("xmark", "Close") { close() }.keyboardShortcut(.cancelAction)
                }
                Text("Scroll or pinch to zoom where the pointer is · drag to move around · double-click to zoom in or out · + − 0 and the arrow keys work too · H hides these controls · Esc closes")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.25)))
            .padding(.horizontal, 40).padding(.bottom, 28)
            .frame(maxWidth: 1200)
    }

    func big(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon).font(.system(size: 22, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

/// Opens a video full screen (one at a time). `loop`: plays it round and round (the loop preview); otherwise once, with its sound.
@MainActor enum FullScreenPlayer {
    private static var window: NSWindow?
    private static var model: ZoomModel?
    private static var observers: [NSObjectProtocol] = []

    static func show(_ url: URL, title: String, loop: Bool, muted: Bool) {
        close()
        let player: AVPlayer, looper: AVPlayerLooper?
        if loop { let q = AVQueuePlayer(); looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url)); player = q }
        else { player = AVPlayer(url: url); looper = nil }
        player.isMuted = muted
        let m = ZoomModel(player: player, looper: looper)
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let w = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = title; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isReleasedWhenClosed = false
        w.backgroundColor = .black; w.collectionBehavior = [.fullScreenPrimary]
        w.contentView = NSHostingView(rootView: ZoomPlayerScreen(model: m, title: title, close: { FullScreenPlayer.close() }))
        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { _ in MainActor.assumeIsolated { FullScreenPlayer.close() } },
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in MainActor.assumeIsolated { FullScreenPlayer.model?.player.pause() } },
        ]
        window = w; model = m
        w.makeKeyAndOrderFront(nil)
        w.toggleFullScreen(nil)
        player.play()
    }

    /// Opens a still picture full screen, zoomable.
    static func showImage(_ url: URL, title: String) {
        guard let img = NSImage(contentsOf: url) else { return }
        close()
        let m = ZoomModel(player: AVPlayer(), looper: nil); m.image = img; m.playing = false
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let w = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = title; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isReleasedWhenClosed = false
        w.backgroundColor = .black; w.collectionBehavior = [.fullScreenPrimary]
        w.contentView = NSHostingView(rootView: ZoomPlayerScreen(model: m, title: title, close: { FullScreenPlayer.close() }))
        observers = [NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { _ in MainActor.assumeIsolated { FullScreenPlayer.close() } }]
        window = w; model = m
        w.makeKeyAndOrderFront(nil); w.toggleFullScreen(nil)
    }

    static func close() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        model?.player.pause(); model = nil
        if let w = window { window = nil; w.orderOut(nil); w.close() }
    }
}
