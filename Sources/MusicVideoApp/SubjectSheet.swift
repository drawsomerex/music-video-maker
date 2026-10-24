// The subject picture: a photo of who or what the drawn pictures should show (redrawn in the chosen style). Choose your own or search for one.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

struct SubjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: URL?
    let set: (URL) -> Void
    let remove: () -> Void
    @State private var query = ""
    @State private var hits: [SubjectHit] = []
    @State private var searching = false
    @State private var searched = false
    @State private var fetching: String?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subject picture").font(.title2.bold())
            Text("A photo of the person, animal, object or place the pictures should show. Every picture drawn from now on shows this subject, redrawn in the art style; the photo itself never appears in the video. Any photo works, since it is redrawn.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                    if let c = current, let img = NSImage(contentsOf: c) { Image(nsImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8)) }
                    else { Text("No subject").font(.callout).foregroundStyle(.secondary) }
                }.frame(width: 150, height: 100)
                VStack(alignment: .leading, spacing: 8) {
                    Button { chooseFile() } label: { Label("Choose a photo from my Mac…", systemImage: "photo") }
                    if current != nil { Button(role: .destructive) { remove(); dismiss() } label: { Label("Stop using a subject", systemImage: "xmark.circle") } }
                }
                Spacer()
            }
            Divider()
            HStack(spacing: 8) {
                TextField("Search for a subject, e.g. highland cow, lighthouse, red fox", text: $query).textFieldStyle(.roundedBorder).onSubmit { search() }
                Button { search() } label: { Label("Search", systemImage: "magnifyingglass") }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            ZStack {
                if searching { ProgressView("Searching…") }
                else if hits.isEmpty { Text(searched ? "Nothing found. Try other words." : "Search Openverse and Wikimedia Commons for a photo of your subject, then click it.").foregroundStyle(.secondary) }
                else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 10)], spacing: 10) {
                            ForEach(hits) { h in
                                Button { pick(h) } label: {
                                    ZStack {
                                        AsyncImage(url: h.thumb) { $0.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.06) }
                                            .frame(height: 110).frame(maxWidth: .infinity).clipped()
                                        if fetching == h.id { Color.black.opacity(0.5); ProgressView().controlSize(.small) }
                                    }.clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).help(h.title.isEmpty ? h.source : "\(h.title) (\(h.source))").disabled(fetching != nil)
                            }
                        }.padding(2)
                    }
                }
            }.frame(minHeight: 300, maxHeight: .infinity)
            if let f = failure { Label(f, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(22).frame(minWidth: 720, idealWidth: 860, minHeight: 600, idealHeight: 680)
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
    func chooseFile() {
        let o = NSOpenPanel(); o.allowedContentTypes = [.image]; o.message = "Choose a photo of the subject"
        if o.runModal() == .OK, let u = o.url { set(u); dismiss() }
    }
}

extension AppModel {
    /// Copies a subject photo into `dir` under a fresh name and returns the name.
    func copySubject(_ url: URL, into dir: URL) -> String? {
        let name = "subject-\(Int(Date().timeIntervalSince1970)).\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased())"
        do { try FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(name)); return name } catch { errorMessage = "Couldn't use that photo: \(error.localizedDescription)"; return nil }
    }
    func setLoopSubject(_ url: URL) { guard let d = loopDir, let n = copySubject(url, into: d) else { return }; editLoop { $0.subject = n } }
    func setSongSubject(_ url: URL) {
        guard let w = workDir, let n = copySubject(url, into: w), var p = plan else { return }
        checkpoint("Choose subject picture"); p.subjectPicture = n; plan = p; persist()
    }
    func removeSongSubject() { guard var p = plan else { return }; checkpoint("Remove subject picture"); p.subjectPicture = nil; plan = p; persist() }
}
