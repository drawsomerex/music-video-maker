// Shorts editor: lyric picker, waveform fine-tuning, style options and live preview.
import SwiftUI
import MVCore

func clock(_ s: Double) -> String { String(format: "%d:%04.1f", Int(s) / 60, s - Double(Int(s) / 60 * 60)) }
func parseClock(_ s: String) -> Double? {
    let p = s.split(separator: ":").map(String.init)
    if p.count == 2, let m = Double(p[0]), let x = Double(p[1]) { return m * 60 + x }
    return Double(s)
}

/// YouTube Shorts: pick lyrics, fine-tune the cut against the waveform, audition it, render a 1080×1920 clip.
struct ShortsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HSplitView {
            list.frame(minWidth: 170, idealWidth: 220, maxWidth: 300)
            Group {
                if let c = model.currentShort { ShortEditor(clip: c).id(c.id) }
                else { empty }
            }.frame(minWidth: 520)
        }
        .onAppear { if model.selectedShort == nil { model.selectedShort = model.plan?.shorts.first?.id } }
    }

    var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.portrait.on.rectangle.portrait").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Make short clips for YouTube Shorts").font(.title2.bold())
            Text("Short vertical clips for phones, up to 3 minutes each. Let the app cut your song into 4 to 7 clips of about 30 seconds, or choose the exact lines yourself.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button { model.autoMakeShorts() } label: { Label("Cut my song into clips for me", systemImage: "sparkles").padding(.horizontal, 8) }.buttonStyle(.borderedProminent).controlSize(.large)
                    .help("The app picks 4 to 7 clips of about 30 seconds, cut at natural pauses between verses. You can still change each one.")
                Button { model.newShort() } label: { Label("Choose the lines myself", systemImage: "plus").padding(.horizontal, 8) }.controlSize(.large)
                    .help("Starts one clip of about 30 seconds that you shape by picking lyric lines.")
                Button { model.newWholeSong() } label: { Label("Whole song", systemImage: "music.note.list").padding(.horizontal, 8) }.controlSize(.large)
                    .help("Turns the whole song into one vertical video. Songs over 3 minutes are split into the fewest equal parts, because Shorts can be at most 3 minutes.")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var list: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.selectedShort }, set: { model.selectedShort = $0; model.stopPlayback(); model.refreshPreview(at: 1) })) {
                ForEach(model.plan?.shorts ?? []) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("\(clock(c.start)) – \(clock(c.end)) · \(Int(c.duration)) s").font(.caption).foregroundStyle(.secondary)
                    }.tag(c.id).contextMenu { Button("Delete", role: .destructive) { model.deleteShort(c.id) } }
                }
            }.listStyle(.sidebar)
            Divider()
            VStack(spacing: 8) {
                HStack {
                    Menu {
                        Button("Auto-make 4–7 Shorts (~30 s at stanza breaks)") { model.autoMakeShorts(replaceExisting: true) }
                        Button("New Short (30 s from the lyrics)") { model.newShort() }
                        Button("Whole song (split into parts if over 3:00)") { model.newWholeSong() }
                    } label: { Label("Add a clip", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                    .help("Add another clip: cut the song automatically, choose lines yourself, or use the whole song.")
                    Spacer()
                    if let id = model.selectedShort { Button(role: .destructive) { model.deleteShort(id) } label: { Image(systemName: "trash") }
                        .help("Deletes the selected clip from this list. Videos you already made are kept.") }
                }
                if let shorts = model.plan?.shorts, shorts.count > 1 {
                    Button {
                        model.renderAllShorts()
                    } label: {
                        Label("Make all \(shorts.count) clips", systemImage: "film.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Creates every clip in the list, one after another.")
                    .disabled(model.shortProgress != nil)
                }
            }.padding(10)
        }
    }
}

/// Colours and words for how long a Short is: orange too short, green ideal, red long.
enum ShortLength {
    static func color(_ d: Double) -> Color {
        if d < 5 { return .orange }
        if d < 15 { return .secondary }
        if d <= 60 { return .green }
        return Color(red: 0.86, green: 0.11, blue: 0.2)
    }
    static func message(_ d: Double) -> String {
        if d >= ShortClip.maxDuration - 0.05 { return "At the 3:00 limit for a Short." }
        if d < 5 { return "Too short for a compelling Short." }
        if d < 15 { return "A little short. 15 to 60 seconds works best." }
        if d <= 60 { return "Ideal length for a Short." }
        return "Longer than 60 seconds. YouTube allows up to 3 minutes for some uploads."
    }
}

/// "34.2 s / 60 s" pill shown on the selection.
struct LengthBadge: View {
    let duration: Double
    var body: some View {
        Text(String(format: "%.1f s / 60 s", duration)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(ShortLength.color(duration).opacity(0.92)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .help("The length of this Short. Green is the ideal range, orange is too short, red is longer than 60 seconds.")
    }
}
