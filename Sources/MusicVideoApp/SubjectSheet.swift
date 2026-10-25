// Finding a picture to base the pictures on: choose your own, or search online (Openverse and Wikimedia Commons). Every result can be seen larger.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

struct FindPictureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let set: (URL) -> Void
    @State private var query = ""
    @State private var hits: [SubjectHit] = []
    @State private var searching = false
    @State private var searched = false
    @State private var fetching: String?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find a picture online").font(.title2.bold())
            Text("Type what you are looking for, for example “highland cow”, “lighthouse” or “Scottish glen”. Click a picture to use it, or the magnifying glass to see it larger. It is only used as a guide: the app always draws a new picture from it.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("What are you looking for?", text: $query).textFieldStyle(.roundedBorder).font(.title3).onSubmit { search() }
                Button { search() } label: { Label("Search", systemImage: "magnifyingglass").font(.title3) }.buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            ZStack {
                if searching { ProgressView("Searching…") }
                else if hits.isEmpty { Text(searched ? "Nothing found. Try other words." : "The pictures you find appear here.").foregroundStyle(.secondary) }
                else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 12)], spacing: 12) {
                            ForEach(hits) { h in
                                ZStack(alignment: .topTrailing) {
                                    Button { pick(h) } label: {
                                        ZStack {
                                            AsyncImage(url: h.thumb) { $0.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.06) }
                                                .frame(height: 125).frame(maxWidth: .infinity).clipped()
                                            if fetching == h.id { Color.black.opacity(0.5); ProgressView().controlSize(.small) }
                                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain).help(h.title.isEmpty ? h.source : "\(h.title) (\(h.source)). Click to use it.").disabled(fetching != nil)
                                    Button { viewLarger(h) } label: { Image(systemName: "plus.magnifyingglass").font(.title3.weight(.semibold)).padding(6).background(Circle().fill(.black.opacity(0.6))).foregroundStyle(.white) }
                                        .buttonStyle(.plain).padding(6).help("See it larger").accessibilityLabel("See it larger")
                                }
                            }
                        }.padding(2)
                    }
                }
            }.frame(minHeight: 320, maxHeight: .infinity)
            if let f = failure { Label(f, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(22).frame(minWidth: 760, idealWidth: 900, minHeight: 620, idealHeight: 720)
    }

    func search() {
        searching = true; failure = nil
        let q = query
        Task { hits = await SubjectPicture.search(q); searched = true; searching = false }
    }
    func pick(_ h: SubjectHit) {
        fetching = h.id; failure = nil
        Task {
            do { let f = try await SubjectPicture.download(h, to: FileManager.default.temporaryDirectory); set(f); dismiss() }
            catch { failure = error.localizedDescription }
            fetching = nil
        }
    }
    func viewLarger(_ h: SubjectHit) {
        Task {
            if let f = try? await SubjectPicture.download(h, to: FileManager.default.temporaryDirectory) { FullScreenPlayer.showImage(f, title: h.title) }
            else { failure = "That picture couldn't be opened. Try another one." }
        }
    }
}

extension AppModel {
    /// The music video's picture options (they work like the looping video's).
    func editSong(_ f: (inout Plan) -> Void) { guard var p = plan else { return }; f(&p); plan = p; persist() }
    var songFocus: NextFocus {
        guard let p = plan else { return .place }
        return NextFocus.resolve(p.nextFocus, reference: p.source.flatMap { n in workDir?.appendingPathComponent(n) })
    }
    /// A picture to base a music video's pictures on (yours or found online), shaped to widescreen first if needed; the picture ideas then use it.
    func setSongReference(_ url: URL) {
        fitThen(url, addCost: { [weak self] c in self?.editSong { $0.totalGenerationCostUSD += c } }) { [weak self] f in
            guard let self, let w = self.workDir else { return }
            let name = "reference-\(Int(Date().timeIntervalSince1970)).\(f.pathExtension.isEmpty ? "jpg" : f.pathExtension.lowercased())"
            do {
                try FileManager.default.copyItem(at: f, to: w.appendingPathComponent(name))
                self.checkpoint("Choose the picture to base it on"); self.editSong { $0.source = name; $0.nextFocus = nil }
                self.readSourceIntoIdeas()
            } catch { self.errorMessage = "Couldn't use that picture: \(error.localizedDescription)" }
        }
    }
    func chooseSongReference() {
        let o = NSOpenPanel(); o.allowedContentTypes = [.image]; o.message = "Choose the picture to base the pictures on"
        if o.runModal() == .OK, let u = o.url { setSongReference(u) }
    }
    /// The picture of a part becomes the picture every other picture is based on.
    func useSectionAsSource(_ section: Int) {
        guard let p = plan, let f = (section < 0 ? p.intro : p.sections[section]).selectedCandidate?.fullFile else { return }
        checkpoint("Choose the picture to base it on"); editSong { $0.source = f; $0.nextFocus = nil }; readSourceIntoIdeas()
    }
    func clearSongSource() { checkpoint("Remove the picture to base it on"); editSong { $0.source = nil; $0.sourceNote = nil } }
    /// Reads the picture the song is based on (its place, building or subject, whichever is kept) and rewrites every picture idea to use it.
    /// Ideas you wrote yourself stay; pictures already drawn stay.
    func readSourceIntoIdeas() {
        guard let p0 = plan, let w = workDir, let src = p0.source else { return }
        guard hasOpenRouterKey else { showOpenRouterKeySheet = true; return }
        let focus = songFocus, cfg = config
        runBackground(initialPhase: "Looking at the picture…") { [weak self] in
            guard let self, var p = self.plan else { return }
            let r = try await Pipeline.describeSource(w.appendingPathComponent(src), focus: focus, config: cfg)
            p.sourceNote = r.text; p.sourceNoteFocus = focus; p.totalGenerationCostUSD += r.cost
            self.plan = p; self.persist()
            let bh = self.busyHandler
            bh("Rewriting the picture ideas to use it…", 0.1)
            try await Pipeline.regeneratePrompts(plan: &p, keepStyle: true, keepWritten: true, config: cfg) { ph, f in bh(ph, 0.1 + f * 0.9) }
            if var cur = self.plan, cur.source == p.source {
                cur.intro.prompt = p.intro.prompt; cur.intro.focal = p.intro.focal
                for i in cur.sections.indices where p.sections.indices.contains(i) && cur.sections[i].id == p.sections[i].id && !cur.sections[i].promptManual {
                    cur.sections[i].prompt = p.sections[i].prompt; cur.sections[i].focal = p.sections[i].focal; cur.sections[i].logicNote = nil
                }
                self.plan = cur; self.persist()
            }
            self.notice = "Every picture idea now uses the picture's " + (focus == .subject ? "subject" : (focus == .building ? "building" : "place")) + ": \(r.text) Ideas you wrote yourself were kept, and pictures already drawn stay until you draw them again."
        }
    }
}
