// The YouTube thumbnail and description made beside a finished video: a look at the thumbnail, and buttons that copy each field for YouTube Studio.
import SwiftUI
import AppKit
import MVCore

struct YouTubeFilesRow: View {
    let files: (thumbnail: URL, description: URL)?
    let busy: Bool
    var vertical = false               // a Short: a tall cover and a narrow layout
    var text: Binding<ThumbnailText>? = nil                        // what is written on the thumbnail (nil = no choice, e.g. a Short's cover)
    var auto: (title: String, badge: String?, line: String?) = ("", nil, nil)   // the automatic words, shown as placeholders
    var revision = 0                   // changes when the thumbnail was drawn again
    let remake: () -> Void
    @State private var copied: String?
    @State private var showText = false

    /// The parts of the description file (TITLE / DESCRIPTION / TAGS / HASHTAGS).
    func part(_ name: String) -> String {
        guard let f = files, let text = try? String(contentsOf: f.description, encoding: .utf8) else { return "" }
        let heads = ["TITLE", "DESCRIPTION", "TAGS", "HASHTAGS"]
        var cur = "", out: [String: [String]] = [:]
        for line in text.components(separatedBy: "\n") {
            if let h = heads.first(where: { line.hasPrefix($0) && (line == $0 || line.hasPrefix($0 + " (")) }) { cur = h; continue }
            if !cur.isEmpty { out[cur, default: []].append(line) }
        }
        return (out[name] ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func copy(_ name: String, _ label: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(part(name), forType: .string); copied = label
    }

    @ViewBuilder func copyButtons(_ f: (thumbnail: URL, description: URL)) -> some View {
        Button("Copy title") { copy("TITLE", "Title") }
        Button("Copy description") { copy("DESCRIPTION", "Description") }
        Button("Copy tags") { copy("TAGS", "Tags") }
        Button { NSWorkspace.shared.activateFileViewerSelecting([f.thumbnail, f.description]) } label: { Label("Show in Finder", systemImage: "folder") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("For YouTube", systemImage: "play.rectangle.fill").font(.headline)
                if busy { ProgressView().controlSize(.small); Text("Writing…").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                if let text {
                    Button { showText.toggle() } label: { Label("Thumbnail text", systemImage: "textformat") }.disabled(files == nil)
                        .help("Choose exactly what is written on the thumbnail: the title, the badge and the line under the title — each on or off, in your own words or the app's.")
                        .popover(isPresented: $showText, arrowEdge: .bottom) { ThumbnailTextEditor(text: text, auto: auto).padding(16).frame(width: 420) }
                }
                Button { remake() } label: { Label(files == nil ? (vertical ? "Make the cover & description" : "Make the thumbnail & description") : "Make them again", systemImage: "arrow.clockwise") }.disabled(busy)
                    .help("Makes a 1280×720 thumbnail (the picture with the title on its quieter side) and a description written for YouTube search (title, description, chapters or lyrics, tags, hashtags). Written on this Mac, free.")
            }
            if let f = files {
                HStack(alignment: .top, spacing: 14) {
                    if let img = NSImage(contentsOf: f.thumbnail) {
                        Image(nsImage: img).resizable().aspectRatio(vertical ? 9.0 / 16 : 16.0 / 9, contentMode: .fit).frame(width: vertical ? 84 : 288).clipShape(RoundedRectangle(cornerRadius: 8)).id(revision)
                            .help(vertical ? "The cover: the Short's own opening frame (1080×1920). YouTube lets you pick a frame of a Short as its thumbnail; use this picture as the cover on TikTok or Instagram Reels."
                                           : "The thumbnail (1280×720, under 2 MB). Upload it under “Thumbnail” in YouTube Studio.")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(part("TITLE")).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(part("DESCRIPTION")).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { copyButtons(f) }
                            VStack(alignment: .leading, spacing: 4) { HStack(spacing: 6) { Button("Copy title") { copy("TITLE", "Title") }; Button("Copy description") { copy("DESCRIPTION", "Description") } }
                                                                      HStack(spacing: 6) { Button("Copy tags") { copy("TAGS", "Tags") }; Button { NSWorkspace.shared.activateFileViewerSelecting([f.thumbnail, f.description]) } label: { Label("Show", systemImage: "folder") } } }
                        }.controlSize(.small)
                        if let c = copied { Text("\(c) copied — paste it into YouTube Studio.").font(.caption).foregroundStyle(.green) }
                    }
                }
            }
        }
        .padding(12).frame(maxWidth: 900, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}


/// The dropdown that chooses what is written on the thumbnail. An empty field uses the app's words (shown greyed).
struct ThumbnailTextEditor: View {
    let text: Binding<ThumbnailText>
    let auto: (title: String, badge: String?, line: String?)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the thumbnail says").font(.headline)
            row("Title", show: \.showTitle, words: \.title, placeholder: auto.title, help: "The big words. Empty = the video's title.")
            row("Badge", show: \.showBadge, words: \.badge, placeholder: auto.badge ?? "e.g. 8 HOURS", help: "The small yellow label above the title (shown in capitals).")
            row("Line under the title", show: \.showLine, words: \.line, placeholder: auto.line ?? "e.g. Study · Focus · Relax", help: "A short line under the title.")
            Text("The thumbnail is drawn again as you change these. Leave a field empty to use the app's words.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Use the app's words for all") { text.wrappedValue = ThumbnailText() } }
        }
    }
    func row(_ name: String, show: WritableKeyPath<ThumbnailText, Bool>, words: WritableKeyPath<ThumbnailText, String>, placeholder: String, help: String) -> some View {
        HStack(spacing: 8) {
            Toggle(name, isOn: Binding(get: { text.wrappedValue[keyPath: show] }, set: { text.wrappedValue[keyPath: show] = $0 })).toggleStyle(.checkbox).frame(width: 150, alignment: .leading)
            TextField(placeholder, text: Binding(get: { text.wrappedValue[keyPath: words] }, set: { text.wrappedValue[keyPath: words] = $0 })).textFieldStyle(.roundedBorder)
                .disabled(!text.wrappedValue[keyPath: show])
        }.help(help)
    }
}
