// The song on a true-to-scale timeline: time ruler and waveform, the lyric lines (and purple music interludes) at their real times,
// the pictures with draggable borders, and the Shorts as draggable bars. Used at the top of the Song page and of the Pictures page.
//
//  • drag a picture border → the pictures on either side grow and shrink (snaps to lyric lines; hold Option for no snapping)
//  • double-click the pictures lane → a new border there; select a border (click) and press Delete → the pictures join
//  • drag a Short's edges to resize it, its middle to move it; double-click the Shorts lane to add one; select and press Delete to remove
import SwiftUI
import MVCore

struct ScaledTimeline: View {
    @EnvironmentObject var model: AppModel
    var showShorts = true
    var onSelectPicture: ((Int) -> Void)? = nil

    @State private var selBorder: Int?
    @State private var dragBorder: Int?
    @State private var dragLabel: String?
    @State private var shortDrag: (id: UUID, mode: Int, start: Double, end: Double)?       // mode 0 = move, 1 = left edge, 2 = right edge
    @State private var focusSelectedShort = false
    @FocusState private var focused: Bool
    @State private var confirmRestore = false

    private let rulerH: CGFloat = 20, waveH: CGFloat = 38, lyricsH: CGFloat = 44, picsH: CGFloat = 58, shortH: CGFloat = 26

    var lines: [LyricLine] { model.timelineLines?.lines ?? [] }
    var duration: Double { max(1, model.timelineLines?.duration ?? 1) }
    var sections: [PhotoSection] { model.previewSections ?? [] }
    var shorts: [ShortClip] { model.timelineShorts }

    /// Music-only stretches (4 s or more with no singing), including before the first line and after the last.
    var interludes: [(Double, Double)] {
        var out: [(Double, Double)] = []; var prev = 0.0
        for l in lines { if l.start - prev >= Planner.shortestBreak { out.append((prev, l.start)) }; prev = max(prev, l.end) }
        if duration - prev >= Planner.shortestBreak { out.append((prev, duration)) }
        return out
    }
    /// Greedy rows so overlapping Shorts do not hide each other.
    var shortRows: [UUID: Int] {
        var ends: [Double] = []; var out: [UUID: Int] = [:]
        for s in shorts.sorted(by: { $0.start < $1.start }) {
            if let r = ends.firstIndex(where: { $0 <= s.start + 0.01 }) { out[s.id] = r; ends[r] = s.end } else { out[s.id] = ends.count; ends.append(s.end) }
        }
        return out
    }
    var rowCount: Int { max(1, (shortRows.values.max() ?? 0) + 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            controls
            GeometryReader { geo in
                let pps = max(2, geo.size.width * model.timelineZoom / duration)
                ScrollView(.horizontal, showsIndicators: true) {
                    content(pps: pps).frame(width: duration * pps, height: totalHeight, alignment: .topLeading)
                }
            }.frame(height: totalHeight + 14)
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.delete) { deleteSelection() }
        .onKeyPress(.deleteForward) { deleteSelection() }
        .task { if model.waveform.isEmpty { model.loadWaveform() } }
        .confirmationDialog("Restore the automatic picture divisions?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore them") { model.restoreAutomaticPictures() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The borders go back to one picture per verse and per music break. Your artwork is kept, and Undo brings your borders back.") }
    }

    var totalHeight: CGFloat { rulerH + waveH + lyricsH + picsH + (showShorts ? CGFloat(rowCount) * (shortH + 4) + 10 : 0) + 18 }

    func deleteSelection() -> KeyPress.Result {
        if let b = selBorder { model.joinPicture(before: b); selBorder = nil; return .handled }
        if focusSelectedShort, let id = model.selectedShort { model.removeTimelineShort(id); focusSelectedShort = false; return .handled }
        return .ignored
    }

    // MARK: controls
    var controls: some View {
        HStack(spacing: 8) {
            Button { model.undoEdit() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(model.editUndo.isEmpty)
                .help(model.editUndo.last.map { "Undo: " + $0.name } ?? "Nothing to undo.")
            Button { model.redoEdit() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(model.editRedo.isEmpty).help("Restore the change you just undid.")
            Spacer()
            Text("Drag a picture border · double-click to add one · select a border and press Delete to join").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if model.timelineShorts.isEmpty {
                Button { if model.plan != nil { model.autoMakeShorts() } else { model.suggestTimelineShorts() } } label: { Label("Make Shorts automatically", systemImage: "sparkles") }
                    .help("Cuts the song into Shorts of about 30 seconds at natural breaks. You can drag, resize, delete or add Shorts afterwards. Your pictures are not changed.")
            }
            Menu {
                Button("Split long sections") { model.splitLongVerses() }
                    .help("Splits every picture longer than 30 seconds into equal pictures. Artwork is reused and Shorts stay unchanged.")
                Button("Restore automatic divisions…") { confirmRestore = true }
                    .help("Puts the picture borders back where the app first placed them (one picture per verse and per music break). Artwork is kept and you can Undo.")
            } label: { Label("More", systemImage: "ellipsis.circle") }.menuIndicator(.hidden).fixedSize()
                .help("More timeline tools. Tip: right-click a lyric line to start a new picture there.")
            Button { model.timelineZoom = max(1, model.timelineZoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out.")
            Button { model.timelineZoom = 1 } label: { Text("Fit the whole song") }.help("Shows the whole song at once.")
            Button { model.timelineZoom = min(40, model.timelineZoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in for precise placement.")
        }.buttonStyle(.bordered).controlSize(.small)
    }

    // MARK: lanes
    func content(pps: Double) -> some View {
        let y0: CGFloat = 0, y1 = rulerH, y2 = rulerH + waveH, y3 = rulerH + waveH + lyricsH, y4 = rulerH + waveH + lyricsH + picsH + 6
        return ZStack(alignment: .topLeading) {
            ruler(pps: pps).frame(height: rulerH + waveH).offset(y: y0)
            Color.clear.frame(width: duration * pps, height: rulerH + waveH).contentShape(Rectangle()).offset(y: y0)
                .onTapGesture(coordinateSpace: .named("tl")) { p in model.timelineCursor = max(0, min(duration, p.x / pps)); focused = true }
            lyricsLane(pps: pps).offset(y: y2)
            picturesLane(pps: pps).offset(y: y3)
            if showShorts { shortsLane(pps: pps).offset(y: y4) }
            playhead(pps: pps)
        }
        .coordinateSpace(name: "tl")
        .overlay(alignment: .topLeading) { _ = y1; return Color.clear }
    }

    func ruler(pps: Double) -> some View {
        Canvas { ctx, size in
            let step = [1, 2, 5, 10, 15, 30, 60, 120, 300].first { Double($0) * pps >= 64 } ?? 300
            for t in stride(from: 0, through: Int(duration), by: step) {
                let x = Double(t) * pps
                ctx.fill(Path(CGRect(x: x, y: 12, width: 1, height: 8)), with: .color(.secondary))
                ctx.draw(Text(String(format: "%d:%02d", t / 60, t % 60)).font(.system(size: 11)).foregroundColor(.secondary), at: CGPoint(x: x + 3, y: 6), anchor: .leading)
            }
            let peaks = model.waveform
            if !peaks.isEmpty {
                var path = Path()
                let mid = rulerH + waveH / 2
                var px = 0.0
                while px < size.width {
                    let lo = min(peaks.count - 1, Int(px / size.width * Double(peaks.count)))
                    let hi = min(peaks.count, max(lo + 1, Int((px + 2) / size.width * Double(peaks.count))))
                    let h = CGFloat(peaks[lo..<hi].max() ?? 0) * (waveH / 2 - 2) * 1.6
                    path.addRect(CGRect(x: px, y: mid - h, width: 1.5, height: max(1, h * 2)))
                    px += 2
                }
                ctx.fill(path, with: .color(.secondary.opacity(0.7)))
            }
        }
    }

    func lyricsLane(pps: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.07)).frame(width: duration * pps, height: lyricsH)
            ForEach(Array(interludes.enumerated()), id: \.offset) { _, g in interludeBlock(g, pps: pps) }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in lineBlock(l, pps: pps) }
        }
    }
    func interludeBlock(_ g: (Double, Double), pps: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        return ZStack(alignment: .leading) {
            shape.fill(Color.purple.opacity(0.22))
            shape.strokeBorder(Color.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            Text("♪ music").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.purple).lineLimit(1).padding(.horizontal, 4)
        }
        .frame(width: max(3, (g.1 - g.0) * pps), height: lyricsH).offset(x: g.0 * pps)
        .help("Music only, \(preciseClock(g.0))–\(preciseClock(g.1)) (\(Int((g.1 - g.0).rounded())) s)")
    }
    func lineBlock(_ l: LyricLine, pps: Double) -> some View {
        let w = max(3, (l.end - l.start) * pps)
        return Text(l.text).font(.system(size: 12)).lineLimit(2).minimumScaleFactor(0.8).padding(.horizontal, 4)
            .frame(width: w, height: lyricsH - 4, alignment: .leading)
            .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            .offset(x: l.start * pps, y: 2)
            .help("\(preciseClock(l.start))  \(l.text)")
            .onTapGesture { model.timelineCursor = l.start; model.playRange(l.start, l.end) }
            .contextMenu {
                Button("Start a new picture here") { model.splitPicture(at: l.start) }
                Button("Listen to this line") { model.timelineCursor = l.start; model.playRange(l.start, l.end) }
            }
    }

    // MARK: pictures
    func picturesLane(pps: Double) -> some View {
        let secs = sections
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: duration * pps, height: picsH).contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .named("tl")) { p in model.splitPicture(at: p.x / pps); focused = true }
            ForEach(Array(secs.enumerated()), id: \.offset) { i, s in
                let w = max(4, s.duration * pps - 2)
                ZStack(alignment: .leading) {
                    if let f = s.selectedCandidate?.thumbFile, let work = model.workDir { Thumb(file: work.appendingPathComponent(f)).opacity(0.45).allowsHitTesting(false) }
                    HStack(spacing: 4) {
                        Text("\(i + 1)\(s.lineIDs.isEmpty ? " ♪" : "")").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                        if s.useClips && !s.clips.isEmpty { Image(systemName: "film").font(.caption) }
                    }.padding(.leading, 12).shadow(color: .white.opacity(0.6), radius: 2)
                }
                .frame(width: w, height: picsH).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.18)))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(model.selectedSection == i ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: model.selectedSection == i ? 3 : 1))
                .offset(x: s.start * pps + 1)
                .onTapGesture(count: 2, coordinateSpace: .named("tl")) { p in model.splitPicture(at: p.x / pps); focused = true }
                .onTapGesture { model.selectedSection = i; model.timelineCursor = s.start; selBorder = nil; onSelectPicture?(i); focused = true }
                .help("Picture \(i + 1): \(preciseClock(s.start))–\(preciseClock(s.end)) (\(Int(s.duration.rounded())) s). Click to select; double-click empty space to add a border.")
            }
            ForEach(Array(secs.enumerated()), id: \.offset) { i, s in
                if i > 0 { borderHandle(i, at: s.start, pps: pps) }
            }
        }
    }

    func borderHandle(_ i: Int, at t: Double, pps: Double) -> some View {
        let isSel = selBorder == i, active = dragBorder == i
        return ZStack {
            Capsule().fill(isSel || active ? Color.accentColor : Color.primary.opacity(0.75)).frame(width: 6, height: picsH)
            Image(systemName: "line.3.horizontal").rotationEffect(.degrees(90)).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            if active || isSel {
                Text(dragLabel ?? preciseClock(t)).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.accentColor)).fixedSize().offset(y: -picsH / 2 - 10)
            }
        }
        .frame(width: 18, height: picsH).contentShape(Rectangle()).offset(x: t * pps - 9)
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("tl"))
            .onChanged { g in
                if dragBorder == nil { dragBorder = i; selBorder = i; model.beginTimelineDrag("Move picture border"); focused = true }
                let v = snap(g.location.x / pps, pps: pps)
                model.moveBoundaryLive(i, to: v); dragLabel = preciseClock(sections.indices.contains(i) ? sections[i].start : v)
            }
            .onEnded { _ in dragBorder = nil; dragLabel = nil; model.endBoundaryDrag() })
        .onTapGesture { selBorder = i; focused = true }
        .contextMenu { Button("Join these two pictures") { model.joinPicture(before: i) } }
        .help("Border between picture \(i) and picture \(i + 1) at \(preciseClock(t)). Drag to move it. Select it and press Delete to join the two pictures.")
    }

    /// Nearest lyric line edge within 8 points, unless Option is held (or snapping is turned off).
    func snap(_ t: Double, pps: Double) -> Double {
        guard model.timelineSnap, !NSEvent.modifierFlags.contains(.option) else { return t }
        var best = t, dist = 8.0 / pps
        for l in lines { for e in [l.start, l.end] where abs(e - t) < dist { best = e; dist = abs(e - t) } }
        return best
    }

    // MARK: shorts
    func shortsLane(pps: Double) -> some View {
        let rows = shortRows
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.06)).frame(width: duration * pps, height: CGFloat(rowCount) * (shortH + 4) + 4)
                .overlay(Text(shorts.isEmpty ? "Shorts — double-click here to add one" : "").font(.caption).foregroundStyle(.secondary).padding(.leading, 8), alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .named("tl")) { p in model.addTimelineShort(at: p.x / pps) }
            ForEach(shorts) { c in
                let sel = model.selectedShort == c.id
                let color = ShortLength.color(c.duration)
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(color.opacity(sel ? 0.55 : 0.32))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(sel ? Color.accentColor : color.opacity(0.8), lineWidth: sel ? 3 : 1.5))
                    Text("\(c.name) · \(Int(c.duration.rounded())) s").font(.system(size: 12, weight: .semibold)).lineLimit(1).padding(.horizontal, 12)
                    HStack { edgeHandle(c, mode: 1, pps: pps); Spacer(); edgeHandle(c, mode: 2, pps: pps) }
                }
                .frame(width: max(14, c.duration * pps), height: shortH)
                .offset(x: c.start * pps, y: CGFloat(rows[c.id] ?? 0) * (shortH + 4) + 2)
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("tl")).onChanged { g in dragShort(c, mode: 0, g, pps: pps) }.onEnded { _ in endShortDrag() })
                .onTapGesture { model.selectedShort = c.id; focusSelectedShort = true; selBorder = nil; focused = true }
                .contextMenu { Button("Delete this Short", role: .destructive) { model.removeTimelineShort(c.id) } }
                .help("\(c.name): \(preciseClock(c.start))–\(preciseClock(c.end)). Drag the middle to move it, the edges to resize it. Select it and press Delete to remove it.")
            }
        }
    }

    func edgeHandle(_ c: ShortClip, mode: Int, pps: Double) -> some View {
        Rectangle().fill(Color.white.opacity(0.001)).frame(width: 10, height: shortH).contentShape(Rectangle())
            .overlay(Capsule().fill(Color.primary.opacity(0.7)).frame(width: 3, height: shortH - 10))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("tl")).onChanged { g in dragShort(c, mode: mode, g, pps: pps) }.onEnded { _ in endShortDrag() })
    }

    func dragShort(_ c: ShortClip, mode: Int, _ g: DragGesture.Value, pps: Double) {
        if shortDrag == nil { shortDrag = (c.id, mode, c.start, c.end); model.beginTimelineDrag("Move Short"); model.selectedShort = c.id }
        guard let d = shortDrag else { return }
        let delta = (g.location.x - g.startLocation.x) / pps
        var s = d.start, e = d.end
        switch d.mode {
        case 1: s = min(snap(d.start + delta, pps: pps), d.end - 1)
        case 2: e = max(snap(d.end + delta, pps: pps), d.start + 1)
        default:
            let len = d.end - d.start
            s = snap(d.start + delta, pps: pps); s = min(max(0, s), duration - len); e = s + len
        }
        model.moveShortLive(c.id, start: max(0, s), end: min(duration, e))
    }
    func endShortDrag() { shortDrag = nil; model.endBoundaryDrag() }

    func playhead(pps: Double) -> some View {
        let t = model.playhead ?? model.timelineCursor
        return Rectangle().fill(model.playhead != nil ? Color.red : Color.primary).frame(width: 2, height: totalHeight - 18).offset(x: t * pps - 1).allowsHitTesting(false)
    }
}


/// The timeline folded away: one slim row with the pictures (and the Shorts as a thin line under them) in true scale. Click it to open the full timeline.
struct TimelineStrip: View {
    @EnvironmentObject var model: AppModel
    let open: () -> Void
    var body: some View {
        let sections = model.previewSections ?? [], shorts = model.timelineShorts
        let duration = max(1, model.timelineLines?.duration ?? 1)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(sections.enumerated()), id: \.offset) { i, s in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hue: Double((i * 47) % 360) / 360, saturation: s.selectedCandidate == nil ? 0.15 : 0.45, brightness: 0.85))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(model.selectedSection == i ? Color.accentColor : .clear, lineWidth: 2))
                        .frame(width: max(2, CGFloat((s.end - s.start) / duration) * w - 1), height: 16)
                        .offset(x: CGFloat(s.start / duration) * w)
                }
                ForEach(shorts) { c in
                    Capsule().fill(Color.pink.opacity(0.8)).frame(width: max(3, CGFloat(c.duration / duration) * w), height: 4)
                        .offset(x: CGFloat(c.start / duration) * w, y: 19)
                }
            }
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .help("The whole song: each block is a picture (pale = no picture yet), the pink line under them shows the Shorts. Click to open the full timeline.")
    }
}
