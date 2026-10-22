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
        .alert("Notice", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.notice ?? "") }
        .sheet(isPresented: $model.showOpenRouterKeySheet) { OpenRouterKeySheet().environmentObject(model) }
    }

    var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat.circle.fill").font(.system(size: 26)).foregroundStyle(.linearGradient(colors: [.teal, .blue, .purple], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 1) {
                Text("Looping long music video").font(.headline)
                Text(p.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
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
        card(1, "The music", p.tracks.count > 1 ? "\(p.tracks.count) songs, played whole in this order (drag to reorder). The video plays them until it reaches the length you choose; no song is ever cut off."
                                                 : "One song, or add more for a playlist (up to 100). Songs are always played whole; no song is ever cut off.") {
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
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("Drag to change the order.")
                    TextField("Song name", text: Binding(get: { t.title }, set: { v in model.editLoop { if $0.tracks.indices.contains(i) { $0.tracks[i].title = v } } }))
                        .textFieldStyle(.plain).help("The song's name: its title card, its chapter and the tracklist. It starts as the file name.")
                    if p.cards == .everySong {
                        Toggle("Card", isOn: Binding(get: { t.cardOn }, set: { v in model.editLoop { if $0.tracks.indices.contains(i) { $0.tracks[i].cardOn = v } } })).toggleStyle(.checkbox).font(.caption)
                            .help("Show this song's title card when it starts.")
                    }
                    Text(timeString(t.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let a = p.analysis[t.file], p.tracks.count > 1 {
                        Image(systemName: a.fadesOut ? "chart.line.downtrend.xyaxis" : "stop.fill").font(.caption2).foregroundStyle(.tertiary)
                            .help(a.fadesOut ? "Ends with a fade-out: in Automatic the next song starts during it." : "Ends on a clear stop: in Automatic a short pause follows.")
                    }
                    Button { model.loopRemoveSong(t.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                        .disabled(working || p.tracks.count <= 1).help(p.tracks.count <= 1 ? "A looping video needs at least one song." : "Remove this song from the video (its file stays in the project folder).")
                }
            }
            .onMove { from, to in model.editLoop { $0.tracks.move(fromOffsets: from, toOffset: to) } }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: min(320, CGFloat(max(1, p.tracks.count)) * 30 + 12))
    }

    var transitionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Between songs").font(.callout.weight(.semibold))
                Picker("", selection: Binding(get: { p.effectiveTransition }, set: { v in model.editLoop { $0.transition = v } })) {
                    ForEach(LoopTransition.allCases, id: \.self) { Text($0.name).tag($0) }
                }.labelsHidden().fixedSize()
                    .help("Seamless: a tight 3-second blend, no audible join. Automatic: like a careful album sequence — two songs are never loud at the same time; a quiet ending can sit under a quiet opening, with about a second of breath between the music of one song and the next. Crossfade: a DJ-style blend with a bass swap. Album gaps: a pause after every song.")
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
                pictureWell
                HStack(spacing: 8) {
                    Button { model.loopMakePicture() } label: { Label(p.picture == nil ? "Draw the picture from the scene (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))" : "Draw another picture (≈ \(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent).disabled(working || p.scene.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Draws a widescreen picture of the scene above with the picture maker (a few cents).")
                    Button { model.loopChoosePicture() } label: { Label("Use my own picture…", systemImage: "photo") }.disabled(working)
                        .help("Choose a picture from your Mac (or drag it onto the box). The loop clip starts from it.")
                }
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
            if let u = model.loopFile(p.picture) { Thumb(file: u).clipShape(RoundedRectangle(cornerRadius: 10)) }
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
                    Text("Standard 768p (≈ \(OpenRouter.formatUSD(LoopVideo.clipPrice(sharp: false, perSecond768: model.videoPricePerSecond))))").tag(false)
                    Text("Sharp 2K (≈ \(OpenRouter.formatUSD(LoopVideo.clipPrice(sharp: true, perSecond768: model.videoPricePerSecond))))").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 460)
                    .help("Sharp 2K gives real full-HD detail in the long video; Standard is upscaled from 768p. Prices are HeyGen's list prices (half while their promotion runs).")
                HStack(alignment: .top, spacing: 14) {
                    clipWell
                    VStack(alignment: .leading, spacing: 8) {
                        Button { confirmClip = true } label: { Label(p.clip == nil ? "Make the loop clip (≈ \(OpenRouter.formatUSD(model.loopClipPrice)))" : "Make another clip (≈ \(OpenRouter.formatUSD(model.loopClipPrice)))", systemImage: "film") }
                            .buttonStyle(.borderedProminent).disabled(working || p.picture == nil)
                            .help(p.picture == nil ? "Add or draw the picture first." : "Makes a 15-second clip from the picture. You see the price first.")
                        Button { model.loopChooseClip() } label: { Label("Use my own video clip…", systemImage: "film.stack") }.disabled(working)
                            .help("Loop a video from your Mac instead (or drag it onto the box). A still camera works best.")
                        if p.clip != nil {
                            Text("This is exactly how it repeats in the long video (shown without sound).").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let w = p.clipWarning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let c = p.clip, let u = model.loopFile(c) {
                    DisclosureGroup(isExpanded: $showTrim) {
                        VideoTrimView(fileURL: u, length: nil, start: p.trim.start, end: p.trim.end, heading: "The part that loops",
                                      subheading: "Only the part between the green and red markers repeats. Leave out anything you don't want (a jump, a flip, a moment that looks odd).") { s, e in model.loopSetTrim(start: s, end: e) }
                            .id(c).padding(.top, 6)
                    } label: { Label("Choose the part that loops", systemImage: "scissors").font(.callout.weight(.semibold)) }
                        .onAppear { if p.clipWarning != nil { showTrim = true } }
                }
                if p.clips.count > 1 {
                    HStack(spacing: 6) {
                        Text("Earlier clips:").font(.callout).foregroundStyle(.secondary)
                        ForEach(Array(p.clips.enumerated()), id: \.offset) { i, c in
                            Button("Clip \(i + 1)") { model.editLoop { $0.clip = c }; if let u = model.loopPreviewURL(for: c), !FileManager.default.fileExists(atPath: u.path) { model.loopMakePreview(c) } }
                                .buttonStyle(.bordered).tint(c == p.clip ? .accentColor : nil).disabled(working)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Make the 15-second loop clip?", isPresented: $confirmClip, titleVisibility: .visible) {
            Button("Make it (≈ \(OpenRouter.formatUSD(model.loopClipPrice)))") { model.loopMakeClip() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(p.sharpClip ? "Sharp 2K" : "Standard 768p") at HeyGen's list price." + (model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? "") + " It takes a few minutes; you can keep working.")
        }
    }
    var clipWell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(clipTargeted ? Color.accentColor.opacity(0.15) : Color.black.opacity(0.85))
            if let c = p.clip, let u = model.loopPreviewURL(for: c), FileManager.default.fileExists(atPath: u.path) { LoopingPlayer(url: u).clipShape(RoundedRectangle(cornerRadius: 10)) }
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
                let need = LoopVideo.estimatedBytes(seconds: model.loopPlan?.total ?? p.hours * 3600), out = model.loopOutputURL(p)
                let free = LoopVideo.freeBytes(at: out.deletingLastPathComponent())
                Text("1080p · about \(ByteCountFormatter.string(fromByteCount: need, countStyle: .file))" + (free.map { " · \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)) free on this disk" } ?? "") + ". Saved as “\(out.lastPathComponent)”.")
                    .font(.callout).foregroundStyle((free ?? .max) < need + 2_000_000_000 ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { model.loopRender() } label: { Label("Make the long video", systemImage: "film").font(.headline).padding(.horizontal, 6).padding(.vertical, 2) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(working || p.clip == nil || p.tracks.isEmpty)
                        .help(p.clip == nil ? "Make or add the loop clip first." : "Makes the long video. Only a minute of video is drawn; the rest is the same loop written again and again, so even 12 hours takes minutes, not hours. Progress shows in the strip at the top.")
                    if let o = p.output, FileManager.default.fileExists(atPath: o) {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: o)]) } label: { Label("Show the last video in Finder", systemImage: "folder") }
                    }
                }
                YouTubeFilesRow(files: p.thumbnail.flatMap { t in p.listing.map { (URL(fileURLWithPath: t), URL(fileURLWithPath: $0)) } }.flatMap { FileManager.default.fileExists(atPath: $0.0.path) ? $0 : nil },
                                busy: model.loopJob?.title.hasPrefix("Writing the YouTube") == true) { model.loopMakeYouTube() }
                    .disabled(working && model.loopJob?.title.hasPrefix("Writing the YouTube") != true)
            }
        }
    }

    /// The exact length, once the songs have been listened to.
    var lengthLine: some View {
        Group {
            if let plan = model.loopPlan {
                let rounds = plan.plays.count == 0 ? 0 : Double(plan.plays.count) / Double(max(1, p.tracks.count))
                Label("Your video will be \(LoopVideo.clock(plan.total)) long: " + (p.playOnce ? (p.tracks.count > 1 ? "\(p.tracks.count) songs, each played once." : "the song played once.")
                      : "\(plan.plays.count) song\(plan.plays.count == 1 ? "" : "s")" + (p.tracks.count > 1 && rounds > 1.05 ? String(format: ", the playlist plays %.1f times", rounds) : "") + "."), systemImage: "clock")
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
                }
            }
        }
    }

    func suggest() {
        ideasBusy = true
        Task { defer { ideasBusy = false }; do { ideas = try await model.loopSuggestScenes(avoid: ideas) } catch { model.errorMessage = error.localizedDescription } }
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
