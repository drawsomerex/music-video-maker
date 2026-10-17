// The two pictures of the song used to choose a Short: the whole-song map, and the word-by-word timeline.
import SwiftUI
import MVCore

enum EdgeDrag { case start, end, move(grab: Double) }

/// The whole song at a glance: its parts as coloured blocks, the waveform, and the bright box that is your Short.
struct SongMap: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    @Binding var cursor: Double?
    @State private var mode: EdgeDrag?
    var c: ShortClip { model.currentShort ?? clip }
    var dur: Double { max(1, model.plan?.songDuration ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("The whole song").font(.headline); Text("Drag the bright box to move your Short, or drag its edges.").font(.callout).foregroundStyle(.secondary) }
            parts
            GeometryReader { geo in
                let w = geo.size.width
                let x: (Double) -> CGFloat = { CGFloat($0 / dur) * w }
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        let peaks = model.waveform
                        if !peaks.isEmpty {
                            var path = Path(); let mid = size.height / 2
                            for px in stride(from: 0, to: Int(size.width), by: 2) {
                                let i0 = max(0, Int(Double(px) / Double(size.width) * dur * 100)), i1 = min(peaks.count, max(i0 + 1, Int(Double(px + 2) / Double(size.width) * dur * 100)))
                                if i0 >= peaks.count { break }
                                let h = max(1, CGFloat(peaks[i0..<i1].max() ?? 0) * size.height * 0.46)
                                path.addRect(CGRect(x: CGFloat(px), y: mid - h, width: 1.4, height: h * 2))
                            }
                            ctx.fill(path, with: .color(.secondary.opacity(0.75)))
                        }
                        let a = x(c.start), b = x(c.end)
                        ctx.fill(Path(CGRect(x: 0, y: 0, width: max(0, a), height: size.height)), with: .color(.black.opacity(0.42)))
                        ctx.fill(Path(CGRect(x: max(0, b), y: 0, width: max(0, size.width - b), height: size.height)), with: .color(.black.opacity(0.42)))
                        ctx.stroke(Path(CGRect(x: max(1, a), y: 1, width: max(3, b - a), height: size.height - 2)), with: .color(ShortLength.color(c.duration)), lineWidth: 2.5)
                        if let ph = model.playhead { ctx.fill(Path(CGRect(x: x(ph) - 1, y: 0, width: 2, height: size.height)), with: .color(.white)) }
                    }
                    RoundedRectangle(cornerRadius: 3).fill(.green).frame(width: 8, height: 28).position(x: x(c.start), y: 28)
                    RoundedRectangle(cornerRadius: 3).fill(.red).frame(width: 8, height: 28).position(x: x(c.end), y: 28)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let t = Double(min(max(0, g.location.x), w) / w) * dur
                        if mode == nil {
                            let xs = x(c.start), xe = x(c.end), px = g.startLocation.x
                            if abs(px - xs) <= 12 { mode = .start } else if abs(px - xe) <= 12 { mode = .end }
                            else if px > xs && px < xe { mode = .move(grab: Double(px / w) * dur - c.start) } else { mode = .move(grab: c.duration / 2) }
                        }
                        let near = 8 * dur / Double(max(1, w)), free = NSEvent.modifierFlags.contains(.shift)
                        @MainActor func snapped(_ v: Double) -> Double { free ? v : model.snapToWordEdge(v, within: near) }
                        switch mode {
                        case .start?: let v = snapped(t); model.update(clip.id) { $0.start = min(v, $0.end - 2) }
                        case .end?: let v = snapped(t); model.update(clip.id) { $0.end = max(v, $0.start + 2) }
                        case .move(let grab)?:
                            let d = c.duration; var s0 = min(max(0, t - grab), max(0, dur - d))
                            let s1 = snapped(s0), e1 = snapped(s0 + d)
                            s0 = abs(s1 - s0) <= abs(e1 - (s0 + d)) ? min(max(0, s1), max(0, dur - d)) : min(max(0, e1 - d), max(0, dur - d))
                            model.update(clip.id) { $0.start = s0; $0.end = s0 + d }
                        case nil: break
                        }
                    }
                    .onEnded { _ in mode = nil })
            }.frame(height: 56)
        }
    }

    var parts: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array((model.plan?.sections ?? []).enumerated()), id: \.offset) { i, sec in
                    let x0 = CGFloat(sec.start / dur) * w, x1 = CGFloat(sec.end / dur) * w, music = sec.lineIDs.isEmpty
                    Button { model.selectSection(clip.id, index: i) } label: {
                        Text(x1 - x0 > 50 ? (music ? "Music" : "Part \(i + (model.plan!.sections.first?.lineIDs.isEmpty == true ? 0 : 1))") : "")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            .frame(width: max(2, x1 - x0 - 2), height: 20)
                            .background(RoundedRectangle(cornerRadius: 4).fill(music ? Color.gray.opacity(0.55) : [Color.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown][i % 8].opacity(0.75)))
                    }
                    .buttonStyle(.plain).offset(x: x0 + 1)
                    .help(music ? "A part with only music. Press to use all of it as your Short." : "Part \(i + 1) of the song. Press to use all of it as your Short.")
                }
            }
        }.frame(height: 20)
    }
}

/// The song laid out in time at a size where every word can be read: waveform on top, words beneath, your Short between the green and red markers.
struct WordTimeline: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    @Binding var cursor: Double?
    var snapshot = false                      // layout pictures only (ScrollView can't be drawn by ImageRenderer)
    @State private var pps: CGFloat = 72            // pixels per second
    @State private var mode: EdgeDrag?
    private let chunkSec = 10.0, rows = 4, rowH: CGFloat = 26, waveH: CGFloat = 64, topPad: CGFloat = 16
    var c: ShortClip { model.currentShort ?? clip }
    var dur: Double { max(1, model.plan?.songDuration ?? 1) }
    var height: CGFloat { topPad + waveH + rowH * CGFloat(rows) + 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("The song, word by word").font(.headline)
                Spacer()
                Button { pps = max(30, pps / 1.3) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out: see more of the song at once.")
                Button { pps = min(180, pps * 1.3) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in: bigger words and finer placing.")
            }
            Text("Drag the green marker (start) and the red marker (end). Or click a word to start the Short there, and Shift-click a word to end it there. Scroll sideways to move along the song.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if snapshot {
                content.offset(x: 20 - CGFloat(c.start) * pps).frame(width: 700, height: height + 14, alignment: .topLeading).clipped()
                    .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
            } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    content
                }
                .frame(height: height + 14)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .onAppear { jump(proxy, c.start - 1.5) }
                .onChange(of: clip.id) { _, _ in jump(proxy, c.start - 1.5) }
                .onChange(of: c.start) { old, new in if abs(new - old) > 3 { jump(proxy, new - 1.5) } }
                .onChange(of: model.playhead) { _, p in if let p, Int(p / chunkSec) != Int((p - 0.5) / chunkSec) || p < 0.6 { jump(proxy, p - 2) } }
            }
            }
            HStack(spacing: 8) {
                Button { cursor = nil } label: { Text("Remove cursor") }.disabled(cursor == nil).font(.caption)
                Spacer()
                Text("Orange line = your cursor · white line = what you hear").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }


    @ViewBuilder var content: some View {
        let words = (model.plan?.lines ?? []).flatMap(\.words)
        let place = layout(words)
        ZStack(alignment: .topLeading) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(0..<Int(dur / chunkSec) + 1, id: \.self) { k in chunk(k, words, place).id(k) }
            }
            Rectangle().fill(.black.opacity(0.30)).frame(width: CGFloat(c.start) * pps, height: height).allowsHitTesting(false)
            Rectangle().fill(.black.opacity(0.30)).frame(width: max(0, CGFloat(dur - c.end) * pps), height: height).offset(x: CGFloat(c.end) * pps).allowsHitTesting(false)
            Rectangle().fill(ShortLength.color(c.duration).opacity(0.10)).frame(width: CGFloat(c.duration) * pps, height: height).offset(x: CGFloat(c.start) * pps).allowsHitTesting(false)
            if let cur = cursor, model.playhead == nil { Rectangle().fill(.orange).frame(width: 2, height: height).offset(x: CGFloat(cur) * pps).allowsHitTesting(false) }
            if let ph = model.playhead { Rectangle().fill(.white).frame(width: 2, height: height).offset(x: CGFloat(ph) * pps).allowsHitTesting(false) }
            handle(.green, "START", t: c.start, isStart: true)
            handle(.red, "END", t: c.end, isStart: false)
        }
        .frame(width: CGFloat(dur) * pps + 60, height: height, alignment: .topLeading)
        .coordinateSpace(name: "tl")
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture(coordinateSpace: .named("tl")).onEnded { v in cursor = Double(v.location.x / pps) })
    }

    func jump(_ proxy: ScrollViewProxy, _ t: Double) { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(max(0, Int(t / chunkSec)), anchor: .leading) } }

    /// 10 seconds of the song: waveform, ruler and the words that start in it.
    func chunk(_ k: Int, _ words: [TimedWord], _ place: [Int]) -> some View {
        let t0 = Double(k) * chunkSec
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let peaks = model.waveform
                let mid = topPad + waveH / 2
                if !peaks.isEmpty {
                    var path = Path()
                    for px in stride(from: 0, to: Int(size.width), by: 2) {
                        let i0 = max(0, Int((t0 + Double(px) / Double(pps)) * 100)), i1 = min(peaks.count, max(i0 + 1, Int((t0 + Double(px + 2) / Double(pps)) * 100)))
                        if i0 >= peaks.count { break }
                        let h = max(1, CGFloat(peaks[i0..<i1].max() ?? 0) * waveH * 0.48)
                        path.addRect(CGRect(x: CGFloat(px), y: mid - h, width: 1.4, height: h * 2))
                    }
                    ctx.fill(path, with: .color(.secondary.opacity(0.8)))
                }
                for s in 0..<Int(chunkSec) {                       // a tick every second, a label every 5 seconds
                    let px = CGFloat(s) * pps, abs = t0 + Double(s)
                    ctx.fill(Path(CGRect(x: px, y: 0, width: 1, height: abs.truncatingRemainder(dividingBy: 5) == 0 ? 10 : 5)), with: .color(.secondary.opacity(0.5)))
                    if abs.truncatingRemainder(dividingBy: 5) == 0 { ctx.draw(Text(clock(abs)).font(.system(size: 9).monospacedDigit()).foregroundColor(.secondary), at: CGPoint(x: px + 3, y: 7), anchor: .leading) }
                }
            }
            .frame(width: CGFloat(chunkSec) * pps, height: topPad + waveH)
            ForEach(Array(words.enumerated()).filter { $0.element.start >= t0 && $0.element.start < t0 + chunkSec }, id: \.offset) { i, w in
                let inside = w.start >= c.start - 0.01 && w.end <= c.end + 0.01
                Button { pick(w) } label: {
                    Text(w.text).font(.system(size: 13, weight: inside ? .semibold : .regular)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 5).frame(height: rowH - 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(inside ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14)))
                        .foregroundStyle(inside ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(w.start - t0) * pps, y: topPad + waveH + 2 + CGFloat(place[i]) * rowH)
                .help("“\(w.text)” at \(clock(w.start)). Click to start the Short here; Shift-click to end it here.")
            }
        }
        .frame(width: CGFloat(chunkSec) * pps, height: height, alignment: .topLeading)
    }

    /// A draggable marker with a flag on top.
    func handle(_ color: Color, _ label: String, t: Double, isStart: Bool) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(color).frame(width: 3, height: height)
            Text(label).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).fixedSize().padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(color)).offset(x: isStart ? 22 : -22, y: 2)
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 12, height: 30).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: 1.5)).offset(y: topPad + 12)
        }
        .frame(width: 26, height: height)
        .contentShape(Rectangle())
        .offset(x: CGFloat(t) * pps - 13)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tl"))
            .onChanged { g in
                let near = 8 / Double(pps), free = NSEvent.modifierFlags.contains(.shift)
                @MainActor func snapped(_ v: Double) -> Double { free ? v : model.snapToWordEdge(v, within: near) }
                let v = snapped(min(max(0, Double(g.location.x / pps)), dur))
                if isStart { model.update(clip.id) { $0.start = min(v, $0.end - 2) } } else { model.update(clip.id) { $0.end = max(v, $0.start + 2) } }
            })
        .help(isStart ? "START: drag to change where the Short starts. Hold Shift for free movement." : "END: drag to change where the Short ends. Hold Shift for free movement.")
    }

    /// Puts each word on the first row where it does not touch the previous word on that row.
    func layout(_ words: [TimedWord]) -> [Int] {
        var end = [CGFloat](repeating: -100, count: rows), out: [Int] = []
        for w in words {
            let x = CGFloat(w.start) * pps, width = CGFloat(w.text.count) * 8 + 16
            let r = (0..<rows).first { x >= end[$0] } ?? (0..<rows).min { end[$0] < end[$1] }!
            end[r] = x + width + 2; out.append(r)
        }
        return out
    }

    func pick(_ w: TimedWord) {
        if NSEvent.modifierFlags.contains(.shift) { model.update(clip.id) { $0.end = max($0.start + 2, w.end + 0.1) } }
        else { model.update(clip.id) { let d = $0.duration; $0.start = max(0, w.start - 0.05); if $0.end <= $0.start + 2 { $0.end = $0.start + min(d, 30) } }; cursor = w.start }
    }
}
