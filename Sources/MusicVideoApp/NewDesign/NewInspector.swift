// The picture inspector (designs 3a and 3b): only the selected picture. Idea, Camera, Versions and Clip tabs, with Move or swap.
import SwiftUI
import MVCore

struct NewInspector: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    @State private var tab = "idea"
    @State private var confirmRemove = false
    var plan: Plan { model.plan! }
    var sec: PhotoSection { section < 0 ? plan.intro : plan.sections[min(max(section, 0), plan.sections.count - 1)] }
    var cand: ImageCandidate? { sec.selectedCandidate }
    var working: Bool { model.workingSection == section }
    var title: String {
        section < 0 ? "Title card" : (sec.lineIDs.isEmpty ? (section == 0 ? "Music before the words" : (section == plan.sections.count - 1 ? "Music after the words" : "Music break")) : "Picture \(section + 1)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                tabBar
                switch tab {
                case "camera": NewCameraTab(section: section)
                case "versions": versions
                case "clip": clip
                default: idea
                }
            }.padding(16)
        }.background(Classical.bg)
    }

    // MARK: header
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(Classical.heading(24))
                Text(section < 0 ? "opening slide" : "\(preciseClock(sec.start).replacingOccurrences(of: ".0", with: ""))–\(timeString(sec.end)) · \(Int(sec.duration)) s").font(Classical.body(11).monospacedDigit()).foregroundStyle(Classical.neutral600)
            }
            if section >= 0 {
                HStack(spacing: 12) {
                    CLink(title: "Split here") { splitHere() }.help("Starts a new picture here. The cut goes at the cursor on the timeline when it is inside this picture, otherwise in the middle.")
                    CLink(title: "Join with next") { model.joinPicture(before: section + 1) }.disabled(section >= plan.sections.count - 1).help("Merges this picture with the next one.")
                    moveMenu
                }
            }
        }
    }
    func splitHere() {
        let t = (model.timelineCursor > sec.start + 0.5 && model.timelineCursor < sec.end - 0.5) ? model.timelineCursor : (sec.start + sec.end) / 2
        model.splitPicture(at: t)
    }
    @ViewBuilder var moveMenu: some View {
        if section >= 0 {
            Menu {
                Section("Move or swap Picture \(section + 1)") {
                    ForEach(plan.sections.indices.filter { $0 != section }, id: \.self) { d in
                        Button("\(plan.sections[d].selectedCandidate == nil ? "Move to" : "Swap with") Picture \(d + 1)\(plan.sections[d].selectedCandidate == nil ? " · empty" : "")") { model.reassignPicture(from: section, to: d) }.disabled(cand == nil)
                    }
                }
                if let r = sec.repeatOf, plan.sections.indices.contains(r), plan.sections[r].selectedCandidate != nil {
                    Divider(); Button("Reuse picture \(r + 1) here · same lyrics") { model.reuse(section: section, from: r) }
                }
            } label: { Text("Move or swap…").font(Classical.body(12)).foregroundStyle(Classical.accent700) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Move this artwork to an empty picture or swap it with another. Dragging rows in the list does the same. Undo reverses it.")
        }
    }

    var tabBar: some View {
        HStack(spacing: 16) {
            ForEach([("idea", "Idea"), ("camera", "Camera"), ("versions", "Versions\(sec.candidates.count > 1 ? " \(sec.candidates.count)" : "")"), ("clip", "Clip")], id: \.0) { id, t in
                Button { tab = id } label: {
                    Text(t).font(Classical.body(13, weight: tab == id ? .semibold : .regular)).foregroundStyle(tab == id ? Classical.text : Classical.neutral600)
                        .padding(.bottom, 4).overlay(alignment: .bottom) { Rectangle().fill(tab == id ? Classical.accent : .clear).frame(height: 2) }
                }.buttonStyle(.plain)
            }
            Spacer()
        }.overlay(alignment: .bottom) { Hairline().offset(y: 1) }
    }

    // MARK: Idea
    var idea: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: Binding(get: { sec.prompt }, set: { model.setPrompt($0, section: section) })).font(Classical.body(13)).scrollContentBackground(.hidden)
                .padding(8).frame(minHeight: 96, maxHeight: 190).background(Classical.paper).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                .disabled(working).help("A description of the picture for this part. The app writes it from your lyrics. You can edit it.")
            HStack(spacing: 14) {
                CLink(title: "Another idea") { model.rewritePrompt(section: section) }.disabled(model.busy).help("Has the AI write a different picture idea for this part.")
                CLink(title: "Copy") { model.copy(model.fullPrompt(section: section)) }.help("Copies this picture idea with the art style so you can paste it into another image maker.")
                if working { ProgressView().controlSize(.mini) }
            }
            if working { Text("The app is working on this picture, so it is locked until it is done.").font(Classical.body(11)).foregroundStyle(Classical.accent800) }
            if sec.focal.count >= 2 { Text("Camera goes from “\(sec.focal[0])” to “\(sec.focal[1])”.").font(Classical.body(11)).foregroundStyle(Classical.neutral700) }
            if let n = sec.logicNote, !n.isEmpty { Text("Story check changed this idea: \(n)").font(Classical.body(11)).foregroundStyle(Classical.neutral700) }
            else if sec.promptManual { Text("Your own wording is never changed by the story check.").font(Classical.body(11)).foregroundStyle(Classical.neutral700) }
            if let c = cand {
                if c.looksLikeSubject { note("This picture looks a lot like your subject photo. To be safe, press Redraw.") }
                if let problem = c.checkNote {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Picture check: \(problem)").font(Classical.body(12)).foregroundStyle(Classical.accent800).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            if c.checkFix != nil { CLink(title: "Fix it  \(OpenRouter.formatUSD(model.perImageCostUSD))") { model.fixPicture(section) }.disabled(model.busy).help("Redraws this picture changing only that, keeping everything else. The picture you have now stays as an earlier version.") }
                            CLink(title: "Keep it") { model.updateCandidate(section: section) { $0.checkNote = nil; $0.checkFix = nil } }
                        }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.accent300, lineWidth: 1))
                }
                if c.looksLikePrevious(model.previousPictureFile(section: section)) { note("This picture has almost the same framing as the one before it. Keep it, or press Redraw for a different view.") }
            }
            Hairline()
            actions
        }
    }
    func note(_ t: String) -> some View { Text(t).font(Classical.body(12)).foregroundStyle(Classical.accent800).padding(10).frame(maxWidth: .infinity, alignment: .leading).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.accent300, lineWidth: 1)) }

    @ViewBuilder var actions: some View {
        let price = OpenRouter.formatUSD(model.perImageCostUSD)
        VStack(alignment: .leading, spacing: 8) {
            Button { model.generateImage(section: section) } label: { HStack { Text(cand == nil ? "Draw this picture" : "Redraw"); Spacer(); Text(price).font(Classical.body(12).monospacedDigit()) }.frame(maxWidth: .infinity) }
                .buttonStyle(.classicalPrimary).disabled(model.busy || working)
                .help(cand == nil ? "Draws a picture from the idea above (a few cents)." : "Draws a new picture for this part. The current one stays under Versions.")
            if let c = cand, c.videoFile == nil, c.fullFile != nil {
                if c.credit.hasPrefix("Highest quality") {
                    Text("Highest quality ✓").font(Classical.body(12)).foregroundStyle(Classical.ok)
                } else {
                    Button { model.makeHighestQuality([section]) } label: { HStack { Text("Highest quality"); Spacer(); Text(OpenRouter.formatUSD(PictureQuality.enhanceEstimate)).font(Classical.body(12).monospacedDigit()) }.frame(maxWidth: .infinity) }
                        .buttonStyle(.classical).disabled(model.busy)
                        .help("Redraws this same picture at the very highest level: finer detail, crisper edges, same composition. The picture you have now stays as an earlier version.")
                }
            }
            HStack(spacing: 14) {
                CLink(title: "Use my own file…") { choose() }.help("Replaces this picture with a file from your Mac, or drop a file on the picture.")
                if cand != nil {
                    if model.styleGuideSection == section { Text("Style guide ✓").font(Classical.body(12)).foregroundStyle(Classical.neutral600) }
                    else { CLink(title: "Use as style guide") { model.setStyleGuide(section) }.help("Pictures drawn from now on match the look of this picture (about half a cent extra each).") }
                    CLink(title: "Copy idea") { model.copy(model.fullPrompt(section: section)) }
                    CLink(title: "Remove") { confirmRemove = true }.foregroundStyle(Classical.warn)
                }
            }
            if let n = cand?.libraryName { Button { model.showPicturesFolder(select: n) } label: { Text(n).font(Classical.body(11)).foregroundStyle(Classical.neutral600).lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain).help("Also saved in your Pictures folder. Click to show it in Finder.") }
        }
        .confirmationDialog("Remove this picture?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove it", role: .destructive) { model.removeImage(section: section) }; Button("Keep it", role: .cancel) {}
        } message: { Text("That part of the video will show a plain colour until you add another. Undo brings it back.") }
    }
    func choose() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.image, .movie]; p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { model.load(u, section: section) }
    }

    // MARK: Versions
    var versions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sec.candidates.count > 0 { EarlierVersions(section: section) }
            Text("Every version is kept, including paid ones you replaced.").font(Classical.body(11)).foregroundStyle(Classical.neutral600)
            HStack(spacing: 14) {
                if let n = cand?.libraryName { CLink(title: "Show in Pictures folder") { model.showPicturesFolder(select: n) } }
                CLink(title: "Extend a photo to 16:9…") {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.image]; p.allowsMultipleSelection = false
                    if p.runModal() == .OK, let u = p.url { model.load(u, section: section) }
                }.help("Choose a photo that is not widescreen. You can extend it with AI or crop it.")
            }
        }
    }

    // MARK: Clip
    @ViewBuilder var clip: some View {
        if let c = cand, c.videoFile == nil, c.fullFile != nil { ClipPanel(section: section) }
        else if let c = cand, c.videoFile != nil { VideoTrimView(section: section, candidate: c, partLength: sec.duration) }
        else { Text("Draw or add a picture first. A clip is made from the picture.").font(Classical.body(12)).foregroundStyle(Classical.neutral600) }
    }
}

/// Camera tab: automatic, or choose where the move starts and ends.
struct NewCameraTab: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    var body: some View {
        let plan = model.plan!
        let sec = section < 0 ? plan.intro : plan.sections[min(max(section, 0), plan.sections.count - 1)]
        VStack(alignment: .leading, spacing: 12) {
            if let c = sec.selectedCandidate {
                HStack(spacing: 8) {
                    seg("Automatic", on: c.cameraPath == nil) { model.useAutomaticCamera(section: section) }
                    seg("I choose the move", on: c.cameraPath != nil) { model.chooseCameraMove(section: section) }
                }
                if let cam = c.cameraPath {
                    Text("Drag ① where the camera starts and ② where it ends. The picture glides between the two frames.").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
                    Text("While it travels").font(Classical.body(12, weight: .semibold))
                    HStack(spacing: 6) {
                        ForEach([(0, "Moves closer"), (1, "Stays level"), (2, "Moves wider")], id: \.0) { z, t in seg(t, on: cam.zoom == z) { model.setCameraZoom(section: section, zoom: z) } }
                    }
                    HStack(spacing: 14) { CLink(title: "Swap start and end") { model.swapCameraPoints(section: section) } }
                } else {
                    Text("The camera drifts slowly toward the most interesting part. Drag the dot on the picture to aim it.").font(Classical.body(12)).foregroundStyle(Classical.neutral700)
                    CLink(title: "Aim for me") { model.resetFocus(section: section) }.help("Finds the most interesting spot, such as a face, and aims the camera there.")
                }
                if c.videoFile != nil || (sec.useClips && !sec.clips.isEmpty) { Text("With a clip in use, the clip plays first and the camera then moves over its last frame.").font(Classical.body(11)).foregroundStyle(Classical.neutral600) }
            } else { Text("Draw or add a picture first.").font(Classical.body(12)).foregroundStyle(Classical.neutral600) }
        }
    }
    func seg(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(Classical.body(12)).foregroundStyle(on ? Classical.accent700 : Classical.neutral700).padding(.horizontal, 10).padding(.vertical, 5).background(on ? Classical.accent100 : .clear)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Classical.accent : Classical.neutral300, lineWidth: 1)) }.buttonStyle(.plain)
    }
}
