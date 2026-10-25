// The picture options both workflows share, so they look and work the same: the subject photo, the source image, what each new picture keeps,
// and the weather and time of day.
import SwiftUI
import MVCore

/// "Subject": a photo of who or what the pictures should show (redrawn in the style).
struct SubjectRow: View {
    let file: URL?
    let open: () -> Void
    let remove: () -> Void
    var disabled = false
    var body: some View {
        HStack(spacing: 8) {
            Text("Subject").font(.callout.weight(.semibold))
            if let u = file { Thumb(file: u).frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 5)) }
            Button(file == nil ? "Choose or search…" : "Change…", action: open).disabled(disabled)
                .help("Optional: a photo of the person, animal, object or place the pictures should show. It is redrawn in the art style; any photo works.")
            if file != nil { Button("Remove", action: remove).disabled(disabled) }
            Text(file == nil ? "optional: a photo of who or what the pictures should show" : "the pictures drawn show this subject").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// "Source image", "Next picture keeps", and the weather and time of day.
struct SeriesRows: View {
    var sourceLabel: some View {
        HStack(spacing: 10) {
            Text("Source image").font(.callout.weight(.semibold))
            if let u = source { Thumb(file: u).frame(width: 72, height: 41).clipShape(RoundedRectangle(cornerRadius: 5)) }
        }
    }
    @ViewBuilder var sourceButtons: some View {
        if let u = useCurrent { Button("Use the current picture", action: u).disabled(disabled).help("Makes the picture shown the source image.") }
        Button("Choose…", action: choose).disabled(disabled).help("Choose a picture of your own as the source image.")
        if let c = clear { Button("Clear", action: c).disabled(disabled).help("No fixed source: each picture follows the picture before it.") }
    }
    var keepsLabel: some View { Text("Next picture keeps").font(.callout.weight(.semibold)) }
    var keepsPicker: some View {
        Picker("", selection: $focus) { ForEach(NextFocus.allCases, id: \.self) { Text($0.name).tag($0) } }
            .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(disabled)
    }
    var weatherPicker: some View {
        HStack(spacing: 8) {
            Text("Weather").font(.callout.weight(.semibold))
            Picker("", selection: $weather) { ForEach(LoopWeather.allCases, id: \.self) { Text($0.name).tag($0) } }.labelsHidden().fixedSize()
        }
    }
    var timePicker: some View {
        HStack(spacing: 8) {
            Text("Time of day").font(.callout.weight(.semibold))
            Picker("", selection: $time) { ForEach(LoopTimeOfDay.allCases, id: \.self) { Text($0.name).tag($0) } }.labelsHidden().fixedSize()
        }
    }

    let source: URL?
    let sourceNote: String
    var useCurrent: (() -> Void)? = nil
    let choose: () -> Void
    var clear: (() -> Void)? = nil
    @Binding var focus: NextFocus
    @Binding var weather: LoopWeather
    @Binding var time: LoopTimeOfDay
    var action: AnyView? = nil
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // each row lays itself out on one line when there is room, and wraps neatly when there is not
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { sourceLabel; sourceButtons; Text(sourceNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) { sourceLabel; Spacer(minLength: 0) }
                    HStack(spacing: 8) { sourceButtons; Spacer(minLength: 0) }
                    Text(sourceNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { keepsLabel; keepsPicker; if let a = action { a }; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) { keepsLabel; keepsPicker; if let a = action { a } }
            }
            if focus != .subject {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { weatherPicker; timePicker; Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 4) { weatherPicker; timePicker }
                }
                .disabled(disabled)
                .help("For landscapes: the weather and time of day of the pictures drawn from now on. “As the scene says” leaves it to the words; your scene words always win.")
            }
            Text(focus == .subject ? "The same subject, moved to a completely different place and seen from another angle."
                 : (focus == .building ? "The same building, kept true to life, from another angle at another time, in other weather or another season."
                                       : "The same place from a different angle, with what the words describe: another time of day, weather, season, or something new."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
