// The words of the song laid out along time, large enough to read. Click a word to start the Short there; Shift-click to end it there.
import SwiftUI
import MVCore

struct WordLane: View {
    @EnvironmentObject var model: AppModel
    let clipID: UUID
    private let pps: CGFloat = 78                 // pixels per second: wide enough that every word can be read
    private let rowH: CGFloat = 26
    private let rows = 4
    var scrollable = true                         // false only for layout snapshots (ScrollView can't be drawn by ImageRenderer)

    var clip: ShortClip? { model.plan?.shorts.first { $0.id == clipID } }

    var body: some View {
        let dur = model.plan?.songDuration ?? 1
        let words = (model.plan?.lines ?? []).flatMap(\.words)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("The words").font(.headline)
                Text("Scroll sideways. Click a word to start the Short at it; Shift-click a word to end the Short at it.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ScrollViewReader { proxy in
                Group {
                    if scrollable {
                        ScrollView(.horizontal, showsIndicators: true) { laneContent(dur, words) }
                    } else {
                        laneContent(dur, words).offset(x: 20 - CGFloat(clip?.start ?? 0) * pps).frame(width: 760, alignment: .leading).clipped()
                    }
                }
                .frame(height: rowH * CGFloat(rows) + 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .onAppear { jump(proxy, to: (clip?.start ?? 0) - 1.5) }
                .onChange(of: clipID) { _, _ in jump(proxy, to: (clip?.start ?? 0) - 1.5) }
                .onChange(of: clip?.start) { _, s in jump(proxy, to: (s ?? 0) - 1.5) }
            }
        }
    }


    @ViewBuilder func laneContent(_ dur: Double, _ words: [TimedWord]) -> some View {
        let place = layout(words)
        ZStack(alignment: .topLeading) {
            // a time ruler: a label every 5 seconds
            ForEach(0..<Int(dur / 5) + 1, id: \.self) { k in
                Text(clock(Double(k * 5))).font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary).offset(x: CGFloat(k * 5) * pps + 2, y: 0)
            }
            if let c = clip {
                // the Short itself: a coloured band behind its words, with a green start line and a red end line
                Rectangle().fill(ShortLength.color(c.duration).opacity(0.16)).frame(width: CGFloat(c.duration) * pps, height: rowH * CGFloat(rows) + 18).offset(x: CGFloat(c.start) * pps, y: 14)
                Rectangle().fill(.green).frame(width: 2, height: rowH * CGFloat(rows) + 18).offset(x: CGFloat(c.start) * pps, y: 14)
                Rectangle().fill(.red).frame(width: 2, height: rowH * CGFloat(rows) + 18).offset(x: CGFloat(c.end) * pps, y: 14)
            }
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                let inside = clip.map { w.start >= $0.start - 0.01 && w.end <= $0.end + 0.01 } ?? false
                Button { pick(w) } label: {
                    Text(w.text).font(.system(size: 13, weight: inside ? .semibold : .regular)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 5).frame(height: rowH - 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(inside ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14)))
                        .foregroundStyle(inside ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(w.start) * pps, y: 16 + CGFloat(place[i]) * rowH)
                .help(String(format: "“%@” at %@. Click to start the Short here; Shift-click to end it here.", w.text, clock(w.start)))
            }
            ForEach(0..<Int(dur / 2) + 1, id: \.self) { k in Color.clear.frame(width: 1, height: 1).offset(x: CGFloat(k * 2) * pps).id(k * 2) }
        }
        .frame(width: CGFloat(dur) * pps + 80, height: rowH * CGFloat(rows) + 34, alignment: .topLeading)
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

    func jump(_ proxy: ScrollViewProxy, to t: Double) { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(max(0, Int(t / 2) * 2), anchor: .leading) } }

    func pick(_ w: TimedWord) {
        if NSEvent.modifierFlags.contains(.shift) { model.update(clipID) { $0.end = max($0.start + 2, w.end + 0.1) } }
        else { model.update(clipID) { let d = $0.duration; $0.start = max(0, w.start - 0.05); if $0.end <= $0.start + 2 { $0.end = $0.start + min(d, 30) } } }
    }
}
