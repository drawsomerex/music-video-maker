// "Divide into parts": the song on a timeline. Every lyric line sits at its time; music-only stretches are purple "Music" blocks.
// One picture per verse and one per music break (a very long break is split into equal pictures). Cut between lines to add pictures,
// join pictures, or split a verse into several. Before the song has been listened to, the lyrics are shown as a plain list.
import SwiftUI
import MVCore

struct LyricDividerView: View {
    @EnvironmentObject var model: AppModel
    var scrollable = true            // false only for layout snapshots (ScrollView can't be drawn by ImageRenderer)
    private let tints: [Color] = [.blue, .orange, .green, .pink, .teal, .indigo, .brown, .red]

    private func clock(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
    private var verseMode: Bool { !LyricText.hasDividers(model.lyrics) && LyricText.rows(model.lyrics).contains { $0.blankBefore } }
    private func toggle(_ i: Int) { if verseMode { model.dividersFromVerses() }; model.toggleDivider(before: i) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if LyricText.rows(model.lyrics).isEmpty {
                Label("Add your lyrics first — switch to “Type or paste”.", systemImage: "text.alignleft").font(.callout).foregroundStyle(.secondary)
            } else if model.listening {
                listeningCard
            } else if let secs = model.previewSections, let t = model.timelineLines {
                timeline(secs, t.lines)
            } else {
                listenCard
            }
        }
    }

    // MARK: before listening
    var listenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.and.magnifyingglass").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("See your song on a timeline").font(.title3.bold())
                    Text("The app listens to the song once (about a minute) to find when every line is sung and where the music-only breaks are. Then you can see and change where each picture goes. Nothing is drawn yet.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button { model.listenToSong() } label: { Label("Listen to the song first (about a minute)", systemImage: "ear").padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.audioURL == nil)
                    .help(model.audioURL == nil ? "Choose your song first." : "Finds when each line is sung and where the music-only breaks are. No pictures are made and nothing is spent.")
                Text(model.audioURL == nil ? "Choose your song first." : "Or just press “Plan my video”: it uses one picture per verse and per music break.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Your lyrics so far").font(.callout.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            Group { if scrollable { ScrollView { plainList } } else { plainList } }
                .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.25)))
        }
    }
    var plainList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(LyricText.rows(model.lyrics)) { r in
                if r.blankBefore { Divider().padding(.vertical, 3) }
                Text(r.text).font(.system(size: 15, design: .rounded)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(10)
    }
    var listeningCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: max(0.03, model.listenFraction)).progressViewStyle(.linear).frame(maxWidth: 360)
            Text(model.listenPhase.isEmpty ? "Listening to the song…" : model.listenPhase).font(.callout).foregroundStyle(.secondary)
            Text("This takes about a minute. You can keep this window open.").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity).padding(30)
    }

    // MARK: the timeline
    enum Item: Identifiable {
        case picture(n: Int, sec: PhotoSection, tint: Color)
        case music(n: Int, sec: PhotoSection)
        case cut(line: Int)
        case line(idx: Int, tint: Color)
        var id: String {
            switch self { case .picture(let n, _, _): return "p\(n)"; case .music(let n, _): return "m\(n)"; case .cut(let l): return "c\(l)"; case .line(let i, _): return "l\(i)" }
        }
    }

    func timeline(_ secs: [PhotoSection], _ lines: [LyricLine]) -> some View {
        var items: [Item] = []
        for (n, s) in secs.enumerated() {
            if s.lineIDs.isEmpty { items.append(.music(n: n, sec: s)); continue }
            let tint = tints[n % tints.count]
            items.append(.picture(n: n, sec: s, tint: tint))
            for (k, i) in s.lineIDs.sorted().enumerated() {
                if k > 0 { items.append(.cut(line: i)) }
                items.append(.line(idx: i, tint: tint))
            }
        }
        let shorts = model.plan?.shorts ?? []
        let cost = Double(secs.count + 1) * model.perImageCostUSD
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "photo.stack").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(secs.count) pictures").font(.title3.bold()) + Text("  ·  about \(OpenRouter.formatUSD(cost)) to draw them all").font(.callout).foregroundColor(.secondary)
                    Text("One picture for every verse and every music break. Cut between lines to add a picture; click a coloured bar to join it with the one above.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { model.splitLongVerses() } label: { Label("Split long verses", systemImage: "scissors").lineLimit(1) }
                    .help("Splits every verse longer than 30 seconds into pictures of about 20 to 30 seconds, cutting between lines.")
                Button { model.clearDividers() } label: { Label("Start over", systemImage: "arrow.counterclockwise").lineLimit(1) }
                    .help("Removes your own cuts, so the pictures follow your verse breaks and the music breaks again.")
                Spacer()
                if model.analysis != nil, model.analysis?.key == model.analysisKey { Label("Song listened to", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
            }
            Group {
                if scrollable { ScrollView { rows(items, secs, lines, shorts) } } else { rows(items, secs, lines, shorts) }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.background.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.25)))
        }
    }

    func shortIndex(_ a: Double, _ b: Double, _ shorts: [ShortClip]) -> Int? { shorts.firstIndex { $0.start < b - 0.2 && $0.end > a + 0.2 } }

    func rows(_ items: [Item], _ secs: [PhotoSection], _ lines: [LyricLine], _ shorts: [ShortClip]) -> some View {
        var lastShort: Int? = nil
        var out: [(Item, Int?, Bool)] = []                       // item, which Short covers it, first row of that Short
        for it in items {
            var s: Int? = nil
            switch it {
            case .line(let i, _): s = shortIndex(lines[i].start, lines[i].end, shorts)
            case .music(_, let sec): s = shortIndex(sec.start, sec.end, shorts)
            default: s = lastShort
            }
            if case .picture = it { s = lastShort }
            out.append((it, s, s != nil && s != lastShort))
            if case .line = it { lastShort = s } else if case .music = it { lastShort = s }
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(out, id: \.0.id) { (it, s, first) in
                HStack(alignment: .top, spacing: 6) {
                    row(it, secs, lines).frame(maxWidth: .infinity)
                    if let s { shortBar(s, first) } else { Color.clear.frame(width: 58) }
                }
            }
        }.padding(10)
    }

    /// A thin bar (with its name on the first row) showing which lines a Short covers.
    func shortBar(_ s: Int, _ first: Bool) -> some View {
        let c = Color.accentColor
        return HStack(spacing: 3) {
            if first { Text("Short \(s + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(c).lineLimit(1).frame(width: 48, alignment: .trailing) } else { Color.clear.frame(width: 48) }
            Rectangle().fill(c.opacity(0.7)).frame(width: 4)
        }.frame(width: 58).help("This part of the song is in Short \(s + 1). Fine-tune it on the Shorts page.")
    }

    @ViewBuilder func row(_ it: Item, _ secs: [PhotoSection], _ lines: [LyricLine]) -> some View {
        switch it {
        case .music(let n, let sec):
            HStack(spacing: 10) {
                Image(systemName: "music.note").font(.title3).foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("♪ Music — no singing").font(.callout.weight(.bold)).foregroundStyle(.purple)
                    Text("\(clock(sec.start)) – \(clock(sec.end)) · \(Int(sec.duration.rounded())) s · picture \(n + 1)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.playRange(sec.start, sec.end) } label: { Image(systemName: "play.fill").font(.caption2) }.buttonStyle(.bordered)
                    .help("Listen to this music break.")
            }
            .padding(.horizontal, 10).padding(.vertical, 8 + min(24, sec.duration * 0.5))
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.purple.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .padding(.vertical, 4)
        case .picture(let n, let sec, let tint):
            let first = sec.lineIDs.min() ?? 0
            let prevHasLines = n > 0 && !(secs[n - 1].lineIDs.isEmpty)
            HStack(spacing: 8) {
                Image(systemName: "photo").font(.caption)
                Text("Picture \(n + 1)").font(.callout.weight(.bold))
                Text("· \(clock(sec.start))–\(clock(sec.end)) · \(Int(sec.duration.rounded())) s · \(sec.lineIDs.count) \(sec.lineIDs.count == 1 ? "line" : "lines")").font(.callout)
                Spacer()
                if sec.lineIDs.count >= 2 {
                    Button { model.subdivide(section: sec, into: 2) } label: { Label("Split in two", systemImage: "scissors").font(.caption) }
                        .buttonStyle(.plain).help("Cuts this picture into two pictures of about the same length, between two lines.")
                }
                if prevHasLines && first > 0 {
                    Button { toggle(first) } label: { Label("Join with above", systemImage: "arrow.up.to.line").font(.caption) }
                        .buttonStyle(.plain).help("Removes this cut, so these lines share the picture above.")
                }
            }
            .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint)).padding(.top, 6).padding(.bottom, 3)
        case .cut(let i):
            Button { toggle(i) } label: {
                HStack(spacing: 6) { Image(systemName: "scissors").font(.caption2); VStack { Divider() }; Text("cut here").font(.caption2); VStack { Divider() } }
                    .foregroundStyle(.tertiary).frame(height: 18).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Click to cut here. The lines below this cut start a new picture.")
        case .line(let i, let tint):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 5)
                Text(clock(lines[i].start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                Text(lines[i].text).font(.system(size: 15, design: .rounded)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button { model.playRange(max(0, lines[i].start - 0.15), lines[i].end + 0.25) } label: { Image(systemName: "play.fill").font(.caption2) }
                    .buttonStyle(.borderless).help("Listen to this line.")
            }
            .padding(.vertical, 3).background(tint.opacity(0.08))
        }
    }
}
