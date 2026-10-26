// Step 2 screen: sections, prompts and picture loading.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

/// Step 2: for each section see the lyrics + a suggested prompt, generate or drop the picture in, and render.
struct PlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropSection: Int?
    @State private var confirmMissing = false
    @State private var confirmRegenAll = false
    @State private var mode = ProcessInfo.processInfo.environment["MV_DEMO_MODE"] == "1" ? 1 : 0   // 0 = full video, 1 = YouTube Shorts

    var plan: Plan { model.plan! }
    var selection: Int { model.selectedSection }
    var section: PhotoSection {
        let idx = selection
        if idx < 0 || !plan.sections.indices.contains(idx) { return plan.intro }
        return plan.sections[idx]
    }

    @AppStorage("picturesTimeline") private var timelineChoice = "auto"     // "auto" (follows the window height), "open" or "closed": your last choice
    @State private var windowHeight: CGFloat = 900
    @State private var confirmAllPictures = false
    @State private var confirmHighest = false
    @State private var confirmAllClips = false
    var timelineOpen: Bool { timelineChoice == "open" || (timelineChoice == "auto" && windowHeight >= 900) }
    var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button { withAnimation { timelineChoice = timelineOpen ? "closed" : "open" } } label: { Label("Timeline", systemImage: timelineOpen ? "chevron.down" : "chevron.right").font(.headline) }.buttonStyle(.plain)
                    .help("The whole song on a true-to-scale timeline: drag the picture borders and the Shorts. Click to open or fold it; the app remembers your choice.")
                if !timelineOpen { TimelineStrip { withAnimation { timelineChoice = "open" } } }
                else { Spacer() }
            }
            if timelineOpen { ScaledTimeline() }
        }.padding(.horizontal, 20).padding(.vertical, timelineOpen ? 8 : 5)
    }
    var snapshot = false
    init(snapshot: Bool = false) { self.snapshot = snapshot }

    /// For screenshots only: the Pictures screen with a plain side-by-side list and detail (the real one uses a split view that cannot be drawn offscreen).
    var snapshotLayout: some View {
        VStack(spacing: 0) {
            modeBar; Divider(); styleBar; Divider()
            HStack(spacing: 0) { sidebar.frame(width: 300); Divider(); detail }
            Divider(); footer
        }
    }

    var body: some View {
        if snapshot { snapshotLayout } else { mainBody }
    }

    @ViewBuilder var mainBody: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            if mode == 0 {
                styleBar
                Divider()
                timelinePanel
                Divider()
                HSplitView {
                    sidebar.frame(minWidth: 220, idealWidth: 300, maxWidth: 520)
                    detail.frame(minWidth: 420)
                }
                Divider()
                footer
            } else {
                ShortsView()
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { windowHeight = g.size.height }.onChange(of: g.size.height) { _, h in windowHeight = h } })
        .sheet(isPresented: $model.showFullPreview, onDismiss: { model.live.pause() }) {
            VStack(spacing: 12) {
                HStack { Text("Preview — \(plan.title)").font(.headline); Spacer(); Button("Done") { model.showFullPreview = false }.keyboardShortcut(.defaultAction) }
                LivePreviewPane(live: model.live, defaultCaption: 0.075) { v in model.setCaptionY(v, shortID: nil) }
                CaptionTimingBar().environmentObject(model)
                Text("This is exactly what the finished video will look like. Drag the words up or down to move them.").font(.callout).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 620, idealWidth: 800, minHeight: 460, idealHeight: 620)
        }
        .onChange(of: model.requestRegenAll) { _, v in if v { confirmRegenAll = true; model.requestRegenAll = false } }
        .sheet(isPresented: $showDescriptionSheet) { DescriptionSheet().environmentObject(model) }
        .sheet(isPresented: $showStyleSheet) { StyleSheet(inProject: true).environmentObject(model) }
        .sheet(isPresented: $showSubjectSheet) { FindPictureSheet(set: { model.setSongReference($0) }) }
        .sheet(isPresented: $model.showOpenRouterKeySheet) {
            OpenRouterKeySheet()
                .environmentObject(model)
        }
        .alert("Notice", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.notice ?? "") }
        .confirmationDialog("\(model.missing.count) section(s) have no picture yet", isPresented: $confirmMissing, titleVisibility: .visible) {
            Button("Draw the \(model.missing.count) missing picture\(model.missing.count == 1 ? "" : "s") (≈ \(OpenRouter.formatUSD(model.missingImagesCostUSD))), then make the video") {
                model.drawMissingThenRender()
            }
            Button("Make it with colour backgrounds in the gaps") { model.render() }
            Button("Keep working", role: .cancel) {}
        }
        .confirmationDialog("Regenerate all \(model.totalImages) pictures for this song?", isPresented: $confirmRegenAll, titleVisibility: .visible) {
            Button("Regenerate All \(model.totalImages) Pictures (~\(OpenRouter.formatUSD(model.allImagesCostUSD)))") {
                model.regenerateAllImages()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will generate \(model.totalImages) new 16:9 Medium images using \(OpenRouter.imageModel) (estimated cost ~\(OpenRouter.formatUSD(model.allImagesCostUSD))) and add the cost to this song's total.")
        }
    }

    var modeBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { modeBarLeading(compact: false); Spacer(minLength: 8); modeBarActions(compact: false) }
            HStack(spacing: 10) { modeBarLeading(compact: true); Spacer(minLength: 6); modeBarActions(compact: true) }
        }
        .padding(.horizontal, 20).padding(.vertical, 8).background(.regularMaterial)
    }

    func modeBarLeading(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 14) {
            StepBar(current: 2, compact: compact)
            Divider().frame(height: 22)
            Picker("", selection: $mode) { Text(compact ? "Video" : "Full video").tag(0); Text(compact ? "Shorts" : "YouTube Shorts").tag(1) }
                .pickerStyle(.segmented).frame(width: compact ? 170 : 260).labelsHidden()
                .help("“Full video” is the whole song in widescreen. “YouTube Shorts” makes short vertical videos for phones.")
            if !compact { Text(plan.title).font(.headline).lineLimit(1).truncationMode(.tail).frame(maxWidth: 260) }
            if plan.timing != "exact" {
                if !compact { Label("Word timing is rough", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).lineLimit(1) }
                Button { model.resync() } label: { Label(model.resyncing ? "Working…" : "Fix the timing", systemImage: "waveform.badge.magnifyingglass") }
                    .disabled(model.resyncing).buttonStyle(.borderedProminent)
                    .help("The word timing is only rough. This listens to the song again to line every word up exactly. Takes about a minute. Your pictures are not touched.")
            }
        }
    }

    func modeBarActions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Button { model.revealProject() } label: { if compact { Image(systemName: "folder") } else { Label("Show folder", systemImage: "folder") } }
                .help("Opens this song's folder in Finder: the MP3, lyrics, pictures and finished videos.")
            Menu {
                Button("Open the Pictures folder") { model.showPicturesFolder() }
                Button("Add my earlier pictures and clips to it…") { model.backfillPictureLibrary() }
            } label: { if compact { Image(systemName: "photo.on.rectangle.angled") } else { Label("Pictures folder", systemImage: "photo.on.rectangle.angled") } }
                .menuIndicator(.hidden).fixedSize()
                .help("Opens the Pictures folder: every picture of every song (drawn by the app or added by you), named with its date, the song and an increasing number, so you can scroll through them.")
            HelpButton(screen: mode == 1 ? "Pictures screen, YouTube Shorts tab" : "Pictures screen")
            Button { model.reset() } label: { if compact { Image(systemName: "xmark.circle") } else { Label("Close", systemImage: "xmark.circle") } }
                .help("Closes this song and returns to the start. Everything is already saved; open it again from “Projects” (Command-O).")
        }
    }

    // MARK: top area — one clear message and a few labelled buttons (no hidden drop-downs)
    @State private var showDescriptionSheet = false
    @State private var showStyleSheet = false
    @State private var showSubjectSheet = false

    var styleBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.canAddInstrumentalIntro, let first = plan.lines.first?.start {
                HStack(spacing: 12) {
                    Image(systemName: "music.note").foregroundStyle(.orange)
                    Text("The first words start at \(timeString(first)), but the music before them has no picture of its own.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button { model.addInstrumentalIntro() } label: { Label("Add a picture for the opening music", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent).disabled(model.busy)
                        .help("Adds a new part to the list for the music before the first words and writes a picture idea for it. Your other pictures stay exactly where they are.")
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
            // one row: the two big jobs, everything else under More; the "what next" sentence only when there is room for it
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { makeAllButton(short: false); clipsAllButton(short: false); moreMenu; nextStepLine.padding(.leading, 6); Spacer(minLength: 0) }
                HStack(spacing: 8) { makeAllButton(short: false); clipsAllButton(short: false); moreMenu; Spacer(minLength: 0) }
                HStack(spacing: 8) { makeAllButton(short: true); clipsAllButton(short: true); moreMenu; Spacer(minLength: 0) }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20).padding(.vertical, 8).background(.regularMaterial)
        .confirmationDialog("Make all the missing pictures?", isPresented: $confirmAllPictures, titleVisibility: .visible) {
            Button("Make \(model.missing.count) picture\(model.missing.count == 1 ? "" : "s") (≈ \(OpenRouter.formatUSD(model.missingImagesCostUSD)))") { model.generateAllMissingImages() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.missing.count) picture\(model.missing.count == 1 ? "" : "s") at about \(OpenRouter.formatUSD(model.missingImagesCostUSD)) in total." + (model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? "") + " Video clips are separate and only made when you ask.")
        }
        .confirmationDialog("Make every picture highest quality?", isPresented: $confirmHighest, titleVisibility: .visible) {
            let n = model.highestQualityTargets.count
            Button("Redraw \(n) picture\(n == 1 ? "" : "s") (≈ \(OpenRouter.formatUSD(Double(n) * PictureQuality.enhanceEstimate)))") { model.makeHighestQuality(model.highestQualityTargets) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each picture is redrawn from itself at the highest quality (finer detail, crisper edges, the same composition), then sharpened on your Mac. The earlier versions stay, so you can go back to any of them." + (model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? ""))
        }
        .confirmationDialog("Make a video clip for every picture?", isPresented: $confirmAllClips, titleVisibility: .visible) {
            Button("Make \(model.clipTargets.count) clip\(model.clipTargets.count == 1 ? "" : "s") (≈ \(OpenRouter.formatUSD(model.allClipsPriceUSD)))") { model.startAllClips() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One clip (5–15 s) for each of \(model.clipTargets.count) picture\(model.clipTargets.count == 1 ? "" : "s") that have none, at HeyGen's list price of \(OpenRouter.formatUSD(model.videoPricePerSecond)) per second — about \(OpenRouter.formatUSD(model.allClipsPriceUSD)) in total (half while their promotion runs)." + (model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? "") + " Each clip plays once, then the camera moves over its last picture. Pictures that already have clips are skipped.")
        }
        .task { model.refreshVideoPrice() }
    }

    func makeAllButton(short: Bool) -> some View {
        Button { if model.hasOpenRouterKey { confirmAllPictures = true } else { model.generateAllMissingImages() } } label: {
            Label(model.missing.isEmpty ? (short ? "All ready" : "All pictures are ready") : (short ? "Missing (\(model.missing.count))" : "Make all missing pictures (\(model.missing.count))"), systemImage: "wand.and.sparkles").lineLimit(1)
        }
        .buttonStyle(.borderedProminent).disabled(model.missing.isEmpty || model.busy)
        .help(model.hasOpenRouterKey ? "Draws a picture for every part that has none (about \(OpenRouter.formatUSD(model.missingImagesCostUSD)) in total). You see the price first, and can watch the progress and cancel at any time."
                                     : "Draws the pictures for you. First add your OpenRouter key (More ▸ Picture maker key).")
    }
    func clipsAllButton(short: Bool) -> some View {
        let clipCount = model.clipTargets.count
        return Button { confirmAllClips = true } label: {
            Label(clipCount == 0 ? (short ? "All have clips" : "Every picture has a video clip") : (short ? "Clips (\(clipCount))" : "Make video clips for all pictures (\(clipCount))"), systemImage: "film.stack").lineLimit(1)
        }
        .disabled(clipCount == 0 || model.busy || model.clipJob != nil)
        .help("Makes one HeyGen video clip for every picture that has none, one after another (about \(OpenRouter.formatUSD(model.allClipsPriceUSD)) in total at list price). You see the price first.")
    }
    var moreMenu: some View {
        Menu {
            Button("Make it all automatically (≈ \(OpenRouter.formatUSD(model.autoSongPrice)))") { model.autoDirect() }
                .help("One click: a director plans the whole video (the story, the style, a reference picture if one helps, every picture idea; your own ideas are kept), then every picture is drawn and the preview opens.")
            Button("Plan with the director (you approve the choices)…") { model.directorPlan() }
                .help("The director plans the video, then you see its choices (brightness, style, weather, time of day, quality, the picture to base it on, the cast) and approve or change them before anything is drawn.")
            if let t = plan.treatment { Button("The director's plan…") { model.notice = t } }
            if !model.highestQualityTargets.isEmpty {
                Button("Make every picture highest quality (\(model.highestQualityTargets.count), ≈ \(OpenRouter.formatUSD(Double(model.highestQualityTargets.count) * PictureQuality.enhanceEstimate)))…") { confirmHighest = true }
                    .help("Redraws every picture at the highest quality (finer detail, sharper), keeping each one's composition. The earlier versions stay.")
            }
            Divider()
            Button("Setting & description…") { showDescriptionSheet = true }
            Button("Art style…") { showStyleSheet = true }
            Button(model.hasOpenRouterKey ? "Picture maker key & credit…" : "Add picture maker key…") { model.showOpenRouterKeySheet = true }
            Divider()
            if plan.shorts.isEmpty { Button("Make Shorts automatically") { model.autoMakeShorts() } }
            Button("Copy all picture ideas") { model.copyAllPrompts() }
            Divider()
            Button("YouTube thumbnail & description") { model.makeYouTubeFilesNow() }
                .help("Makes the YouTube thumbnail (the title card picture with the song title) and a search-friendly title, description with the lyrics, tags and hashtags. They are also made with the video.")
        } label: { Label("More", systemImage: "ellipsis.circle") }
        .menuIndicator(.hidden).fixedSize()
        .help("Setting & description, art style, the picture maker key and credit, making Shorts automatically, and copying all picture ideas.")
    }
    var nextStepLine: some View {
        let text: String, icon: String, tint: Color
        if model.missing.isEmpty { text = "All \(model.totalImages) pictures are ready — press Preview, then “Make my video”."; icon = "checkmark.seal.fill"; tint = .green }
        else if model.hasOpenRouterKey { text = "\(model.loadedCount) of \(model.totalImages) pictures ready — make the rest, or drag in your own."; icon = "photo.on.rectangle"; tint = .secondary }
        else { text = "\(model.loadedCount) of \(model.totalImages) pictures ready — drag in your own pictures, or add a picture maker key (More)."; icon = "photo.on.rectangle"; tint = .secondary }
        return Label(text, systemImage: icon).font(.callout).foregroundStyle(tint).lineLimit(1).fixedSize()
    }

    /// One plain sentence about what to do next, always visible above the pictures.
    var nextStepCard: some View {
        Group {
            if model.missing.isEmpty {
                NextStepCard(icon: "checkmark.seal.fill", title: "All \(model.totalImages) pictures are ready",
                             detail: "Press Preview to watch it, then “Make my video” at the bottom right.", tint: .green)
            } else if model.hasOpenRouterKey {
                NextStepCard(icon: "photo.on.rectangle", title: "\(model.loadedCount) of \(model.totalImages) pictures ready",
                             detail: "Press “Make all missing pictures” to have the app draw the rest, or click a part in the list and drag in your own picture.")
            } else {
                NextStepCard(icon: "photo.on.rectangle", title: "\(model.loadedCount) of \(model.totalImages) pictures ready",
                             detail: "Click a part in the list on the left, then drag in a picture you made. To have the app draw them for you, add a picture maker key.")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: sidebar
    var sidebar: some View {
        List(selection: Binding(get: { model.selectedSection }, set: { model.selectedSection = $0 ?? -1 })) {
            SlotRow(number: 0, title: "Title card", subtitle: plan.title, time: "", cand: plan.intro.selectedCandidate, work: model.workDir!, repeatNote: nil).tag(-1)
            ForEach(plan.sections.indices, id: \.self) { i in
                let s = plan.sections[i]
                SlotRow(number: i + 1, title: s.lineIDs.isEmpty ? (i == 0 ? "Music before the words" : (i == plan.sections.count - 1 ? "Music after the words" : "Music break")) : "Picture \(i + 1)", subtitle: s.lineIDs.first.flatMap { plan.lines.indices.contains($0) ? plan.lines[$0].text : nil } ?? "♪",
                        time: timeString(s.start), cand: s.selectedCandidate, work: model.workDir!, repeatNote: s.repeatOf.map { "same lyrics as \($0 + 1)" }).tag(i)
                    .onDrag { NSItemProvider(object: "mv-picture:\(i)" as NSString) }
                    .onDrop(of: [UTType.text], isTargeted: Binding(get: { dropSection == i }, set: { dropSection = $0 ? i : nil })) { providers in
                        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                            guard let value = value as? String, value.hasPrefix("mv-picture:"), let source = Int(value.dropFirst(11)), source != i else { return }
                            Task { @MainActor in dropSection = nil; model.reassignPicture(from: source, to: i) }
                        }
                        return true
                    }
                    .overlay(alignment: .bottom) { if dropSection == i { Text(s.selectedCandidate == nil ? "Move here" : "Swap pictures").font(.callout.bold()).padding(5).background(.regularMaterial) } }
                    .help("Drag this picture onto another section to move it there or swap their artwork. Undo reverses the action.")
            }
        }.listStyle(.sidebar)
    }

    // MARK: detail
    func lineHead(_ lineIdx: Int, _ line: LyricLine) -> some View {
        HStack(spacing: 6) {
            Button { model.playRange(max(0, line.start - 0.15), line.end + 0.25) } label: { Image(systemName: "play.fill").font(.caption2) }
                .buttonStyle(.bordered).help("Listen to this line of the song.")
            Text(String(format: "%d:%04.1f", Int(line.start) / 60, line.start.truncatingRemainder(dividingBy: 60)))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            Text("♪ " + line.text).font(.body).lineLimit(1)
        }
    }
    func lineNudges(_ lineIdx: Int) -> some View {
        HStack(spacing: 2) {
            Button("−0.5s") { model.nudgeLine(lineIdx, delta: -0.5) }
            Button("−0.1s") { model.nudgeLine(lineIdx, delta: -0.1) }
            Button("+0.1s") { model.nudgeLine(lineIdx, delta: 0.1) }
            Button("+0.5s") { model.nudgeLine(lineIdx, delta: 0.5) }
        }
        .buttonStyle(.bordered).controlSize(.small).font(.caption.monospacedDigit()).fixedSize()
        .help("Moves just this line earlier (−) or later (+) in the video. 0.1 s is a tiny nudge; 0.5 s is half a second.")
    }

    @State private var detailSize = CGSize(width: 800, height: 600)
    /// Wide enough to put the words and the idea beside the picture (a full-screen window); otherwise everything is one column.
    var wideDetail: Bool { detailSize.width >= 1150 }

    var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader
                if wideDetail {
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 16) { wordsBox; repeatBox; ideaBox; pictureOptionsBox; moveMenu }.frame(width: detailSize.width * 0.38)
                        DropWell(section: selection, maxPictureHeight: detailSize.height * 0.62).disabled(model.workingSection == selection)
                    }
                } else {
                    wordsBox; repeatBox; ideaBox; pictureOptionsBox; moveMenu
                    DropWell(section: selection, maxPictureHeight: max(220, detailSize.height * 0.55)).disabled(model.workingSection == selection)
                }
            }.padding(24)
        }
        .background(GeometryReader { g in Color.clear.onAppear { detailSize = g.size }.onChange(of: g.size) { _, v in detailSize = v } })
    }

    /// The picture options, the same as the looping video's: the subject, the source image, what each picture keeps, the weather and time of day.
    var pictureOptionsBox: some View {
        let w = model.workDir
        let current = section.selectedCandidate?.fullFile
        return VStack(alignment: .leading, spacing: 8) {
            Label("Picture options (for every picture drawn)", systemImage: "slider.horizontal.3").font(.headline)
            ReferenceRows(reference: plan.source.flatMap { w?.appendingPathComponent($0) },
                          note: plan.source == nil ? "Optional: a picture or photo to base every picture on. Without one, each picture is based on the picture before it."
                                                   : "Pictures whose idea shows this place, building or subject are based on it (always redrawn, never copied); a picture whose idea is about something else is drawn from its own words.",
                          read: plan.source != nil ? plan.sourceNote.map { "Every picture idea uses: " + $0 } : nil,
                          useCurrent: current != nil && current != plan.source ? { model.useSectionAsSource(selection) } : nil,
                          choose: { model.chooseSongReference() }, find: { showSubjectSheet = true },
                          remove: plan.source != nil ? { model.clearSongSource() } : nil,
                          focus: Binding(get: { model.songFocus }, set: { v in model.editSong { $0.nextFocus = v }; if plan.source != nil, plan.sourceNoteFocus != v { model.readSourceIntoIdeas() } }),
                          weather: Binding(get: { plan.weather }, set: { v in model.editSong { $0.weather = v } }),
                          time: Binding(get: { plan.timeOfDay }, set: { v in model.editSong { $0.timeOfDay = v } }),
                       disabled: model.busy && model.directorRun?.waiting != true,
                          quality: Binding(get: { plan.pictureQuality }, set: { v in model.editSong { $0.pictureQuality = v } }),
                          brightness: Binding(get: { plan.brightness }, set: { v in model.editSong { $0.brightness = v } }),
                          shot: Binding(get: { plan.shot }, set: { v in model.editSong { $0.shot = v } }))
        }
        .padding(12).frame(maxWidth: 1000, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder var detailHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(selection < 0 ? "Title card" : (section.lineIDs.isEmpty ? (selection == 0 ? "Music before the words" : (selection == plan.sections.count - 1 ? "Music after the words" : "Music break")) : "Picture \(selection + 1)")).font(.title2.bold())
            Text(selection < 0 ? "opening slide" : "\(timeString(section.start))–\(timeString(section.end)) · \(Int(section.duration)) s")
                .foregroundStyle(.secondary)
            Spacer()
            if model.lyricsMismatch {
                Label("Only \(Int(plan.alignmentCoverage * 100))% of the lyrics were heard in this song. Is it the right MP3?", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                    .help("When the song is right, almost all the words are heard (over 90%). This low a match usually means the MP3 is a different song, or the lyrics belong to another song. The pictures and timing follow the lyrics, so check the song first.")
            }
        }

    }
    @ViewBuilder var wordsBox: some View {
        if !section.lineIDs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Words in this part").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("▶ plays a line. If a line shows too early or late, use the small − and + buttons.").font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(section.lineIDs.filter { plan.lines.indices.contains($0) }, id: \.self) { lineIdx in
                    let line = plan.lines[lineIdx]
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { lineHead(lineIdx, line); Spacer(minLength: 4); lineNudges(lineIdx) }
                        VStack(alignment: .leading, spacing: 4) { HStack(spacing: 6) { lineHead(lineIdx, line); Spacer(minLength: 0) }; HStack { Spacer().frame(width: 52); lineNudges(lineIdx) } }
                    }
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        }
    }
    @ViewBuilder var repeatBox: some View {
        if let r = section.repeatOf, plan.sections.indices.contains(r) {
            HStack {
                Label("Same lyrics as section \(r + 1)", systemImage: "arrow.triangle.2.circlepath").font(.callout)
                Spacer()
                Button("Reuse its picture") { model.reuse(section: selection, from: r) }.disabled(plan.sections[r].selectedCandidate == nil)
            }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(.blue.opacity(0.1)))
        }

    }
    @ViewBuilder var ideaBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text("Picture idea").font(.headline).help("A description of the picture for this part of the song. The app writes it from your lyrics. You can edit it."); Spacer()
                if model.workingSection == selection { ProgressView().controlSize(.small) }
                Button { model.rewritePrompt(section: selection) } label: { Label("Another idea", systemImage: "arrow.clockwise") }.disabled(model.busy)
                    .help("Has the AI write a different picture idea for this part.")
                Button { model.copy(model.fullPrompt(section: selection)) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                    .help("Copies this picture idea (with the art style) so you can paste it into another image maker.")
                Button {
                    model.generateImage(section: selection)
                } label: {
                    Label(
                        section.hasImage
                            ? "Try another picture (about \(OpenRouter.formatUSD(model.perImageCostUSD)))"
                            : "Make this picture (about \(OpenRouter.formatUSD(model.perImageCostUSD)))",
                        systemImage: section.hasImage ? "dice.fill" : "sparkles"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy)
                .help(section.hasImage ? "Draws a new picture for this part and replaces the current one. It costs a few cents." : "Draws a picture for this part from the idea above. It costs a few cents.")
            }
            HStack(spacing: 8) {
                Text("Picture idea").font(.headline).help("A description of the picture for this part of the song. The app writes it from your lyrics. You can edit it."); Spacer()
                if model.workingSection == selection { ProgressView().controlSize(.small) }
                Button { model.rewritePrompt(section: selection) } label: { Label("Another idea", systemImage: "arrow.clockwise") }.disabled(model.busy)
                    .help("Has the AI write a different picture idea for this part.")
                Button { model.copy(model.fullPrompt(section: selection)) } label: { Label("Copy", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                    .help("Copies this picture idea (with the art style) so you can paste it into another image maker.")
                Button {
                    model.generateImage(section: selection)
                } label: {
                    Label(
                        section.hasImage
                            ? "Try another picture (about \(OpenRouter.formatUSD(model.perImageCostUSD)))"
                            : "Make this picture (about \(OpenRouter.formatUSD(model.perImageCostUSD)))",
                        systemImage: section.hasImage ? "dice.fill" : "sparkles"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy)
                .help(section.hasImage ? "Draws a new picture for this part and replaces the current one. It costs a few cents." : "Draws a picture for this part from the idea above. It costs a few cents.")
            }.labelStyle(.iconOnly)
            }
            TextEditor(text: Binding(get: { section.prompt }, set: { model.setPrompt($0, section: selection) }))
                .font(.callout).scrollContentBackground(.hidden).padding(8).frame(minHeight: 86, maxHeight: 170)
                .disabled(model.workingSection == selection)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            if model.workingSection == selection {
                Label("The app is working on this picture right now, so it is locked until it is done. Everything else stays open.", systemImage: "lock.fill").font(.callout).foregroundStyle(.orange)
            } else {
                Text("The picture is drawn from this idea plus the art style, in widescreen with no text.").font(.callout).foregroundStyle(.tertiary)
            }
            if let n = section.logicNote, !n.isEmpty {
                Label("Story check changed this idea: \(n)", systemImage: "checkmark.seal").font(.callout).foregroundStyle(.blue).fixedSize(horizontal: false, vertical: true)
                    .help("The local AI checked that this picture follows the one before it, is physically possible and fits the song, and rewrote it. Edit the idea to keep your own words; edited ideas are never changed.")
            } else if section.promptManual {
                Label("Your own wording — the story check leaves it alone.", systemImage: "pencil").font(.callout).foregroundStyle(.secondary)
            }
            if section.focal.count >= 2 {
                Label("The camera moves from “\(section.focal[0])” to “\(section.focal[1])”", systemImage: "scope").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .help("Every picture idea has two focal points. The automatic camera travels from the first to the second, and a video clip animates the first moving toward the second.")
            }
        }

    }
    @ViewBuilder var moveMenu: some View {
        if selection >= 0, section.selectedCandidate != nil {
            Menu("Use in another section…") {
                ForEach(plan.sections.indices.filter { $0 != selection }, id: \.self) { destination in
                    Button("\(plan.sections[destination].selectedCandidate == nil ? "Move to" : "Swap with") picture \(destination + 1)") { model.reassignPicture(from: selection, to: destination) }
                        .help("Move into an empty section, or swap if it already has artwork. Undo reverses this action.")
                }
            }.help("Move this artwork to an empty section or swap it with another section's artwork.")
        }
    }

    // MARK: footer
    @State private var showMakeOptions = false

    var footer: some View {
        HStack(spacing: 12) {
            Button { model.openFullPreview() } label: { Label("Preview", systemImage: "play.rectangle") }.controlSize(.large).disabled(model.loadedCount == 0)
                .help(model.loadedCount == 0 ? "Add at least one picture first, then you can watch a preview." : "Watch the video before it is made. Nothing is saved or changed.")
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: Double(model.loadedCount), total: Double(max(1, model.totalImages))).frame(width: 110)
                Text("\(model.loadedCount) of \(model.totalImages) pictures").font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            .help("How many parts of the song have a picture. Parts without one get a plain colour background.")
            Spacer(minLength: 8)
            Button { showMakeOptions = true } label: {
                Label("\(model.quality == 2160 ? "4K" : "\(model.quality)p")\(model.autoRenderShorts ? " + Shorts" : "")", systemImage: "slider.horizontal.3")
            }
            .controlSize(.large)
            .help("Choose the picture sharpness and whether YouTube Shorts are made too.")
            .popover(isPresented: $showMakeOptions, arrowEdge: .top) { makeOptions.padding(18).frame(width: 330) }
            Button { model.missing.isEmpty ? model.render() : (confirmMissing = true) } label: {
                Label("Make my video", systemImage: "film").font(.headline).padding(.horizontal, 6).padding(.vertical, 3).fixedSize()
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command).disabled(model.busy || model.videoJob != nil)
            .help(model.autoRenderShorts ? "Creates the finished video and the YouTube Shorts. It takes a few minutes; you can watch the progress and cancel at any time."
                                         : "Creates the finished video file. It takes a few minutes; you can watch the progress and cancel at any time.")
        }
        .padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
    }

    var makeOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before you make it").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Picture sharpness").font(.subheadline.weight(.medium))
                Picker("", selection: $model.quality) { Text("720p").tag(720); Text("1080p HD").tag(1080); Text("1440p").tag(1440); Text("4K").tag(2160) }
                    .pickerStyle(.segmented).labelsHidden()
                    .help("1080p HD is right for YouTube. 4K is sharper but takes much longer and makes a bigger file.")
                Text("1080p HD is right for YouTube.").font(.callout).foregroundStyle(.secondary)
            }
            Toggle(isOn: $model.autoRenderShorts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also make YouTube Shorts").font(.subheadline.weight(.medium))
                    Text(plan.shorts.isEmpty ? "No Shorts yet: the app cuts your song into Shorts of about 30 seconds at natural breaks and makes them with the video." : "\(plan.shorts.count) Shorts, made with the video.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox).help("Also make the YouTube Shorts when the main video is made. You can change them on the Shorts page.")
            Button("Done") { showMakeOptions = false }.help("Close this window.").keyboardShortcut(.defaultAction).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = "Choose a folder of pictures named 00.png (title card), 01.png, 02.png …"
        if p.runModal() == .OK, let u = p.url { model.loadFolder(u) }
    }
}

/// Sheet for entering or updating the OpenRouter API key and checking remaining credits.
struct OpenRouterKeySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "key.radiowaves.forward.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenRouter Image Generation").font(.title3.bold())
                    Text("Model: \(OpenRouter.imageModel) · 16:9 · Medium quality")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenRouter API Key").font(.subheadline.weight(.medium))
                SecureField("sk-or-v1-…", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                Text("Stored locally in ~/Library/Application Support/MusicVideo/config.json (permissions 0600). Never shared anywhere except openrouter.ai.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated Cost").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("~\(OpenRouter.formatUSD(model.perImageCostUSD)) per image · ~\(OpenRouter.formatUSD(model.missingImagesCostUSD)) for \(model.missing.count) missing · ~\(OpenRouter.formatUSD(model.allImagesCostUSD)) for all \(model.totalImages)")
                        .font(.caption.monospacedDigit())
                }
                Spacer()
                if model.checkingCredits {
                    ProgressView().controlSize(.small)
                } else if let rem = model.openRouterCredits {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Credits Remaining").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("\(OpenRouter.formatCredits(rem)) (≈ \(Int(rem / max(0.01, model.perImageCostUSD))) images)")
                            .font(.callout.monospacedDigit().weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            if let err = model.openRouterCreditError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            if model.hasOpenRouterKey && model.totalImages > 0 {
                Button { dismiss(); model.requestRegenAll = true } label: { Label("Make every picture again (about \(OpenRouter.formatUSD(model.allImagesCostUSD)))", systemImage: "arrow.triangle.2.circlepath") }
                    .help("Throws away the current pictures and draws a new one for every part. You will be asked to confirm first.")
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Check Credits") {
                    model.saveOpenRouterKey(keyText)
                }
                .buttonStyle(.bordered)
                .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.checkingCredits)

                Button("Save Key") {
                    model.saveOpenRouterKey(keyText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            keyText = model.config.openRouterKey
            if model.hasOpenRouterKey {
                model.refreshOpenRouterCredits(silent: false)
            }
        }
    }
}

/// Big drop target / preview for the current section's picture, with interactive focal-point reticle and 9:16 Short crop preview.
struct DropWell: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    var maxPictureHeight: CGFloat = .infinity       // the picture never grows taller than this (it scales with the window)
    var pictureMaxWidth: CGFloat { maxPictureHeight.isFinite ? min(1000, maxPictureHeight * 16.0 / 9.0) : 1000 }
    @State private var targeted = false
    @State private var showShortCrop = true
    @State private var dragEnd: Bool?           // while dragging a camera dot: false = start dot, true = end dot
    var sec: PhotoSection {
        if section < 0 || !model.plan!.sections.indices.contains(section) { return model.plan!.intro }
        return model.plan!.sections[section]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) { dropHeader; dropHeader.labelStyle(.iconOnly) }
            dropWell
        }
    }

    var dropHeader: some View {
            HStack {
                Text("Picture for this part").font(.headline)
                Spacer()
                if let f = sec.selectedCandidate?.fullFile, let w = model.workDir {
                    Button { FullScreenPlayer.showImage(w.appendingPathComponent(f), title: "Picture") } label: { Label("View larger", systemImage: "plus.magnifyingglass") }
                        .help("See this picture full screen and zoom in on any part (Esc closes).")
                }
                if let c = sec.selectedCandidate, c.videoFile == nil, c.fullFile != nil {
                    if c.credit.hasPrefix("Highest quality") {
                        Label("Highest quality", systemImage: "sparkles").font(.callout).foregroundStyle(.green)
                            .help("This picture was redrawn at the highest quality and sharpened. The earlier version is still under the picture.")
                    } else {
                        Button { model.makeHighestQuality([section]) } label: { Label("Make highest quality", systemImage: "sparkles") }
                            .disabled(model.busy)
                            .help("Redraws this same picture at the picture maker's very highest level, above the High used for new pictures (about \(OpenRouter.formatUSD(PictureQuality.enhanceEstimate)), under a minute): finer detail, crisper edges and sharper textures, keeping the composition, the people and the colours. Then it is sharpened 4× on your Mac. The picture you have now stays as an earlier version.")
                    }
                }
                if sec.selectedCandidate != nil {
                    Button {
                        model.generateImage(section: section)
                    } label: {
                        Label("Try another picture", systemImage: "dice.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                    .help("Draws a new picture for this part and replaces this one (a few cents).")
                } else {
                    Button {
                        model.generateImage(section: section)
                    } label: {
                        Label("Make this picture for me", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                    .help("Draws a picture from the idea below (a few cents). Or drag your own picture into the box.")
                }
            }
    }

    var dropWell: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(16.0 / 9, contentMode: .fit).overlay { GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    if let c = sec.selectedCandidate, let t = c.thumbFile {
                        Thumb(file: model.workDir!.appendingPathComponent(t))
                            .frame(width: w, height: h)
                            .clipped()
                        if let cam = c.cameraPath {
                            cameraOverlay(cam, c, w, h)
                        } else if showShortCrop {
                            let fx = CGFloat(c.focusX)
                            let fy = CGFloat(c.focusY)
                            // 9:16 vertical crop box inside a 16:9 frame has width = h * (9/16)
                            let cropW = min(w, h * (9.0 / 16.0))
                            let cropCenterX = min(w - cropW / 2, max(cropW / 2, fx * w))
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: cropW, height: h - 6)
                                .position(x: cropCenterX, y: h / 2)
                                .shadow(color: .black.opacity(0.6), radius: 2)

                            // Focal point reticle (y is bottom-up in Vision, convert to top-down for SwiftUI display)
                            let dispX = fx * w
                            let dispY = (1.0 - fy) * h
                            ZStack {
                                Circle().fill(Color.black.opacity(0.45)).frame(width: 26, height: 26)
                                Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 22, height: 22)
                                Circle().fill(Color.orange).frame(width: 7, height: 7)
                            }
                            .position(x: dispX, y: dispY)
                            .help("Drag this dot to choose where the camera slowly drifts toward.")
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 34)).foregroundStyle(.secondary)
                            Text("Drag a picture or video clip here, or click to choose one").font(.headline)
                            Text("Widescreen pictures work best (1920 × 1080 or larger)").font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(width: w, height: h)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard let c = sec.selectedCandidate else { return }
                            let fx = Double(g.location.x / max(1, w)), fy = Double(g.location.y / max(1, h))
                            if let cam = c.cameraPath {                    // your own move: drag whichever dot (start or end) is closer
                                if dragEnd == nil {
                                    let ds = hypot(fx - cam.start.x, (fy - cam.start.y) * 0.56), de = hypot(fx - cam.end.x, (fy - cam.end.y) * 0.56)
                                    dragEnd = de < ds
                                }
                                model.moveCameraPoint(section: section, end: dragEnd ?? false, x: fx, y: fy)
                            } else {
                                model.setFocus(x: min(0.95, max(0.05, fx)), y: min(0.95, max(0.05, 1.0 - fy)), section: section)
                            }
                        }
                        .onEnded { _ in dragEnd = nil }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if sec.selectedCandidate == nil { choose() }
                    }
                )
            } }
            .frame(maxWidth: pictureMaxWidth)
            .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: sec.selectedCandidate == nil ? [6, 5] : [])).foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5)))
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }; model.load(u, section: section); return true
            } isTargeted: { targeted = $0 }
            if sec.candidates.count > 1 { EarlierVersions(section: section).frame(maxWidth: 1000, alignment: .leading) }
            if let c = sec.selectedCandidate {
                if c.videoFile == nil, c.fullFile != nil { ClipPanel(section: section).frame(maxWidth: 1000, alignment: .leading) }
                if c.videoFile != nil { VideoTrimView(section: section, candidate: c, partLength: sec.duration).frame(maxWidth: 1000, alignment: .leading) }
                cameraControls(c).frame(maxWidth: 640, alignment: .leading)
                if c.looksLikeSubject {
                    Label("This picture looks a lot like your subject photo (a similar pose or angle). To be safe, press “Try another picture”.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 640, alignment: .leading)
                }
                if let problem = c.checkNote {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("The picture check found: \(problem)").font(.callout).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if c.checkFix != nil {
                            Button { model.fixPicture(section) } label: { Label("Fix it (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "wand.and.rays") }
                                .buttonStyle(.borderedProminent).tint(.orange).disabled(model.busy)
                                .help("Redraws this picture changing only that (\(c.checkFix ?? "")), keeping everything else. The picture you have now stays as an earlier version.")
                        }
                    }
                    .padding(10).frame(maxWidth: 640, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }
                if c.looksLikePrevious(model.previousPictureFile(section: section)) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("This picture has almost the same framing as the picture before it. Keep it if you like it, or press “Try another picture” for a different view.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10).frame(maxWidth: 640, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                    .help("A free check compares where the light and dark areas and the edges sit in the two pictures. Nothing is redrawn automatically; you decide.")
                }
                HStack {
                    if let n = sec.selectedCandidate?.libraryName {
                        Button { model.showPicturesFolder(select: n) } label: { Label(n, systemImage: "photo.on.rectangle.angled").lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("This picture is also saved in your Pictures folder under this name. Click to show it in Finder.")
                    }
                    if model.styleGuideSection == section {
                        Label("Style guide for all pictures", systemImage: "paintpalette.fill").font(.callout).foregroundStyle(.tint)
                            .help("Every other picture is drawn to match the look of this one (it adds about half a cent per picture).")
                    } else {
                        Button { model.setStyleGuide(section) } label: { Label("Use as the style guide", systemImage: "paintpalette") }
                            .help("Pictures drawn from now on are matched to the look of this picture (about half a cent extra each). The title card is the guide unless you choose another.")
                    }
                    Spacer()
                    Button("Choose a different file…") { choose() }
                        .help("Replaces this picture with another file from your Mac.")
                    Button("Remove picture", role: .destructive) { model.removeImage(section: section) }
                        .help("Takes this picture away. That part of the video will show a plain colour until you add another.")
                }.frame(maxWidth: 640)
            }
        }
    }

    // MARK: camera move (Ken Burns): automatic, or your own start and end points
    func cameraOverlay(_ cam: CameraPath, _ c: ImageCandidate, _ w: CGFloat, _ h: CGFloat) -> some View {
        let iw = Double(max(1, c.width)), ih = Double(max(1, c.height))
        let z = cam.zooms(imageW: iw, imageH: ih, aspect: 16.0 / 9)
        let fs = cam.frame(imageW: iw, imageH: ih, aspect: 16.0 / 9, end: false), fe = cam.frame(imageW: iw, imageH: ih, aspect: 16.0 / 9, end: true)
        func center(_ p: CGPoint, _ f: CGSize) -> CGPoint {                 // keep the drawn frame inside the picture, as the renderer does
            CGPoint(x: min(max(p.x, f.width / 2), 1 - f.width / 2) * w, y: min(max(p.y, f.height / 2), 1 - f.height / 2) * h)
        }
        let s = center(cam.start, fs), e = center(cam.end, fe)
        _ = z
        return ZStack {
            Path { p in p.move(to: s); p.addLine(to: e) }.stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 5])).shadow(color: .black.opacity(0.7), radius: 2)
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.green, style: StrokeStyle(lineWidth: 2, dash: [6, 4])).frame(width: fs.width * w, height: fs.height * h).position(s).shadow(color: .black.opacity(0.6), radius: 2)
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.red, lineWidth: 2).frame(width: fe.width * w, height: fe.height * h).position(e).shadow(color: .black.opacity(0.6), radius: 2)
            dot("1", .green).position(CGPoint(x: cam.start.x * w, y: cam.start.y * h)).help("START. The camera begins here. Drag this dot.")
            dot("2", .red).position(CGPoint(x: cam.end.x * w, y: cam.end.y * h)).help("END. The camera slowly travels here. Drag this dot.")
        }
    }
    func dot(_ n: String, _ color: Color) -> some View {
        ZStack { Circle().fill(color).frame(width: 28, height: 28); Circle().strokeBorder(.white, lineWidth: 2).frame(width: 28, height: 28); Text(n).font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
            .shadow(color: .black.opacity(0.5), radius: 3)
    }

    @ViewBuilder func cameraControls(_ c: ImageCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if c.videoFile != nil || (model.plan.map { (section < 0 ? $0.intro : $0.sections[section]).useClips && !(section < 0 ? $0.intro : $0.sections[section]).clips.isEmpty } ?? false) {
                Text("A video clip is in use: the clip plays first, then the camera below moves over its last picture.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Text("Camera").font(.subheadline.weight(.semibold))
                Button { model.useAutomaticCamera(section: section) } label: { Label("Automatic", systemImage: "wand.and.stars").frame(minWidth: 110) }
                    .buttonStyle(.bordered).tint(c.cameraPath == nil ? .accentColor : nil)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.cameraPath == nil ? Color.accentColor : .clear, lineWidth: 2))
                    .help("The camera drifts slowly toward the most interesting part of the picture. You can still drag the orange dot to aim it.")
                Button { model.chooseCameraMove(section: section) } label: { Label("I choose the move", systemImage: "arrow.right.circle").frame(minWidth: 140) }
                    .buttonStyle(.bordered).tint(c.cameraPath != nil ? .accentColor : nil)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.cameraPath != nil ? Color.accentColor : .clear, lineWidth: 2))
                    .help("Choose where the camera starts and where it ends. Two dots appear on the picture: drag them.")
                if c.cameraPath == nil {
                    Toggle("Show the aim", isOn: $showShortCrop).toggleStyle(.checkbox).font(.callout)
                        .help("Shows the orange dot the camera moves toward, and the dashed box kept in the tall YouTube Shorts version.")
                    Button("Aim for me") { model.resetFocus(section: section) }
                        .help("Lets the app find the most interesting spot in the picture (such as a face) and aim the camera there.")
                }
            }
            if let cam = c.cameraPath {
                Text("Drag the green dot ① (where the camera starts) and the red dot ② (where it ends). The dashed green frame is what the viewer sees first, the red frame what they see last; the picture slowly glides between them.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach([(0, "Moves closer", "plus.magnifyingglass"), (1, "Stays level", "equal.circle"), (2, "Moves wider", "minus.magnifyingglass")], id: \.0) { z in
                        Button { model.setCameraZoom(section: section, zoom: z.0) } label: { Label(z.1, systemImage: z.2) }
                            .buttonStyle(.bordered).tint(cam.zoom == z.0 ? .accentColor : nil)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(cam.zoom == z.0 ? Color.accentColor : .clear, lineWidth: 2))
                            .help(z.0 == 0 ? "While it travels, the view also moves slowly closer to the picture." : (z.0 == 1 ? "The view slides across without zooming." : "While it travels, the view also moves slowly back, showing more of the picture."))
                    }
                    Button { model.swapCameraPoints(section: section) } label: { Label("Swap start and end", systemImage: "arrow.left.arrow.right") }
                        .help("Reverses the direction of travel.")
                }
            }
        }
    }

    func choose() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.image, .movie]; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { model.load(u, section: section) }
    }
}

struct SlotRow: View {
    let number: Int, title: String, subtitle: String, time: String
    let cand: ImageCandidate?
    let work: URL
    let repeatNote: String?
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Thumb(file: cand?.thumbFile.map { work.appendingPathComponent($0) })
                if cand == nil { Image(systemName: "plus").foregroundStyle(.tertiary) }
            }.frame(width: 72, height: 41).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(String(format: "%02d", number)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    Text(title).font(.callout.weight(.semibold)); Spacer()
                    if cand != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    Text(time).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Text(repeatNote.map { "↺ \($0)" } ?? subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.vertical, 2)
    }
}

struct Thumb: View {
    let file: URL?
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
        }
        .clipped()
        .task(id: file) { if let f = file { image = NSImage(contentsOf: f) } else { image = nil } }
    }
}


/// "Words a little early or late?" — one pair of buttons that shifts every caption of the song.
struct CaptionTimingBar: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Words look too early or late?", systemImage: "captions.bubble").font(.callout.weight(.medium))
            HStack(spacing: 8) {
                Button { model.nudgeCaptions(by: -0.05) } label: { Label("Sooner", systemImage: "backward.fill") }
                    .help("Makes every word appear a little earlier (a twentieth of a second per click). Use this if the words seem to arrive after the singer.")
                Button { model.nudgeCaptions(by: 0.05) } label: { Label("Later", systemImage: "forward.fill").labelStyle(TrailingIcon()) }
                    .help("Makes every word appear a little later. Use this if the words seem to arrive before the singer.")
                Button("Reset") { model.resetCaptionTiming() }.help("Goes back to the standard timing.")
            }
            Text("Now: words \(model.captionShiftText)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}


/// Every picture this part has had (each "Try another picture", your own files, artwork kept from a join), as small thumbnails.
/// Click one to use it again (free); ✕ throws that version away.
struct EarlierVersions: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    @State private var confirmDelete: Int?
    var sec: PhotoSection? { model.plan.flatMap { section < 0 ? $0.intro : ($0.sections.indices.contains(section) ? $0.sections[section] : nil) } }

    var body: some View {
        if let sec, let w = model.workDir {
            VStack(alignment: .leading, spacing: 4) {
                Text("Earlier versions (\(sec.candidates.count))").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(Array(sec.candidates.enumerated()), id: \.offset) { i, c in
                            ZStack(alignment: .topTrailing) {
                                Button { model.selectArtwork(i, section: section) } label: {
                                    Group {
                                        if let t = c.thumbFile ?? c.fullFile { Thumb(file: w.appendingPathComponent(t)) } else { Color.secondary.opacity(0.2) }
                                    }
                                    .frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(i == sec.selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: i == sec.selected ? 3 : 1))
                                    .overlay(alignment: .bottomLeading) { if c.videoFile != nil { Image(systemName: "film").font(.caption2).padding(3).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3)).foregroundStyle(.white).padding(3) } }
                                }
                                .buttonStyle(.plain)
                                .help(hoverText(c, work: w) + (i == sec.selected ? " — in use now." : " — click to use this one again (free)."))
                                if i != sec.selected {
                                    Button { confirmDelete = i } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .black.opacity(0.6)) }
                                        .buttonStyle(.plain).padding(2).help("Throw this version away (it is removed from this song; a copy stays in your Pictures folder).")
                                }
                            }
                        }
                    }.padding(.vertical, 2)
                }
            }
            .confirmationDialog("Throw this version away?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
                Button("Throw it away", role: .destructive) { if let i = confirmDelete { model.deleteArtwork(i, section: section) }; confirmDelete = nil }
                Button("Keep it", role: .cancel) { confirmDelete = nil }
            } message: { Text("It is removed from this song. A copy stays in your Pictures folder, and Undo brings it back.") }
        }
    }

    func hoverText(_ c: ImageCandidate, work: URL) -> String {
        var parts: [String] = []
        if let f = c.videoFile ?? c.fullFile, let d = (try? FileManager.default.attributesOfItem(atPath: work.appendingPathComponent(f).path))?[.modificationDate] as? Date {
            parts.append("Made " + d.formatted(date: .abbreviated, time: .shortened))
        }
        if c.provider == "OpenRouter", let r = c.credit.range(of: #"\(\$[0-9.]+\)"#, options: .regularExpression) { parts.append("cost " + c.credit[r].dropFirst().dropLast()) }
        else if c.provider == "Manual" || c.provider == "Video" { parts.append("your own file (\(c.credit))") }
        return parts.isEmpty ? (c.credit.isEmpty ? "Earlier version" : c.credit) : parts.joined(separator: ", ")
    }
}
