// The YouTube thumbnail and description made beside a finished video: a look at the thumbnail, and buttons that copy each field for YouTube Studio.
import SwiftUI
import AppKit

struct YouTubeFilesRow: View {
    let files: (thumbnail: URL, description: URL)?
    let busy: Bool
    let remake: () -> Void
    @State private var copied: String?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("For YouTube", systemImage: "play.rectangle.fill").font(.headline)
                if busy { ProgressView().controlSize(.small); Text("Writing…").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button { remake() } label: { Label(files == nil ? "Make the thumbnail & description" : "Make them again", systemImage: "arrow.clockwise") }.disabled(busy)
                    .help("Makes a 1280×720 thumbnail (the picture with the title on its quieter side) and a description written for YouTube search (title, description, chapters or lyrics, tags, hashtags). Written on this Mac, free.")
            }
            if let f = files {
                HStack(alignment: .top, spacing: 14) {
                    if let img = NSImage(contentsOf: f.thumbnail) {
                        Image(nsImage: img).resizable().aspectRatio(16.0 / 9, contentMode: .fit).frame(width: 288).clipShape(RoundedRectangle(cornerRadius: 8))
                            .help("The thumbnail (1280×720, under 2 MB). Upload it under “Thumbnail” in YouTube Studio.")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(part("TITLE")).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(part("DESCRIPTION")).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                        HStack(spacing: 6) {
                            Button("Copy title") { copy("TITLE", "Title") }
                            Button("Copy description") { copy("DESCRIPTION", "Description") }
                            Button("Copy tags") { copy("TAGS", "Tags") }
                            Button { NSWorkspace.shared.activateFileViewerSelecting([f.thumbnail, f.description]) } label: { Label("Show in Finder", systemImage: "folder") }
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
