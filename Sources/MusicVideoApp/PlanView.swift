// Step 2 screen: sections, prompts and picture loading.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

/// Step 2: for each section see the lyrics + a suggested prompt, generate or drop the picture in, and render.
struct PlanView: View {
    @EnvironmentObject var model: AppModel
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

    var body: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            modeBar
            Divider()
            if mode == 0 {
                // On a small screen the top area may use at most ~40 % of the window height and scrolls instead of pushing the picture area off screen.
                ScrollView(.vertical) { styleBar }.frame(maxHeight: max(150, geo.size.height * 0.40)).fixedSize(horizontal: false, vertical: true)
                Divider()
                HSplitView {
                    sidebar.frame(minWidth: 220, idealWidth: 300, maxWidth: 400)
                    detail.frame(minWidth: 420)
                }
                Divider()
                footer
            } else {
                ShortsView()
            }
        }
        }
        .sheet(isPresented: $model.showFullPreview, onDismiss: { model.live.pause() }) {
            VStack(spacing: 12) {
                HStack { Text("Preview — \(plan.title)").font(.headline); Spacer(); Button("Done") { model.showFullPreview = false }.keyboardShortcut(.defaultAction) }
                LivePreviewPane(live: model.live, defaultCaption: 0.075) { v in model.setCaptionY(v, shortID: nil) }
                CaptionTimingBar().environmentObject(model)
                Text("This is exactly what the finished video will look like. Drag the words up or down to move them.").font(.callout).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 620, idealWidth: 800, minHeight: 460, idealHeight: 620)
        }
        .sheet(isPresented: $model.showOpenRouterKeySheet) {
            OpenRouterKeySheet()
                .environmentObject(model)
        }
        .alert("Notice", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.notice ?? "") }
        .confirmationDialog("\(model.missing.count) section(s) have no picture yet", isPresented: $confirmMissing, titleVisibility: .visible) {
            Button("Generate \(model.missing.count) missing picture(s) (~\(OpenRouter.formatUSD(model.missingImagesCostUSD)))") {
                model.generateAllMissingImages()
            }
            Button("Render anyway (colour gradients fill the gaps)") { model.render() }
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
                .help("“Full video” is the whole song in widescreen. “YouTube Shorts” makes short vertical clips for phones.")
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
            Button { model.reset() } label: { if compact { Image(systemName: "xmark.circle") } else { Label("Close", systemImage: "xmark.circle") } }
                .help("Closes this song and returns to the start. Everything is already saved; use “Open earlier project” to come back.")
        }
    }

    // MARK: style + bulk actions
    @State private var showDescription = false

    var styleBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                nextStepCard
                pictureMaker.frame(width: 370)
            }
            if model.canAddInstrumentalIntro, let first = plan.lines.first?.start {
                HStack(spacing: 12) {
                    Image(systemName: "music.note").foregroundStyle(.orange)
                    Text("The first words start at \(timeString(first)), but the music before them has no picture of its own. Add one so that part of the song has its own scene.")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.addInstrumentalIntro() } label: { Label("Add picture for the opening music", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent).disabled(model.busy)
                        .help("Adds a new part to the list for the music before the first words and writes a picture idea for it. Your other pictures stay exactly where they are.")
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
            DisclosureGroup(isExpanded: $showDescription) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("What the song is about (the app wrote this from your lyrics)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                        Button { model.redescribe() } label: { Label("Write it again", systemImage: "arrow.clockwise") }.disabled(model.busy)
                            .help("Has the AI read your lyrics again and write a new description and new picture ideas. Your own edits to the description are replaced.")
                        Button { model.regeneratePrompts() } label: { Label("Make new picture ideas", systemImage: "wand.and.stars") }.disabled(model.busy)
                            .help("Keeps the description below (including any changes you made) and writes fresh picture ideas from it.")
                    }
                    TextEditor(text: Binding(get: { model.plan?.description ?? "" }, set: { model.setDescription($0) }))
                        .font(.callout).scrollContentBackground(.hidden).padding(6)
                        .frame(height: 70).background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .help("You can edit this. Every picture idea is built from it, so changing it changes the pictures.")
                    HStack {
                        Text("Art style for every picture (keeps them looking alike)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(Array(StylePreset.all.dropFirst())) { preset in Button(preset.name) { model.applyStylePreset(preset.name) } }
                        } label: { Label("Choose a style", systemImage: "paintpalette") }
                        .fixedSize().help("Pick a ready-made art style such as oil painting, watercolor or anime. It is added to every picture idea.")
                    }
                    TextEditor(text: Binding(get: { model.plan?.style ?? "" }, set: { model.setStyle($0) }))
                        .font(.callout).scrollContentBackground(.hidden).padding(6)
                        .frame(height: 50).background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .help("The look of the pictures, in words. It is added to every picture idea so all the pictures match.")
                }.padding(.top, 6)
            } label: {
                Label("Song description and art style (written for you; open to change)", systemImage: "text.alignleft").font(.callout.weight(.medium))
            }
            .help("The app already wrote these. Open this only if you want to change how the pictures look.")
        }
        .padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
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
                             detail: "Click a part in the list on the left, then drag in a picture you made. To have the app draw them for you, add an OpenRouter key.")
            }
        }
        .frame(maxWidth: .infinity)
    }

    var pictureMaker: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(.tint)
                Text("Picture maker").font(.headline)
                Spacer()
                Button { model.showOpenRouterKeySheet = true } label: { Label(model.hasOpenRouterKey ? "Key" : "Add key", systemImage: "key.fill") }
                    .help(model.hasOpenRouterKey ? "Change or check your OpenRouter key." : "Add your OpenRouter key so the app can draw the pictures. You can also skip this and drag in your own pictures.")
            }
            if model.hasOpenRouterKey {
                HStack(spacing: 6) {
                    Text("Credit left:").font(.callout).foregroundStyle(.secondary)
                    if model.checkingCredits { ProgressView().controlSize(.small) }
                    else if let rem = model.openRouterCredits {
                        Text(OpenRouter.formatCredits(rem)).font(.callout.monospacedDigit().weight(.bold)).foregroundStyle(rem < model.missingImagesCostUSD ? .orange : .green)
                    } else { Button("Check") { model.refreshOpenRouterCredits(silent: false) }.buttonStyle(.borderless) }
                    Spacer()
                    Text("about \(OpenRouter.formatUSD(model.perImageCostUSD)) each").font(.callout).foregroundStyle(.secondary)
                }
                .help("What is left on your OpenRouter account, and the usual price of one picture.")
            } else {
                Text("Optional: add an OpenRouter key and the app will draw the pictures for you.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { model.generateAllMissingImages() } label: {
                    Label(model.missing.isEmpty ? "All pictures ready" : "Make all missing pictures (\(model.missing.count), about \(OpenRouter.formatUSD(model.missingImagesCostUSD)))", systemImage: "wand.and.sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.missing.isEmpty || model.busy)
                .help("Draws a picture for every part that does not have one yet. You are only charged for pictures it makes. You can watch the progress and press Cancel at any time.")
            }
            HStack(spacing: 8) {
                Menu {
                    Button("Make every picture again (about \(OpenRouter.formatUSD(model.allImagesCostUSD)))") {
                        if model.hasOpenRouterKey { confirmRegenAll = true } else { model.showOpenRouterKeySheet = true }
                    }
                    Divider()
                    Button("Copy all picture ideas") { model.copyAllPrompts() }
                    Button("Open picture ideas as a document") { if let w = model.workDir { NSWorkspace.shared.open(Pipeline.promptsURL(w)) } }
                } label: { Label("More", systemImage: "ellipsis.circle") }
                .fixedSize().help("Other things you can do with the pictures: make them all again, or copy the picture ideas to use in another app.")
                Button { chooseFolder() } label: { Label("Add pictures from a folder…", systemImage: "folder") }
                    .help("Choose a folder of pictures named 00.png, 01.png, 02.png and so on. 00 is the title card. Each picture goes to the matching part of the song.")
                Spacer()
                Text("This song so far: \(OpenRouter.formatUSD(plan.totalGenerationCostUSD))").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .help("What this song has cost in picture-making so far.")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }

    // MARK: sidebar
    var sidebar: some View {
        List(selection: Binding(get: { model.selectedSection }, set: { model.selectedSection = $0 ?? -1 })) {
            SlotRow(number: 0, title: "Title card", subtitle: plan.title, time: "", cand: plan.intro.selectedCandidate, work: model.workDir!, repeatNote: nil).tag(-1)
            ForEach(plan.sections.indices, id: \.self) { i in
                let s = plan.sections[i]
                SlotRow(number: i + 1, title: s.lineIDs.isEmpty ? (i == 0 ? "Music before the words" : (i == plan.sections.count - 1 ? "Music after the words" : "Music break")) : "Section \(i + 1)", subtitle: s.lineIDs.first.map { plan.lines[$0].text } ?? "♪",
                        time: timeString(s.start + plan.audioOffset), cand: s.selectedCandidate, work: model.workDir!, repeatNote: s.repeatOf.map { "same lyrics as \($0 + 1)" }).tag(i)
            }
        }.listStyle(.sidebar)
    }

    // MARK: detail
    var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selection < 0 ? "Title card" : (section.lineIDs.isEmpty ? (selection == 0 ? "Music before the words" : (selection == plan.sections.count - 1 ? "Music after the words" : "Music break")) : "Section \(selection + 1)")).font(.title2.bold())
                    Text(selection < 0 ? "opening slide" : "\(timeString(section.start + plan.audioOffset))–\(timeString(section.end + plan.audioOffset)) · \(Int(section.duration)) s")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.plan!.alignmentCoverage < 0.5 && selection <= 0 {
                        Label("Lyrics only \(Int(plan.alignmentCoverage * 100))% matched", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }

                if !section.lineIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Words in this part").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("▶ plays a line. If a line shows too early or late, use the small − and + buttons.").font(.callout).foregroundStyle(.tertiary)
                        }
                        ForEach(section.lineIDs, id: \.self) { lineIdx in
                            let line = plan.lines[lineIdx]
                            HStack(spacing: 6) {
                                Button {
                                    model.playRange(max(0, line.start - 0.15), line.end + 0.25)
                                } label: {
                                    Image(systemName: "play.fill").font(.caption2)
                                }
                                .buttonStyle(.bordered).help("Listen to this line of the song.")

                                Text(String(format: "%d:%04.1f", Int(line.start) / 60, line.start.truncatingRemainder(dividingBy: 60)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)

                                Text("♪ " + line.text).font(.body).lineLimit(1)
                                Spacer(minLength: 4)

                                HStack(spacing: 2) {
                                    Button("−0.5s") { model.nudgeLine(lineIdx, delta: -0.5) }
                                    Button("−0.1s") { model.nudgeLine(lineIdx, delta: -0.1) }
                                    Button("+0.1s") { model.nudgeLine(lineIdx, delta: 0.1) }
                                    Button("+0.5s") { model.nudgeLine(lineIdx, delta: 0.5) }
                                }
                                .buttonStyle(.bordered).controlSize(.small).font(.caption.monospacedDigit())
                                .help("Moves just this line earlier (−) or later (+) in the video. 0.1 s is a tiny nudge; 0.5 s is half a second.")
                            }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
                }
                if let r = section.repeatOf {
                    HStack {
                        Label("Same lyrics as section \(r + 1)", systemImage: "arrow.triangle.2.circlepath").font(.callout)
                        Spacer()
                        Button("Reuse its picture") { model.reuse(section: selection, from: r) }.disabled(plan.sections[r].selectedCandidate == nil)
                    }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(.blue.opacity(0.1)))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Picture idea").font(.headline).help("A description of the picture for this part of the song. The app writes it from your lyrics. You can edit it."); Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
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
                    TextEditor(text: Binding(get: { section.prompt }, set: { model.setPrompt($0, section: selection) }))
                        .font(.callout).scrollContentBackground(.hidden).padding(8).frame(minHeight: 86)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    Text("The picture is drawn from this idea plus the art style, in widescreen with no text.").font(.callout).foregroundStyle(.tertiary)
                }

                DropWell(section: selection)
            }.padding(24)
        }
    }

    // MARK: footer
    var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { previewControls; Spacer(minLength: 8); makeControls(compact: false) }
            HStack(spacing: 10) { previewControls; Spacer(minLength: 6); makeControls(compact: true) }
            VStack(spacing: 8) { HStack { previewControls; Spacer() }; HStack { Spacer(); makeControls(compact: true) } }
        }
        .padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
    }

    var previewControls: some View {
        HStack(spacing: 12) {
            Button { model.openFullPreview() } label: { Label("Preview", systemImage: "play.rectangle") }.controlSize(.large).disabled(model.loadedCount == 0)
                .help(model.loadedCount == 0 ? "Add at least one picture first, then you can watch a preview." : "Watch the video before it is made. Nothing is saved or changed.")
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: Double(model.loadedCount), total: Double(max(1, model.totalImages))).frame(width: 130)
                Text("\(model.loadedCount) of \(model.totalImages) pictures ready").font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
            .help("How many parts of the song have a picture. Parts without one get a plain colour background.")
        }
    }

    func makeControls(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            Toggle(isOn: $model.autoRenderShorts) {
                Text(compact ? "Also Shorts" : "Also make \(plan.shorts.isEmpty ? "short" : "\(plan.shorts.count)") clips").font(.callout).lineLimit(1).fixedSize()
            }
            .toggleStyle(.checkbox)
            .help("Also makes \(plan.shorts.isEmpty ? "several" : "\(plan.shorts.count)") vertical clips of about 30 seconds each for YouTube Shorts, cut between the parts of your song.")
            Group {
                if compact {
                    Picker("Quality", selection: $model.quality) { Text("720p").tag(720); Text("1080p HD").tag(1080); Text("1440p").tag(1440); Text("4K").tag(2160) }
                        .pickerStyle(.menu).frame(width: 110)
                } else {
                    Picker("Quality", selection: $model.quality) { Text("720p").tag(720); Text("1080p HD").tag(1080); Text("1440p").tag(1440); Text("4K").tag(2160) }
                        .pickerStyle(.segmented).frame(width: 240)
                }
            }
            .labelsHidden()
            .help("Picture sharpness. 1080p HD is right for YouTube. 4K is sharper but takes much longer and makes a bigger file.")
            Button { model.missing.isEmpty ? model.render() : (confirmMissing = true) } label: {
                Label(model.autoRenderShorts && !compact ? "Make my video and clips" : "Make my video", systemImage: "film")
                    .font(.headline).padding(.horizontal, 8).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command)
            .help("Creates the finished video file. It takes a few minutes; you can watch the progress and cancel at any time.")
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
    @State private var targeted = false
    @State private var showShortCrop = true
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
                if sec.selectedCandidate != nil {
                    Toggle("Show the camera aim", isOn: $showShortCrop)
                        .toggleStyle(.checkbox).font(.callout).foregroundStyle(.secondary)
                        .help("Shows the orange dot the camera slowly moves toward, and the dashed box that is kept in the tall YouTube Shorts version.")
                    Button("Aim automatically") { model.resetFocus(section: section) }
                        .buttonStyle(.bordered)
                        .help("Lets the app find the most interesting spot in the picture (such as a face) and aim the camera there.")
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
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    if let c = sec.selectedCandidate, let t = c.thumbFile {
                        Thumb(file: model.workDir!.appendingPathComponent(t))
                            .frame(width: w, height: h)
                            .clipped()
                        if showShortCrop {
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
                            Text("Drag a picture here, or click to choose one").font(.headline)
                            Text("Widescreen pictures work best (1920 × 1080 or larger)").font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(width: w, height: h)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard sec.selectedCandidate != nil else { return }
                            let nx = min(0.95, max(0.05, Double(g.location.x / max(1, w))))
                            let ny = min(0.95, max(0.05, 1.0 - Double(g.location.y / max(1, h))))
                            model.setFocus(x: nx, y: ny, section: section)
                        }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if sec.selectedCandidate == nil { choose() }
                    }
                )
            }
            .frame(maxWidth: 640).aspectRatio(16.0 / 9, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: sec.selectedCandidate == nil ? [6, 5] : [])).foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5)))
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }; model.load(u, section: section); return true
            } isTargeted: { targeted = $0 }
            if let c = sec.selectedCandidate {
                HStack {
                    Text("Tip: drag the orange dot to choose where the camera drifts toward.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose a different file…") { choose() }
                        .help("Replaces this picture with another file from your Mac.")
                    Button("Remove picture", role: .destructive) { model.removeImage(section: section) }
                        .help("Takes this picture away. That part of the video will show a plain colour until you add another.")
                }.frame(maxWidth: 640)
            }
        }
    }

    func choose() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.image]; p.allowsMultipleSelection = false
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
        HStack(spacing: 10) {
            Label("Words look too early or late?", systemImage: "captions.bubble").font(.callout.weight(.medium))
            Button { model.nudgeCaptions(by: -0.05) } label: { Label("Show sooner", systemImage: "backward.fill") }
                .help("Makes every word appear a little earlier (a twentieth of a second per click). Use this if the words seem to arrive after the singer.")
            Text("now \(model.captionShiftText)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 130)
            Button { model.nudgeCaptions(by: 0.05) } label: { Label("Show later", systemImage: "forward.fill") }
                .help("Makes every word appear a little later. Use this if the words seem to arrive before the singer.")
            Button("Reset") { model.resetCaptionTiming() }
                .help("Goes back to the standard timing.")
        }
    }
}
