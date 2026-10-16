// Step 2 screen: sections, prompts and picture loading.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

/// Step 2: for each section see the lyrics + a suggested prompt, make the picture elsewhere, and drop it in.
struct PlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = -1
    @State private var confirmMissing = false
    @State private var mode = ProcessInfo.processInfo.environment["MV_DEMO_MODE"] == "1" ? 1 : 0   // 0 = full video, 1 = YouTube Shorts

    var plan: Plan { model.plan! }
    var section: PhotoSection { selection < 0 ? plan.intro : plan.sections[selection] }

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
        .alert("Notice", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.notice ?? "") }
        .confirmationDialog("\(model.missing.count) section(s) have no picture yet", isPresented: $confirmMissing, titleVisibility: .visible) {
            Button("Render anyway (colour gradients fill the gaps)") { model.render() }
            Button("Keep working", role: .cancel) {}
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
            Button { model.revealProject() } label: { Label("Show project folder", systemImage: "folder") }.controlSize(.small)
            Button { model.reset() } label: { Label("Close project", systemImage: "xmark.circle") }.controlSize(.small)
        }.padding(.horizontal, 20).padding(.vertical, 8).background(.regularMaterial)
    }

    // MARK: style + bulk actions
    var styleBar: some View {
        HStack(alignment: .top, spacing: 14) {
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
                    .frame(height: 64).background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                Text("Shared style — appended to every prompt so the pictures match").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { model.plan?.style ?? "" }, set: { model.setStyle($0) }))
                    .font(.callout).scrollContentBackground(.hidden).padding(6)
                    .frame(height: 46).background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            }
            VStack(alignment: .leading, spacing: 6) {
                Button { model.copyAllPrompts() } label: { Label("Copy all prompts", systemImage: "doc.on.doc") }
                Button { chooseFolder() } label: { Label("Load a folder of pictures…", systemImage: "folder") }
                Button { if let w = model.workDir { NSWorkspace.shared.open(Pipeline.promptsURL(w)) } } label: { Label("Open prompts.md", systemImage: "doc.text") }
            }.buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 10).background(.regularMaterial)
    }

    // MARK: sidebar
    var sidebar: some View {
        List(selection: Binding(get: { selection }, set: { selection = $0 ?? -1 })) {
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
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(section.lineIDs, id: \.self) { Text("♪ " + plan.lines[$0].text).font(.callout) }
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
                    HStack {
                        Text("Suggested prompt").font(.headline); Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                        Button { model.rewritePrompt(section: selection) } label: { Label("Another take", systemImage: "arrow.clockwise") }.disabled(model.busy)
                        Button { model.copy(model.fullPrompt(section: selection)) } label: { Label("Copy prompt + style", systemImage: "doc.on.doc") }.buttonStyle(.borderedProminent)
                    }.controlSize(.small)
                    TextEditor(text: Binding(get: { section.prompt }, set: { model.setPrompt($0, section: selection) }))
                        .font(.callout).scrollContentBackground(.hidden).padding(8).frame(minHeight: 86)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    Text("Copied text = this prompt + the shared style + “16:9, no text”.").font(.caption).foregroundStyle(.tertiary)
                }

                DropWell(section: selection)
            }.padding(24)
        }
    }

    // MARK: footer
    var footer: some View {
        HStack(spacing: 14) {
            Button { model.openFullPreview() } label: { Label("Preview video", systemImage: "play.rectangle") }.disabled(model.loadedCount == 0)
            ProgressView(value: Double(model.loadedCount), total: Double(max(1, model.totalImages))).frame(width: 140)
            Text("\(model.loadedCount) of \(model.totalImages) pictures loaded").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Picker("Quality", selection: $model.quality) {
                Text("720p").tag(720); Text("1080p HD").tag(1080); Text("1440p").tag(1440); Text("4K").tag(2160)
            }.pickerStyle(.segmented).frame(width: 280).labelsHidden()
            Button { model.missing.isEmpty ? model.render() : (confirmMissing = true) } label: { Label("Render Video", systemImage: "film").font(.headline).padding(.horizontal, 8).padding(.vertical, 3) }
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

/// Big drop target / preview for the current section's picture.
struct DropWell: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    @State private var targeted = false
    var sec: PhotoSection { section < 0 ? model.plan!.intro : model.plan!.sections[section] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your picture").font(.headline)
            ZStack {
                if let c = sec.selectedCandidate, let t = c.thumbFile {
                    Thumb(file: model.workDir!.appendingPathComponent(t)).aspectRatio(16.0 / 9, contentMode: .fill)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text("Drop the picture here").font(.callout.weight(.medium))
                        Text("or click to choose a file").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 640).aspectRatio(16.0 / 9, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 12).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: sec.selectedCandidate == nil ? [6, 5] : [])).foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.5)))
            .contentShape(Rectangle())
            .onTapGesture { choose() }
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first else { return false }; model.load(u, section: section); return true
            } isTargeted: { targeted = $0 }
            if let c = sec.selectedCandidate {
                HStack {
                    Text("\(c.credit) · \(c.width)×\(c.height)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
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
