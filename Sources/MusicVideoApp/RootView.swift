// Main screens: setup, progress panel, finished video, Settings and first-run model setup.
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
        .overlay(alignment: .top) {
            if model.busy {
                BackgroundTaskBanner()
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.35), value: model.stage)
        .animation(.smooth(duration: 0.25), value: model.busy)
    }
}

/// Floating on-screen progress bar shown whenever any background operation is running.
struct BackgroundTaskBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let el = max(0, ctx.date.timeIntervalSince(model.busyStarted))
            let f = min(max(model.busyProgress, 0), 1)
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(model.busyPhase.isEmpty ? "Working in background…" : model.busyPhase)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(f * 100))% · \( Int(el) / 60 ):\( String(format: "%02d", Int(el) % 60) )")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: max(0.03, f))
                        .progressViewStyle(.linear)
                }
                .frame(width: 360)
                Button("Cancel") { model.cancelBackgroundTask() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
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
                VStack(alignment: .leading, spacing: 11) {
                    header
                    Picker("Audio Source", selection: $model.audioInputMode) {
                        Label("Drop MP3 / WAV", systemImage: "music.note").tag(0)
                        Label("Record Song Playing", systemImage: "waveform.badge.mic").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if model.audioInputMode == 0 {
                        dropZone
                    } else {
                        recordZone
                    }

                    if let trim = model.trimSummary {
                        Label(trim, systemImage: "scissors")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    field("Song title", "e.g. Highway Lights", text: $model.title)
                    field("Subtitle on the title card (optional)", "e.g. A ballad of the Oklahoma oil boom", text: $model.subject)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Picture style").font(.subheadline.weight(.medium))
                        Picker("Picture style", selection: $model.selectedStylePreset) {
                            ForEach(StylePreset.all) { preset in
                                Text(preset.name).tag(preset.name)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.regular)
                    }

                    Label("The AI reads your lyrics and writes the song description & prompts — plus 4–7 ~30s Shorts cut at stanza breaks.", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(width: 370)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Lyrics").font(.headline)
                        if model.liveTranscribing {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("Transcribing live…").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button {
                            model.pasteOverLyrics()
                        } label: {
                            Label("Paste Over Lyrics", systemImage: "doc.on.clipboard")
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .help("Replace the lyrics below with the contents of your clipboard")

                        if model.audioURL != nil && !model.isRecording {
                            Button {
                                model.transcribeLoadedAudio()
                            } label: {
                                Label("Auto-Transcribe", systemImage: "waveform.and.mic")
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(model.busy)
                            .help("Transcribe lyrics from the loaded audio file using Parakeet")

                            Button {
                                model.trimLoadedAudioSilence()
                            } label: {
                                Label("Trim Silence", systemImage: "scissors")
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                            .disabled(model.busy)
                            .help("Automatically cut off silence at the beginning and after the song ends")
                        }
                    }
                    Text("Blank line = new stanza · [Chorus] tags are used for pacing, never shown · Edit or paste over live-transcribed lyrics anytime")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $model.lyrics)
                        .font(.system(size: 14, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(model.isRecording ? Color.red.opacity(0.6) : Color.secondary.opacity(0.25)))
                        .overlay(alignment: .topLeading) {
                            if model.lyrics.isEmpty {
                                Text(model.audioInputMode == 1
                                     ? "Start recording a song — lyrics will appear here in real time as it plays.\nAfterwards, you can fix any words or click “Paste Over Lyrics” to paste the official lyrics."
                                     : "Paste your lyrics here.\nThe on-screen text is exactly what you paste; the transcription only supplies timing.")
                                    .foregroundStyle(.tertiary).padding(18).allowsHitTesting(false)
                            }
                        }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Text("One picture about every").font(.callout)
                    Stepper(value: $model.imageInterval, in: 8...40, step: 1) { Text("\(Int(model.imageInterval)) s").monospacedDigit().frame(width: 44, alignment: .trailing) }
                    if model.estimatedImages > 0 { Text("≈ \(model.estimatedImages) pictures to make").font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                Button { model.chooseSaveFolder() } label: {
                    Label("Saving to \((model.config.projectsRoot.path as NSString).abbreviatingWithTildeInPath)", systemImage: "externaldrive")
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: 260)
                }.buttonStyle(.bordered).help("Folder for all projects, pictures and finished videos. Click to change.")
                Menu {
                    Button("Open a project folder…") { model.chooseProject() }
                    if !model.recents.isEmpty { Divider(); ForEach(model.recents, id: \.self) { u in Button(u.deletingLastPathComponent().lastPathComponent) { model.openProject(u) } } }
                } label: { Label("Open Project", systemImage: "folder") }.menuStyle(.borderlessButton).fixedSize()
                Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }.buttonStyle(.bordered)
                Button { model.start() } label: {
                    Label("Plan the Video", systemImage: "sparkles")
                        .font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStart || model.isRecording)
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
            VStack(spacing: 6) {
                if let url = model.audioURL {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 32)).foregroundStyle(.tint)
                    Text(url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    if model.audioDuration > 0 { Text(timeString(model.audioDuration)).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Image(systemName: "music.note").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Drop an MP3 or WAV here").font(.callout.weight(.medium))
                    Text("or click to choose").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: model.audioURL == nil ? [6, 5] : [])).foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .clipped()
        .dropDestination(for: URL.self) { urls, _ in
            guard let u = urls.first, ["mp3", "wav", "m4a", "aiff", "aif", "flac"].contains(u.pathExtension.lowercased()) else { return false }
            model.setAudio(u); return true
        } isTargeted: { targeted = $0 }
    }

    var recordZone: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Source:").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Picker("Input", selection: $model.recordSource) {
                    ForEach(LiveSongRecorder.Source.allCases) { src in
                        Text(src.rawValue).tag(src)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(model.isRecording)
            }

            if model.isRecording {
                HStack(spacing: 8) {
                    Canvas { ctx, size in
                        let bars = 28
                        let step = size.width / CGFloat(bars)
                        let barW = max(2.0, step - 2.0)
                        let hist = model.recordingHistory
                        for i in 0..<bars {
                            let sampleIdx = hist.count - bars + i
                            let lvl = sampleIdx >= 0 && sampleIdx < hist.count ? CGFloat(hist[sampleIdx]) : 0.04
                            let h = max(3.0, min(size.height, lvl * size.height * 1.4))
                            let rect = CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: barW, height: h)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.red))
                        }
                    }
                    .frame(height: 22)
                    Text("\(timeString(model.recordingSeconds))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize()
                }
                Button {
                    model.stopRecording()
                } label: {
                    Label("Stop & Auto-Trim Silence", systemImage: "stop.circle.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
            } else {
                if let url = model.audioURL {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                        Text("\(url.lastPathComponent) (\(timeString(model.audioDuration)))")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("Play your song on your Mac and click Record. Silence at start & end is auto-trimmed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Button {
                    model.startRecording()
                } label: {
                    Label(model.audioURL == nil ? "Start Recording Song" : "Record Again", systemImage: "record.circle")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .clipped()
        .background(RoundedRectangle(cornerRadius: 16).fill(model.isRecording ? Color.red.opacity(0.08) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(model.isRecording ? Color.red.opacity(0.6) : Color.secondary.opacity(0.4), lineWidth: 1.5))
    }

    func field(_ label: String, _ prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.subheadline.weight(.medium))
            TextField(prompt, text: text).textFieldStyle(.roundedBorder).controlSize(.large)
        }
    }
}

func timeString(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

// MARK: Progress

struct ProgressStage: View {
    @EnvironmentObject var model: AppModel
    static let planSteps: [(String, Double)] = [("Listening to the song", 0), ("Syncing your lyrics", 0.55), ("Reading the lyrics", 0.62), ("Writing picture prompts", 0.75)]
    @State private var started = Date()

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: model.stage == .rendering ? "film" : "waveform.and.magnifyingglass")
                .font(.system(size: 54)).symbolEffect(.pulse).foregroundStyle(.tint)
            Text(model.stage == .rendering ? (model.autoRenderShorts ? "Rendering your video & Shorts" : "Rendering your video") : "Planning your video").font(.title.bold())
            ProgressPanel(fraction: model.progress, phase: model.phase, started: started,
                          steps: model.stage == .rendering ? [] : Self.planSteps.map { $0.0 },
                          currentStep: Self.planSteps.lastIndex { model.progress >= $0.1 } ?? 0)
            Text(model.stage == .rendering ? "Hardware-encoded on your Mac. You can leave this running." : "Speech recognition and prompt writing run on this Mac.")
                .font(.caption).foregroundStyle(.tertiary)
            Button("Cancel", role: .cancel) { model.cancelMainTask() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }.padding()
        .onAppear { started = Date() }
    }
}

/// Big, clear progress: percentage, bar, current task, optional step checklist, elapsed time and time left.
struct ProgressPanel: View {
    let fraction: Double
    let phase: String
    let started: Date
    var steps: [String] = []
    var currentStep = 0
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let el = ctx.date.timeIntervalSince(started)
            let f = min(max(fraction, 0), 1)
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(f * 100))%").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Elapsed \(clock(el))").monospacedDigit()
                        if f > 0.04 && f < 0.995 { Text("About \(clock(el / f * (1 - f))) left").monospacedDigit().foregroundStyle(.secondary) }
                    }.font(.callout)
                }
                ProgressView(value: f).progressViewStyle(.linear).scaleEffect(x: 1, y: 2.2, anchor: .center)
                Text(phase).font(.callout.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, name in
                            HStack(spacing: 8) {
                                Image(systemName: i < currentStep ? "checkmark.circle.fill" : (i == currentStep ? "circle.dotted" : "circle"))
                                    .foregroundStyle(i <= currentStep ? Color.accentColor : Color.secondary.opacity(0.5))
                                Text(name).foregroundStyle(i <= currentStep ? .primary : .secondary)
                            }.font(.callout)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 440)
    }
    func clock(_ s: Double) -> String { let n = Int(max(0, s)); return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60) : String(format: "%d:%02d", n / 60, n % 60) }
}

// MARK: Done

struct DoneView: View {
    @EnvironmentObject var model: AppModel
    @State private var player: AVPlayer?
    var body: some View {
        VStack(spacing: 16) {
            Text(model.renderedShorts.isEmpty ? "Your video is ready" : "Your video & \(model.renderedShorts.count) Shorts are ready").font(.title.bold())
            if let p = player { PlayerView(player: p).aspectRatio(16.0 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(radius: 18, y: 8).frame(maxWidth: 840) }
            if !model.renderedShorts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill").foregroundStyle(.tint)
                    Text("Also rendered \(model.renderedShorts.count) ~30s Shorts broken at stanza boundaries:")
                        .font(.callout.weight(.medium))
                    Text(model.renderedShorts.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.10)))
            }
            if let u = model.outputURL {
                Text(u.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 12) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([u]) } label: { Label("Show Video in Finder", systemImage: "folder") }.buttonStyle(.borderedProminent).controlSize(.large)
                    if !model.renderedShorts.isEmpty {
                        Button { NSWorkspace.shared.activateFileViewerSelecting(model.renderedShorts) } label: {
                            Label("Show \(model.renderedShorts.count) Shorts in Finder", systemImage: "rectangle.portrait.fill")
                        }.buttonStyle(.bordered).controlSize(.large)
                    }
                    ShareLink(item: u) { Label("Share", systemImage: "square.and.arrow.up") }.controlSize(.large)
                    Button { model.stage = .plan } label: { Label("Back to Pictures & Shorts", systemImage: "photo.on.rectangle") }.controlSize(.large)
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
            Section("Image Generation — OpenRouter (openai/gpt-image-2.5-sunburst)") {
                SecureField("OpenRouter API Key (sk-or-v1-…)", text: $model.config.openRouterKey)
                LabeledContent("Credits Remaining") {
                    HStack(spacing: 8) {
                        if model.checkingCredits {
                            ProgressView().controlSize(.mini)
                        } else if let rem = model.openRouterCredits {
                            let approxImgs = Int(rem / max(0.01, model.perImageCostUSD))
                            let summaryText = OpenRouter.formatCredits(rem) + " (≈ \(approxImgs) images)"
                            Text(summaryText)
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundStyle(rem < 0.25 ? Color.orange : Color.green)
                        } else if model.hasOpenRouterKey {
                            Text("Click Refresh to check").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("No API key set").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Refresh") {
                            save()
                            model.refreshOpenRouterCredits(silent: false)
                        }
                        .controlSize(.small)
                        .disabled(!model.hasOpenRouterKey || model.checkingCredits)
                    }
                }
                if let err = model.openRouterCreditError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Text("Generates 16:9 Medium images using \(OpenRouter.imageModel) (~\(OpenRouter.formatUSD(model.perImageCostUSD)) per image). Each song saves its total image cost in project.mvproj.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Where things are saved") {
                folderRow("Main folder", model.config.projectsFolder, defaultText: "~/Movies/Music Videos") { model.config.projectsFolder = $0 }
                folderRow("Finished videos & Shorts", model.config.outputFolder, defaultText: "inside each project (same main folder)") { model.config.outputFolder = $0 }
                Text("Everything lives in the main folder: one folder per song with the MP3, transcript, synced lyrics, pictures, save file, video and Shorts. Pick a separate folder for finished videos only if you want them elsewhere.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Dock") {
                LabeledContent("Music Video Maker") {
                    HStack {
                        Text(model.inDock ? "In your Dock" : "Not in your Dock").foregroundStyle(.secondary)
                        Button(model.inDock ? "Remove from Dock" : "Add to Dock") { model.toggleDock() }.controlSize(.small)
                    }
                }
                if let n = model.dockNote { Text(n).font(.caption).foregroundStyle(.secondary) }
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
        .formStyle(.grouped).frame(width: 580, height: 640)
        .task { await check(); model.refreshOpenRouterCredits(silent: true) }
        .onChange(of: model.config.openRouterKey) { save(); model.refreshOpenRouterCredits(silent: true) }
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
                ProgressPanel(fraction: model.setupProgress, phase: model.setupPhase, started: model.setupStarted)
            } else {
                Picker("Size", selection: $model.nativeTier) {
                    Text("Small — about 1.5 GB total (fastest, plainer prompts)").tag("small")
                    Text("Balanced — about 4.1 GB total, Gemma 4 E2B (recommended)").tag("balanced")
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
