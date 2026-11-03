// The other two Pictures layouts: 2e, the timeline as a storyboard, and 2f, a board of every picture. Both open the 2d inspector for more.
import SwiftUI
import UniformTypeIdentifiers
import MVCore

/// The 2d picture and inspector in a sheet, for layouts that have no inspector of their own.
struct NewInspectorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let section: Int
    @State private var aim = true
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                DropWell(section: section, maxPictureHeight: 460, pictureOnly: true, aim: $aim).disabled(model.workingSection == section)
                HStack { Button { aim.toggle() } label: { HStack(spacing: 5) { Image(systemName: aim ? "checkmark.square" : "square"); Text("Show the aim and the Shorts crop") }.font(Classical.body(12)) }.buttonStyle(.plain); Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.classicalPrimary).keyboardShortcut(.defaultAction) }
                Spacer(minLength: 0)
            }.padding(20).frame(maxWidth: .infinity)
            VHairline()
            NewInspector(section: section).frame(width: 330)
        }.frame(width: 1000, height: 640).background(Classical.bg).environment(\.colorScheme, .light)
    }
}

// MARK: 2e · storyboard

struct NewStoryboardLayout: View {
    @EnvironmentObject var model: AppModel
    @State private var more: Int?
    var plan: Plan { model.plan! }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(-1..<plan.sections.count, id: \.self) { i in block(i); Hairline() }
            }.frame(maxWidth: 980).padding(.horizontal, 30).padding(.vertical, 12).frame(maxWidth: .infinity)
        }
        .sheet(item: Binding(get: { more.map { SectionID(id: $0) } }, set: { more = $0?.id })) { NewInspectorSheet(section: $0.id).environmentObject(model) }
    }
    struct SectionID: Identifiable { let id: Int }

    func block(_ i: Int) -> some View {
        let s = i < 0 ? plan.intro : plan.sections[i]
        let c = s.selectedCandidate
        return HStack(alignment: .top, spacing: 22) {
            ZStack {
                Rectangle().fill(Color(hex: 0xE4E2E2))
                if let t = c?.thumbFile, let w = model.workDir { Thumb(file: w.appendingPathComponent(t)) } else { Text("No picture yet").font(Classical.body(12)).foregroundStyle(Classical.neutral500) }
            }.frame(width: 360, height: 203).clipped().overlay(Rectangle().stroke(Classical.divider, lineWidth: 1))
                .onTapGesture { model.selectedSection = i; more = i }
                .dropDestination(for: URL.self) { urls, _ in guard let u = urls.first else { return false }; model.load(u, section: i); return true }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(i < 0 ? "Title card" : "Picture \(i + 1)").font(Classical.heading(22))
                    Text(i < 0 ? "" : "\(preciseClock(s.start).replacingOccurrences(of: ".0", with: ""))–\(timeString(s.end))").font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
                    Spacer()
                    if i >= 0 { CLink(title: "Split") { model.selectedSection = i; model.splitPicture(at: (s.start + s.end) / 2) }; CLink(title: "Join →") { model.joinPicture(before: i + 1) }.disabled(i >= plan.sections.count - 1) }
                }
                if !s.lineIDs.isEmpty { Text(s.lineIDs.compactMap { plan.lines.indices.contains($0) ? plan.lines[$0].text : nil }.joined(separator: "\n")).font(Classical.italic(13)).foregroundStyle(Classical.text).fixedSize(horizontal: false, vertical: true) }
                TextEditor(text: Binding(get: { s.prompt }, set: { model.setPrompt($0, section: i) })).font(Classical.body(12)).scrollContentBackground(.hidden).padding(6).frame(height: 70)
                    .background(Classical.paper).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1)).disabled(model.workingSection == i)
                HStack(spacing: 10) {
                    Text("Camera").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                    seg("Automatic", on: c != nil && c?.cameraPath == nil && !(s.useClips && !s.clips.isEmpty)) { model.useAutomaticCamera(section: i) }.disabled(c == nil)
                    seg("I choose", on: c?.cameraPath != nil) { model.chooseCameraMove(section: i) }.disabled(c == nil)
                    seg("Clip", on: s.useClips && !s.clips.isEmpty) { model.selectedSection = i; more = i }
                }
                HStack(spacing: 12) {
                    Button { model.generateImage(section: i) } label: { Text((c == nil ? "Draw" : "Redraw") + "  \(OpenRouter.formatUSD(model.perImageCostUSD))") }.buttonStyle(.classicalPrimary).disabled(model.busy || model.workingSection == i)
                    CLink(title: "More for this picture ⌄") { model.selectedSection = i; more = i }
                }
            }
        }.padding(.vertical, 16)
    }
    func seg(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(Classical.body(11)).foregroundStyle(on ? Classical.accent700 : Classical.neutral700).padding(.horizontal, 9).padding(.vertical, 4).background(on ? Classical.accent100 : .clear).overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Classical.accent : Classical.neutral300, lineWidth: 1)) }.buttonStyle(.plain)
    }
}

// MARK: 2f · board

struct NewBoardLayout: View {
    @EnvironmentObject var model: AppModel
    @Binding var openInspector: Bool
    @State private var open: Int?
    @State private var dropTarget: Int?
    var plan: Plan { model.plan! }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Drop files onto any picture · drag pictures to swap").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 330), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(-1..<plan.sections.count, id: \.self) { tile($0) }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: Binding(get: { open.map { NewStoryboardLayout.SectionID(id: $0) } }, set: { open = $0?.id })) { NewInspectorSheet(section: $0.id).environmentObject(model) }
    }

    func tile(_ i: Int) -> some View {
        let s = i < 0 ? plan.intro : plan.sections[i]; let c = s.selectedCandidate
        return VStack(alignment: .leading, spacing: 5) {
            ZStack {
                Rectangle().fill(Color(hex: 0xE4E2E2))
                if let t = c?.thumbFile, let w = model.workDir { Thumb(file: w.appendingPathComponent(t)) }
                else if model.workingSection == i { ProgressView().controlSize(.small) }
                else { Button { model.generateImage(section: i) } label: { Text("Draw  \(OpenRouter.formatUSD(model.perImageCostUSD))") }.buttonStyle(.classicalSmall).disabled(model.busy) }
            }.aspectRatio(16.0 / 9, contentMode: .fit).clipped()
                .overlay(Rectangle().stroke(dropTarget == i ? Classical.accent : Classical.divider, lineWidth: dropTarget == i ? 2 : 1))
            HStack(spacing: 5) {
                Text(String(format: "%02d", i + 1)).font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
                if c?.checkNote != nil { Text("⚠").font(.system(size: 10)).foregroundStyle(Classical.warn) }
                if s.useClips && !s.clips.isEmpty { Text("▶ clip").font(Classical.body(10)).foregroundStyle(Classical.accent700) }
                Spacer(); if i >= 0 { Text(timeString(s.start)).font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600) }
            }
            Text(i < 0 ? plan.title : (s.lineIDs.first.flatMap { plan.lines.indices.contains($0) ? plan.lines[$0].text : nil } ?? "♪ music")).font(Classical.body(12)).lineLimit(2).foregroundStyle(Classical.text)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selectedSection = i; open = i }
        .onDrag { NSItemProvider(object: "mv-picture:\(i)" as NSString) }
        .onDrop(of: [UTType.fileURL, UTType.text], isTargeted: Binding(get: { dropTarget == i }, set: { dropTarget = $0 ? i : nil })) { providers in
            if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in dropTarget = nil; model.load(url, section: i) } } }; return true
            }
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let value = value as? String, value.hasPrefix("mv-picture:"), let source = Int(value.dropFirst(11)), source != i else { return }
                Task { @MainActor in dropTarget = nil; model.reassignPicture(from: source, to: i) }
            }
            return true
        }
        .help("Click to open this picture. Drop a file here to replace it, or drag another picture here to swap.")
    }
}

