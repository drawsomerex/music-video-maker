// "Where it starts" / "Where it ends": a close-up of one end of the Short — waveform, the words, the music-only stretches and the beats —
// where you click or drag to put the end exactly where you want it, then nudge it and hear it.
import SwiftUI
import MVCore

struct EdgeCard: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    let isStart: Bool
    @State private var span = 12.0                    // seconds shown in the close-up
    var c: ShortClip { model.currentShort ?? clip }
    var t: Double { isStart ? c.start : c.end }
    var color: Color { isStart ? .green : .red }
    var allWords: [TimedWord] { (model.plan?.lines ?? []).flatMap(\.words) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(info).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { hear() } label: { Label(isStart ? "Hear the start" : "Hear the ending", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .help(isStart ? "Plays the first few seconds of the Short." : "Plays the last few seconds of the Short, up to where it stops.")
            }
            EdgeStrip(clip: clip, isStart: isStart, span: $span, onSet: { v in set(v); hear() })
            nudges
            if !isStart { ending }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.5), lineWidth: 1.5))
    }

    /// What is at this end right now, in plain words.
    var info: String {
        let ws = allWords
        if isStart {
            guard let fw = ws.first(where: { $0.end > c.start }) else { return "There are no words after this point." }
            if fw.start > c.start + 0.15 { return String(format: "%.1f seconds of music, then the first word “%@” at %@.", fw.start - c.start, fw.text, clock(fw.start)) }
            return "The Short starts at the word “\(fw.text)”. Click earlier on the picture below if you want some music first."
        }
        guard let lw = ws.last(where: { $0.start < c.end }) else { return "There are no words before this point." }
        if lw.end < c.end - 0.15 { return String(format: "The last word, “%@”, ends at %@. After it there are %.1f seconds of music only. Click on the picture below where you want the Short to stop.", lw.text, clock(lw.end), c.end - lw.end) }
        return "The Short stops during the word “\(lw.text)” (it ends at \(clock(lw.end))). Click later on the picture below to let the music play on after the words."
    }

    func set(_ v: Double) {
        let x = min(max(0, v), model.plan?.songDuration ?? v)
        model.update(clip.id) { if isStart { $0.start = min(x, $0.end - 0.5) } else { $0.end = max(x, $0.start + 0.5) } }
    }
    func hear() {
        if isStart { model.playRange(c.start, c.start + 3.5) } else { model.playRange(max(c.start, c.end - 4), c.end) }
    }
    func move(by d: Double) { set(t + d); hear() }
    func beat(_ forward: Bool) { if let b = forward ? model.nextBeat(after: t) : model.previousBeat(before: t) { set(b); hear() } }

    var earlier: some View {
        HStack(spacing: 6) {
            nb("◀ beat", "Moves this end back to the previous beat of the music.") { beat(false) }
            nb("−1 s", "Moves this end one second earlier.") { move(by: -1) }
            nb("−0.25 s", "Moves this end a quarter of a second earlier.") { move(by: -0.25) }
            nb("−0.05 s", "Moves this end a very small step earlier (5 hundredths of a second).") { move(by: -0.05) }
        }
    }
    var later: some View {
        HStack(spacing: 6) {
            nb("+0.05 s", "Moves this end a very small step later (5 hundredths of a second).") { move(by: 0.05) }
            nb("+0.25 s", "Moves this end a quarter of a second later.") { move(by: 0.25) }
            nb("+1 s", "Moves this end one second later.") { move(by: 1) }
            nb("beat ▶", "Moves this end forward to the next beat of the music.") { beat(true) }
        }
    }
    /// One row when there is room; otherwise "Earlier" and "Later" on two rows, so no button is ever squeezed.
    var nudges: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Text("Earlier").font(.callout.weight(.semibold)).frame(width: 52, alignment: .leading)
                earlier; Divider().frame(height: 18); later
                Text("Later").font(.callout.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { Text("Earlier").font(.callout.weight(.semibold)).frame(width: 52, alignment: .leading); earlier }
                HStack(spacing: 6) { Text("Later").font(.callout.weight(.semibold)).frame(width: 52, alignment: .leading); later }
            }
        }
    }
    func nb(_ title: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.callout.monospacedDigit()).lineLimit(1) }.buttonStyle(.bordered).fixedSize().help(help + " You hear the result straight away.")
    }

    /// How the Short finishes: loop back to the start, fade out, or stop sharply.
    var ending: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it finishes").font(.subheadline.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    endChoice("Quick fade", on: !c.loop && c.fadeOut == 0.5, "The picture and music fade out over half a second.") { set(loop: false, fade: 0.5) }
                    endChoice("Slow fade", on: !c.loop && c.fadeOut == 2.0, "The picture and music fade out slowly over 2 seconds. Good for an instrumental ending.") { set(loop: false, fade: 2.0) }
                    endChoice("Stop sharply", on: !c.loop && c.fadeOut == 0.05, "The music and picture stop right at the end with no fade.") { set(loop: false, fade: 0.05) }
                    endChoice("Loop back to the start", on: c.loop, "The last moment blends back into the first, so the Short repeats smoothly on phones.") { set(loop: true, fade: nil) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        endChoice("Quick fade", on: !c.loop && c.fadeOut == 0.5, "The picture and music fade out over half a second.") { set(loop: false, fade: 0.5) }
                        endChoice("Slow fade", on: !c.loop && c.fadeOut == 2.0, "The picture and music fade out slowly over 2 seconds. Good for an instrumental ending.") { set(loop: false, fade: 2.0) }
                    }
                    HStack(spacing: 8) {
                        endChoice("Stop sharply", on: !c.loop && c.fadeOut == 0.05, "The music and picture stop right at the end with no fade.") { set(loop: false, fade: 0.05) }
                        endChoice("Loop back to the start", on: c.loop, "The last moment blends back into the first, so the Short repeats smoothly on phones.") { set(loop: true, fade: nil) }
                    }
                }
            }
        }
    }
    func set(loop: Bool, fade: Double?) { model.update(clip.id) { $0.loop = loop; $0.fadeOut = fade }; model.refreshPreview(at: 1) }
    func endChoice(_ t: String, on: Bool, _ help: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).lineLimit(1) }.buttonStyle(.bordered).tint(on ? .accentColor : nil)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2)).help(help)
    }
}

/// A close-up of one end. Click or drag anywhere on it to put that end there.
struct EdgeStrip: View {
    @EnvironmentObject var model: AppModel
    let clip: ShortClip
    let isStart: Bool
    @Binding var span: Double
    let onSet: (Double) -> Void
    private let rows = 3
    var c: ShortClip { model.currentShort ?? clip }
    var t: Double { isStart ? c.start : c.end }
    var dur: Double { max(1, model.plan?.songDuration ?? 1) }
    var color: Color { isStart ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(isStart ? "Click or drag on the picture to move the start." : "Click or drag on the picture to move the end. Purple parts are music only.").font(.callout.weight(.medium))
                Spacer()
                Button { span = min(40, span * 1.5) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out: see more of the song around this end.")
                Button { span = max(3, span / 1.5) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in: place this end very exactly.")
            }
            GeometryReader { geo in
                let lo = min(max(0, t - span / 2), max(0, dur - span)), hi = min(dur, lo + span), w = geo.size.width, h = geo.size.height
                let x: (Double) -> CGFloat = { CGFloat(($0 - lo) / max(0.1, hi - lo)) * w }
                let words = (model.plan?.lines ?? []).flatMap(\.words)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        // music-only stretches (no word for 1.2 s or more) are tinted purple
                        var prevEnd = 0.0
                        for wd in words + [TimedWord(text: "", start: dur, end: dur)] {
                            if wd.start - prevEnd >= 1.2 {
                                let a = max(lo, prevEnd), b = min(hi, wd.start)
                                if b > a {
                                    ctx.fill(Path(CGRect(x: x(a), y: 0, width: x(b) - x(a), height: size.height)), with: .color(.purple.opacity(0.13)))
                                    if x(b) - x(a) > 90 { ctx.draw(Text("♪ music only").font(.system(size: 14, weight: .semibold)).foregroundColor(.purple.opacity(0.85)), at: CGPoint(x: (x(a) + x(b)) / 2, y: 30), anchor: .center) }
                                }
                            }
                            prevEnd = max(prevEnd, wd.end)
                        }
                        // waveform
                        let peaks = model.waveform; let mid = size.height * 0.40
                        if !peaks.isEmpty {
                            var path = Path()
                            for px in stride(from: 0, to: Int(size.width), by: 2) {
                                let i0 = max(0, Int((lo + Double(px) / Double(size.width) * (hi - lo)) * 100)), i1 = min(peaks.count, max(i0 + 1, Int((lo + Double(px + 2) / Double(size.width) * (hi - lo)) * 100)))
                                if i0 >= peaks.count { break }
                                let bar = max(1, CGFloat(peaks[i0..<i1].max() ?? 0) * size.height * 0.34)
                                path.addRect(CGRect(x: CGFloat(px), y: mid - bar, width: 1.4, height: bar * 2))
                            }
                            ctx.fill(path, with: .color(.secondary.opacity(0.85)))
                        }
                        // beats
                        for b in model.beats where b >= lo && b <= hi { ctx.fill(Path(CGRect(x: x(b), y: size.height * 0.74 - 14, width: 1, height: 14)), with: .color(.blue.opacity(0.55))) }
                        // seconds ruler
                        var s = ceil(lo)
                        while s <= hi { ctx.fill(Path(CGRect(x: x(s), y: 0, width: 1, height: s.truncatingRemainder(dividingBy: 5) == 0 ? 9 : 4)), with: .color(.secondary.opacity(0.45)))
                            if s.truncatingRemainder(dividingBy: 5) == 0 { ctx.draw(Text(clock(s)).font(.system(size: 13).monospacedDigit()).foregroundColor(.secondary), at: CGPoint(x: x(s) + 3, y: 14), anchor: .leading) }
                            s += 1 }
                        // words, three staggered rows
                        var rowEnd = [CGFloat](repeating: -100, count: rows); var n = 0
                        for wd in words where wd.start >= lo - 0.5 && wd.start <= hi {
                            let px = x(wd.start), r = n % rows; n += 1
                            let y = size.height * 0.74 + CGFloat(r) * 12 + 2
                            ctx.fill(Path(CGRect(x: px, y: size.height * 0.74 - 14, width: 1, height: 14 + CGFloat(r) * 12)), with: .color(.orange.opacity(0.5)))
                            if px >= rowEnd[r] { ctx.draw(Text(wd.text).font(.system(size: 14, weight: .semibold)).foregroundColor(.orange), at: CGPoint(x: px + 3, y: y + 5), anchor: .leading); rowEnd[r] = px + CGFloat(wd.text.count) * 6.4 + 8 }
                        }
                        // what is outside the Short is dimmed
                        if isStart { ctx.fill(Path(CGRect(x: 0, y: 0, width: max(0, x(c.start)), height: size.height)), with: .color(.black.opacity(0.38))) }
                        else { ctx.fill(Path(CGRect(x: max(0, x(c.end)), y: 0, width: max(0, size.width - x(c.end)), height: size.height)), with: .color(.black.opacity(0.38))) }
                        if let ph = model.playhead, ph >= lo, ph <= hi { ctx.fill(Path(CGRect(x: x(ph) - 1, y: 0, width: 2, height: size.height)), with: .color(.primary)) }
                    }
                    // the marker
                    Rectangle().fill(color).frame(width: 3, height: h).offset(x: x(t) - 1.5)
                    Text(clock(t)).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(.white).fixedSize().padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(color)).offset(x: min(max(0, x(t) - 28), max(0, w - 60)), y: h - 20)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        model.beginTimelineDrag()
                        let raw = lo + Double(min(max(0, g.location.x), w) / w) * (hi - lo)
                        let near = NSEvent.modifierFlags.contains(.shift) ? 0 : 10 * (hi - lo) / Double(max(1, w))      // snapping reach: 10 pixels
                        let v = model.snap(raw, near: near, edgeStart: isStart)
                        model.update(clip.id) { if isStart { $0.start = min(v, $0.end - 0.5) } else { $0.end = max(v, $0.start + 0.5) } }
                    }
                    .onEnded { _ in model.endTimelineDrag(); onSet(t) })
            }.frame(minHeight: 150, idealHeight: 190, maxHeight: 260)
        }
    }
}
