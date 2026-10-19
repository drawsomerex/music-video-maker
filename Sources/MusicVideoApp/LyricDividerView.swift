import SwiftUI
import MVCore

struct LyricDividerView: View {
    @EnvironmentObject var model: AppModel
    var scrollable = true
    @State private var expanded = false
    var body: some View {
        Group {
            if model.listening {
                VStack(spacing: 12) {
                    ProgressView(value: model.listenFraction)
                    Text(model.listenPhase).font(.body)
                    Button("Cancel listening") { model.listenTask?.cancel() }.help("Stop listening. Your lyrics are kept.")
                }.padding()
            } else if model.timelineLines != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pictures & Shorts").font(.headline)
                        Spacer()
                        Button("Expand timeline") { expanded = true }.help("Open the same picture and Shorts controls in a larger window.")
                    }
                    SongTimelineEditor(scrollable: scrollable)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose where pictures change and where Shorts begin and end.").font(.title3)
                    Text("Listen once to put your words and music on a timeline. No pictures are generated.").foregroundStyle(.secondary)
                    Button("Listen and show the timeline") { model.listenToSong() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.audioURL == nil || LyricText.rows(model.lyrics).isEmpty)
                        .help("Choose a song and paste its lyrics first. Listening finds the timing and does not spend picture credit.")
                    ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(LyricText.rows(model.lyrics)) { r in Text(r.text).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading) } } }
                }
            }
        }
        .sheet(isPresented: $expanded) {
            VStack {
                HStack { Text("Song timeline").font(.title2); Spacer(); Button("Done") { expanded = false }.help("Return to the first page. Your changes are kept.") }
                SongTimelineEditor()
            }.padding(20).frame(minWidth: 800, idealWidth: 1100, minHeight: 500, idealHeight: 720)
        }
    }
}

struct SongTimelineEditor: View {
    @EnvironmentObject var model: AppModel
    var scrollable = true
    @State private var picture = 0
    @State private var tab = 0
    @State private var reset = false
    @State private var pendingSplit: Double?
    @State private var pendingJoin: Int?
    var sections: [PhotoSection] { model.previewSections ?? [] }
    var duration: Double { model.timelineLines?.duration ?? 1 }
    var body: some View {
        ScrollViewReader { proxy in
            Group { if scrollable { ScrollView { content } } else { content } }
                .disabled(model.busy || model.shortProgress != nil || model.stage == .rendering)
                .onChange(of: picture) { _, new in withAnimation { proxy.scrollTo("pic\(new)", anchor: .top) } }
        }
    }
    var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { history; Spacer(); zoom }
                VStack(alignment: .leading) { history; zoom }
            }
            GeometryReader { area in
                ScrollView(.horizontal) { timelineStrip.frame(width: max(1, area.size.width * model.timelineZoom), height: CGFloat(96 + model.timelineShorts.count * 30)) }
            }.frame(height: CGFloat(96 + model.timelineShorts.count * 30))
            HStack {
                Text("Listening point: \(preciseClock(model.timelineCursor))").monospacedDigit()
                Spacer()
                Button(model.playhead == nil ? "Listen here" : "Stop") {
                    if model.playhead == nil { model.playRange(model.timelineCursor, duration) } else { model.stopPlayback() }
                }.help("Listen from the chosen point. This does not change a picture or Short.")
            }.font(.callout)
            Slider(value: $model.timelineCursor, in: 0...max(0.1, duration))
                .help("Choose a listening or split point. Moving this slider does not edit anything.")
                .accessibilityLabel("Listening and split point")
            Toggle("Keep whole words when placing cuts", isOn: $model.timelineSnap).font(.callout)
                .help("When the point falls inside a sung word, start before the word or end after it. Turn off for an exact cut.")
            Picker("Edit", selection: $tab) { Text("Pictures (\(sections.count))").tag(0); Text("Shorts (\(model.timelineShorts.count))").tag(1) }
                .pickerStyle(.segmented).help("Picture divisions and Shorts have independent controls.")
            editList
            if !model.snapDescription.isEmpty {
                HStack(spacing: 10) {
                    Text(model.snapDescription).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if !model.editUndo.isEmpty { Button("Undo") { model.undoEdit() }.buttonStyle(.borderedProminent).help("Put the pictures back exactly as they were before this change.") }
                }.padding(8).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.saveStatus.isEmpty {
                HStack { Text(model.saveStatus).font(.callout); if model.saveStatus != "Saved" { Button("Try saving again") { model.persist() }.help("Try to save the current project again.") } }
            }
        }
        .confirmationDialog("Restore automatic picture divisions?", isPresented: $reset, titleVisibility: .visible) {
            Button("Restore picture divisions") { model.restoreAutomaticPictures() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your artwork is kept. Shorts are unchanged. You can Undo this action.") }
        .confirmationDialog("Start a new picture here?", isPresented: Binding(get: { pendingSplit != nil }, set: { if !$0 { pendingSplit = nil } }), titleVisibility: .visible, presenting: pendingSplit) { t in
            Button("Start new picture at \(preciseClock(t))") { model.splitPicture(at: t) }
            Button("Hear this change") { model.playRange(max(0, t - 2), min(duration, t + 3)) }
            Button("Cancel", role: .cancel) {}
        } message: { t in Text("A new picture starts at \(preciseClock(t)). Every other picture, the song and the Shorts stay as they are. You can Undo.") }
        .confirmationDialog("Join these two pictures?", isPresented: Binding(get: { pendingJoin != nil }, set: { if !$0 { pendingJoin = nil } }), titleVisibility: .visible) {
            Button("Join pictures") { if let i = pendingJoin { model.joinPicture(before: i); picture = max(0, i - 1) }; pendingJoin = nil }
            Button("Cancel", role: .cancel) { pendingJoin = nil }
        } message: { Text("The first picture will cover both sections. Other artwork is kept as alternatives. Audio and Shorts stay unchanged.") }
    }
    var history: some View {
        HStack {
            Button("Undo") { model.undoEdit() }.disabled(model.editUndo.isEmpty).help(model.editUndo.last.map { "Undo: " + $0.name } ?? "Nothing to undo.")
            Button("Redo") { model.redoEdit() }.disabled(model.editRedo.isEmpty).help("Restore the edit you just undid.")
        }
    }
    var zoom: some View {
        HStack {
            Button("−") { model.timelineZoom = max(1, model.timelineZoom / 1.4) }.help("Zoom out to see more of the song.")
            Text("Timeline zoom").font(.callout)
            Button("+") { model.timelineZoom = min(8, model.timelineZoom * 1.4) }.help("Zoom in for more precise placement.")
        }
    }
    var timelineStrip: some View {
        GeometryReader { geo in
            let width = geo.size.width, d = max(0.1, duration)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let ideal = d * 65 / max(1, width)
                    let step = [5, 10, 15, 30, 60, 120, 300, 600].first { Double($0) >= ideal } ?? 600
                    for t in stride(from: 0, through: Int(d), by: step) {
                        let x = Double(t) / d * size.width
                        context.draw(Text(String(format: "%d:%02d", t / 60, t % 60)).font(.system(size: 13)).foregroundColor(.secondary), at: CGPoint(x: x + 2, y: 8), anchor: .topLeading)
                    }
                    let peaks = model.waveform
                    if !peaks.isEmpty {
                        var path = Path()
                        for px in stride(from: 0, to: Int(width), by: 2) {
                            let lo = min(peaks.count - 1, Int(Double(px) / width * Double(peaks.count)))
                            let hi = min(peaks.count, max(lo + 1, Int(Double(px + 2) / width * Double(peaks.count))))
                            let h = CGFloat(peaks[lo..<hi].max() ?? 0) * 9
                            path.addRect(CGRect(x: CGFloat(px), y: 34 - h, width: 1.5, height: max(1, h * 2)))
                        }
                        context.fill(path, with: .color(.secondary))
                    }
                }.frame(height: 46)
                ForEach(Array(sections.enumerated()), id: \.offset) { i, s in
                    Button {
                        picture = i; tab = 0; model.timelineCursor = s.start
                    } label: {
                        Text("\(i + 1)\(s.lineIDs.isEmpty ? " ♪" : "")").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            .frame(width: max(4, CGFloat(s.duration / d) * width - 2), height: 30)
                            .background(picture == i ? Color.accentColor : Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(picture == i ? Color.white : Color.primary)
                    }.buttonStyle(.plain).offset(x: CGFloat(s.start / d) * width, y: 48)
                        .help("Picture \(i + 1): \(preciseClock(s.start)) to \(preciseClock(s.end)). Selects it without changing its timing.")
                }
                ForEach(Array(model.timelineShorts.enumerated()), id: \.element.id) { i, c in
                    Button { model.selectedShort = c.id; tab = 1; model.timelineCursor = c.start } label: {
                        Text(c.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            .frame(width: max(4, CGFloat(c.duration / d) * width - 2), height: 26)
                            .background(Color.orange.opacity(model.selectedShort == c.id ? 0.8 : 0.3), in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).offset(x: CGFloat(c.start / d) * width, y: CGFloat(86 + i * 30))
                        .help("Select \(c.name). This does not move or resize the Short.")
                }
                Rectangle().fill(Color.primary).frame(width: 2).offset(x: CGFloat((model.playhead ?? model.timelineCursor) / d) * width).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in model.timelineCursor = max(0, min(d, location.x / width * d)) }
        }
    }
    @ViewBuilder var editList: some View {
        if tab == 0 {
            VStack(alignment: .leading, spacing: 10) {
                Text("Picture changes leave the song audio intact. The title card is separate from these numbered pictures.").font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
                    Button("Split picture at point") { pendingSplit = model.snappedTimelineTime(model.timelineCursor, start: true) }.help("Preview a picture split at the listening point, including within music-only sections.")
                    Button("Split long sections") { model.splitLongVerses() }.help("Split sections longer than 30 seconds into equal pictures. Artwork is reused and Shorts stay unchanged.")
                    Button("Restore automatic divisions") { reset = true }.help("Restore automatic verse and music divisions. Artwork is kept and you can Undo.")
                }.buttonStyle(.bordered)
                ForEach(Array(sections.enumerated()), id: \.offset) { i, s in pictureRow(i, s) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Add a Short") { model.addTimelineShort() }.help("Add a 30-second Short at the listening point. You can adjust both ends.")
                    Button("Suggest Shorts") { model.suggestTimelineShorts() }.help("Add suggested Shorts using lyric pauses. Existing Shorts and pictures are kept.")
                }.buttonStyle(.bordered)
                Text("Shorts have their own start, end, split and join controls. Picture edits do not change them.").font(.callout).foregroundStyle(.secondary)
                ForEach(model.timelineShorts) { c in shortRow(c) }
            }
        }
    }
    func pictureRow(_ i: Int, _ s: PhotoSection) -> some View {
        let lines = model.timelineLines?.lines ?? []
        let ids = s.lineIDs.filter { lines.indices.contains($0) }.sorted()
        return VStack(alignment: .leading, spacing: 6) {
            Button { picture = i; model.timelineCursor = s.start } label: {
                HStack { Label("Picture \(i + 1)\(s.lineIDs.isEmpty ? " — music only" : "")", systemImage: s.lineIDs.isEmpty ? "music.note" : "photo").font(.headline); Spacer(); Text("\(preciseClock(s.start))–\(preciseClock(s.end)) · \(Int(s.duration.rounded())) s").font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
            }.buttonStyle(.plain).help("Select this picture and place the listening point at its start.")
            ViewThatFits(in: .horizontal) {
                HStack { pictureActions(i, s) }
                VStack(alignment: .leading, spacing: 6) { pictureActions(i, s) }
            }
            if ids.isEmpty {
                Label("♪ Music — no singing", systemImage: "music.note").font(.callout.weight(.semibold)).foregroundStyle(.purple)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 8)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            // every lyric line of this picture, always visible, with a cut line between lines
            ForEach(ids, id: \.self) { line in
                VStack(alignment: .leading, spacing: 2) {
                    if line != ids.first, lines[line].start >= s.start + 0.5, lines[line].start <= s.end - 0.5 {
                        Button { pendingSplit = lines[line].start } label: {
                            HStack(spacing: 6) { Image(systemName: "scissors").font(.caption2); VStack { Divider() }; Text("start a new picture here (\(preciseClock(lines[line].start)))").font(.caption); VStack { Divider() } }
                                .foregroundStyle(.secondary).frame(minHeight: 24).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Starts a new picture before the line below. Every other picture stays as it is, and you can Undo.")
                    }
                    HStack(spacing: 8) {
                        Text(preciseClock(lines[line].start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                        Text(lines[line].text).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                        Button { model.timelineCursor = lines[line].start; model.playRange(lines[line].start, lines[line].end) } label: { Image(systemName: "play.fill").font(.caption2) }
                            .buttonStyle(.borderless).help("Listen to this line. Nothing is changed.")
                    }
                }
            }
        }
        .id("pic\(i)")
        .padding(12).background(picture == i ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
    @ViewBuilder func pictureActions(_ i: Int, _ s: PhotoSection) -> some View {
        Button("Listen") { model.playRange(s.start, s.end) }.help("Listen to this entire picture section.")
        Button("Split in two") { model.subdivide(section: s, into: 2) }.disabled(s.duration < 1).help("Make two equal picture sections using the same artwork, including for music-only sections.")
        Button("Join with previous") { pendingJoin = i }.disabled(i == 0).help("Remove the boundary with the previous picture, including between music and singing.")
    }
    func shortRow(_ c: ShortClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Short name", text: Binding(get: { model.timelineShorts.first(where: { $0.id == c.id })?.name ?? c.name }, set: { name in model.editTimelineShort(c.id) { $0.name = name } }))
                .textFieldStyle(.roundedBorder).font(.headline).help("Rename this Short. The name is used for its video file.")
            Text("\(preciseClock(c.start))–\(preciseClock(c.end)) · \(Int(c.duration.rounded())) seconds").monospacedDigit()
            HStack {
                Text("Start")
                Slider(value: Binding(get: { model.timelineShorts.first(where: { $0.id == c.id })?.start ?? c.start }, set: { value in model.editTimelineShort(c.id) { $0.start = min(model.snappedTimelineTime(value, start: true), $0.end - 0.5) } }), in: 0...max(0.1, duration), onEditingChanged: { editing in if editing { model.beginTimelineDrag() } else { model.endTimelineDrag() } })
                    .help("Move only the start of this Short. Whole-word mode moves it before a word.")
            }
            HStack {
                Text("End")
                Slider(value: Binding(get: { model.timelineShorts.first(where: { $0.id == c.id })?.end ?? c.end }, set: { value in model.editTimelineShort(c.id) { $0.end = max(model.snappedTimelineTime(value, start: false), $0.start + 0.5) } }), in: 0...max(0.1, duration), onEditingChanged: { editing in if editing { model.beginTimelineDrag() } else { model.endTimelineDrag() } })
                    .help("Move only the end of this Short. Whole-word mode moves it after a word. Maximum length is 3 minutes.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))]) {
                Button("Play Short") { model.selectedShort = c.id; model.playRange(c.start, c.end) }.help("Play this Short from its start to its end.")
                Button("Split at point") { model.splitTimelineShort(c.id) }.disabled(model.timelineCursor < c.start + 0.5 || model.timelineCursor > c.end - 0.5).help("Replace this Short with two at the listening point. Undo restores the original.")
                Button("Join with next Short") { model.joinTimelineShort(c.id) }.disabled(!canJoin(c)).help(joinHelp(c))
                Button("Delete Short", role: .destructive) { model.removeTimelineShort(c.id) }.help("Remove only this Short. The song and pictures are kept. Undo restores it.")
            }.buttonStyle(.bordered)
        }.padding(12).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
    func canJoin(_ c: ShortClip) -> Bool {
        let sorted = model.timelineShorts.sorted { $0.start < $1.start }
        guard let i = sorted.firstIndex(where: { $0.id == c.id }), i + 1 < sorted.count else { return false }
        return max(c.end, sorted[i + 1].end) - min(c.start, sorted[i + 1].start) <= ShortClip.maxDuration
    }
    func joinHelp(_ c: ShortClip) -> String {
        canJoin(c) ? "Join with the next Short, including all music and singing in between. Undo restores both." : "There is no next Short, or the joined Short would exceed 3 minutes. Move the ends closer to join."
    }
}
