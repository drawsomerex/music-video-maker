// Looping video stages: 1 Music (design 3f), 2 Scenes (2g), 3 Shorts, 4 Export. Same shell and the same actions as a music video.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

/// Before the looping video exists: choose the songs and name it.
struct NewLoopStart: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var songs: [URL] = []
    @State private var title = ""
    @State private var targeted = false
    var song: URL? { songs.first }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ClassicalHeading(text: "Songs", note: songs.isEmpty ? nil : "\(songs.count) song\(songs.count == 1 ? "" : "s")")
                    Text("One song, or up to 100, over scenes that loop seamlessly, made into a 1 to 12 hour video for study or background music.")
                        .font(Classical.body(13)).foregroundStyle(Classical.neutral700)
                    Button {
                        let o = NSOpenPanel(); o.allowedContentTypes = [.audio]; o.allowsMultipleSelection = true
                        if o.runModal() == .OK { pick(o.urls) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: song == nil ? "music.note" : "waveform").font(.system(size: 24)).foregroundStyle(Classical.accent700)
                            Text(songs.count > 1 ? "\(songs.count) songs" : (song?.lastPathComponent ?? "Drag your song or songs here (any length, up to 100)")).font(Classical.body(14, weight: .semibold)).foregroundStyle(Classical.text).lineLimit(1).truncationMode(.middle)
                            Text(song == nil ? "or click to choose MP3, WAV or M4A files" : "Click to choose different songs (you can add more on the next screen)").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        .background(targeted ? Classical.accent100 : Classical.paper)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(targeted ? Classical.accent : Classical.neutral300))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .dropDestination(for: URL.self) { urls, _ in guard !urls.isEmpty else { return false }; pick(urls); return true } isTargeted: { targeted = $0 }
                    CField(label: "Name of this video", prompt: "e.g. Rainy Library", text: $title)
                    if !model.hasOpenRouterKey {
                        HStack(spacing: 10) {
                            Text("Drawing and the director need an OpenRouter key.").font(Classical.body(12)).foregroundStyle(Classical.accent800)
                            CLink(title: "Add my key…") { openSettings() }
                            Text("You can still drop in your own pictures.").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                        }
                    }
                }.frame(maxWidth: 640).padding(30).frame(maxWidth: .infinity)
            }
            CFooter {
                Text("saved in \((model.config.projectsRoot.path as NSString).abbreviatingWithTildeInPath)").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
            } right: {
                Button { if !songs.isEmpty { model.startLoopProject(songs: songs, title: title) } } label: { HStack(spacing: 6) { Text("Step by step"); Text("free").font(Classical.body(11)).foregroundStyle(Classical.neutral600) } }
                    .buttonStyle(.classical).disabled(song == nil).help("Creates a folder for this looping video and opens its stages one at a time.")
                Button { if !songs.isEmpty { model.startLoopProject(songs: songs, title: title, automatic: true) } } label: { Text("Direct it for me") }
                    .buttonStyle(.classicalPrimary).disabled(song == nil || !model.hasOpenRouterKey)
                    .help("A director plans the scenes and the style, you see the price, then the app draws the pictures, makes the loop clips and opens a preview.")
            }
        }
    }
    func pick(_ us: [URL]) {
        let audio = us.filter { ["mp3", "wav", "m4a", "aac", "aif", "aiff", "flac", "caf"].contains($0.pathExtension.lowercased()) }
        guard !audio.isEmpty else { return }
        songs = Array(audio.prefix(LoopVideo.maxTracks)); if title.isEmpty { title = audio[0].deletingPathExtension().lastPathComponent }
    }
}

/// Stage 1 · Music: the songs, how they play, how long the video is.
struct NewLoopMusicStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    var body: some View {
        VStack(spacing: 0) {
            LoopView(part: .music)
            CFooter {
                Text("saved in \((model.config.projectsRoot.path as NSString).abbreviatingWithTildeInPath)").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
            } right: {
                Button { nd.route = .pictures } label: { Text("Step by step") }.buttonStyle(.classical).help("Go on to the scenes.")
                Button { model.loopAutoAsk() } label: { HStack(spacing: 6) { Text("Direct it for me"); Text("≈ " + OpenRouter.formatUSD(model.loopAutoPrice)).font(Classical.body(11).monospacedDigit()) } }
                    .buttonStyle(.classicalPrimary).disabled(model.loopJob != nil || (model.loopProject?.tracks.isEmpty ?? true))
            }
        }
    }
}
