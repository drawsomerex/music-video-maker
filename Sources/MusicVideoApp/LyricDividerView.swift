// "Divide into parts": click between lyric lines to choose which lines belong together. Each part becomes one picture, and Shorts begin and end at part edges.
import SwiftUI
import MVCore

struct LyricDividerView: View {
    @EnvironmentObject var model: AppModel
    private let tints: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]

    var body: some View {
        let rows = LyricText.rows(model.lyrics)
        let parts = rows.filter(\.startsPart).count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(model.lyrics.isEmpty ? "Add your lyrics first" : (LyricText.hasDividers(model.lyrics) ? "\(parts) parts → \(parts) pictures" : "Automatic: the app divides the song itself"), systemImage: "scissors")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button("Use my verse breaks") { model.dividersFromVerses() }
                    .help("Starts a new part wherever you left a blank line between verses. A quick starting point; then adjust it below.")
                Button("Clear my parts") { model.clearDividers() }.disabled(!LyricText.hasDividers(model.lyrics))
                    .help("Removes your dividers so the app chooses the parts automatically again.")
            }
            Text("Click the scissors between two lines to start a new part there. Lines of the same part share one picture, so group lines that are about the same thing. Click again to join them back together.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { _, r in
                        let partNo = rows[0...r.index].filter(\.startsPart).count          // 1-based
                        let tint = tints[(partNo - 1) % tints.count]
                        if r.startsPart && r.index > 0 { Divider().padding(.vertical, 4) }
                        if r.startsPart {
                            HStack(spacing: 8) {
                                Text("Part \(partNo)").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(tint))
                                Text("\(rows.dropFirst(r.index).prefix { !($0.startsPart && $0.index != r.index) }.count) lines — one picture").font(.caption).foregroundStyle(.secondary)
                                if r.index > 0 {
                                    Spacer()
                                    Button { model.toggleDivider(before: r.index) } label: { Label("Join with the part above", systemImage: "arrow.up.to.line") }
                                        .buttonStyle(.borderless).font(.caption)
                                        .help("Removes the divider above this line, so these lines share the same picture as the part above.")
                                }
                            }.padding(.top, r.index == 0 ? 0 : 2).padding(.bottom, 3)
                        } else if r.blankBefore {
                            Color.clear.frame(height: 4)
                        }
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4)
                            Text(r.text).font(.system(size: 15, design: .rounded)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            if !r.startsPart {
                                Button { model.toggleDivider(before: r.index) } label: { Image(systemName: "scissors") }
                                    .buttonStyle(.bordered).controlSize(.small)
                                    .help("Start a new part (a new picture) at this line.")
                            }
                        }
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.07))
                    }
                }
                .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(.background.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.25)))
        }
    }
}
