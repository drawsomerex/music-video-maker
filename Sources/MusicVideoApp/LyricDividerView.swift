// "Divide into parts": cut the lyrics into groups. Every group becomes ONE picture, and Shorts start and end between groups.
import SwiftUI
import MVCore

struct LyricDividerView: View {
    @EnvironmentObject var model: AppModel
    @State private var evenParts = 6
    var scrollable = true            // false only for layout snapshots (ScrollView can't be drawn by ImageRenderer)
    private let tints: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]

    var body: some View {
        let rows = LyricText.rows(model.lyrics)
        let parts = rows.filter(\.startsPart).count
        let custom = LyricText.hasDividers(model.lyrics)
        VStack(alignment: .leading, spacing: 10) {
            // 1 · what you have
            HStack(spacing: 10) {
                Image(systemName: "photo.stack").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rows.isEmpty ? "Add your lyrics first" : (custom ? "\(parts) pictures" : "Automatic")).font(.title3.bold())
                    Text(rows.isEmpty ? "Switch to “Type or paste” and add the words." : (custom ? "You chose where each picture starts." : "The app will choose where each picture starts. Cut the lyrics below to choose yourself."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            // 2 · quick ways to start
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Quick start").font(.callout.weight(.medium))
                    Button { model.dividersFromVerses() } label: { Label("One picture per verse", systemImage: "text.alignleft").lineLimit(1) }
                        .help("Starts a new picture wherever you left a blank line between verses.")
                    Spacer()
                    Button { model.clearDividers() } label: { Label("Start over", systemImage: "arrow.counterclockwise").lineLimit(1) }.disabled(!custom)
                        .help("Removes all your cuts so the app chooses automatically again.")
                }
                HStack(spacing: 8) {
                    Text("Or").font(.callout)
                    Stepper(value: $evenParts, in: 2...20) { Text("\(evenParts) equal pictures").font(.callout).monospacedDigit().lineLimit(1).fixedSize() }
                        .help("Choose how many pictures you want.")
                    Button("Divide") { model.divideEvenly(evenParts) }
                        .help("Cuts the lyrics into \(evenParts) groups of about the same length. You can still change any cut below.")
                    Spacer()
                }
            }
            .disabled(rows.isEmpty)
            // 3 · the lyrics, with a cut line between every two lines
            Group { if scrollable { ScrollView { list(rows) } } else { list(rows) } }
            .background(RoundedRectangle(cornerRadius: 14).fill(.background.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.25)))
        }
    }

    func list(_ rows: [LyricText.Row]) -> some View {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { r in
                        let partNo = rows[0...r.index].filter(\.startsPart).count
                        let tint = tints[(partNo - 1) % tints.count]
                        if r.index == 0 {
                            header(partNo: 1, tint: tint, lines: lineCount(rows, from: 0), joinable: false, index: 0)
                        } else if r.startsPart {
                            header(partNo: partNo, tint: tint, lines: lineCount(rows, from: r.index), joinable: true, index: r.index)
                        } else {
                            Button { model.toggleDivider(before: r.index) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "scissors").font(.caption2)
                                    VStack { Divider() }
                                    Text("cut here").font(.caption2)
                                    VStack { Divider() }
                                }
                                .foregroundStyle(.tertiary).frame(height: 18).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Click to cut the lyrics here. The lines below this cut will start a new picture.")
                        }
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 5)
                            Text(r.text).font(.system(size: 15, design: .rounded)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 3).background(tint.opacity(0.08))
                    }
                }
                .padding(10)
    }

    func lineCount(_ rows: [LyricText.Row], from i: Int) -> Int { 1 + rows.dropFirst(i + 1).prefix { !$0.startsPart }.count }

    /// The coloured bar where a picture starts. Click it (except the first) to join this picture with the one above.
    @ViewBuilder func header(partNo: Int, tint: Color, lines: Int, joinable: Bool, index: Int) -> some View {
        let label = HStack(spacing: 8) {
            Image(systemName: "photo").font(.caption)
            Text("Picture \(partNo)").font(.callout.weight(.bold))
            Text("· \(lines) \(lines == 1 ? "line" : "lines")").font(.callout)
            Spacer()
            if joinable { Label("click to join with the picture above", systemImage: "arrow.up.to.line").font(.caption) }
        }
        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint))
        .padding(.top, index == 0 ? 0 : 6).padding(.bottom, 3)
        if joinable {
            Button { model.toggleDivider(before: index) } label: { label }.buttonStyle(.plain)
                .help("Click to remove this cut, so these lines share the same picture as the lines above.")
        } else { label }
    }
}
