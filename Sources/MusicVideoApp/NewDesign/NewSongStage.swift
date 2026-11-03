// Stage 1 · Song (design 2c, recording 3g, loop start 3f's empty state). The song, its title, optional direction, and the lyrics.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

struct NewSongStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    @AppStorage("startKind") private var startKind = 0
    var body: some View {
        if model.stage == .loop { NewLoopMusicStage() }
        else if startKind == 1 { NewLoopStart() }
        else { NewMusicSongStage() }
    }
}

struct NewMusicSongStage: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var importing = false
    @State private var targeted = false
    @State private var showStyles = false
    @State private var showIdeas = false

    var recordingMode: Bool { model.audioInputMode == 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 30) {
                ScrollView(.vertical, showsIndicators: false) { left.padding(.trailing, 4) }.frame(width: 330)
                lyricsColumn
            }.padding(.horizontal, 30).padding(.vertical, 24)
            noKeyNote
            footer
        }
        .sheet(isPresented: $showStyles) { StyleSheet(inProject: false).environmentObject(model) }
        .sheet(isPresented: $showIdeas) { SettingIdeasSheet(applyToProject: false).environmentObject(model) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mp3, .wav]) { if case .success(let u) = $0 { model.setAudio(u) } }
    }

    // MARK: left column
    var left: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.hasProject {
                Text("You are working on “\(model.plan?.title ?? "")”. Its pictures and video are safe. Choose a song with a different name to start a new video.")
                    .font(Classical.body(12)).foregroundStyle(Classical.accent800).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Classical.accent100).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.accent300, lineWidth: 1))
            }
            ClassicalHeading(text: "The song")
            if recordingMode { NewRecordCard() } else { songCard }
            CLink(title: recordingMode ? "Use a file instead" : "or record it as it plays") { model.audioInputMode = recordingMode ? 0 : 1 }
                .help("Record a song that is playing on this Mac (for example from a web page) instead of choosing a saved file.")
            CField(label: "Title", prompt: "e.g. Highway Lights", text: $model.title)
                .help("The name of your song. It appears on the opening title card and names the folder where everything is saved.")
            CField(label: "Subtitle on the title card", note: "optional", prompt: "e.g. A ballad of the Oklahoma oil boom", text: $model.subject)
            Hairline()
            HStack(alignment: .firstTextBaseline) { ClassicalHeading(text: "Direction", size: 20); Text("optional · also under Look later").font(Classical.body(11)).foregroundStyle(Classical.neutral600) }
            CField(label: "About", prompt: "e.g. An upbeat bluegrass ballad about the first oil gusher in Oklahoma, 1897", text: $model.songNotes, axis: .vertical, lines: 2...5)
            VStack(alignment: .leading, spacing: 4) {
                CField(label: "Setting", prompt: "Let the lyrics decide", text: $model.settingTheme)
                HStack { Spacer(); CLink(title: "Suggest 10") { showIdeas = true }.disabled(model.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Art style").font(Classical.body(12, weight: .semibold)).foregroundStyle(Classical.neutral800)
                Button { showStyles = true } label: {
                    HStack { Text(model.selectedStyleName).lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.system(size: 10)) }
                        .font(Classical.body(13)).foregroundStyle(Classical.text).padding(.horizontal, 9).padding(.vertical, 7).background(Classical.paper)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                }.buttonStyle(.plain)
                    .help("The art style for all your pictures. “AI Auto” lets the app choose one that fits your song.")
            }
        }
    }

    var songCard: some View {
        Button { importing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: model.audioURL == nil ? "music.note" : "waveform").font(.system(size: 20)).foregroundStyle(Classical.accent700).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.audioURL?.lastPathComponent ?? "Drag your song here").font(Classical.body(13, weight: .semibold)).foregroundStyle(Classical.text).lineLimit(1).truncationMode(.middle)
                    Text(model.audioURL == nil ? "an MP3 or WAV file, or click to choose one" : timeString(model.audioDuration) + (model.trimSummary != nil ? " · silence trimmed" : "")).font(Classical.body(11)).foregroundStyle(Classical.neutral600)
                }
                Spacer(minLength: 4)
                if model.audioURL != nil { Text("Change").font(Classical.body(12)).foregroundStyle(Classical.accent700) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(targeted ? Classical.accent100 : Classical.paper)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: model.audioURL == nil ? [5, 4] : [])).foregroundStyle(targeted ? Classical.accent : Classical.neutral300))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help("Click to choose your song file, or drag the file from Finder onto this box. MP3, WAV, M4A and other common music files work.")
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first, ["mp3", "wav", "m4a", "aiff", "aif", "flac"].contains(u.pathExtension.lowercased()) else { return false }
                model.setAudio(u); return true
            } isTargeted: { targeted = $0 }
    }

    // MARK: lyrics
    var lyricsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ClassicalHeading(text: "Lyrics")
                if model.liveTranscribing { HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Writing the words as they play…").font(Classical.body(11)).foregroundStyle(Classical.accent700) } }
                Spacer()
                CLink(title: "Paste") { model.pasteOverLyrics() }.help("Replaces the lyrics below with whatever you last copied (Command-C), for example from a lyrics web page.")
                if model.audioURL != nil && !model.isRecording {
                    CLink(title: "Write them from the song") { model.transcribeLoadedAudio() }.disabled(model.busy)
                        .help("The app listens to the song and types out the lyrics for you. Check them afterwards.")
                }
            }
            TextEditor(text: $model.lyrics).font(Classical.body(14)).scrollContentBackground(.hidden).padding(10).background(Classical.paper)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(model.isRecording ? Classical.warn : Classical.divider, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if model.lyrics.isEmpty {
                        Text(recordingMode ? "Start recording a song. The lyrics will appear here as it plays." : "Paste your lyrics here. The words on screen are exactly what you paste; the app only listens to the song to find the timing.")
                            .font(Classical.body(13)).foregroundStyle(Classical.neutral500).padding(16).allowsHitTesting(false)
                    }
                }
                .help("Your lyrics. What you type or paste here is exactly what appears on the screen.")
            Text("A blank line starts a new verse and --- starts a new picture. Tags like [Chorus] never appear on screen. You can split and join pictures in the next stage.")
                .font(Classical.body(11)).foregroundStyle(Classical.neutral600).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: footer
    @ViewBuilder var noKeyNote: some View {
        if !model.hasOpenRouterKey && !model.hasProject {
            HStack(spacing: 10) {
                Text("Drawing and the director need an OpenRouter key.").font(Classical.body(12)).foregroundStyle(Classical.accent800)
                CLink(title: "Add my key…") { openSettings() }
                Text("You can still drop in your own pictures.").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                Spacer()
            }.padding(.horizontal, 30).padding(.bottom, 10)
        }
    }

    var footer: some View {
        CFooter {
            HStack(spacing: 6) {
                Text(model.estimatedImages > 0 ? "≈ \(model.estimatedImages) pictures" : "One picture per verse").font(Classical.body(12))
                Text("·")
                Button { model.chooseSaveFolder() } label: { Text("saved in \((model.config.projectsRoot.path as NSString).abbreviatingWithTildeInPath)").lineLimit(1).truncationMode(.middle).underline() }.buttonStyle(.plain)
                    .help("Everything is saved here. Click to pick a different folder.")
            }.font(Classical.body(12)).foregroundStyle(Classical.neutral600)
        } right: {
            if model.hasProject && !model.setupChanged {
                Button("Back to my pictures →") { model.goToStep(2) }.buttonStyle(.classicalPrimary).keyboardShortcut(.return, modifiers: .command)
                    .help("Nothing was changed, so there is nothing to plan again.")
            } else {
                Button { model.autoPending = false; model.start() } label: { HStack(spacing: 6) { Text("Step by step"); Text("free").font(Classical.body(11)).foregroundStyle(Classical.neutral600) } }
                    .buttonStyle(.classical).disabled(!model.canStart || model.isRecording).keyboardShortcut(.return, modifiers: .command)
                    .help("You choose each step yourself: pictures, then Shorts, then the video.")
                Button { model.autoPending = true; model.start() } label: { HStack(spacing: 6) { Text("Direct it for me"); Text("≈ " + OpenRouter.formatUSD(Double(model.estimatedImages + 1) * model.perImageCostUSD)).font(Classical.body(11).monospacedDigit()) } }
                    .buttonStyle(.classicalPrimary).disabled(!model.canStart || model.isRecording || !model.hasOpenRouterKey)
                    .help(model.hasOpenRouterKey ? "A director plans the whole video, draws every picture and opens the preview. One click, no questions." : "Needs your OpenRouter key (Settings).")
            }
        }
    }
}

/// Recording a song as it plays (design 3g).
struct NewRecordCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Record from").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
                Picker("", selection: $model.recordSource) { ForEach(LiveSongRecorder.Source.allCases) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).fixedSize().disabled(model.isRecording)
                    .help("Where the sound comes from. “System audio” records whatever your Mac is playing; the other choices use a microphone or audio input.")
            }
            if model.isRecording {
                HStack(spacing: 10) {
                    Canvas { ctx, size in
                        let bars = 28, step = size.width / CGFloat(bars), hist = model.recordingHistory
                        for i in 0..<bars {
                            let idx = hist.count - bars + i
                            let lvl = idx >= 0 && idx < hist.count ? CGFloat(hist[idx]) : 0.04
                            let h = max(3, min(size.height, lvl * size.height * 1.4))
                            ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: max(2, step - 2), height: h), cornerRadius: 1.5), with: .color(Classical.warn))
                        }
                    }.frame(height: 26)
                    Text(timeString(model.recordingSeconds)).font(Classical.body(20).monospacedDigit()).foregroundStyle(Classical.warn)
                }
                Button { model.stopRecording() } label: { Text("Stop recording").frame(maxWidth: .infinity) }.buttonStyle(.classical).help("Stops recording. Silence at the start and end is cut off automatically.")
                Text("The lyrics are written into the Lyrics box as the song plays. Silence at the start and end is cut when you stop.").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            } else {
                if let url = model.audioURL { Text("\(url.lastPathComponent) · \(timeString(model.audioDuration))").font(Classical.body(12)).foregroundStyle(Classical.ok).lineLimit(1) }
                else { Text("Press Start recording, then play your song on this Mac. Press Stop when it ends.").font(Classical.body(12)).foregroundStyle(Classical.neutral700) }
                Button { model.startRecording() } label: { Text(model.audioURL == nil ? "Start recording" : "Record again").frame(maxWidth: .infinity) }.buttonStyle(.classicalPrimary)
                    .help("Starts recording the sound your Mac is playing. macOS may ask your permission the first time.")
            }
            HStack(spacing: 4) {
                Text("If macOS blocks recording even though the switch in System Settings is on:").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
                CLink(title: "Fix recording permission") { model.showRecordingFix = true }
            }
        }
        .padding(12).background(Classical.paper).overlay(RoundedRectangle(cornerRadius: 4).stroke(model.isRecording ? Classical.warn : Classical.neutral300, lineWidth: 1))
    }
}
