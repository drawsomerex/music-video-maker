import SwiftUI
import AVKit
import UniformTypeIdentifiers
import MVCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            Backdrop()
            if model.needsNativeSetup { NativeSetupView().transition(.opacity) } else {
            switch model.stage {
            case .setup: SetupView().transition(.opacity)
            case .working, .rendering: ProgressStage().transition(.opacity)
            case .plan: PlanView().transition(.opacity)
            case .done: DoneView().transition(.opacity)
            }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.stage)
    }
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            LinearGradient(colors: [Color.indigo.opacity(0.22), Color.purple.opacity(0.10), Color.orange.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
    }
}

// MARK: Setup

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var importing = false
    @State private var targeted = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    dropZone
                    field("Song title", "e.g. First Strike on the Caney River", text: $model.title)
                    field("Subtitle on the title card (optional)", "e.g. A ballad of the Oklahoma oil boom", text: $model.subject)
                    Label("The AI reads your lyrics and writes the song description itself — it drives the picture prompts.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(width: 360)

                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Lyrics").font(.headline); Spacer()
                        Text("Blank line = new stanza · [Chorus] tags are used for pacing, never shown").font(.caption).foregroundStyle(.secondary) }
                    TextEditor(text: $model.lyrics)
                        .font(.system(size: 14, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
                        .overlay(alignment: .topLeading) {
                            if model.lyrics.isEmpty { Text("Paste your lyrics here.\nThe on-screen text is exactly what you paste; the transcription only supplies timing.").foregroundStyle(.tertiary).padding(18).allowsHitTesting(false) }
                        }
                }
            }
            .padding(28)

            Divider()
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Text("One picture about every").font(.callout)
                    Stepper(value: $model.imageInterval, in: 8...40, step: 1) { Text("\(Int(model.imageInterval)) s").monospacedDigit().frame(width: 44, alignment: .trailing) }
                    if model.estimatedImages > 0 { Text("≈ \(model.estimatedImages) pictures to make").font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                Menu {
                    Button("Open a project folder…") { model.chooseProject() }
                    if !model.recents.isEmpty { Divider(); ForEach(model.recents, id: \.self) { u in Button(u.deletingLastPathComponent().lastPathComponent) { model.openProject(u) } } }
                } label: { Label("Open Project", systemImage: "folder") }.menuStyle(.borderlessButton).fixedSize()
                Button { openSettings() } label: { Label("Local AI", systemImage: "cpu") }.buttonStyle(.bordered)
                Button { model.start() } label: {
                    Label("Plan the Video", systemImage: "sparkles")
                        .font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStart)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(.regularMaterial)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav]) { if case .success(let u) = $0 { model.setAudio(u) } }
    }

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack.fill").font(.system(size: 30)).foregroundStyle(.linearGradient(colors: [.orange, .pink, .purple], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading) { Text("Music Video Maker").font(.title2.bold()); Text("Plan → make your pictures → render").font(.subheadline).foregroundStyle(.secondary) }
        }
    }

    var dropZone: some View {
        Button { importing = true } label: {
            VStack(spacing: 8) {
                if let url = model.audioURL {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 34)).foregroundStyle(.tint)
                    Text(url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                    if model.audioDuration > 0 { Text(timeString(model.audioDuration)).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("Drop an MP3 or WAV here").font(.callout.weight(.medium))
                    Text("or click to choose").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120).padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: model.audioURL == nil ? [6, 5] : [])).foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first, ["mp3", "wav", "m4a", "aiff", "aif", "flac"].contains(u.pathExtension.lowercased()) else { return false }
            model.setAudio(u); return true
        } isTargeted: { targeted = $0 }
    }

    func field(_ label: String, _ prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium))
            TextField(prompt, text: text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3).controlSize(.large)
        }
    }
}

func timeString(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

// MARK: Progress

struct ProgressStage: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: model.stage == .rendering ? "film" : "waveform.and.magnifyingglass")
                .font(.system(size: 54)).symbolEffect(.pulse).foregroundStyle(.tint)
            Text(model.stage == .rendering ? "Rendering your video" : "Working on it").font(.title.bold())
            VStack(spacing: 8) {
                ProgressView(value: model.progress).progressViewStyle(.linear).frame(width: 420)
                Text(model.phase).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(model.stage == .rendering ? "Hardware-encoded on your Mac." : "Speech recognition and prompt writing run locally through oMLX.")
                .font(.caption).foregroundStyle(.tertiary)
        }.padding()
    }
}

// MARK: Done

struct DoneView: View {
    @EnvironmentObject var model: AppModel
    @State private var player: AVPlayer?
    var body: some View {
        VStack(spacing: 18) {
            Text("Your video is ready").font(.title.bold())
            if let p = player { PlayerView(player: p).aspectRatio(16.0 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(radius: 18, y: 8).frame(maxWidth: 860) }
            if let u = model.outputURL {
                Text(u.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 12) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([u]) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.borderedProminent).controlSize(.large)
                    ShareLink(item: u) { Label("Share", systemImage: "square.and.arrow.up") }.controlSize(.large)
                    Button { model.stage = .plan } label: { Label("Back to Pictures", systemImage: "photo.on.rectangle") }.controlSize(.large)
                    Button { model.reset() } label: { Label("New Video", systemImage: "plus") }.controlSize(.large)
                }
            }
        }
        .padding(28)
        .onAppear { if let u = model.outputURL { player = AVPlayer(url: u) } }
        .onDisappear { player?.pause() }
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var status = "Checking…"
    @State private var ids: [String] = []

    func modelPicker(_ title: String, _ binding: Binding<String>, _ fallback: String) -> some View {
        Picker(title, selection: binding) {
            Text("Default (\(fallback))").tag("")
            ForEach(ids, id: \.self) { Text($0).tag($0) }
        }
    }

    var body: some View {
        Form {
            Section("Where things are saved") {
                folderRow("Projects", model.config.projectsFolder, defaultText: "~/Movies/Music Videos") { model.config.projectsFolder = $0 }
                folderRow("Finished videos & Shorts", model.config.outputFolder, defaultText: "next to each project") { model.config.outputFolder = $0 }
                Text("A project folder holds the song, transcript, synced lyrics, pictures and the save file. Videos are written to the second folder if you choose one.").font(.caption).foregroundStyle(.secondary)
            }
            if model.isNativeBuild {
                Section("On-device AI") {
                    Text("Speech (Parakeet Ultra) and prompt writing run inside this app with Apple MLX — nothing else needs to be installed.").font(.callout)
                }
            } else {
            Section("Local AI — oMLX") {
                LabeledContent("Status") { Text(status).foregroundStyle(ids.isEmpty ? .orange : .green) }
                modelPicker("Speech (Parakeet)", $model.config.sttModel, OMLX.defaultSTT)
                modelPicker("Writes the image prompts", $model.config.llmModel, OMLX.defaultLLM)
                TextField("Server URL (blank = http://127.0.0.1:8000)", text: $model.config.omlxURL)
                SecureField("API key (blank = read from oMLX's own settings)", text: $model.config.omlxKey)
                Button("Re-check connection") { Task { await check() } }
            }
            }
        }
        .formStyle(.grouped).frame(width: 560, height: 470)
        .task { await check() }
        .onChange(of: model.config.omlxKey) { save() }.onChange(of: model.config.omlxURL) { save() }
        .onChange(of: model.config.sttModel) { save() }.onChange(of: model.config.llmModel) { save() }
    }
    func folderRow(_ title: String, _ value: String, defaultText: String, set: @escaping (String) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Text(value.isEmpty ? defaultText : (value as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle).foregroundStyle(value.isEmpty ? .secondary : .primary)
                Button("Choose…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                    p.prompt = "Use This Folder"
                    if p.runModal() == .OK, let u = p.url { set(u.path); save() }
                }.controlSize(.small)
                if !value.isEmpty { Button("Reset") { set(""); save() }.controlSize(.small) }
            }
        }
    }
    func save() { try? model.config.save() }
    func check() async {
        status = "Checking…"
        do { ids = try await OMLX(config: model.config).models().sorted(); status = "Connected — \(ids.count) models" }
        catch { ids = []; status = error.localizedDescription }
    }
}

/// AppKit player (SwiftUI's VideoPlayer crashes at launch of this screen in a SwiftPM-built app).
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.player = player; v.controlsStyle = .floating; v.showsFullScreenToggleButton = true; return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { if v.player !== player { v.player = player } }
}

/// First launch of the native build: pick a size, download once, then it all runs on this Mac.
struct NativeSetupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle").font(.system(size: 52)).foregroundStyle(.tint)
            Text("One-time setup").font(.largeTitle.bold())
            Text("Music Video Maker does its speech recognition and prompt writing on this Mac. Pick a size — it downloads once and then works offline.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            if model.settingUp {
                VStack(spacing: 8) {
                    ProgressView(value: model.setupProgress).frame(width: 380)
                    Text(model.setupPhase).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Picker("Size", selection: $model.nativeTier) {
                    Text("Small — about 1.5 GB total").tag("small")
                    Text("Balanced — about 2.8 GB total (recommended)").tag("balanced")
                    Text("Best — about 6.5 GB total").tag("best")
                }.pickerStyle(.radioGroup).labelsHidden()
                Text("Includes Parakeet Ultra for word-accurate lyric timing (0.5 GB) plus a language model for the prompts. Bigger models write better prompts.")
                    .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: 440).multilineTextAlignment(.center)
                Button { model.runNativeSetup() } label: { Label("Download & set up", systemImage: "arrow.down.to.line").padding(.horizontal, 10) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(40)
    }
}
