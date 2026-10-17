// Windows opened from the Pictures screen's buttons: the song description and the art style (instead of hidden drop-downs).
import SwiftUI
import MVCore

struct DescriptionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) { Image(systemName: "text.alignleft").font(.title).foregroundStyle(.tint); Text("Setting and song description").font(.title2.bold()) }
            Text("The app wrote this from your lyrics. Every picture idea is built from it, so if you change it, press “Make new picture ideas” afterwards.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Setting and theme for every picture").font(.subheadline.weight(.medium))
                TextField("e.g. Brightly lit colonial Philadelphia (optional)", text: Binding(get: { model.plan?.setting ?? "" }, set: { model.setSetting($0) }))
                    .textFieldStyle(.roundedBorder).controlSize(.large)
                    .help("Every picture idea states this setting and follows it. After changing it, press “Make new picture ideas”.")
            }
            Text("What the song is about").font(.subheadline.weight(.medium))
            TextEditor(text: Binding(get: { model.plan?.description ?? "" }, set: { model.setDescription($0) }))
                .font(.body).scrollContentBackground(.hidden).padding(8)
                .frame(height: 170).background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .help("You can edit this. Every picture idea is built from it.")
            HStack(spacing: 10) {
                Button { model.redescribe() } label: { Label("Write it again", systemImage: "arrow.clockwise") }.disabled(model.busy)
                    .help("Has the AI read your lyrics again and write a new description and new picture ideas. Your own edits to the description are replaced.")
                Button { model.regeneratePrompts() } label: { Label("Make new picture ideas", systemImage: "wand.and.stars") }.disabled(model.busy)
                    .help("Keeps the description above (including any changes you made) and writes fresh picture ideas from it.")
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 560)
    }
}

struct StyleSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) { Image(systemName: "paintpalette").font(.title).foregroundStyle(.tint); Text("Art style for every picture").font(.title2.bold()) }
            Text("Press a style to use it, or describe your own below. The same style is added to every picture idea so all the pictures look like they belong together.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(Array(StylePreset.all.dropFirst())) { p in
                    let on = (model.plan?.style ?? "") == p.prompt
                    Button { model.applyStylePreset(p.name) } label: { Text(p.name).frame(maxWidth: .infinity).padding(.vertical, 3) }
                        .buttonStyle(.bordered).tint(on ? .accentColor : nil)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                        .help(p.prompt)
                }
            }
            Text("Your own style words").font(.subheadline.weight(.medium))
            TextEditor(text: Binding(get: { model.plan?.style ?? "" }, set: { model.setStyle($0) }))
                .font(.body).scrollContentBackground(.hidden).padding(8)
                .frame(height: 90).background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .help("The look of the pictures, in words. It is added to every picture idea.")
            HStack {
                Text("New pictures use this style. Pictures you already made are not changed.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 600)
    }
}
