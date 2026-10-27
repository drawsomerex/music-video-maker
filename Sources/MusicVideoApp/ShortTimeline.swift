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
                .gesture(DragGesture(minimumDistance: 5)
                    .onChanged { g in
                        let t = Double(min(max(0, g.location.x), w) / w) * dur
                        if mode == nil {
                            let xs = x(c.start), xe = x(c.end), px = g.startLocation.x
                            if abs(px - xs) <= 12 { mode = .start } else if abs(px - xe) <= 12 { mode = .end }
                            else if px > xs && px < xe { mode = .move(grab: Double(px / w) * dur - c.start) } else { return }
                        }
                        model.beginTimelineDrag()
                        // this map is coarse (a few pixels are several seconds), so it moves freely while you drag and settles on a word or beat when you let go
                        switch mode {
                        case .start?: model.update(clip.id) { $0.start = min(t, $0.end - 0.5) }
                        case .end?: model.update(clip.id) { $0.end = max(t, $0.start + 0.5) }
                        case .move(let grab)?:
                            let d = c.duration, s0 = min(max(0, t - grab), max(0, dur - d))
                            model.update(clip.id) { $0.start = s0; $0.end = s0 + d }
                        case nil: break
                        }
                    }
                    .onEnded { _ in
                        if !NSEvent.modifierFlags.contains(.shift), let m = mode {
                            switch m {
                            case .start: let v = model.snap(c.start, near: 0.6); model.update(clip.id) { $0.start = min(v, $0.end - 0.5) }
                            case .end: let v = model.snap(c.end, near: 0.6); model.update(clip.id) { $0.end = max(v, $0.start + 0.5) }
                            case .move:
                                let d = c.duration, s1 = model.snap(c.start, near: 0.6), e1 = model.snap(c.end, near: 0.6)
                                let s0 = max(0, abs(s1 - c.start) <= abs(e1 - c.end) ? s1 : e1 - d)
                                model.update(clip.id) { $0.start = s0; $0.end = s0 + d }
                            }
                        }
                        mode = nil; model.endTimelineDrag() })
                .onTapGesture { point in cursor = min(dur, max(0, point.x / w * dur)); if let t = cursor { model.playRange(t, min(dur, t + 4)) } }
            }.frame(height: 56)
        }
    }

    var parts: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array((model.plan?.sections ?? []).enumerated()), id: \.offset) { i, sec in
                    let x0 = CGFloat(sec.start / dur) * w, x1 = CGFloat(sec.end / dur) * w, music = sec.lineIDs.isEmpty
                    Button { cursor = sec.start; model.playRange(sec.start, sec.end) } label: {
                        Text(x1 - x0 > 50 ? (music ? "Music" : "Picture \(i + 1)") : "")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            .frame(width: max(2, x1 - x0 - 2), height: 30)
                            .background(RoundedRectangle(cornerRadius: 4).fill(music ? Color.gray.opacity(0.55) : [Color.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown][i % 8].opacity(0.75)))
                    }
                    .buttonStyle(.plain).offset(x: x0 + 1)
                    .help(music ? "A part with only music. Press to listen without changing the Short." : "Part \(i + 1) of the song. Press to listen without changing the Short.")
                }
            }
        }.frame(height: 30)
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
            Text("Use this to find the right part. Click anywhere to hear the song from that spot; a small card then lets you start or end the Short there. Or drag the green and red markers. Scroll sideways to move along the song.")
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
            Text("Orange line = the spot you clicked (the song plays from there) · white line = what you hear").font(.caption).foregroundStyle(.tertiary)
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
            if let cur = cursor { Rectangle().fill(.orange).frame(width: 2, height: height).offset(x: CGFloat(cur) * pps).allowsHitTesting(false) }
            if let ph = model.playhead { Rectangle().fill(.white).frame(width: 2, height: height).offset(x: CGFloat(ph) * pps).allowsHitTesting(false) }
            handle(.green, "START", t: c.start, isStart: true)
            handle(.red, "END", t: c.end, isStart: false)
            if let cur = cursor {                                  // a small card right at the spot you clicked
                HStack(spacing: 6) {
                    Button { setEdge(start: true, at: cur) } label: { Text("Start the Short here").font(.caption.weight(.semibold)) }.tint(.green)
                    Button { setEdge(start: false, at: cur) } label: { Text("End the Short here").font(.caption.weight(.semibold)) }.tint(.red)
                    Button { cursor = nil; model.stopPlayback() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close this card")
                }
                .buttonStyle(.bordered).controlSize(.regular).padding(5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)).shadow(radius: 3)
                .offset(x: min(max(4, CGFloat(cur) * pps - 90), max(4, CGFloat(dur) * pps - 270)), y: topPad + waveH + 4)
            }
        }
        .frame(width: CGFloat(dur) * pps + 60, height: height, alignment: .topLeading)
        .coordinateSpace(name: "tl")
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture(coordinateSpace: .named("tl")).onEnded { v in let t = Double(v.location.x / pps); cursor = t; model.playRange(t, dur) })
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
                    if abs.truncatingRemainder(dividingBy: 5) == 0 { ctx.draw(Text(clock(abs)).font(.system(size: 13).monospacedDigit()).foregroundColor(.secondary), at: CGPoint(x: px + 3, y: 7), anchor: .leading) }
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
                .help("“\(w.text)” at \(clock(w.start)). Click to hear the song from this word; a card then lets you start or end the Short here.")
            }
        }
        .frame(width: CGFloat(chunkSec) * pps, height: height, alignment: .topLeading)
    }

    /// A draggable marker with a flag on top.
    func handle(_ color: Color, _ label: String, t: Double, isStart: Bool) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(color).frame(width: 3, height: height)
            Text(label).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).fixedSize().padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(color)).offset(x: isStart ? 22 : -22, y: 2)
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 24, height: 36).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: 1.5)).offset(y: topPad + 12)
        }
        .frame(width: 26, height: height)
        .contentShape(Rectangle())
        .accessibilityLabel(isStart ? "Short start marker" : "Short end marker")
        .accessibilityValue(String(format: "%.2f seconds", t))
        .accessibilityAdjustableAction { direction in
            let value = t + (direction == .increment ? 0.1 : -0.1)
            model.update(clip.id) { if isStart { $0.start = min(max(0, value), $0.end - 0.5) } else { $0.end = min(dur, max(value, $0.start + 0.5)) } }
        }
        .offset(x: CGFloat(t) * pps - 13)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tl"))
            .onChanged { g in
                model.beginTimelineDrag()
                let near = NSEvent.modifierFlags.contains(.shift) ? 0 : 10 / Double(pps)          // snapping reach: 10 pixels
                let v = model.snap(min(max(0, Double(g.location.x / pps)), dur), near: near, edgeStart: isStart)
                if isStart { model.update(clip.id) { $0.start = min(v, $0.end - 0.5) } } else { model.update(clip.id) { $0.end = max(v, $0.start + 0.5) } }
            }
            .onEnded { _ in model.endTimelineDrag(); model.playRange(isStart ? c.start : max(c.start, c.end - 3), isStart ? c.start + 3 : c.end) })
        .help(isStart ? "START: drag to change where the Short starts. It sticks to words and beats; hold Shift for free movement." : "END: drag to change where the Short ends. It sticks to words and beats; hold Shift for free movement.")
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

    func pick(_ w: TimedWord) { cursor = w.start; model.playRange(w.start, dur) }
    func setEdge(start: Bool, at t: Double) {
        let v = model.snap(t, near: 0.4, edgeStart: start)
        model.update(clip.id) { if start { $0.start = min(v, $0.end - 0.5) } else { $0.end = max(v, $0.start + 0.5) } }
        model.playRange(start ? v : max(c.start, v - 3), start ? v + 3 : v)
        cursor = nil
    }
}
