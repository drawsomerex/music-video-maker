// Look (design 3c): one panel for every song-wide picture choice. Used for every picture drawn from now on. The looping video uses the same panel.
import SwiftUI
import MVCore

extension AppModel {
    /// Draws the cast sheet (one picture of the people and things that stay the same) from the cast words.
    func drawCastSheet() {
        guard plan != nil, let w = workDir else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let cfg = config
        runBackground(initialPhase: "Drawing the cast sheet…") { [weak self] in
            guard let self, var p = self.plan else { return }
            let before = p
            _ = try await Pipeline.makeCastSheet(plan: &p, work: w, config: cfg)
            self.mergeTaskResult(p, startedFrom: before, work: w, section: -1, artwork: false)
            self.refreshOpenRouterCredits(silent: true)
        }
    }
}

struct NewLookPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = StyleLibrary.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showStyles = false
    @State private var showIdeas = false
    @State private var showSubject = false
    @State private var confirmAll = false
    var plan: Plan { model.plan! }
    var selected: StylePreset? { library.preset(id: model.selectedStylePreset) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        ClassicalHeading(text: "Look", size: 28)
                        Text("Used for every picture drawn from now on. Pictures you already have stay as they are.").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
                    }
                    section("Art style") {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(library.all.prefix(8))) { p in chip(p.name, on: model.selectedStylePreset == p.id) { model.selectedStylePreset = p.id; model.applyStylePreset(p.id) } }
                            CLink(title: "All \(library.all.count) styles…") { showStyles = true }
                        }
                        if let s = selected, !s.prompt.isEmpty { Text(s.prompt).font(Classical.italic(12)).foregroundStyle(Classical.neutral700).fixedSize(horizontal: false, vertical: true) }
                    }
                    section("Setting") {
                        CField(label: "About the song", prompt: "e.g. An upbeat bluegrass ballad about the first oil gusher in Oklahoma, 1897", text: Binding(get: { model.songNotes }, set: { v in model.songNotes = v; model.editSong { $0.songNotes = v } }), axis: .vertical, lines: 1...4)
                        CField(label: "Every picture", prompt: "Let the lyrics decide", text: Binding(get: { plan.setting }, set: { v in model.settingTheme = v; model.editSong { $0.setting = v } }))
                        HStack { Spacer(); CLink(title: "Suggest 10") { showIdeas = true } }
                    }
                    section("Pictures") { pictureRows }
                    section("Cast", note: "people and things that look the same in every picture") {
                        CField(label: "", prompt: "e.g. George Keeler; a young driller in a flat cap (empty = none)", text: Binding(get: { plan.cast }, set: { v in model.editSong { $0.cast = v; $0.castSheet = nil } }), axis: .vertical, lines: 1...3)
                        HStack(spacing: 12) {
                            Button { model.drawCastSheet() } label: { Text("Draw cast sheet  \(OpenRouter.formatUSD(model.perImageCostUSD))") }.buttonStyle(.classical)
                                .disabled(plan.cast.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                            if plan.castSheet != nil { Text("Cast sheet drawn ✓").font(Classical.body(12)).foregroundStyle(Classical.ok) }
                        }
                    }
                }.padding(28)
            }
            CFooter {
                Text("Loops add: Cloudless sky · What moves").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            } right: {
                Button("Redraw all \(model.totalImages)  \(OpenRouter.formatUSD(model.allImagesCostUSD))") { confirmAll = true }.buttonStyle(.classical).disabled(model.busy || !model.hasOpenRouterKey)
                Button("Done") { dismiss() }.buttonStyle(.classicalPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 620, height: 700).background(Classical.bg).environment(\.colorScheme, .light)
        .sheet(isPresented: $showStyles) { StyleSheet(inProject: true).environmentObject(model) }
        .sheet(isPresented: $showIdeas) { SettingIdeasSheet(applyToProject: true).environmentObject(model) }
        .sheet(isPresented: $showSubject) { FindPictureSheet(set: { model.setSongReference($0) }) }
        .confirmationDialog("Redraw all \(model.totalImages) pictures?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Redraw all \(model.totalImages) (~\(OpenRouter.formatUSD(model.allImagesCostUSD)))") { model.regenerateAllImages(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Every picture is drawn again with the Look above. The earlier versions stay under Versions, and the cost is added to this song's total.") }
    }

    func section<C: View>(_ t: String, note: String? = nil, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Hairline(); ClassicalHeading(text: t, note: note, size: 20); c() }
    }
    func chip(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(Classical.body(12)).foregroundStyle(on ? Classical.accent700 : Classical.neutral800).padding(.horizontal, 10).padding(.vertical, 5).background(on ? Classical.accent100 : .clear)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Classical.accent : Classical.neutral300, lineWidth: 1)) }.buttonStyle(.plain)
    }

    var pictureRows: some View {
        let w = model.workDir
        let current = plan.sections.indices.contains(model.selectedSection) ? plan.sections[model.selectedSection].selectedCandidate?.fullFile : plan.intro.selectedCandidate?.fullFile
        return ReferenceRows(reference: plan.source.flatMap { w?.appendingPathComponent($0) },
                      note: plan.source == nil ? "Optional: a picture or photo to base every picture on. Without one, each picture is based on the picture before it." : "Pictures whose idea shows this place, building or subject are based on it (always redrawn, never copied).",
                      read: plan.source != nil ? plan.sourceNote.map { "Every picture idea uses: " + $0 } : nil,
                      useCurrent: current != nil && current != plan.source ? { model.useSectionAsSource(model.selectedSection) } : nil,
                      choose: { model.chooseSongReference() }, find: { showSubject = true },
                      remove: plan.source != nil ? { model.clearSongSource() } : nil,
                      focus: Binding(get: { model.songFocus }, set: { v in model.editSong { $0.nextFocus = v }; if plan.source != nil, plan.sourceNoteFocus != v { model.readSourceIntoIdeas() } }),
                      weather: Binding(get: { plan.weather }, set: { v in model.editSong { $0.weather = v } }),
                      time: Binding(get: { plan.timeOfDay }, set: { v in model.editSong { $0.timeOfDay = v } }),
                      disabled: model.busy && model.directorRun?.waiting != true,
                      quality: Binding(get: { plan.pictureQuality }, set: { v in model.editSong { $0.pictureQuality = v } }),
                      brightness: Binding(get: { plan.brightness }, set: { v in model.editSong { $0.brightness = v } }),
                      shot: Binding(get: { plan.shot }, set: { v in model.editSong { $0.shot = v } }))
    }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600; var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > w { x = 0; y += row + spacing; row = 0 }; x += z.width + spacing; row = max(row, z.height) }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }; s.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += z.width + spacing; row = max(row, z.height) }
    }
}
