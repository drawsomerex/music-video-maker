// Main screens: setup, progress panel, finished video, Settings and first-run model setup.
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import MVCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            UpdateStrip()
            if model.busy { BackgroundTaskBanner().transition(.move(edge: .top).combined(with: .opacity)) }
            if !model.needsNativeSetup { CostBar() }
            screens
        }
        .background(WindowFitter())
        .animation(.smooth(duration: 0.3), value: updaterVisible)
        .animation(.smooth(duration: 0.25), value: model.busy)
    }
    @EnvironmentObject var updater: Updater
    var updaterVisible: Bool { updater.isInstalling || (updater.available != nil && !updater.bannerDismissed) }

    var screens: some View {
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

/// Progress strip across the top while any background task runs. It sits ABOVE the screen (never on top of its buttons).
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
                .frame(maxWidth: 520)
                Spacer(minLength: 0)
                Button("Cancel") { model.cancelBackgroundTask() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Stops this task. Nothing you made so far is lost.")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// Keeps the window inside the screen: on a small MacBook screen the default size would run under the Dock or off the bottom.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window, let screen = w.screen ?? NSScreen.main else { return }
            let vf = screen.visibleFrame
            var f = w.frame
            f.size.width = min(f.size.width, vf.width); f.size.height = min(f.size.height, vf.height)
            f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
            f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
            if f != w.frame { w.setFrame(f, display: true) }
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
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
    @State private var lyricMode = 0
    @State private var showStyles = false
    @State private var showIdeas = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if model.hasProject {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill").foregroundStyle(.tint)
                            Text("You are working on “\(model.plan?.title ?? "")”. Its pictures and video are safe. Choose a song with a different name to start a new video.")
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.10)))
                    }
                    Picker("Where is your song?", selection: $model.audioInputMode) {
                        Label("I have an MP3 / WAV file", systemImage: "music.note").tag(0)
                        Label("Record it as it plays", systemImage: "waveform.badge.mic").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Choose “I have an MP3 / WAV file” if the song is saved on this Mac. Choose “Record it as it plays” to capture a song that is playing on this Mac (for example from a web page).")

                    if model.audioInputMode == 0 { dropZone } else { recordZone }

                    if let trim = model.trimSummary {
                        Label(trim, systemImage: "scissors")
                            .font(.callout.weight(.medium)).foregroundStyle(.green)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }

                    field("Song title", "e.g. Highway Lights", text: $model.title,
                          help: "The name of your song. It appears on the opening title card and names the folder where everything is saved.")
                    field("Subtitle on the title card (optional)", "e.g. A ballad of the Oklahoma oil boom", text: $model.subject,
                          help: "Optional. A short line shown under the title on the opening card. You can leave it empty.")
                    field("Setting and theme for every picture (optional)", "e.g. Brightly lit colonial Philadelphia", text: $model.settingTheme,
                          help: "Describe the place, time and mood once and every picture follows it. The words are put into every picture idea, and the pictures still change from part to part (time of day, weather, camera view). Leave empty to let the app decide from your lyrics.")
                    Button { showIdeas = true } label: { Label("Suggest 10 ideas for me", systemImage: "lightbulb") }
                        .disabled(model.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(model.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add your lyrics first. The ideas are made by reading them." : "The app reads your lyrics and suggests 10 different places and moods. Press one to use it.")

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Look of the pictures").font(.subheadline.weight(.medium))
                        Button { showStyles = true } label: {
                            HStack { Image(systemName: "paintpalette"); Text(model.selectedStyleName).lineLimit(1); Spacer(); Text("Change…").foregroundStyle(.secondary) }
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                        .help("The art style for all your pictures, such as oil painting or watercolor. Press to see all the styles, change them, or make your own. “AI Auto” lets the app choose a style that fits your song.")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 2)
                }
                .frame(width: 350)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Lyrics").font(.title3.bold())
                        Picker("", selection: $lyricMode) { Text("Type or paste").tag(0); Text("Divide into parts").tag(1) }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 270)
                            .help("“Type or paste” is for entering the words. “Divide into parts” lets you choose which lines belong together; each part becomes one picture, and Shorts start and end between parts.")
                        if model.liveTranscribing {
                            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Writing the words as they play…").font(.callout).foregroundStyle(.orange) }
                        }
                        Spacer()
                        Button { model.pasteOverLyrics() } label: { Label("Paste from clipboard", systemImage: "doc.on.clipboard") }
                            .buttonStyle(.bordered)
                            .help("Replaces the lyrics below with whatever you last copied (Command-C), for example from a lyrics web page.")
                        if model.audioURL != nil && !model.isRecording {
                            Menu {
                                Button { model.transcribeLoadedAudio() } label: { Label("Listen to the song and write the lyrics for me", systemImage: "waveform.and.mic") }
                                    .disabled(model.busy)
                                Button { model.trimLoadedAudioSilence() } label: { Label("Cut the silence at the start and end", systemImage: "scissors") }
                                    .disabled(model.busy)
                            } label: { Label("More tools", systemImage: "wrench.and.screwdriver") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .help("Extra helpers: have the app type out the lyrics by listening to the song, or trim empty silence from the beginning and end of the recording.")
                        }
                    }
                    if lyricMode == 0 {
                    Text("Paste your lyrics below. Leave a blank line between verses. A line with --- starts a new picture (or use “Divide into parts”). Tags like [Chorus] are never shown on screen.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $model.lyrics)
                        .font(.system(size: 15, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(model.isRecording ? Color.red.opacity(0.6) : Color.secondary.opacity(0.25)))
                        .overlay(alignment: .topLeading) {
                            if model.lyrics.isEmpty {
                                Text(model.audioInputMode == 1
                                     ? "Start recording a song. The lyrics will appear here as it plays.\nAfterwards you can fix any words, or use “Paste from clipboard” to paste the official lyrics."
                                     : "Paste your lyrics here.\nThe words on screen are exactly what you paste here; the app only listens to the song to find the timing.")
                                    .foregroundStyle(.tertiary).padding(18).allowsHitTesting(false)
                            }
                        }
                        .help("Your lyrics. What you type or paste here is exactly what appears on the screen.")
                    } else {
                        LyricDividerView()
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()
            ViewThatFits(in: .horizontal) {                     // roomy → squeezed → two rows, so nothing ever overlaps on a small screen
                HStack(spacing: 14) { intervalControl(compact: false); Spacer(minLength: 8); utilityButtons(compact: false); primaryButton }
                HStack(spacing: 10) { intervalControl(compact: true); Spacer(minLength: 6); utilityButtons(compact: true); primaryButton }
                VStack(spacing: 8) {
                    HStack(spacing: 10) { intervalControl(compact: true); Spacer(minLength: 6); utilityButtons(compact: true) }
                    HStack { Spacer(); primaryButton }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .sheet(isPresented: $showStyles) { StyleSheet(inProject: false).environmentObject(model) }
        .sheet(isPresented: $showIdeas) { SettingIdeasSheet(applyToProject: false).environmentObject(model) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav]) { if case .success(let u) = $0 { model.setAudio(u) } }
    }

    func intervalControl(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text(compact ? "A picture every" : "One picture about every").font(.callout).lineLimit(1).fixedSize()
            Stepper(value: $model.imageInterval, in: 8...40, step: 1) { Text("\(Int(model.imageInterval)) s").monospacedDigit().frame(width: 40, alignment: .trailing) }
                .help("How often the picture changes, in seconds. A smaller number means more pictures to make and a busier video; a bigger number means fewer, longer pictures.")
            if model.estimatedImages > 0 && !compact { Text("≈ \(model.estimatedImages) pictures").font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize() }
        }
    }

    func utilityButtons(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Button { model.chooseSaveFolder() } label: {
                if compact { Image(systemName: "externaldrive") }
                else { Label("Saving to \((model.config.projectsRoot.path as NSString).abbreviatingWithTildeInPath)", systemImage: "externaldrive").lineLimit(1).truncationMode(.middle).frame(maxWidth: 220) }
            }.buttonStyle(.bordered)
                .help("Everything is saved in \((model.config.projectsRoot.path as NSString).abbreviatingWithTildeInPath): your songs, pictures and finished videos. Click to pick a different folder.")
            Menu {
                Button("Open a project folder…") { model.chooseProject() }
                if !model.recents.isEmpty { Divider(); ForEach(model.recents, id: \.self) { u in Button(u.deletingLastPathComponent().lastPathComponent) { model.openProject(u) } } }
            } label: { if compact { Image(systemName: "folder") } else { Label("Open earlier project", systemImage: "folder") } }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Go back to a video you started before. All your pictures and settings are kept.")
            HelpButton(screen: "Song screen (first screen)")
            Button { openSettings() } label: { if compact { Image(systemName: "gearshape") } else { Label("Settings", systemImage: "gearshape") } }.buttonStyle(.bordered)
                .help("Folders, the picture maker key, adding the app to your Dock, and more.")
        }
    }

    @ViewBuilder var primaryButton: some View {
        if model.hasProject && !model.setupChanged {
            Button { model.goToStep(2) } label: {
                Label("Back to my pictures", systemImage: "arrow.right.circle.fill").font(.headline).padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command)
            .help("Nothing was changed, so there is nothing to plan again. Go back to this video's pictures.")
        } else {
            Button { model.start() } label: {
                Label(model.hasProject ? "Plan as a new video" : "Plan my video", systemImage: "arrow.right.circle.fill")
                    .font(.headline).padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStart || model.isRecording)
            .keyboardShortcut(.return, modifiers: .command)
            .help(model.canStart ? (model.hasProject ? "You changed the song, title or lyrics, so this makes a new video next to the earlier one. The earlier one stays saved and unchanged."
                                                     : "Go to the next step. The app listens to your song, matches the lyrics and suggests a picture for each part. Takes a minute or two.")
                                 : "This button turns on once you have chosen a song, typed a title and added lyrics.")
        }
    }

    var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack.fill").font(.system(size: 30)).foregroundStyle(.linearGradient(colors: [.orange, .pink, .purple], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 4) { Text("Music Video Maker").font(.title2.bold()); StepBar(current: 1) }
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
                    Text("Drag your song here").font(.headline)
                    Text("an MP3 or WAV file — or click to choose one").font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: model.audioURL == nil ? [6, 5] : [])).foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .help("Click to choose your song file, or drag the file from Finder onto this box. MP3, WAV, M4A and other common music files work.")
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
                Text("Record from:").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Picker("Input", selection: $model.recordSource) {
                    ForEach(LiveSongRecorder.Source.allCases) { src in
                        Text(src.rawValue).tag(src)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(model.isRecording)
                .help("Where the sound comes from. “System audio” records whatever your Mac is playing; the other choices use a microphone or audio input.")
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
                    Label("Stop recording", systemImage: "stop.circle.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
                .help("Stops recording. Empty silence at the start and end is cut off automatically.")
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
                    Text("Press the red button, then play your song on this Mac. Press Stop when it ends.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Button {
                    model.startRecording()
                } label: {
                    Label(model.audioURL == nil ? "Start recording" : "Record again", systemImage: "record.circle")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
                .help("Starts recording the sound your Mac is playing. macOS may ask your permission the first time.")
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

    func field(_ label: String, _ prompt: String, text: Binding<String>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.subheadline.weight(.medium))
            TextField(prompt, text: text).textFieldStyle(.roundedBorder).controlSize(.large).help(help)
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
            HStack(spacing: 12) {
            Button("Cancel", role: .cancel) { model.cancelMainTask() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Stops what the app is doing. Nothing you made so far is lost.")
            HelpButton(screen: model.stage == .rendering ? "Making the video (progress screen)" : "Planning the video (progress screen)")
            }
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
            HStack { Spacer(); HelpButton(screen: "Video screen (finished video)") }.padding(.trailing, 4)
            StepBar(current: 3)
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
                    Button { NSWorkspace.shared.activateFileViewerSelecting([u]) } label: { Label("Show video in Finder", systemImage: "folder") }.buttonStyle(.borderedProminent).controlSize(.large)
                        .help("Opens the folder that holds your finished video, with the video selected.")
                    if !model.renderedShorts.isEmpty {
                        Button { NSWorkspace.shared.activateFileViewerSelecting(model.renderedShorts) } label: {
                            Label("Show \(model.renderedShorts.count) Shorts in Finder", systemImage: "rectangle.portrait.fill")
                        }.buttonStyle(.bordered).controlSize(.large)
                        .help("Opens the folder with your vertical YouTube Shorts.")
                    }
                    ShareLink(item: u) { Label("Share", systemImage: "square.and.arrow.up") }.controlSize(.large)
                        .help("Send the video by Messages, Mail or AirDrop.")
                    Button { model.stage = .plan } label: { Label("Change something", systemImage: "photo.on.rectangle") }.controlSize(.large)
                        .help("Go back to your pictures to swap one, fix the words, or make Shorts. Nothing is lost.")
                    Button { model.reset() } label: { Label("Start a new video", systemImage: "plus") }.controlSize(.large)
                        .help("Starts over with a new song. This video stays saved in its folder.")
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
                folderRow("Main folder", model.config.projectsFolder, defaultText: "~/Movies/Music Videos") { model.config.projectsFolder = $0 }
                    .help("Every song gets its own folder inside this one, holding the MP3, lyrics, pictures, the save file, the finished video and Shorts.")
                folderRow("Finished videos only", model.config.outputFolder, defaultText: "same as the main folder") { model.config.outputFolder = $0 }
                    .help("Optional. Pick a different folder here only if you want finished videos and Shorts kept somewhere else, such as Desktop.")
                Text("Each song gets its own folder. You only need the second choice if you want finished videos kept somewhere else.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Picture maker (optional)") {
                SecureField("OpenRouter key (starts with sk-or-)", text: $model.config.openRouterKey)
                    .help("Paste your OpenRouter key here to let the app draw the pictures for you. Without a key you can still drag in pictures you made yourself. The key is saved privately on this Mac (in a file only your account can read) and is only ever sent to OpenRouter.")
                LabeledContent("Credit left") {
                    HStack(spacing: 8) {
                        if model.checkingCredits {
                            ProgressView().controlSize(.small)
                        } else if let rem = model.openRouterCredits {
                            Text(OpenRouter.formatCredits(rem) + " (about \(Int(rem / max(0.01, model.perImageCostUSD))) pictures)")
                                .font(.callout.weight(.semibold)).foregroundStyle(rem < 0.25 ? Color.orange : Color.green)
                        } else {
                            Text(model.hasOpenRouterKey ? "Press Check" : "No key entered").foregroundStyle(.secondary)
                        }
                        Button("Check") { save(); model.refreshOpenRouterCredits(silent: false) }
                            .disabled(!model.hasOpenRouterKey || model.checkingCredits)
                            .help("Looks up how much credit is left on your OpenRouter account.")
                    }
                }
                if let err = model.openRouterCreditError { Text(err).font(.callout).foregroundStyle(.red) }
                Text("About \(OpenRouter.formatUSD(model.perImageCostUSD)) per picture. Each song remembers how much it has cost.").font(.callout).foregroundStyle(.secondary)
            }
            UpdatesSettingsSection()
            Section("Shortcuts & help") {
                LabeledContent("Music Video Maker") {
                    HStack {
                        Text(model.inDock ? "In your Dock" : "Not in your Dock").foregroundStyle(.secondary)
                        Button(model.inDock ? "Remove from Dock" : "Add to Dock") { model.toggleDock() }
                            .help("Puts the app's icon in your Dock so you can open it with one click.")
                    }
                }
                if let n = model.dockNote { Text(n).font(.callout).foregroundStyle(.secondary) }
                LabeledContent("Recording a song") { Button("Fix recording permission…") { model.showRecordingFix = true }.help("Use this if “Record it as it plays” says macOS is blocking it, even though the switch in System Settings is on.") }
                LabeledContent("Step-by-step guide") { Button("Show Quick Guide") { model.showGuide = true }.help("Opens the plain-language instructions.") }
            }
            if model.isNativeBuild {
                Section("On-device AI") {
                    Text("Listening to your song and writing picture ideas both happen on this Mac. Nothing about your song is sent anywhere.").font(.callout)
                    ModelRows()
                    Picker("Size of the language model", selection: $model.nativeTier) {
                        Text("Small — about 1 GB, fastest").tag("small")
                        Text("Balanced — about 3.6 GB, Gemma 4 E2B (recommended)").tag("balanced")
                        Text("Best — about 6 GB").tag("best")
                    }
                    .help("Chooses which language model “Download” and “Download again” fetch. Bigger models write better picture ideas but take more space and time.")
                    .disabled(model.downloadingModel)
                }
            } else {
                Section("Local AI — oMLX (advanced)") {
                    LabeledContent("Status") { Text(status).foregroundStyle(ids.isEmpty ? .orange : .green) }
                    modelPicker("Speech (Parakeet)", $model.config.sttModel, OMLX.defaultSTT)
                    modelPicker("Writes the image prompts", $model.config.llmModel, OMLX.defaultLLM)
                    TextField("Server URL (blank = http://127.0.0.1:8000)", text: $model.config.omlxURL)
                    SecureField("API key (blank = read from oMLX's own settings)", text: $model.config.omlxKey)
                    Button("Re-check connection") { Task { await check() } }.help("Test the connection to the oMLX server again.")
                }
            }
        }
        .formStyle(.grouped).frame(width: 640, height: 600)
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
                }
                if !value.isEmpty { Button("Reset") { set(""); save() }.help("Go back to the standard folder.") }
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
                ModelRows().frame(width: 520)
            } else {
                Picker("Size", selection: $model.nativeTier) {
                    Text("Small — about 1.5 GB total (fastest, plainer prompts)").tag("small")
                    Text("Balanced — about 4.1 GB total, Gemma 4 E2B (recommended)").tag("balanced")
                    Text("Best — about 6.5 GB total").tag("best")
                }.pickerStyle(.radioGroup).labelsHidden().help("Bigger models write better picture ideas but need more space and time to download. Balanced is right for most Macs.")
                Text("Includes Parakeet Ultra for word-accurate lyric timing (0.5 GB) plus a language model for the prompts. Bigger models write better prompts.")
                    .font(.caption).foregroundStyle(.tertiary).frame(maxWidth: 440).multilineTextAlignment(.center)
                ModelRows().frame(width: 520)
                Button { model.runNativeSetup() } label: { Label("Download & set up", systemImage: "arrow.down.to.line").padding(.horizontal, 10) }
                    .buttonStyle(.borderedProminent).controlSize(.large).help("Download the AI models (one time, needs internet). The progress is shown below.")
            }
        }.padding(40)
        .overlay(alignment: .topTrailing) { HelpButton(screen: "First-time setup (downloading models)").padding(16) }
    }
}
