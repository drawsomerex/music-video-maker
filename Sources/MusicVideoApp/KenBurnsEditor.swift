// The slow pan and zoom, under your control: numbered dots on the picture (two or more), the camera visits them in order and then comes back to
// the first, so the clip repeats without a seam. Drag a dot to choose where it looks; the slider chooses how close it is.
import SwiftUI
import MVCore

struct KenBurnsEditor: View {
    @EnvironmentObject var model: AppModel
    let picture: String
    @State private var selected = 0

    private var path: LoopVideo.KenBurnsPath { model.loopProject?.kenBurnsPaths[picture] ?? .standard }
    private func edit(_ change: (inout LoopVideo.KenBurnsPath) -> Void) {
        model.editLoop { q in var k = q.kenBurnsPaths[picture] ?? .standard; change(&k); q.kenBurnsPaths[picture] = k }
    }
    private var sel: Int { min(selected, path.points.count - 1) }

    var body: some View {
        let pts = path.points
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag the numbered dots to choose where the camera looks. It visits them in order, then comes back to dot 1.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in
                let W = geo.size.width, H = geo.size.height
                ZStack(alignment: .topLeading) {
                    if let u = model.loopFile(picture), let img = NSImage(contentsOf: u) {
                        Image(nsImage: img).resizable().scaledToFill().frame(width: W, height: H).clipped()
                    } else { Rectangle().fill(.gray.opacity(0.3)) }
                    // the camera's route
                    Path { r in
                        for k in 0...90 {
                            let c = path.camera(at: Double(k) / 90), pt = CGPoint(x: c.x * W, y: c.y * H)
                            k == 0 ? r.move(to: pt) : r.addLine(to: pt)
                        }
                    }.stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [5, 4])).shadow(radius: 1)
                    // what the chosen dot sees
                    let z = pts[sel].zoom, cx = min(max(pts[sel].x * W, W / (2 * z)), W - W / (2 * z)), cy = min(max(pts[sel].y * H, H / (2 * z)), H - H / (2 * z))
                    Rectangle().stroke(Color.yellow, lineWidth: 2).frame(width: W / z, height: H / z).position(x: cx, y: cy)
                    ForEach(pts.indices, id: \.self) { k in
                        ZStack {
                            Circle().fill(k == sel ? Color.yellow : Color.white).frame(width: 26, height: 26).shadow(radius: 2)
                            Text("\(k + 1)").font(.callout.weight(.bold)).foregroundStyle(.black)
                        }
                        .position(x: pts[k].x * W, y: pts[k].y * H)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("kbpicture")).onChanged { g in
                            selected = k
                            edit { $0.points[k].x = min(1, max(0, g.location.x / W)); $0.points[k].y = min(1, max(0, g.location.y / H)) }
                        })
                    }
                }
                .coordinateSpace(name: "kbpicture")
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: 520)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Text("Dot \(sel + 1) of \(pts.count) · how close:").font(.callout)
                Slider(value: Binding(get: { pts[sel].zoom }, set: { v in edit { $0.points[sel].zoom = v } }), in: 1...3).frame(maxWidth: 200)
                Text(String(format: "%.1f×", pts[sel].zoom)).font(.callout.monospacedDigit()).frame(width: 40, alignment: .leading)
            }
            HStack(spacing: 8) {
                Button { addPoint() } label: { Label("Add a dot", systemImage: "plus.circle") }
                    .help("Adds a dot after the chosen one (halfway to the next), so the camera makes one more stop.")
                Button { removePoint() } label: { Label("Remove this dot", systemImage: "minus.circle") }.disabled(pts.count <= 2)
                    .help("Takes the chosen dot out. At least two dots stay.")
                Button { edit { $0 = .standard }; selected = 0 } label: { Text("Start again") }
                Spacer()
                Picker("One round takes", selection: Binding(get: { path.seconds }, set: { v in edit { $0.seconds = v } })) {
                    ForEach([10.0, 20.0, 30.0, 45.0, 60.0, 90.0], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }.pickerStyle(.menu).fixedSize()
                    .help("How long the camera takes to visit every dot and come back to the first. Longer is slower and gentler.")
            }
            Text("After changing the dots, press the button below to make the clip again.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addPoint() {
        edit { k in
            let i = min(sel, k.points.count - 1), a = k.points[i], b = k.points[(i + 1) % k.points.count]
            k.points.insert(LoopVideo.KenBurnsPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, zoom: (a.zoom + b.zoom) / 2), at: i + 1)
        }
        selected = sel + 1
    }
    private func removePoint() {
        guard path.points.count > 2 else { return }
        let i = sel
        edit { $0.points.remove(at: i) }
        selected = max(0, i - 1)
    }
}
