// Projects: every music video and looping video in your main folder (and ones opened from elsewhere), newest first.
// Search, show only one kind, open, show in Finder, or move to the Trash.
import SwiftUI
import MVCore

struct ProjectsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ProjectInfo] = []
    @State private var loading = true
    @State private var search = ""
    @State private var kind = 0                  // 0 = all, 1 = music videos, 2 = looping videos
    @State private var sortByName = false
    @State private var confirmTrash: ProjectInfo?

    var shown: [ProjectInfo] {
        var l = items
        if kind == 1 { l = l.filter { $0.kind == .lyric } } else if kind == 2 { l = l.filter { $0.kind == .loop } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { l = l.filter { $0.title.lowercased().contains(q) } }
        return sortByName ? l.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } : l
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Projects").font(.title2.bold())
                Text("\(items.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Open a folder…") { dismiss(); model.chooseProject() }.help("Open a project that is not in your main folder (for example on another disk).")
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
            HStack(spacing: 10) {
                TextField("Search by title", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                Picker("", selection: $kind) { Text("All").tag(0); Text("Music videos").tag(1); Text("Looping videos").tag(2) }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Spacer()
                Picker("Sort", selection: $sortByName) { Text("Newest first").tag(false); Text("By name").tag(true) }.fixedSize()
            }.padding(.horizontal, 20).padding(.bottom, 10)
            Divider()
            if loading { ProgressView("Looking for your projects…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if shown.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(items.isEmpty ? "No projects yet in \((model.config.projectsRoot.path as NSString).abbreviatingWithTildeInPath)." : "Nothing matches.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                        ForEach(shown) { card($0) }
                    }.padding(20)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 960, minHeight: 440, idealHeight: 680)
        .onAppear { reload() }
        .confirmationDialog("Move “\(confirmTrash?.title ?? "")” to the Trash?", isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } }), titleVisibility: .visible, presenting: confirmTrash) { p in
            Button("Move to Trash", role: .destructive) { trash(p) }
            Button("Keep it", role: .cancel) {}
        } message: { p in
            Text("This moves the folder “\(p.trashTarget(root: model.config.projectsRoot).lastPathComponent)” to the Trash: the song, its pictures, clips and finished videos. You can put it back from the Trash. Copies in your Pictures folder stay, and what it cost stays counted in “All songs together”.")
        }
    }

    func card(_ p: ProjectInfo) -> some View {
        let open = model.loopDir?.standardizedFileURL == p.folder.standardizedFileURL || model.workDir?.standardizedFileURL == p.folder.standardizedFileURL
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // the card decides the width; the picture fills it and is cropped (it never pushes the card wider)
                Color.secondary.opacity(0.15).frame(height: 150).frame(maxWidth: .infinity)
                    .overlay { if let t = p.thumbnail, FileManager.default.fileExists(atPath: t.path) { Thumb(file: t).scaledToFill() } else { Image(systemName: p.kind == .loop ? "repeat" : "music.note").font(.system(size: 28)).foregroundStyle(.secondary) } }
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                Text(p.kind == .loop ? "LOOPING" : "MUSIC VIDEO").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(p.kind == .loop ? Color.teal : Color.accentColor)).foregroundStyle(.white).padding(6)
                if open { Text("OPEN NOW").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 3).background(Capsule().fill(.green)).foregroundStyle(.white).padding(6).frame(maxWidth: .infinity, alignment: .topTrailing) }
            }
            Text(p.title).font(.headline).lineLimit(1).truncationMode(.tail)
            Text(p.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("Changed " + p.modified.formatted(date: .abbreviated, time: .shortened) + (p.spentUSD > 0 ? " · " + OpenRouter.formatUSD(p.spentUSD) : ""))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
            Label(p.video != nil ? "Video made" : "No video yet", systemImage: p.video != nil ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption).foregroundStyle(p.video != nil ? .green : .secondary)
            HStack(spacing: 6) {
                Button { dismiss(); model.openProject(p.folder) } label: { Label("Open", systemImage: "arrow.up.forward.app") }.buttonStyle(.borderedProminent).disabled(open)
                Button { NSWorkspace.shared.activateFileViewerSelecting([p.video ?? p.folder]) } label: { Image(systemName: "folder") }.help("Show in Finder" + (p.video != nil ? " (the finished video is selected)" : ""))
                Spacer()
                Button(role: .destructive) { confirmTrash = p } label: { Image(systemName: "trash") }.disabled(open).help(open ? "Close it first." : "Move this project to the Trash (you can put it back).")
            }.controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(open ? Color.green.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: open ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !open { dismiss(); model.openProject(p.folder) } }
        .help("Double-click to open.")
    }

    /// Reading the projects is quick (a small file each), so the list is there the moment the window opens.
    func reload() {
        items = ProjectLibrary.scan(root: model.config.projectsRoot, extra: model.recents)
        loading = false
    }

    func trash(_ p: ProjectInfo) {
        let target = p.trashTarget(root: model.config.projectsRoot)
        do {
            try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            model.recents.removeAll { $0.standardizedFileURL == p.folder.standardizedFileURL }
            UserDefaults.standard.set(model.recents.map(\.path), forKey: "recentProjects")
            items.removeAll { $0.id == p.id }
        } catch { model.errorMessage = "Couldn't move it to the Trash: \(error.localizedDescription)" }
    }
}
