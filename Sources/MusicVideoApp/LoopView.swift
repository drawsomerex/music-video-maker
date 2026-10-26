// Looping long music video: its own screen. One column of four steps (song, picture, loop clip, long video) that reads top to bottom
// in a small window and spreads out in full screen.
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import MVCore

/// Plays a short file over and over without a gap (the loop preview).
struct LoopingPlayer: NSViewRepresentable {
    let url: URL
    final class Box { var player: AVQueuePlayer?; var looper: AVPlayerLooper? }
    func makeCoordinator() -> Box { Box() }
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.controlsStyle = .none; v.videoGravity = .resizeAspect
        load(url, into: v, box: context.coordinator); return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if (context.coordinator.player?.currentItem?.asset as? AVURLAsset)?.url != url { load(url, into: v, box: context.coordinator) }
    }
    private func load(_ u: URL, into v: AVPlayerView, box: Box) {
        let item = AVPlayerItem(url: u), q = AVQueuePlayer()
        box.looper = AVPlayerLooper(player: q, templateItem: item); box.player = q
        q.isMuted = true; v.player = q; q.play()
    }
}

struct LoopView: View {
    @EnvironmentObject var model: AppModel
    @State private var ideas: [String] = []
    @State private var ideasBusy = false
    @State private var confirmClip = false
    @State private var customHours = 2.0
    @State private var pictureTargeted = false
    @State private var clipTargeted = false
    @State private var showTrim = false
    @State private var showSubject = false
    @State private var confirmAddScene = false

    var p: LoopProject { model.loopProject ?? LoopProject() }
    func bind<T>(_ k: WritableKeyPath<LoopProject, T>) -> Binding<T> { Binding(get: { p[keyPath: k] }, set: { v in model.editLoop { $0[keyPath: k] = v } }) }
    var working: Bool { model.loopJob != nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    // full screen: song and picture on the left, the loop and the long video on the right
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 18) { songCard; pictureCard }.frame(width: 760)
                        VStack(alignment: .leading, spacing: 18) { clipCard; longVideoCard }.frame(width: 760)
                    }
                    VStack(alignment: .leading, spacing: 18) { songCard; pictureCard; clipCard; longVideoCard }.frame(maxWidth: 980)
                }
                .padding(24).frame(maxWidth: .infinity)
            }
        }
        .task { model.refreshVideoPrice() }
        .onChange(of: model.loopAutoFinished) { _, v in if v { model.loopAutoFinished = false; model.loopPreview(.start) } }
        .alert("Notice", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.notice ?? "") }
        .sheet(isPresented: $model.showOpenRouterKeySheet) { OpenRouterKeySheet().environmentObject(model) }
        .sheet(isPresented: $showSubject) { FindPictureSheet(set: { model.loopSetReference($0) }) }
        .sheet(isPresented: Binding(get: { model.loopSample != nil }, set: { if !$0 { model.loopSample = nil } })) {
            VStack(spacing: 12) {
                HStack {
                    Text("Preview").font(.headline); Spacer()
                    if let u = model.loopSample {
                        Button { let t = p.title; model.loopSample = nil; FullScreenPlayer.show(u, title: "Preview – \(t)", loop: false, muted: false) } label: { Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                            .help("Watch this preview full screen, with sound, and zoom in on any part (Esc closes).")
                    }
                    Button("Done") { model.loopSample = nil }.keyboardShortcut(.defaultAction)
                }
                if let u = model.loopSample { ClipPlayer(url: u, autoplay: true).frame(minWidth: 640, minHeight: 360) }
                Text("A short part of the long video, exactly as it will be, with sound.").font(.callout).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 680, idealWidth: 900)
        }
    }

    var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat.circle.fill").font(.system(size: 26)).foregroundStyle(.linearGradient(colors: [.teal, .blue, .purple], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 1) {
                Text("Looping long music video").font(.headline)
                Text(p.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.loopDirectorPlan() } label: { Label("Plan with the director…", systemImage: "person.crop.rectangle.stack") }
                .disabled(working || p.tracks.isEmpty)
                .help("The director plans the scenes, then you see its choices (brightness, style, weather, time of day, quality, the picture to base it on, how many scenes) and approve or change them before anything is made.")
            Button { model.loopAutoAsk() } label: { Label("Make it all automatically (≈ \(OpenRouter.formatUSD(model.loopAutoPrice)))", systemImage: "wand.and.stars") }
                .buttonStyle(.borderedProminent).disabled(working || p.tracks.isEmpty)
                .help("One click: a director plans \(model.loopAutoScenes) scene\(model.loopAutoScenes == 1 ? "" : "s") and the style (and finds a reference photo if it helps), then the app draws the pictures, makes the loop clips and opens a preview.")
            Text("Spent: \(OpenRouter.formatUSD(p.imagesUSD + p.videoUSD))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .help("Picture \(OpenRouter.formatUSD(p.imagesUSD)) and loop clip \(OpenRouter.formatUSD(p.videoUSD)) for this looping video (the cost OpenRouter reported).")
            Button { if let d = model.loopDir { NSWorkspace.shared.activateFileViewerSelecting([d]) } } label: { Label("Show folder", systemImage: "folder") }.labelStyle(.iconOnly)
                .help("Opens this looping video's folder in Finder: the song, pictures, clips and previews.")
            Button { model.showProjects = true } label: { Label("Projects", systemImage: "square.grid.2x2") }.labelStyle(.iconOnly).help("All your projects (Command-O).")
            HelpButton(screen: "Looping long music video")
            Button { model.closeLoop() } label: { Label("Close", systemImage: "xmark.circle") }
                .help("Closes this looping video and returns to the start. Everything is saved; open it again from “Projects” (Command-O).")
        }
        .padding(.horizontal, 20).padding(.vertical, 8).background(.regularMaterial)
    }

    func card<C: View>(_ n: Int, _ title: String, _ subtitle: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(n)").font(.headline.monospacedDigit()).foregroundStyle(.white).frame(width: 24, height: 24).background(Circle().fill(Color.accentColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.bold())
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
    }

    // MARK: 1 song
    var songCard: some View {
        card(1, "The music", p.tracks.count > 1 ? "\(p.tracks.count) songs, in this order (drag to reorder; click a name to rename it). The video plays them until it reaches the length you choose. “Repeat” plays a song several times, or for a set time, before the next."
                                                 : "One song, or add more for a playlist (up to 100). Click the name to rename it; “Repeat” plays it several times, or for a set time, before the playlist goes on.") {
            VStack(alignment: .leading, spacing: 10) {
                trackList
                HStack(spacing: 8) {
                    Button { model.loopAddSongs() } label: { Label("Add songs…", systemImage: "plus") }.disabled(working || p.tracks.count >= LoopVideo.maxTracks)
                        .help("Add one or more songs (MP3, WAV, M4A…). You can also drag files onto the list.")
                    Spacer()
                    Text("\(p.tracks.count) song\(p.tracks.count == 1 ? "" : "s") · \(timeString(p.tracks.reduce(0) { $0 + $1.seconds }))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                TextField("About the music (optional), e.g. Gentle acoustic guitar for rainy afternoons of reading", text: bind(\.about), axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder)
                    .help("Your own words about the music: its mood, style and what it is for. “Suggest scenes” and the YouTube description follow them.")
                Divider()
                transitionControls
                Divider()
                cardControls
                titleField
            }
        }
        .dropDestination(for: URL.self) { urls, _ in let a = urls.filter { ["mp3", "wav", "m4a", "aac", "aif", "aiff", "flac", "caf"].contains($0.pathExtension.lowercased()) }; guard !a.isEmpty else { return false }; model.loopAddSongs(a); return true }
    }

    var trackList: some View {
        List {
            ForEach(Array(p.tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(index: i, track: t, project: p, working: working)
            }
            .onMove { from, to in model.editLoop { $0.tracks.move(fromOffsets: from, toOffset: to) } }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: min(360, CGFloat(max(1, p.tracks.count)) * 34 + 12))
    }

    var transitionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Between songs").font(.callout.weight(.semibold))
                Picker("", selection: Binding(get: { p.effectiveTransition }, set: { v in model.editLoop { $0.transition = v } })) {
                    ForEach(LoopTransition.allCases, id: \.self) { Text($0.name).tag($0) }
                }.labelsHidden().fixedSize()
                    .help("Back to back (the usual for several songs): every song plays in full, untouched, and the next one starts the moment it ends — you hear all of every song. Seamless: a 3-second blend (the usual for one song, so its end flows into its start). Crossfade: the end of one song blends into the start of the next over the seconds you choose. Album gaps: a pause after every song.")
                if p.effectiveTransition == .crossfade {
                    Slider(value: Binding(get: { p.crossfade }, set: { v in model.editLoop { $0.crossfade = v } }), in: 2...12, step: 0.5).frame(maxWidth: 200)
                    Text(String(format: "%.1f s", p.crossfade)).font(.caption.monospacedDigit())
                }
                if p.effectiveTransition == .albumGaps {
                    Slider(value: Binding(get: { p.gap }, set: { v in model.editLoop { $0.gap = v } }), in: 0.5...5, step: 0.5).frame(maxWidth: 200)
                    Text(String(format: "%.1f s", p.gap)).font(.caption.monospacedDigit())
                }
                if p.transition == nil { Text("(the usual for \(p.tracks.count > 1 ? "several songs" : "one song"))").font(.caption).foregroundStyle(.secondary) }
            }
            if p.tracks.count > 1 {
                HStack(spacing: 16) {
                    Toggle("Even out the volume between songs", isOn: Binding(get: { p.effectiveEvenVolume }, set: { v in model.editLoop { $0.evenVolume = v } })).toggleStyle(.checkbox)
                        .help("Each song is measured and raised or lowered as a whole to the same loudness (YouTube's reference level); the music inside is not changed. A safety limiter stops a raised song from clipping.")
                    if !p.playOnce {
                        Toggle("Shuffle each time the playlist repeats", isOn: bind(\.shuffle)).toggleStyle(.checkbox)
                            .help("The first time through plays in your order; every time after that is shuffled (never the same song twice in a row).")
                    }
                }
            }
        }
    }

    var cardControls: some View {
        HStack(spacing: 10) {
            Text("Title cards").font(.callout.weight(.semibold))
            Picker("", selection: bind(\.cards)) {
                ForEach(LoopCards.allCases, id: \.self) { c in Text(c == .everySong && p.tracks.count == 1 ? "Song too" : c.name).tag(c) }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
                .help("None: just the scene. Only at the beginning: the video's title fades into the scene. Every song: the video's title, then each song's name as it starts (the first one after the title has faded). Cards are drawn on top; the loop underneath never changes.")
            if p.cards != .none {
                TextField(p.title.isEmpty ? "Video title" : p.title, text: bind(\.screenTitle)).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    .help("The title on the opening card. Empty = the video's name.")
            }
        }
    }
    var titleField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Name of this video").font(.callout.weight(.semibold))
            TextField("e.g. Rainy Library", text: bind(\.title)).textFieldStyle(.roundedBorder).help("Names the files, the YouTube title and the opening card (unless you type another title for the card).")
        }
    }
    var screenTitleField: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Title on the opening screen").font(.callout.weight(.semibold))
            TextField(p.title.isEmpty ? "The song title" : p.title, text: bind(\.screenTitle)).textFieldStyle(.roundedBorder)
                .help("Shown large at the very start of the video, then it fades into the loop. Leave it empty to use the song title.")
        }
    }

    // MARK: 2 picture
    var pictureCard: some View {
        card(2, "The picture", "The loop clip starts from this picture. Use your own, or describe a scene and let the app draw it.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Scene").font(.callout.weight(.semibold))
                    Spacer()
                    Menu {
                        if ideas.isEmpty { Text(ideasBusy ? "Thinking of scenes…" : "Press “Suggest scenes” first") }
                        ForEach(ideas, id: \.self) { i in Button(i) { model.editLoop { $0.scene = i } } }
                    } label: { Label("Ideas (\(ideas.count))", systemImage: "list.bullet") }.fixedSize().disabled(ideas.isEmpty)
                    Button { suggest() } label: { Label(ideasBusy ? "Thinking…" : "Suggest scenes", systemImage: "lightbulb") }.disabled(ideasBusy)
                        .help("The app suggests 10 calm scenes that loop well (written on this Mac, free).")
                }
                TextEditor(text: bind(\.scene)).font(.callout).frame(minHeight: 54, maxHeight: 90).scrollContentBackground(.hidden).padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7))).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                HStack(spacing: 8) {
                    Text("Look").font(.callout.weight(.semibold))
                    TextField("optional, e.g. soft watercolor", text: bind(\.style)).textFieldStyle(.roundedBorder)
                    Menu("Styles") { ForEach(StylePreset.all) { s in Button(s.name) { model.editLoop { $0.style = s.prompt } } } }.fixedSize()
                }
                referenceRows
                Toggle("Cloudless sky (loops most cleanly)", isOn: bind(\.clearSky)).font(.callout)
                    .help("New pictures are drawn with a clear, cloudless sky. Clouds that move can't come back to where they started, so a clear sky gives the cleanest loop. Clouds still work: they just blend slowly at the join.")
                if let pic = p.picture, p.subjectClose[pic] != nil {
                    Label("This picture looks a lot like your subject photo (a similar pose or angle). To be safe, draw another.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                pictureWell
                if let pic = p.picture, let check = p.checks[pic], check.count == 2 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("The picture check found: \(check[0])").font(.callout).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { model.loopFixPicture() } label: { Label("Fix it (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "wand.and.rays") }
                            .buttonStyle(.borderedProminent).tint(.orange).disabled(working)
                            .help("Redraws this picture changing only that (\(check[1])), keeping everything else. The picture you have now stays in the list below.")
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }
                HStack(spacing: 8) {
                    Button { model.loopMakePicture() } label: { Label(p.picture == nil ? "Draw the picture from the scene (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))" : "Draw another picture (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).disabled(working || p.scene.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Draws a widescreen picture of the scene above with the picture maker (a few cents).")
                    Button { model.loopChoosePicture() } label: { Label("Use my own picture as it is…", systemImage: "photo") }.disabled(working)
                        .help("Uses a picture from your Mac exactly as it is (or drag it onto the box). The loop clip starts from it.")
                }
                if p.picture != nil { nextSceneButton }
                if p.pictures.count > 1 { thumbs(p.pictures, selected: p.picture) { n in model.editLoop { $0.picture = n }; model.loopDescribeMotion() } }
                if p.picture != nil {
                    HStack {
                        Text("What moves").font(.callout.weight(.semibold))
                        Spacer()
                        Button { model.loopDescribeMotion() } label: { Label("Describe it from the picture", systemImage: "eye") }.disabled(working || !model.hasOpenRouterKey)
                            .help("Looks at the picture and lists what should move in the clip (a fraction of a cent). Done automatically for every new picture.")
                    }
                    TextField("e.g. waves rolling onto the beach, foam washing up the sand, clouds drifting very slowly", text: bind(\.motion), axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        .help("Goes into the clip's instructions word for word. Anything else that would naturally move moves gently too; clouds and the sky always move very slowly so the loop's seam stays invisible.")
                }
            }
        }
    }
    var pictureWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(pictureTargeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
            if let u = model.loopFile(p.picture) {
                Thumb(file: u).clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle()).onTapGesture { FullScreenPlayer.showImage(u, title: "Picture") }
                    .help("Click to see the picture full screen and zoom in.")
                HStack(spacing: 8) {
                    if let pic = p.picture, p.enhanced.contains(pic) {
                        Label("Highest quality", systemImage: "sparkles").font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.65))).foregroundStyle(.green)
                            .help("This picture was redrawn at the highest quality and sharpened. The earlier version is in the list below.")
                    } else {
                        Button { model.loopHighestQuality() } label: {
                            Label("Make highest quality", systemImage: "sparkles").font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.65))).foregroundStyle(.white)
                        }.buttonStyle(.plain).disabled(working)
                        .help("Redraws this same picture at the picture maker's very highest level (about \(OpenRouter.formatUSD(PictureQuality.enhanceEstimate)), under a minute): finer detail, crisper edges and sharper textures, keeping the composition and colours. Then it is sharpened 4× on your Mac. The picture you have now stays in the list below.")
                    }
                    Button { FullScreenPlayer.showImage(u, title: "Picture") } label: {
                        Label("View larger", systemImage: "plus.magnifyingglass").font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.65))).foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Drag your own picture here, or draw one from the scene").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(16.0 / 9, contentMode: .fit).frame(maxWidth: 560)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: p.picture == nil ? [6, 5] : [])).foregroundStyle(.secondary.opacity(0.5)))
        .dropDestination(for: URL.self) { urls, _ in guard let u = urls.first else { return false }; model.loopUsePicture(u); return true } isTargeted: { pictureTargeted = $0 }
    }

    // MARK: 3 clip
    var clipCard: some View {
        card(3, "The loop clip", "15 seconds made by HeyGen from the picture: a still camera with gentle, repeating motion. Its end blends into its start, so it loops without a seam.") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Clip quality", selection: bind(\.sharpClip)) {
                    Text("Standard 768p → 1080p (≈ \(OpenRouter.formatUSD(LoopVideo.clipPrice(sharp: false, perSecond768: model.videoPricePerSecond))))").tag(false)
                    Text("Sharp 2K → 1080p (≈ \(OpenRouter.formatUSD(LoopVideo.clipPrice(sharp: true, perSecond768: model.videoPricePerSecond))))").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 540)
                    .help("HeyGen makes clips at 768p or 2K (it has no 1080p setting). Prices are HeyGen's list prices (half while their promotion runs).")
                Text("Either way the long video is 1080p. Standard is made at 768p and scaled up, so it's a little soft; Sharp is made at 2K and scaled down, so it has full 1080p detail.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 14) {
                    clipWell
                    VStack(alignment: .leading, spacing: 8) {
                        Button { confirmClip = true } label: { Label(p.clip == nil ? "Make the loop clip (≈ \(OpenRouter.formatUSD(model.loopClipPrice)))" : "Make another clip (≈ \(OpenRouter.formatUSD(model.loopClipPrice)))", systemImage: "film") }
                            .buttonStyle(.borderedProminent).disabled(working || p.picture == nil)
                            .help(p.picture == nil ? "Add or draw the picture first." : "Makes a 15-second clip from the picture. You see the price first.")
                        Button { model.loopChooseClip() } label: { Label("Use my own video clip…", systemImage: "film.stack") }.disabled(working)
                            .help("Loop a video from your Mac instead (or drag it onto the box). A still camera works best.")
                        if p.clip != nil {
                            Text("This is exactly how it repeats in the long video (shown without sound). Click it to watch full screen and zoom in.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let w = p.clipWarning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let c = p.clip {
                    HStack(spacing: 8) {
                        if let s = p.loopScores[c], s < 90 {
                            Label("Loop: " + LoopVideo.loopQuality(s) + slowNote(p.loopDrift[c]), systemImage: s <= 3 ? "checkmark.seal" : "exclamationmark.triangle").font(.callout)
                                .foregroundStyle(s <= 3 ? Color.green : (s <= 5 ? Color.secondary : Color.orange)).fixedSize(horizontal: false, vertical: true)
                                .help("The app chose the stretch of the clip whose end matches its start most closely (in picture and motion), so the dissolve from the end back to the start joins two nearly identical moments. Parts that move one way and so can never match (like clouds sliding across) dissolve slowly over several seconds instead, and any slow change of brightness or colour is spread over the whole loop.")
                        }
                        Spacer()
                        Button { model.loopFindBestLoop() } label: { Label("Find the best loop", systemImage: "wand.and.stars") }.disabled(working)
                            .help("Searches the clip for the start and end that match most closely and moves the markers there (it is done automatically for every new clip).")
                    }
                }
                if let c = p.clip, let u = model.loopFile(c) {
                    DisclosureGroup(isExpanded: $showTrim) {
                        VideoTrimView(fileURL: u, length: nil, start: p.trim.start, end: p.trim.end, heading: "The part that loops",
                                      subheading: "Only the part between the green and red markers repeats. Leave out anything you don't want (a jump, a flip, a moment that looks odd).") { s, e in model.loopSetTrim(start: s, end: e) }
                            .id(c).padding(.top, 6)
                    } label: { Label("Choose the part that loops", systemImage: "scissors").font(.callout.weight(.semibold)) }
                        .onAppear { if p.clipWarning != nil { showTrim = true } }
                }
                if !p.clips.isEmpty { clipStrip }
            }
        }
        .confirmationDialog("Make the 15-second loop clip?", isPresented: $confirmClip, titleVisibility: .visible) {
            Button("Make it (≈ \(OpenRouter.formatUSD(model.loopClipPrice)))") { model.loopMakeClip() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(p.sharpClip ? "Sharp: made at 2K" : "Standard: made at 768p"), for a 1080p video, at HeyGen's list price." + (model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? "") + " It takes a few minutes; you can keep working.")
        }
    }
    /// The picture to base the pictures on (optional), what to keep from it, the weather and time of day: the same rows as a music video's.
    var referenceRows: some View {
        let focus = model.loopDir.map { LoopVideo.nextFocus(p, dir: $0) } ?? .place
        return ReferenceRows(reference: model.loopFile(p.source),
                             note: p.source == nil ? "Optional: a picture or photo to base the pictures on. Without one, the picture is drawn from the scene words, and each next scene is based on the picture shown."
                                                   : "The picture and every next scene are based on this picture (always redrawn, never copied).",
                             useCurrent: p.picture != nil && p.source != p.picture ? { model.editLoop { $0.source = $0.picture; $0.nextFocus = nil } } : nil,
                             choose: { model.loopChooseSource() }, find: { showSubject = true },
                             remove: p.source != nil ? { model.editLoop { $0.source = nil } } : nil,
                             focus: Binding(get: { focus }, set: { v in model.editLoop { $0.nextFocus = v } }), weather: bind(\.weather), time: bind(\.timeOfDay),
                             disabled: working && model.directorRun?.waiting != true, quality: bind(\.pictureQuality), brightness: bind(\.brightness), shot: bind(\.shot))
    }
    /// The next scene of a series: the same place, building or subject, something new.
    var nextSceneButton: some View {
        let focus = model.loopDir.map { LoopVideo.nextFocus(p, dir: $0) } ?? .place
        return Button { model.loopMakeNextPicture() } label: { Label(focus.action + " (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "arrow.forward.square") }
            .disabled(working || p.picture == nil)
            .help("Draws the next picture of the series from the picture it is based on: the same " + (focus == .subject ? "subject in a new place" : (focus == .building ? "building from a new view" : "place at a new moment")) + ". Make a clip from it to use it as another scene.")
    }

    /// More than one scene: which clips, and when the picture changes (a slow cross-fade).
    var scenesRow: some View {
        let have = LoopVideo.sceneClips(p).count
        let wanted = model.loopPlan.map { LoopVideo.scenesWanted(p, plan: $0) } ?? 1
        let changes = model.loopPlan.map { LoopVideo.sceneChangeTimes(p, plan: $0).count } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Change the scene").font(.callout.weight(.semibold))
                Picker("", selection: bind(\.sceneChange)) { ForEach(LoopSceneChange.allCases, id: \.self) { Text($0.name).tag($0) } }.labelsHidden().fixedSize()
                if p.sceneChange == .time || p.sceneChange == .both {
                    Stepper("every \(Int(p.sceneMinutes)) min", value: bind(\.sceneMinutes), in: 1...60, step: 1).fixedSize()
                }
                Spacer()
            }
            .help("The picture changes to another scene with a slow cross-fade: every few minutes, when one song ends and the next begins, or both. The music never changes because of it.")
            if p.sceneChange != .never && p.clip != nil {
                if have < wanted && changes > 0 {
                    // the reminder: the video changes scene, but there are not enough scenes yet
                    VStack(alignment: .leading, spacing: 8) {
                        Label(have <= 1 ? "This video changes scene \(changes) time\(changes == 1 ? "" : "s"), but it has only one scene, so it stays the same picture. Add another scene."
                                        : "This video changes scene \(changes) times and has \(have) scenes. \(wanted) would look best.", systemImage: "lightbulb.fill")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button { confirmAddScene = true } label: { Label("Add another scene (picture + clip, ≈ \(OpenRouter.formatUSD(model.loopAddScenePrice)))", systemImage: "plus.rectangle.on.rectangle").font(.headline) }
                            .buttonStyle(.borderedProminent).disabled(working)
                            .help("Draws the next picture (the same place, building or subject, something new), makes its clip, and adds it to the video. You see the price first.")
                    }
                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.14)))
                } else {
                    HStack(spacing: 10) {
                        Text(changes == 0 ? "No scene changes at this length." : "The scene changes \(changes) time\(changes == 1 ? "" : "s"), taking turns between \(have) scene\(have == 1 ? "" : "s").")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { confirmAddScene = true } label: { Label("Add another scene (≈ \(OpenRouter.formatUSD(model.loopAddScenePrice)))", systemImage: "plus.rectangle.on.rectangle") }.disabled(working)
                    }
                }
            }
        }
        .confirmationDialog("Add another scene?", isPresented: $confirmAddScene, titleVisibility: .visible) {
            Button("Add it (≈ \(OpenRouter.formatUSD(model.loopAddScenePrice)))") { model.loopAddScene() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app draws the next picture (about \(OpenRouter.formatUSD(model.perImageCostUSD))), then HeyGen makes its 15-second clip (about \(OpenRouter.formatUSD(model.loopClipPrice)) at list price). It takes a few minutes; you can keep working. The new scene joins the video automatically.")
        }
    }

    /// The clips as pictures: click one to look at it (and use it to start the video); the tick says whether it is one of the scenes in the video.
    var clipStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your scenes (click one to look at it)").font(.callout.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(Array(p.clips.enumerated()), id: \.offset) { i, c in
                        let shown = c == p.clip, inVideo = LoopVideo.sceneClips(p).contains(c)
                        VStack(spacing: 4) {
                            Button {
                                model.editLoop { $0.clip = c }
                                if let u = model.loopPreviewURL(for: c), !FileManager.default.fileExists(atPath: u.path) { model.loopMakePreview(c) }
                            } label: {
                                ZStack {
                                    Color.black
                                    if let d = model.loopDir, let t = LoopVideo.clipThumbnail(c, dir: d) { Thumb(file: t) }
                                }
                                .frame(width: 128, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(shown ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: shown ? 3 : 1))
                            }.buttonStyle(.plain).disabled(working)
                                .help(shown ? "Showing now. The video starts with this scene." : "Look at this scene (the video then starts with it).")
                            Toggle(isOn: Binding(get: { inVideo }, set: { v in model.editLoop { q in
                                guard c != q.clip else { return }                 // the scene shown always starts the video
                                var list = LoopVideo.sceneClips(q)
                                if v { if !list.contains(c) { list.append(c) } } else if list.count > 1 { list.removeAll { $0 == c } }
                                q.sceneClips = list
                            } })) { Text("Scene \(i + 1)").font(.caption) }
                                .toggleStyle(.checkbox).disabled(working || shown)
                                .help(shown ? "The scene shown is always in the video." : "Tick to use this scene in the video.")
                        }
                    }
                }.padding(.vertical, 2)
            }
        }
    }

    /// The part of the picture that dissolves slowly, in words.
    func slowNote(_ share: Double?) -> String {
        guard let s = share, s >= 0.03 else { return "" }
        return ". Parts that drift one way (about \(max(5, Int((s * 20).rounded()) * 5))% of the picture, such as clouds) blend slowly, so they never jump"
    }

    var clipWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(clipTargeted ? Color.accentColor.opacity(0.15) : Color.black.opacity(0.85))
            if let c = p.clip, let u = model.loopPreviewURL(for: c), FileManager.default.fileExists(atPath: u.path) {
                LoopingPlayer(url: u).clipShape(RoundedRectangle(cornerRadius: 10))
                Color.clear.contentShape(Rectangle()).onTapGesture { FullScreenPlayer.show(u, title: "The loop – \(p.title)", loop: true, muted: true) }
                    .help("Click to watch it full screen and zoom in on any part.")
                    .accessibilityElement().accessibilityLabel("The loop. Opens full screen.").accessibilityAddTraits(.isButton)
                Button { FullScreenPlayer.show(u, title: "The loop – \(p.title)", loop: true, muted: true) } label: {
                    Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right").font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.65))).foregroundStyle(.white)
                }.buttonStyle(.plain).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .help("Watch the loop full screen and zoom in on any part (Esc closes).")
            }
            else if p.clip != nil { VStack(spacing: 6) { ProgressView().controlSize(.small); Text("Preparing the preview…").font(.caption).foregroundStyle(.white.opacity(0.8)) } }
            else { Text("The loop appears here").font(.callout).foregroundStyle(.white.opacity(0.7)) }
        }
        .aspectRatio(16.0 / 9, contentMode: .fit).frame(maxWidth: 480)
        .dropDestination(for: URL.self) { urls, _ in guard let u = urls.first else { return false }; model.loopUseClip(u); return true } isTargeted: { clipTargeted = $0 }
    }

    // MARK: 4 long video
    var longVideoCard: some View {
        card(4, "The long video", "The scene with the music for at least as long as you choose: the song playing when that length is reached always finishes, then the picture fades to black. A YouTube thumbnail and a description written for search are made with it.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Length").font(.callout.weight(.semibold))
                    Picker("", selection: Binding(get: { p.playOnce ? -2 : ([1.0, 3, 8, 12].contains(p.hours) ? p.hours : -1) }, set: { v in
                        model.editLoop { q in
                            if v == -2 { q.playOnce = true } else { q.playOnce = false; q.hours = v > 0 ? v : customHours }
                        } })) {
                        Text(p.tracks.count > 1 ? "Each song once" : "The song once").tag(-2.0)
                        Text("1 hour").tag(1.0); Text("3 hours").tag(3.0); Text("8 hours").tag(8.0); Text("12 hours").tag(12.0); Text("Other").tag(-1.0)
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560)
                        .help("Each song once: the video is exactly as long as the album (or the one song), played through one time. The hours are a minimum: songs play whole, in order and again from the top, until that length is reached.")
                    if !p.playOnce && ![1.0, 3, 8, 12].contains(p.hours) {
                        Stepper(String(format: "%.1f h", p.hours), value: Binding(get: { p.hours }, set: { v in customHours = v; model.editLoop { $0.hours = v } }), in: 0.5...12, step: 0.5).fixedSize()
                    }
                }
                lengthLine
                scenesRow
                let need = LoopVideo.estimatedBytes(seconds: model.loopPlan?.total ?? p.hours * 3600), out = model.loopOutputURL(p)
                let free = LoopVideo.freeBytes(at: out.deletingLastPathComponent())
                Text("1080p · about \(ByteCountFormatter.string(fromByteCount: need, countStyle: .file))" + (free.map { " · \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)) free on this disk" } ?? "") + ". Saved as “\(out.lastPathComponent)”.")
                    .font(.callout).foregroundStyle((free ?? .max) < need + 2_000_000_000 ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Menu {
                        Button("The start (45 seconds)") { model.loopPreview(.start) }
                        if p.tracks.count > 1 { Button("A song change (40 seconds)") { model.loopPreview(.change) } }
                        Button("The end (40 seconds)") { model.loopPreview(.end) }
                    } label: { Label("Preview", systemImage: "play.rectangle") }
                        .fixedSize().disabled(working || p.clip == nil || p.tracks.isEmpty)
                        .help("Watch a short part of the long video with sound — the scene, the music, the joins between songs and the title cards — exactly as it will be. It takes a few seconds to make.")
                    Button { model.loopRender() } label: { Label("Make the long video", systemImage: "film").font(.headline).padding(.horizontal, 6).padding(.vertical, 2) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(working || p.clip == nil || p.tracks.isEmpty)
                        .help(p.clip == nil ? "Make or add the loop clip first." : "Makes the long video. Only a minute of video is drawn; the rest is the same loop written again and again, so even 12 hours takes minutes, not hours. Progress shows in the strip at the top.")
                    if let o = p.output, FileManager.default.fileExists(atPath: o) {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: o)]) } label: { Label("Show the last video in Finder", systemImage: "folder") }
                    }
                }
                HStack(spacing: 10) {
                    Button { model.loopMakeShorts() } label: { Label(p.tracks.count > 1 ? "Make Shorts (one per song, \(p.tracks.count))" : "Make a Short", systemImage: "rectangle.portrait.on.rectangle.portrait") }
                        .disabled(working || p.clip == nil || p.tracks.isEmpty)
                        .help("YouTube Shorts: for each song, its liveliest 45 seconds with the scene it plays over (upright, the scene in the middle over a soft blurred copy, the song's title above and the video's title below). A text file beside each has its YouTube title, description and tags. Free and made on this Mac.")
                    let shorts = model.loopShortsFolder(p)
                    if FileManager.default.fileExists(atPath: shorts.path) {
                        Button { NSWorkspace.shared.open(shorts) } label: { Label("Show the Shorts", systemImage: "folder") }
                    }
                }
                YouTubeFilesRow(files: p.thumbnail.flatMap { t in p.listing.map { (URL(fileURLWithPath: t), URL(fileURLWithPath: $0)) } }.flatMap { FileManager.default.fileExists(atPath: $0.0.path) ? $0 : nil },
                                busy: model.loopJob?.title.hasPrefix("Writing the YouTube") == true,
                                text: Binding(get: { p.thumbText }, set: { model.setLoopThumbText($0) }),
                                auto: { let a = LoopVideo.thumbAuto(p); return (a.title, a.badge, a.line) }(), revision: model.thumbRevision) { model.loopMakeYouTube() }
                    .disabled(working && model.loopJob?.title.hasPrefix("Writing the YouTube") != true)
            }
        }
    }

    /// The exact length, once the songs have been listened to.
    var lengthLine: some View {
        Group {
            if let plan = model.loopPlan {
                let turns = plan.turns.count
                let rounds = turns == 0 ? 0 : Double(turns) / Double(max(1, p.tracks.count))
                let repeating = p.tracks.contains { $0.repeatMode != .once }
                Label("Your video will be \(LoopVideo.clock(plan.total)) long: " + (p.playOnce ? (p.tracks.count > 1 ? "\(p.tracks.count) songs, each \(repeating ? "with its repeats" : "played once")." : (repeating ? "the song with its repeats." : "the song played once."))
                      : "\(turns) song\(turns == 1 ? "" : "s")" + (repeating ? " (with their repeats)" : "") + (p.tracks.count > 1 && rounds > 1.05 ? String(format: ", the playlist plays %.1f times", rounds) : "") + "."), systemImage: "clock")
                    .font(.callout.weight(.medium))
            } else if !p.tracks.isEmpty {
                Label(model.loopListening ?? "Listening to the songs to work out the exact length…", systemImage: "ear").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    func thumbs(_ files: [String], selected: String?, pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(files, id: \.self) { f in
                    Button { pick(f) } label: {
                        Group { if let u = model.loopFile(f) { Thumb(file: u) } else { Color.secondary.opacity(0.2) } }
                            .frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(f == selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: f == selected ? 3 : 1))
                    }.buttonStyle(.plain).help(f == selected ? "In use now." : "Use this picture again (free).")
                    .overlay(alignment: .bottomTrailing) {
                        if let u = model.loopFile(f) {
                            Button { FullScreenPlayer.showImage(u, title: "Picture") } label: { Image(systemName: "plus.magnifyingglass").font(.caption.weight(.bold)).padding(4).background(Circle().fill(.black.opacity(0.6))).foregroundStyle(.white) }
                                .buttonStyle(.plain).padding(3).help("See it larger")
                        }
                    }
                }
            }
        }
    }

    func suggest() {
        ideasBusy = true
        Task {
            defer { ideasBusy = false }
            do {
                ideas = try await model.loopSuggestScenes(avoid: ideas)
                // the first idea goes straight into the scene, unless you have written one yourself
                if let first = ideas.first, p.scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.editLoop { $0.scene = first } }
            } catch { model.errorMessage = error.localizedDescription }
        }
    }
}

/// The front page when "Looping long music video" is chosen: pick the song and a title, then start.
struct LoopStartView: View {
    @EnvironmentObject var model: AppModel
    @State private var songs: [URL] = []
    var song: URL? { songs.first }
    @State private var title = ""
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One song, one beautiful 15-second scene that loops seamlessly, made into a 1 to 12 hour video, for study or background music.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button {
                let o = NSOpenPanel(); o.allowedContentTypes = [.audio]; o.allowsMultipleSelection = true
                if o.runModal() == .OK { pick(o.urls) }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: song == nil ? "music.note" : "waveform.circle.fill").font(.system(size: 32)).foregroundStyle(song == nil ? .secondary : Color.accentColor)
                    Text(songs.count > 1 ? "\(songs.count) songs" : (song?.lastPathComponent ?? "Drag your song or songs here (any length, up to 100)")).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(song == nil ? "or click to choose MP3, WAV or M4A files" : "Click to choose different songs (you can add more on the next screen)").font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(.secondary.opacity(0.5)))
            }.buttonStyle(.plain)
            .dropDestination(for: URL.self) { urls, _ in guard !urls.isEmpty else { return false }; pick(urls); return true } isTargeted: { targeted = $0 }
            VStack(alignment: .leading, spacing: 3) {
                Text("Name of this video").font(.callout.weight(.semibold))
                TextField("e.g. Rainy Library", text: $title).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button { if !songs.isEmpty { model.startLoopProject(songs: songs, title: title, automatic: true) } } label: { Label("Do it all automatically", systemImage: "wand.and.stars").font(.headline).padding(.horizontal, 6).padding(.vertical, 3) }
                    .controlSize(.large).disabled(song == nil || !model.hasOpenRouterKey)
                    .help("Automatic mode: a director plans the scenes and the style, you see the price, then the app draws the pictures, makes the loop clips and opens a preview.")
                Button { if !songs.isEmpty { model.startLoopProject(songs: songs, title: title) } } label: { Label("Start the looping video", systemImage: "arrow.right.circle.fill").font(.headline).padding(.horizontal, 6).padding(.vertical, 3) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(song == nil)
                    .help("Creates a folder for this looping video and opens its screen: song, picture, loop clip, long video.")
            }
        }
        .frame(maxWidth: 620)
    }
    func pick(_ us: [URL]) {
        let audio = us.filter { ["mp3", "wav", "m4a", "aac", "aif", "aiff", "flac", "caf"].contains($0.pathExtension.lowercased()) }
        guard !audio.isEmpty else { return }
        songs = Array(audio.prefix(LoopVideo.maxTracks)); if title.isEmpty { title = audio[0].deletingPathExtension().lastPathComponent }
    }
}

/// One song in the looping video's list: its name (click to rename), how it repeats, its title card, its length.
struct TrackRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let track: LoopTrack
    let project: LoopProject
    let working: Bool
    @State private var renaming = false
    @State private var newName = ""

    func set(_ f: @escaping (inout LoopTrack) -> Void) {
        let id = track.id
        model.editLoop { p in if let k = p.tracks.firstIndex(where: { $0.id == id }) { f(&p.tracks[k]) } }
    }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("Drag to change the order.")
            Button { newName = track.title; renaming = true } label: {
                HStack(spacing: 5) {
                    Text(track.title.isEmpty ? "Untitled song" : track.title).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Click to rename this song (its title card, chapter and the tracklist).")
            .popover(isPresented: $renaming, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Song name").font(.headline)
                    TextField("Song name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 340).onSubmit { save() }
                    Text("Shown on its title card, in the chapters and the tracklist.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Use the file name") { newName = (track.file as NSString).deletingPathExtension.components(separatedBy: "/").last ?? newName }
                        Spacer()
                        Button("Cancel") { renaming = false }.keyboardShortcut(.cancelAction)
                        Button("Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    }
                }.padding(16)
            }
            Spacer(minLength: 6)
            repeatMenu
            if project.cards == .everySong {
                Toggle("Card", isOn: Binding(get: { track.cardOn }, set: { v in set { $0.cardOn = v } })).toggleStyle(.checkbox).font(.caption)
                    .help("Show this song's title card when it starts.")
            }
            Text(LoopTrackTime.string(track.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let a = project.analysis[track.file], project.tracks.count > 1 {
                Image(systemName: a.fadesOut ? "chart.line.downtrend.xyaxis" : "stop.fill").font(.caption2).foregroundStyle(.tertiary)
                    .help(a.fadesOut ? "Ends with a fade-out: in Automatic the next song starts during it." : "Ends on a clear stop: in Automatic a short pause follows.")
            }
            Button { model.loopRemoveSong(track.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                .disabled(working || project.tracks.count <= 1).help(project.tracks.count <= 1 ? "A looping video needs at least one song." : "Remove this song from the video (its file stays in the project folder).")
        }
        .padding(.vertical, 2)
    }
    func save() {
        let v = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { set { $0.title = v } }
        renaming = false
    }

    var repeatMenu: some View {
        Menu {
            Section("Play it") {
                choice(.once, "Once (no repeat)")
                ForEach([2, 3, 4, 5, 6, 8, 10], id: \.self) { n in choice(.times(n), "\(n) times in a row") }
            }
            Section("Repeat it for") {
                ForEach([5.0, 10, 15, 20, 30, 45, 60, 90, 120], id: \.self) { m in choice(.minutes(m), TrackRepeat.minutes(m).label) }
                choice(.scene, "As long as its scene (\(Int(project.sceneMinutes)) min)")
            }
            Divider()
            Button("Use “\(track.repeatMode.label)” for every song") { model.editLoop { p in for k in p.tracks.indices { p.tracks[k].repeatMode = track.repeatMode } } }
        } label: {
            Label(track.repeatMode == .once ? "Repeat" : "Repeat: \(track.repeatMode == .scene ? "scene (\(Int(project.sceneMinutes)) min)" : track.repeatMode.label)",
                  systemImage: track.repeatMode == .once ? "repeat" : "repeat.circle.fill")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Play this song several times in a row, or for a set time, before the next song (or before the playlist starts again). Repeats join its end to its start smoothly; a set time that ends in the middle of the song fades it out at a quiet moment and blends straight into what comes next.")
    }
    func choice(_ r: TrackRepeat, _ text: String) -> some View {
        Button { set { $0.repeatMode = r } } label: { if track.repeatMode == r { Label(text, systemImage: "checkmark") } else { Text(text) } }
    }
}

enum LoopTrackTime {
    static func string(_ s: Double) -> String { let t = Int(s.rounded()); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60) }
}
