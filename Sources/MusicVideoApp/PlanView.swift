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
        VStack(spacing: 0) {
            modeBar
            Divider()
            if mode == 0 {
                styleBar
                Divider()
                HSplitView {
                    sidebar.frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                    detail.frame(minWidth: 560)
                }
                Divider()
                footer
            } else {
                ShortsView()
            }
        }
        .sheet(isPresented: $model.showFullPreview, onDismiss: { model.live.pause() }) {
            VStack(spacing: 12) {
                HStack { Text("Preview — \(plan.title)").font(.headline); Spacer(); Button("Done") { model.showFullPreview = false }.keyboardShortcut(.defaultAction) }
                LivePreviewPane(live: model.live, defaultCaption: 0.075) { v in model.setCaptionY(v, shortID: nil) }
                Text("This is the same renderer as the final export, at preview size. Drag the captions to move them for the whole video.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(width: 780, height: 560)
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
        HStack(spacing: 14) {
            Picker("", selection: $mode) { Text("Full video").tag(0); Text("YouTube Shorts").tag(1) }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
            Text(plan.title).font(.headline).lineLimit(1)
            if plan.timing != "exact" {
                Label("Lyric timing is approximate", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                Button { model.resync() } label: { Label(model.resyncing ? "Re-syncing…" : "Re-sync (exact)", systemImage: "waveform.badge.magnifyingglass") }
                    .controlSize(.small).disabled(model.resyncing).buttonStyle(.borderedProminent)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.green)
                Text("Song Cost: \(OpenRouter.formatUSD(plan.totalGenerationCostUSD))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                if plan.imagesGeneratedCount > 0 {
                    Text("(\(plan.imagesGeneratedCount) img)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color.green.opacity(0.12)))
            .help("Total OpenRouter image generation cost spent on this song (saved in project.mvproj)")

            Button { model.revealProject() } label: { Label("Show project folder", systemImage: "folder") }.controlSize(.small)
            Button { model.reset() } label: { Label("Close project", systemImage: "xmark.circle") }.controlSize(.small)
        }.padding(.horizontal, 20).padding(.vertical, 8).background(.regularMaterial)
    }

    // MARK: style + bulk actions
    var styleBar: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Song description — written from your lyrics; drives every prompt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button { model.redescribe() } label: { Label("Rewrite", systemImage: "arrow.clockwise") }.controlSize(.small).disabled(model.busy)
                    Button { model.regeneratePrompts() } label: { Label("Redo prompts from this", systemImage: "wand.and.stars") }.controlSize(.small).disabled(model.busy)
                }
                TextEditor(text: Binding(get: { model.plan?.description ?? "" }, set: { model.setDescription($0) }))
                    .font(.callout).scrollContentBackground(.hidden).padding(6)
                    .frame(height: 60).background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                HStack {
                    Text("Shared style — appended to every prompt so the pictures match").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(Array(StylePreset.all.dropFirst())) { preset in
                            Button(preset.name) {
                                model.applyStylePreset(preset.name)
                            }
                        }
                    } label: {
                        Label("Style Presets", systemImage: "paintpalette")
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
                TextEditor(text: Binding(get: { model.plan?.style ?? "" }, set: { model.setStyle($0) }))
                    .font(.callout).scrollContentBackground(.hidden).padding(6)
                    .frame(height: 44).background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }

            // OpenRouter Image Generation & Credits Panel
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(.tint)
                    Text("OpenRouter · gpt-image-2.5-sunburst (16:9 Med)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button {
                        model.showOpenRouterKeySheet = true
                    } label: {
                        Label(model.hasOpenRouterKey ? "API Key" : "Set API Key…", systemImage: "key.fill")
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    if model.hasOpenRouterKey {
                        HStack(spacing: 4) {
                            Text("Credits left:")
                                .font(.caption2).foregroundStyle(.secondary)
                            if model.checkingCredits {
                                ProgressView().controlSize(.mini)
                            } else if let rem = model.openRouterCredits {
                                Text(OpenRouter.formatCredits(rem))
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(rem < model.missingImagesCostUSD ? .orange : .green)
                            } else {
                                Button("Check") { model.refreshOpenRouterCredits(silent: false) }
                                    .controlSize(.mini).buttonStyle(.borderless)
                            }
                            Button {
                                model.refreshOpenRouterCredits(silent: false)
                            } label: {
                                Image(systemName: "arrow.clockwise").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Refresh OpenRouter credit balance")
                        }
                    } else {
                        Text("Add your OpenRouter API key to auto-generate images")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("~\(OpenRouter.formatUSD(model.perImageCostUSD))/img · Song total: \(OpenRouter.formatUSD(plan.totalGenerationCostUSD))")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Button {
                        model.generateAllMissingImages()
                    } label: {
                        Label(
                            model.missing.isEmpty
                                ? "All \(model.totalImages) Pictures Ready"
                                : "Generate \(model.missing.count) Missing (~\(OpenRouter.formatUSD(model.missingImagesCostUSD)))",
                            systemImage: "wand.and.sparkles"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.missing.isEmpty || model.busy)
                    .help("Generate all missing section pictures with openai/gpt-image-2.5-sunburst (16:9 Medium)")

                    Button {
                        if model.hasOpenRouterKey {
                            confirmRegenAll = true
                        } else {
                            model.showOpenRouterKeySheet = true
                        }
                    } label: {
                        Text("Reroll All \(model.totalImages) (~\(OpenRouter.formatUSD(model.allImagesCostUSD)))")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.busy)
                    .help("Regenerate all \(model.totalImages) pictures for the entire song (estimated ~\(OpenRouter.formatUSD(model.allImagesCostUSD)))")
                }

                Divider()

                HStack(spacing: 6) {
                    Button { model.copyAllPrompts() } label: { Label("Copy prompts", systemImage: "doc.on.doc") }
                    Button { chooseFolder() } label: { Label("Load folder…", systemImage: "folder") }
                    Button { if let w = model.workDir { NSWorkspace.shared.open(Pipeline.promptsURL(w)) } } label: { Label("prompts.md", systemImage: "doc.text") }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(10)
            .frame(width: 390)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
        .padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
    }

    // MARK: sidebar
    var sidebar: some View {
        List(selection: Binding(get: { model.selectedSection }, set: { model.selectedSection = $0 ?? -1 })) {
            SlotRow(number: 0, title: "Title card", subtitle: plan.title, time: "", cand: plan.intro.selectedCandidate, work: model.workDir!, repeatNote: nil).tag(-1)
            ForEach(plan.sections.indices, id: \.self) { i in
                let s = plan.sections[i]
                SlotRow(number: i + 1, title: s.lineIDs.isEmpty ? "Instrumental" : "Section \(i + 1)", subtitle: s.lineIDs.first.map { plan.lines[$0].text } ?? "♪",
                        time: timeString(s.start + plan.audioOffset), cand: s.selectedCandidate, work: model.workDir!, repeatNote: s.repeatOf.map { "same lyrics as \($0 + 1)" }).tag(i)
            }
        }.listStyle(.sidebar)
    }

    // MARK: detail
    var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selection < 0 ? "Title card" : (section.lineIDs.isEmpty ? "Instrumental" : "Section \(selection + 1)")).font(.title2.bold())
                    Text(selection < 0 ? "opening slide" : "\(timeString(section.start + plan.audioOffset))–\(timeString(section.end + plan.audioOffset)) · \(Int(section.duration)) s")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.plan!.alignmentCoverage < 0.5 && selection <= 0 {
                        Label("Lyrics only \(Int(plan.alignmentCoverage * 100))% matched", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }

                if !section.lineIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Lyrics in this section").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text("Click ▶ to hear a line · Nudge timing if a line arrives early or late").font(.caption2).foregroundStyle(.tertiary)
                        }
                        ForEach(section.lineIDs, id: \.self) { lineIdx in
                            let line = plan.lines[lineIdx]
                            HStack(spacing: 6) {
                                Button {
                                    model.playRange(max(0, line.start - 0.15), line.end + 0.25)
                                } label: {
                                    Image(systemName: "play.fill").font(.caption2)
                                }
                                .buttonStyle(.bordered).controlSize(.mini).help("Play this lyric line")

                                Text(String(format: "%d:%04.1f", Int(line.start) / 60, line.start.truncatingRemainder(dividingBy: 60)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)

                                Text("♪ " + line.text).font(.callout).lineLimit(1)
                                Spacer(minLength: 4)

                                HStack(spacing: 2) {
                                    Button("−0.5s") { model.nudgeLine(lineIdx, delta: -0.5) }
                                    Button("−0.1s") { model.nudgeLine(lineIdx, delta: -0.1) }
                                    Button("+0.1s") { model.nudgeLine(lineIdx, delta: 0.1) }
                                    Button("+0.5s") { model.nudgeLine(lineIdx, delta: 0.5) }
                                }
                                .buttonStyle(.bordered).controlSize(.mini).font(.caption2.monospacedDigit())
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
                        Text("Suggested prompt").font(.headline); Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                        Button { model.rewritePrompt(section: selection) } label: { Label("Another take", systemImage: "arrow.clockwise") }.disabled(model.busy)
                        Button { model.copy(model.fullPrompt(section: selection)) } label: { Label("Copy prompt + style", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                        Button {
                            model.generateImage(section: selection)
                        } label: {
                            Label(
                                section.hasImage
                                    ? "Reroll Picture (~\(OpenRouter.formatUSD(model.perImageCostUSD)))"
                                    : "Generate Picture (~\(OpenRouter.formatUSD(model.perImageCostUSD)))",
                                systemImage: section.hasImage ? "dice.fill" : "sparkles"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busy)
                        .help("Generate a 16:9 Medium picture for this section using \(OpenRouter.imageModel)")
                    }.controlSize(.small)
                    TextEditor(text: Binding(get: { section.prompt }, set: { model.setPrompt($0, section: selection) }))
                        .font(.callout).scrollContentBackground(.hidden).padding(8).frame(minHeight: 86)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    Text("Full prompt sent to \(OpenRouter.imageModel) = this prompt + the shared style + “16:9, no text”.").font(.caption).foregroundStyle(.tertiary)
                }

                DropWell(section: selection)
            }.padding(24)
        }
    }

    // MARK: footer
    var footer: some View {
        HStack(spacing: 14) {
            Button { model.openFullPreview() } label: { Label("Preview video", systemImage: "play.rectangle") }.disabled(model.loadedCount == 0)
            ProgressView(value: Double(model.loadedCount), total: Double(max(1, model.totalImages))).frame(width: 120)
            Text("\(model.loadedCount) of \(model.totalImages) pictures").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: $model.autoRenderShorts) {
                Label("Also make \(plan.shorts.isEmpty ? "4–7" : "\(plan.shorts.count)") Shorts (~30s)", systemImage: "rectangle.portrait.fill")
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .help("Automatically render the main video and \(plan.shorts.isEmpty ? "4–7" : "\(plan.shorts.count)") ~30-second Shorts cut at natural stanza boundaries")

            Picker("Quality", selection: $model.quality) {
                Text("720p").tag(720); Text("1080p HD").tag(1080); Text("1440p").tag(1440); Text("4K").tag(2160)
            }.pickerStyle(.segmented).frame(width: 240).labelsHidden()
            Button { model.missing.isEmpty ? model.render() : (confirmMissing = true) } label: {
                Label(model.autoRenderShorts ? "Render Video + Shorts" : "Render Video", systemImage: "film")
                    .font(.headline).padding(.horizontal, 8).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
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
            HStack {
                Text("Your picture").font(.headline)
                Spacer()
                if sec.selectedCandidate != nil {
                    Toggle("Show 9:16 Short crop & focal point", isOn: $showShortCrop)
                        .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
                    Button("Auto Focus") { model.resetFocus(section: section) }
                        .controlSize(.mini).buttonStyle(.bordered)
                        .help("Re-detect the face / subject focal point automatically")
                    Button {
                        model.generateImage(section: section)
                    } label: {
                        Label("Reroll (~\(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "dice.fill")
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                    .help("Generate a new 16:9 Medium replacement image with \(OpenRouter.imageModel)")
                } else {
                    Button {
                        model.generateImage(section: section)
                    } label: {
                        Label("Generate with OpenRouter (~\(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "sparkles")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                }
            }
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
                            .help("Focal point for Ken Burns pan & 9:16 Shorts crop — drag to adjust")
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 34)).foregroundStyle(.secondary)
                            Text("Drop a picture here, click to choose a file, or click Generate above").font(.callout.weight(.medium))
                            Text("\(OpenRouter.imageModel) · 16:9 Medium · ~\(OpenRouter.formatUSD(model.perImageCostUSD))").font(.caption).foregroundStyle(.secondary)
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
                    Text("\(c.credit) · \(c.width)×\(c.height) · Drag the orange target to aim the camera pan & 9:16 Short crop").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.generateImage(section: section)
                    } label: {
                        Label("Reroll (~\(OpenRouter.formatUSD(model.perImageCostUSD)))", systemImage: "dice")
                    }
                    .controlSize(.small)
                    .disabled(model.busy)
                    Button("Replace…") { choose() }.controlSize(.small)
                    Button("Remove", role: .destructive) { model.removeImage(section: section) }.controlSize(.small)
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
