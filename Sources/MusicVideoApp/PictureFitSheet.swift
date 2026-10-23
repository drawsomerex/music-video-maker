// When an outside photo isn't widescreen: extend it to 16:9 (every original pixel kept, only the new sides painted) or choose the crop.
import SwiftUI
import MVCore

/// A photo waiting to be fitted, and what to do with the result.
struct PictureFitRequest: Identifiable {
    let id = UUID()
    let source: URL
    let scene: String
    let use: (URL) -> Void
    let addCost: (Double) -> Void
}

extension AppModel {
    /// Uses the picture at once when it is (nearly) widescreen; otherwise asks first: extend it to 16:9 or choose the crop.
    func fitThen(_ url: URL, scene: String = "", addCost: @escaping (Double) -> Void, use: @escaping (URL) -> Void) {
        if PictureFit.needsFitting(url) { pictureFit = PictureFitRequest(source: url, scene: scene, use: use, addCost: addCost) } else { use(url) }
    }
}

struct PictureFitSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let req: PictureFitRequest
    @State private var centre = CGPoint(x: 0.5, y: 0.5)
    @State private var extended: URL?
    @State private var working = false
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var aspect: Double { PictureFit.aspect(req.source) ?? PictureFit.target }
    var crop: CGRect { PictureFit.cropRect(aspect: aspect, centre: centre) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(extended == nil ? "This picture isn't widescreen" : "Extended to widescreen").font(.title2.bold())
            Text(extended == nil ? PictureFit.describe(req.source) + " Videos are 16:9. Extend it (the picture maker paints the missing sides; your photo itself stays exactly as it is) or choose the part to use."
                                 : "Your photo is untouched in the middle; only the sides are new. Check where they meet it.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ZStack {
                Color.black.opacity(0.85)
                if let e = extended, let img = NSImage(contentsOf: e) { Image(nsImage: img).resizable().scaledToFit() }
                else { cropper }
                if working {
                    VStack(spacing: 10) { ProgressView().controlSize(.large); Text("Painting the missing sides… (about 30 seconds)").font(.headline).foregroundStyle(.white) }
                        .padding(24).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.7)))
                }
            }
            .frame(minHeight: 360, idealHeight: 470).clipShape(RoundedRectangle(cornerRadius: 10))
            if let f = failure { Label(f, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 10) {
                Button("Cancel", role: .cancel) { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if extended != nil {
                    Button("Back to the crop") { extended = nil }.disabled(working)
                    Button { extend() } label: { Text("Try again (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))") }.disabled(working)
                    Button { if let e = extended { finish(e) } } label: { Text("Use it").frame(minWidth: 80) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(working)
                } else {
                    Button("Use this crop") { useCrop() }.disabled(working)
                        .help("Uses only the part inside the frame. Drag the frame to choose which part.")
                    Button { extend() } label: { Label("Extend to 16:9 (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "arrow.left.and.right.square") }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(working || !model.hasOpenRouterKey)
                        .help(model.hasOpenRouterKey ? "The picture maker paints the missing sides to match; then your original photo is laid back over the middle, so it stays exactly as it was." : "Needs your OpenRouter key (Settings).")
                }
            }
        }
        .padding(22).frame(minWidth: 720, idealWidth: 860)
        .onDisappear { task?.cancel() }
    }

    /// The photo with the 16:9 frame on it; drag to move the frame.
    var cropper: some View {
        GeometryReader { geo in
            let a = aspect, box = geo.size
            let w = min(box.width, box.height * a), h = w / a
            let origin = CGPoint(x: (box.width - w) / 2, y: (box.height - h) / 2)
            let r = CGRect(x: origin.x + crop.minX * w, y: origin.y + crop.minY * h, width: crop.width * w, height: crop.height * h)
            ZStack(alignment: .topLeading) {
                if let img = NSImage(contentsOf: req.source) { Image(nsImage: img).resizable().frame(width: w, height: h).offset(x: origin.x, y: origin.y) }
                Path { p in p.addRect(CGRect(origin: origin, size: CGSize(width: w, height: h))); p.addRect(r) }
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                Rectangle().strokeBorder(Color.white, lineWidth: 3).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                Text("Drag to choose the part to use").font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.6))).foregroundStyle(.white).offset(x: r.minX + 10, y: r.minY + 10)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                centre = CGPoint(x: (g.location.x - origin.x) / w, y: (g.location.y - origin.y) / h)
            })
        }
    }

    func useCrop() {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("cropped-\(UUID().uuidString.prefix(8)).jpg")
        do { try PictureFit.crop(req.source, rect: crop, output: out); finish(out) } catch { failure = error.localizedDescription }
    }

    func extend() {
        working = true; failure = nil
        let src = req.source, scene = req.scene, cfg = Config.load()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("extended-\(UUID().uuidString.prefix(8)).jpg")
        task = Task {
            do {
                let cost = try await PictureFit.extend(src, output: out, scene: scene, config: cfg)
                req.addCost(cost); extended = out
                model.refreshOpenRouterCredits(silent: true)
            } catch is CancellationError {
            } catch { failure = "The picture couldn't be extended: \(error.localizedDescription) You can try again or use the crop." }
            working = false
        }
    }

    func finish(_ url: URL) {
        let base = (req.source.deletingPathExtension().lastPathComponent as NSString).replacingOccurrences(of: "/", with: "-")
        let named = FileManager.default.temporaryDirectory.appendingPathComponent("\(base) (16x9).jpg")       // keeps the photo's own name in the Pictures folder
        try? FileManager.default.removeItem(at: named)
        let use = (try? FileManager.default.copyItem(at: url, to: named)) != nil ? named : url
        dismiss()
        req.use(use)
    }
}
