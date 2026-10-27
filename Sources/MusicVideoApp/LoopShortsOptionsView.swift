// The same portrait crop geometry is used here and by LoopVideo.renderShort.
import SwiftUI
import MVCore

struct LoopShortsOptionsView: View {
    @EnvironmentObject var model: AppModel
    let project: LoopProject
    @State private var picture: NSImage?
    var options: LoopShortOptions { project.shortOptions }
    var clip: String { project.clip ?? "" }
    var framing: ShortFraming { options.framing[clip] ?? ShortFraming() }
    func option<T>(_ key: WritableKeyPath<LoopShortOptions, T>) -> Binding<T> {
        Binding(get: { options[keyPath: key] }, set: { value in model.editLoop { $0.shortOptions[keyPath: key] = value } })
    }
    var body: some View {
        DisclosureGroup("Shorts text & framing") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Top text", selection: option(\.heading)) {
                    Text("Song name").tag(ShortHeading.song); Text("My text").tag(ShortHeading.custom); Text("No text").tag(ShortHeading.none)
                }.pickerStyle(.segmented).help("Choose the words shown on the Short without renaming the song.")
                if options.heading == .custom {
                    TextField("Your words instead of the song name", text: Binding(get: { options.text }, set: { text in model.editLoop { $0.shortOptions.text = String(text.prefix(180)) } }), axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3).accessibilityLabel("Custom text on the Short")
                        .help("Up to 180 characters. These words replace the song name on screen.")
                }
                TextField("Lower text (leave empty to hide)", text: Binding(get: { options.subtitle(project: project.shownTitle, playlist: project.tracks.count > 1) }, set: { text in model.editLoop { $0.shortOptions.subtitle = String(text.prefix(180)) } }))
                    .textFieldStyle(.roundedBorder).help("Optional words near the bottom. Clear the field to hide them. This does not change the long video or the song name.")
                Toggle("Fill the whole portrait screen (crop the sides)", isOn: option(\.fillScreen))
                    .help("On: the actual scene fills 9:16, with no blurred bands. Off: fit the whole scene over a blurred background.")
                HStack(alignment: .top, spacing: 16) {
                    cropPreview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frame the scene shown above").font(.callout.weight(.semibold))
                        Text("Move the subject into view. Each scene keeps its own framing.").font(.callout).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { framing.x }, set: { model.setLoopShortFraming(clip: clip, x: $0, y: framing.y) }), in: 0...1, onEditingChanged: drag)
                            .accessibilityLabel("Short framing left to right").help("Move left or right to keep the important part in the full-screen crop.")
                        HStack { Text("Left"); Spacer(); Text("Right") }.font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { framing.y }, set: { model.setLoopShortFraming(clip: clip, x: framing.x, y: $0) }), in: 0...1, onEditingChanged: drag)
                            .accessibilityLabel("Short framing top to bottom").help("Move up or down for a tall source. A widescreen source already fills the portrait height.")
                        HStack { Text("Top"); Spacer(); Text("Bottom") }.font(.caption).foregroundStyle(.secondary)
                        Button("Center the picture") { model.setLoopShortFraming(clip: clip, x: 0.5, y: 0.5) }
                        Button("Preview this Short (5 seconds)") { model.loopPreviewShort() }.buttonStyle(.borderedProminent)
                            .help("Renders the current scene with these words and framing, using the first song. Free, on this Mac.")
                    }
                }
                Text("Full-screen cropping removes the sides. Sharp 2K clips give the crop more detail. The song and filenames keep their original names.").font(.callout).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
        .disabled(model.loopJob != nil)
        .task(id: clip) {
            if let dir = model.loopDir, let url = LoopVideo.clipThumbnail(clip, dir: dir) { picture = NSImage(contentsOf: url) } else { picture = nil }
        }
    }
    func drag(_ active: Bool) {
        if active { model.beginTimelineDrag("Frame looping Short") }
        else { model.timelineDragging = false; model.persistLoop() }
    }
    var cropPreview: some View {
        ZStack {
            Color.black
            if let picture {
                GeometryReader { geometry in
                    let canvas = geometry.size
                    let rect = LoopShortOptions.crop(source: picture.size, canvas: canvas, framing: framing)
                    if options.fillScreen {
                        Image(nsImage: picture).resizable().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: canvas.height - rect.midY)
                    } else {
                        Image(nsImage: picture).resizable().scaledToFit().frame(width: canvas.width, height: canvas.height)
                    }
                }
            }
            VStack {
                let song = project.tracks.first?.title ?? "Song"
                Text(options.title(song: song)).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center).shadow(radius: 3).padding(.top, 40)
                Spacer()
                Text(options.subtitle(project: project.shownTitle, playlist: project.tracks.count > 1)).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center).shadow(radius: 3).padding(.bottom, 45)
            }.foregroundStyle(.white).padding(.horizontal, 12)
        }.frame(width: 160, height: 284).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Portrait framing preview").help("Framing guide for the current scene. Preview this Short shows the actual video and text with sound.")
    }
}
