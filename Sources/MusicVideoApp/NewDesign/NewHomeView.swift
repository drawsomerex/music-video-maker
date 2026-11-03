// New Design home: two equal ways to start, then every project, searchable. (Design 2b and the empty first home in 3j.)
import SwiftUI
import MVCore

struct NewHomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    @State private var items: [ProjectInfo] = []
    @State private var loaded = false
    @State private var search = ""
    @State private var kind = 0                        // 0 all, 1 music videos, 2 looping videos
    @State private var confirmTrash: ProjectInfo?

    var shown: [ProjectInfo] {
        var l = items
        if kind == 1 { l = l.filter { $0.kind == .lyric } } else if kind == 2 { l = l.filter { $0.kind == .loop } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { l = l.filter { $0.title.lowercased().contains(q) } }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 20) {
                    startCard("New music video", "A song with its lyrics on screen, a picture for each part, and Shorts cut from it.", icon: "film") { newMusicVideo() }
                    startCard("New looping video", "Up to 100 songs over scenes that loop seamlessly, from 1 to 12 hours long.", icon: "repeat") { newLoopingVideo() }
                }
                Hairline()
                if loaded && items.isEmpty { emptyHome } else { projects }
            }
            .padding(.horizontal, 36).padding(.vertical, 28).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .onAppear { reload() }
        .confirmationDialog("Move “\(confirmTrash?.title ?? "")” to the Trash?", isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } }), titleVisibility: .visible, presenting: confirmTrash) { p in
            Button("Move to Trash", role: .destructive) { trash(p) }
            Button("Keep it", role: .cancel) {}
        } message: { p in
            Text("This moves the folder “\(p.trashTarget(root: model.config.projectsRoot).lastPathComponent)” to the Trash: the song, its pictures, clips and finished videos. You can put it back from the Trash. Copies in your Pictures folder stay, and what it cost stays counted.")
        }
    }

    func startCard(_ title: String, _ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Classical.accent700).frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Classical.heading(24)).foregroundStyle(Classical.text)
                    Text(text).font(Classical.body(13)).foregroundStyle(Classical.neutral700).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.accent, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var projects: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Projects").font(Classical.heading(30))
                Text("\(items.count)").font(Classical.body(13).monospacedDigit()).foregroundStyle(Classical.neutral600)
                Spacer()
                HStack(spacing: 0) { seg("All", 0); seg("Music videos", 1); seg("Looping videos", 2) }
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Classical.neutral600)
                    TextField("Search by title", text: $search).textFieldStyle(.plain).font(Classical.body(13))
                }.padding(.horizontal, 8).padding(.vertical, 5).frame(width: 190)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                Button("Open a folder…") { model.chooseProject(); afterOpen() }.buttonStyle(.classicalGhost)
                    .help("Open a project that is not in your main folder (for example on another disk).")
            }
            if shown.isEmpty { Text("Nothing matches.").font(Classical.body(13)).foregroundStyle(Classical.neutral600) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 24, alignment: .top)], alignment: .leading, spacing: 22) {
                ForEach(shown) { row($0) }
            }
        }
    }

    func seg(_ t: String, _ k: Int) -> some View {
        Button { kind = k } label: {
            Text(t).font(Classical.body(12)).foregroundStyle(kind == k ? Classical.accent700 : Classical.neutral700)
                .padding(.horizontal, 10).padding(.vertical, 5).background(kind == k ? Classical.accent100 : .clear)
        }.buttonStyle(.plain)
    }

    func row(_ p: ProjectInfo) -> some View {
        Button { model.openProject(p.folder); afterOpen() } label: {
            HStack(alignment: .top, spacing: 12) {
                Color(hex: 0xE4E2E2).frame(width: 118, height: 66)
                    .overlay { if let t = p.thumbnail, FileManager.default.fileExists(atPath: t.path) { Thumb(file: t).scaledToFill() } else { Image(systemName: p.kind == .loop ? "repeat" : "music.note").foregroundStyle(Classical.neutral500) } }
                    .clipped().overlay(Rectangle().stroke(Classical.divider, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.kind == .loop ? "LOOPING VIDEO" : "MUSIC VIDEO").font(Classical.body(9).weight(.semibold)).tracking(0.8).foregroundStyle(Classical.accent700)
                    Text(p.title).font(Classical.heading(18)).foregroundStyle(Classical.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text("Changed " + p.modified.formatted(.dateTime.day().month(.abbreviated)) + (p.spentUSD > 0 ? " · " + OpenRouter.formatUSD(p.spentUSD) : "")).font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
                    Text(p.video != nil ? "Video made" : p.detail).font(Classical.body(11)).foregroundStyle(Classical.neutral600).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([p.video ?? p.folder]) }
            Button("Move to Trash…", role: .destructive) { confirmTrash = p }
        }
        .help("Open this project. Right-click for Show in Finder and Trash.")
    }

    var emptyHome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects").font(Classical.heading(30))
            Text("Your projects will appear here.").font(Classical.body(14)).foregroundStyle(Classical.neutral700)
            HStack(spacing: 14) {
                Button("Open a folder…") { model.chooseProject(); afterOpen() }.buttonStyle(.classicalGhost)
                Text("Already made some elsewhere?").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                Button("Quick guide") { model.showGuide = true }.buttonStyle(.classicalGhost)
            }
        }.padding(.top, 8)
    }

    // MARK: actions
    func reload() { items = ProjectLibrary.scan(root: model.config.projectsRoot, extra: model.recents); loaded = true }

    func newMusicVideo() {
        if model.stage == .loop { model.closeLoop(); guard model.stage != .loop else { return } }
        else if model.hasProject { model.reset(); guard !model.hasProject else { return } }
        UserDefaults.standard.set(0, forKey: "startKind")
        nd.route = .song
    }
    func newLoopingVideo() {
        if model.hasProject { model.reset(); guard !model.hasProject else { return } }
        UserDefaults.standard.set(1, forKey: "startKind")
        nd.route = .song
    }
    func afterOpen() {
        guard model.hasProject || model.loopProject != nil else { return }
        nd.route = .pictures
    }
    func trash(_ p: ProjectInfo) {
        do {
            try FileManager.default.trashItem(at: p.trashTarget(root: model.config.projectsRoot), resultingItemURL: nil)
            model.recents.removeAll { $0.standardizedFileURL == p.folder.standardizedFileURL }
            UserDefaults.standard.set(model.recents.map(\.path), forKey: "recentProjects")
            items.removeAll { $0.id == p.id }
        } catch { model.errorMessage = "Couldn't move it to the Trash: \(error.localizedDescription)" }
    }
}

// MARK: stages not yet redone wrap the original screens (replaced one by one)
struct NewShortsStage: View { @EnvironmentObject var model: AppModel; var body: some View { if model.stage == .loop { LoopView(part: .shorts) } else { ShortsView() } } }
struct NewSetupView: View { var body: some View { NativeSetupView() } }
