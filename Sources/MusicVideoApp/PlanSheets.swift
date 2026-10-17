// Windows opened from the Pictures screen's buttons: the song description and the art style (instead of hidden drop-downs).
import SwiftUI
import MVCore

struct DescriptionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showIdeas = false
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
                Button { showIdeas = true } label: { Label("Suggest 10 ideas for me", systemImage: "lightbulb") }
                    .help("The app reads your lyrics and suggests 10 different places and moods. Press one to use it.")
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
                Button("Done") { dismiss() }.help("Save and close this window.").buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 560)
        .sheet(isPresented: $showIdeas) { SettingIdeasSheet(applyToProject: true).environmentObject(model) }
    }
}

/// The picture-style library: press a style to use it; change its name or text, delete it, or make a new one. Everything is saved permanently.
struct StyleSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = StyleLibrary.shared
    @Environment(\.dismiss) private var dismiss
    let inProject: Bool                      // true: from the Pictures screen (also sets this song's style); false: from the first screen
    @State private var draftName = ""
    @State private var draftPrompt = ""
    @State private var loadedID = ""
    @State private var confirmDelete = false

    var selected: StylePreset? { library.preset(id: model.selectedStylePreset) }
    var isAuto: Bool { model.selectedStylePreset == StylePreset.autoID }
    var changed: Bool { guard let p = selected, !isAuto else { return false }; return draftName != p.name || draftPrompt != p.prompt }

    var body: some View { ScrollView { content.padding(22) }.frame(width: 640).frame(maxHeight: 680).onAppear { reload() }.onChange(of: model.selectedStylePreset) { _, _ in reload() }.confirmationDialog("Delete “\(selected?.name ?? "")”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let p = selected { library.delete(id: p.id); model.selectedStylePreset = StylePreset.autoID } }
            Button("Keep it", role: .cancel) {}
        } }

    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { Image(systemName: "paintpalette").font(.title).foregroundStyle(.tint); Text("Picture styles").font(.title2.bold()) }
            Text(inProject ? "Press a style to use it for this song's pictures. Below it you can change the style's words or make your own style; changes are kept for next time."
                           : "Press a style to use it. Below it you can change the style's words or make your own style; changes are kept for next time.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 8)], spacing: 8) {
                    ForEach(library.all) { p in
                        let on = model.selectedStylePreset == p.id
                        Button { choose(p) } label: {
                            HStack(spacing: 5) {
                                if on { Image(systemName: "checkmark.circle.fill") }
                                Text(p.name).lineLimit(1)
                                if !p.builtIn { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange).help("A style you made") }
                                else if library.isModified(p) { Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary).help("You changed this style") }
                            }.frame(maxWidth: .infinity).padding(.vertical, 3)
                        }
                        .buttonStyle(.bordered).tint(on ? .accentColor : nil)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                        .help(p.prompt.isEmpty ? "Lets the app choose a style that fits your song." : p.prompt)
                    }
                }.padding(2)
            }.frame(height: 220)
            Divider()
            if isAuto {
                Text("“AI Auto” has no words of its own. The app writes a style that fits your song.").font(.callout).foregroundStyle(.secondary)
            } else if selected != nil {
                Text("Edit this style").font(.subheadline.weight(.medium))
                TextField("Name", text: $draftName).textFieldStyle(.roundedBorder).controlSize(.large)
                    .help("The name shown on the style's button.")
                TextEditor(text: $draftPrompt).font(.body).scrollContentBackground(.hidden).padding(8)
                    .frame(height: 90).background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .help("The look in words. It is added to every picture idea, so describe the medium, colours, light and mood.")
            }
            HStack(spacing: 8) {
                Button { newStyle() } label: { Label("New style", systemImage: "plus") }
                    .help("Makes a new style of your own. Give it a name and describe the look in words.")
                if !isAuto, let p = selected {
                    Button { library.update(id: p.id, name: draftName, prompt: draftPrompt); reload(); if inProject { model.applyStylePreset(p.id) } } label: { Label("Save changes", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent).disabled(!changed || draftPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Keeps your changes to this style permanently.")
                    if library.isModified(p) {
                        Button { library.reset(id: p.id); reload() } label: { Label("Back to original", systemImage: "arrow.uturn.backward") }
                            .help("Puts this style's name and words back the way they came with the app.")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        .help(p.builtIn ? "Removes this style from the list. You can bring ready-made styles back with “Restore deleted styles”." : "Removes this style of yours for good.")
                }
                Spacer()
                if library.hasDeletedBuiltIns { Button("Restore deleted styles") { library.restoreBuiltIns() }.help("Brings back the ready-made styles you deleted.") }
            }
            if inProject {
                Divider()
                Text("Words used for this song").font(.subheadline.weight(.medium))
                TextEditor(text: Binding(get: { model.plan?.style ?? "" }, set: { model.setStyle($0) }))
                    .font(.body).scrollContentBackground(.hidden).padding(8)
                    .frame(height: 64).background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .help("The style words this song's pictures use right now. You can also write them by hand here.")
                Text("New pictures use these words. Pictures you already made are not changed.").font(.callout).foregroundStyle(.secondary)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.help("Save and close this window.").buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }
    }

    func choose(_ p: StylePreset) { if inProject { model.applyStylePreset(p.id) } else { model.selectedStylePreset = p.id } }
    func reload() { if let p = selected, !isAuto { draftName = p.name; draftPrompt = p.prompt; loadedID = p.id } else { draftName = ""; draftPrompt = "" } }
    func newStyle() {
        let p = library.add(name: "My new style", prompt: "Describe the look here: the medium, the colours, the light and the mood.")
        choose(p); reload()
    }
}

/// Ten different ideas for the video's setting, written by the local AI from the lyrics. Press one to use it.
struct SettingIdeasSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let applyToProject: Bool
    @State private var ideas: [String] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { Image(systemName: "lightbulb").font(.title).foregroundStyle(.yellow); Text("Ideas for the setting").font(.title2.bold()) }
            Text("The app read your lyrics and thought of different places and moods. Press the one you like and it becomes the setting every picture follows. Nothing is changed until you press one.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if loading && ideas.isEmpty {
                HStack(spacing: 10) { ProgressView(); Text("Thinking of ideas… this takes a few seconds.").foregroundStyle(.secondary) }.padding(.vertical, 20)
            }
            ForEach(ideas, id: \.self) { idea in
                Button { use(idea) } label: {
                    HStack { Text(idea).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "arrow.right.circle").foregroundStyle(.tint) }
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .help("Use “\(idea)” as the setting for every picture.")
            }
            if let e = error { Text(e).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button { Task { await fetch(more: true) } } label: { Label(ideas.isEmpty ? "Try again" : "Suggest 10 more", systemImage: "arrow.clockwise") }
                    .disabled(loading).help("Thinks of 10 more ideas, different from these.")
                if loading && !ideas.isEmpty { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 560)
        .task { if ideas.isEmpty { await fetch(more: false) } }
    }

    func fetch(more: Bool) async {
        loading = true; error = nil
        do {
            let new = try await model.fetchSettingIdeas(avoid: more ? ideas : [])
            ideas = more ? ideas + new : new
            if ideas.count > 30 { ideas = Array(ideas.suffix(30)) }
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    func use(_ idea: String) {
        if applyToProject { model.setSetting(idea); model.notice = "Setting saved. Press “Make new picture ideas” in Setting & description to apply it to every picture." } else { model.settingTheme = idea }
        dismiss()
    }
}
