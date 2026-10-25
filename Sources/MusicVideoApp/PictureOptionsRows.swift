// The picture options both workflows share, so they look and work the same: one picture to base the pictures on (yours, found online, or the
// current one), what to keep from it (the place, the building or the subject), and the weather and time of day. Every picture shown here can be
// opened full screen and zoomed (click it).
import SwiftUI
import MVCore

/// A small picture that opens full screen when clicked.
struct ZoomableThumb: View {
    let file: URL
    var width: CGFloat = 72, height: CGFloat = 41
    var body: some View {
        Thumb(file: file).frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottomTrailing) { Image(systemName: "plus.magnifyingglass").font(.caption2.weight(.bold)).padding(3).background(Circle().fill(.black.opacity(0.55))).foregroundStyle(.white).padding(2) }
            .contentShape(Rectangle())
            .onTapGesture { FullScreenPlayer.showImage(file, title: file.lastPathComponent) }
            .help("Click to see it full screen and zoom in.")
            .accessibilityAddTraits(.isButton).accessibilityLabel("Picture. Opens full screen.")
    }
}

struct ReferenceRows: View {
    let reference: URL?
    let note: String                           // what the reference does (or that there is none)
    var read: String? = nil                    // what was read from it, shown under it
    var useCurrent: (() -> Void)? = nil
    let choose: () -> Void
    let find: () -> Void
    var remove: (() -> Void)? = nil
    @Binding var focus: NextFocus
    @Binding var weather: LoopWeather
    @Binding var time: LoopTimeOfDay
    var action: AnyView? = nil
    var disabled = false

    var title: some View {
        HStack(spacing: 10) {
            Text("Picture to base it on").font(.callout.weight(.semibold))
            if let u = reference { ZoomableThumb(file: u) }
        }
    }
    @ViewBuilder var buttons: some View {
        if let u = useCurrent { Button("Use the current picture", action: u).disabled(disabled).help("Bases the new pictures on the picture shown.") }
        Button("Choose from my Mac…", action: choose).disabled(disabled).help("Choose a picture or photo of your own.")
        Button("Find online…", action: find).disabled(disabled).help("Search for a photo (it is always redrawn, never copied).")
        if let r = remove { Button("Remove", action: r).disabled(disabled) }
    }
    var keeps: some View {
        HStack(spacing: 10) {
            Text("Keep from it").font(.callout.weight(.semibold))
            Picker("", selection: $focus) { ForEach(NextFocus.allCases, id: \.self) { Text($0.name).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(disabled)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // each row on one line when there is room, wrapped neatly when there is not
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { title; buttons; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) { title; HStack(spacing: 8) { buttons; Spacer(minLength: 0) } }
                VStack(alignment: .leading, spacing: 4) { title; VStack(alignment: .leading, spacing: 4) { buttons } }
            }
            Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let r = read { Label(r, systemImage: "text.viewfinder").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { keeps; if let a = action { a }; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) { keeps; if let a = action { a } }
            }
            if focus != .subject {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { weatherPicker; timePicker; Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 4) { weatherPicker; timePicker }
                }
                .disabled(disabled)
                .help("For landscapes: the weather and time of day of the pictures drawn from now on. “As the scene says” leaves it to the words; your words always win.")
            }
            Text(focus == .subject ? "The place: anywhere the words say. The subject (a creature, person or thing) stays the same, from a new angle and in a new pose."
                 : (focus == .building ? "The building stays true to life; it is seen from another angle, at another time, in other weather or another season."
                                       : "The place stays the same; it is seen from a different angle, with what the words describe (another time, weather or season)."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
