// Under a picture: choose Ken Burns (the default) or a HeyGen video clip, make clips (one, or the whole section back to back), and watch each one.
import SwiftUI
import AVKit
import MVCore

struct ClipPlayer: View {
    let url: URL
    var autoplay = false
    @State private var player: AVPlayer?
    var body: some View {
        Group { if let player { PlayerView(player: player) } else { Color.black } }
            .aspectRatio(16.0 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear { player = AVPlayer(url: url); if autoplay { player?.play() } }
            .onChange(of: url) { _, u in player = AVPlayer(url: u) }
            .onDisappear { player?.pause() }
    }
}

struct ClipPanel: View {
    @EnvironmentObject var model: AppModel
    let section: Int
    @State private var confirmChain: Bool?          // shows the price confirmation: false = one clip, true = whole section
    @State private var confirmDelete = false
    @State private var toggled: Set<String> = []       // clips whose trim panel was flipped from its default (open for one clip, closed for several)

    var sec: PhotoSection { (section < 0 ? model.plan?.intro : model.plan?.sections[section]) ?? PhotoSection(id: 0, start: 0, end: 1, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 0) }
    var work: URL? { model.workDir }
    var coveredSeconds: Double { sec.clips.reduce(0) { $0 + $1.playSeconds } }
    var job: ClipJob? { model.clipJob?.section == section ? model.clipJob : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Motion", systemImage: "film").font(.headline)
                Spacer()
                Picker("", selection: Binding(get: { sec.useClips && !sec.clips.isEmpty }, set: { model.setClipMode(section: section, use: $0) })) {
                    Text("Ken Burns").tag(false); Text("Video clip").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 230).disabled(sec.clips.isEmpty || model.clipJob != nil)
                    .help("Ken Burns slowly pans and zooms the picture (the default and it is free). “Video clip” plays the generated video instead. Make a clip first to switch.")
            }
            clipOptions
            if let j = job { jobView(j) }
            else if sec.clips.isEmpty { makeButtons }
            else { clipList }
            if !sec.retainedClips.isEmpty && job == nil { savedClips }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .task { model.refreshVideoPrice() }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirmChain != nil }, set: { if !$0 { confirmChain = nil } }), titleVisibility: .visible, presenting: confirmChain) { chain in
            Button("Make \(chain ? "the video clips" : "the clip") (≈ \(OpenRouter.formatUSD(price(chain))))") { model.startClips(section: section, chain: chain) }
            Button("Cancel", role: .cancel) {}
        } message: { chain in Text(confirmMessage(chain)) }
        .confirmationDialog("Delete the video clips for this picture?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete the clips", role: .destructive) { model.deleteClips(section: section) }
            Button("Keep them", role: .cancel) {}
        } message: { Text("The picture stays. Earlier clips keeps the paid originals; Undo restores this assignment.") }
    }

    func price(_ chain: Bool) -> Double { model.clipPriceUSD(model.clipSeconds(section: section, chain: chain), sharp: sec.clipOptions.sharp) }
    var confirmTitle: String { confirmChain == true ? "Make the whole section as video?" : "Make a video clip?" }
    func confirmMessage(_ chain: Bool) -> String {
        let l = model.clipSeconds(section: section, chain: chain)
        let cr = model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? ""
        return chain ? "\(l.count) clip\(l.count == 1 ? "" : "s") (\(l.map { "\($0) s" }.joined(separator: " + "))) at HeyGen's list price of \(OpenRouter.formatUSD(model.videoPricePerSecond)) per second. Each clip starts on the last frame of the one before, and you watch each one before the next is made.\(cr)"
                     : sec.clipOptions.durationExplanation + " A \(l.first ?? 0)-second clip starting from this picture, at HeyGen's list price of \(OpenRouter.formatUSD(model.videoPricePerSecond)) per second.\(cr) The real billed cost is shown after it finishes."
    }

    var clipOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Clip length", selection: Binding(get: { sec.clipOptions.seconds ?? 0 }, set: { v in model.setClipOptions(section: section, seconds: v == 0 ? nil : v, sharp: sec.clipOptions.sharp, repeatClip: sec.repeatClips) })) {
                Text("Match section").tag(0); Text("3 seconds").tag(3); Text("5 seconds").tag(5); Text("8 seconds").tag(8); Text("15 seconds").tag(15)
            }.pickerStyle(.segmented).disabled(job != nil)
                .help("A 3-second choice uses part of a 5-second order and costs 5 seconds. Match section orders 5 to 15 seconds.")
            Picker("Clip quality", selection: Binding(get: { sec.clipOptions.sharp }, set: { sharp in model.setClipOptions(section: section, seconds: sec.clipOptions.seconds, sharp: sharp, repeatClip: sec.repeatClips) })) {
                Text("Standard 768p").tag(false); Text("Sharp 2K").tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 350).disabled(job != nil)
                .help("Sharp requests 2K from HeyGen. Quality affects the next order, not clips already made.")
            Toggle("Repeat the clip until this section ends", isOn: Binding(get: { sec.repeatClips }, set: { on in model.setClipOptions(section: section, seconds: sec.clipOptions.seconds, sharp: sec.clipOptions.sharp, repeatClip: on) }))
                .disabled(sec.clips.count > 1 || job != nil).help("Blends the end into the beginning. The overlap makes each repeat shorter than the source range.")
            if sec.clipOptions.seconds == 3 { Text(sec.clipOptions.durationExplanation).font(.callout).foregroundStyle(.secondary) }
        }
    }
    var savedClips: some View {
        DisclosureGroup("Earlier clips (free to reuse)") {
            ForEach(sec.retainedClips) { c in
                HStack {
                    if let w = work { ClipPlayer(url: w.appendingPathComponent(c.file)).frame(width: 170) }
                    VStack(alignment: .leading) {
                        Text(String(format: "%.1f seconds · %@", c.playSeconds, OpenRouter.formatUSD(c.costUSD)))
                        Text(c.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Button("Use this clip") { model.useSavedClip(section: section, clip: c) }
                            .help("Uses this saved original without another paid order. Undo restores the previous assignment.")
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    var makeButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            let one = model.clipSeconds(section: section, chain: false)
            HStack(spacing: 10) {
                Button { confirmChain = false } label: { Label("Make this a video clip (\(one.first ?? 0) s ≈ \(OpenRouter.formatUSD(price(false))))", systemImage: "sparkles.tv") }
                    .buttonStyle(.borderedProminent).disabled(one.isEmpty || model.busy)
                    .help("Makes a video clip that starts from this picture. You see the price first and watch the clip before it is used. If the section is longer than the clip, the last frame holds and Ken Burns carries on.")
                if sec.duration > Double(OpenRouterVideo.maxSeconds) + 0.5 {
                    let many = model.clipSeconds(section: section, chain: true)
                    Button { confirmChain = true } label: { Label("Make the whole section as video (\(many.count) clips ≈ \(OpenRouterVideo.formatPrice(model.clipPriceUSD(many, sharp: sec.clipOptions.sharp))))", systemImage: "film.stack") }
                        .disabled(model.busy)
                        .help("Covers the whole section with back-to-back clips, each starting on the last frame of the one before. You watch each clip before the next is made.")
                }
            }
            Text("Ken Burns stays unless you choose video. Prices are HeyGen's list price; the real cost is shown afterwards.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    var clipList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sec.clips) { c in
                HStack(alignment: .top, spacing: 12) {
                    if let w = work { ClipPlayer(url: w.appendingPathComponent(c.file)).frame(width: 240) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(c.seconds.rounded())) s clip · \(OpenRouter.formatUSD(c.costUSD))").font(.callout.weight(.semibold))
                        Text(c.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        if let n = c.libraryName {
                            Button { model.showPicturesFolder(select: n) } label: { Label(n, systemImage: "photo.on.rectangle.angled").font(.caption).lineLimit(1).truncationMode(.middle) }.buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("This clip is also saved in your Pictures folder under this name. Click to show it in Finder.")
                        }
                        if let w = c.warning { Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                DisclosureGroup(isExpanded: Binding(get: { (sec.clips.count == 1) != toggled.contains(c.id) }, set: { open in
                    if open == (sec.clips.count == 1) { toggled.remove(c.id) } else { toggled.insert(c.id) } })) {
                    VideoTrimView(section: section, clip: c, partLength: sec.duration).padding(.top, 6)
                } label: { Label("Choose the part that plays" + (sec.clips.count == 1 ? " · repeat" : ""), systemImage: "scissors").font(.callout.weight(.semibold)) }
            }
            if coveredSeconds + 0.5 < sec.duration {
                Text(sec.useClips ? (sec.repeatClips && sec.clips.count == 1 ? "The clip repeats, blending into its own beginning, until this part of the song ends." : "The clip plays once for \(Int(coveredSeconds.rounded())) s, then the last frame holds and the camera moves between its main features for the remaining \(Int((sec.duration - coveredSeconds).rounded())) s.") : "Switch to “Video clip” above to use it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                let more = model.clipSeconds(section: section, chain: true)
                if !more.isEmpty && sec.duration > coveredSeconds + 1 {
                    Button { confirmChain = true } label: { Label("Continue with more video (\(more.count) clip\(more.count == 1 ? "" : "s") ≈ \(OpenRouterVideo.formatPrice(model.clipPriceUSD(more, sharp: sec.clipOptions.sharp))))", systemImage: "film.stack") }
                        .disabled(model.busy).help("Adds more clips after these, each starting on the last frame of the one before, until the section is covered.")
                }
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete clips", systemImage: "trash") }
                    .help("Removes the video clips and goes back to Ken Burns. The picture stays.")
            }
        }
    }

    @ViewBuilder func jobView(_ j: ClipJob) -> some View {
        if let err = j.failed {
            VStack(alignment: .leading, spacing: 6) {
                Label(err, systemImage: "xmark.octagon.fill").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("OK") { model.dismissClipError() }
            }
        } else if j.waiting, let c = j.preview, let w = work {
            VStack(alignment: .leading, spacing: 8) {
                Text(j.chain ? "Clip \(j.index + 1) of \(j.secondsList.count) is ready — watch it" : "Your clip is ready — watch it").font(.callout.weight(.semibold))
                ClipPlayer(url: w.appendingPathComponent(c.file)).frame(maxWidth: 420)
                Text("Watch it, then choose Use or Looks good to put it in the video. Redo and Discard keep this paid original under Earlier clips.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let warn = c.warning { Label("Realism check: \(warn)", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Text("Cost: \(OpenRouter.formatUSD(c.costUSD))").font(.caption).foregroundStyle(.secondary)
                let nextPrice = model.clipPriceUSD(Array(j.secondsList.dropFirst(j.index + 1).prefix(1)), sharp: sec.clipOptions.sharp)
                ViewThatFits(in: .horizontal) { HStack(spacing: 8) { decisionButtons(j, nextPrice) }; VStack(alignment: .leading, spacing: 8) { decisionButtons(j, nextPrice) } }
                if j.chain && j.index < j.secondsList.count - 1 {
                    Toggle("Make the rest without asking", isOn: Binding(get: { model.clipJob?.autoContinue ?? false }, set: { model.clipJob?.autoContinue = $0 })).toggleStyle(.checkbox)
                        .help("Makes all the remaining clips one after another. You can still watch them afterwards.")
                }
            }
        } else {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text((j.chain ? "Clip \(j.index + 1) of \(j.secondsList.count): " : "") + j.phase).font(.callout)
                Spacer()
                Button("Stop") { model.cancelClipJob() }.help("Stops. A clip that is already being made is still charged by HeyGen; finished clips are kept.")
            }
        }
    }

    @ViewBuilder func decisionButtons(_ j: ClipJob, _ nextPrice: Double) -> some View {
        let again = OpenRouter.formatUSD(model.clipPriceUSD([j.secondsList[min(j.index, j.secondsList.count - 1)]], sharp: sec.clipOptions.sharp))
        if j.chain {
            if j.index < j.secondsList.count - 1 {
                Button { model.decideClip(.next) } label: { Label("Looks good — make the next (≈ \(OpenRouter.formatUSD(nextPrice)))", systemImage: "forward.fill") }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            } else { Button { model.decideClip(.next) } label: { Label("Looks good — finish", systemImage: "checkmark") }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
            Button { model.decideClip(.redo) } label: { Label("Redo this clip (≈ \(again))", systemImage: "arrow.counterclockwise") }
            Button { model.decideClip(.stop) } label: { Label("Stop here (keep these)", systemImage: "stop.fill") }
        } else {
            Button { model.decideClip(.use) } label: { Label("Use this clip", systemImage: "checkmark") }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            Button { model.decideClip(.redo) } label: { Label("Redo (≈ \(again))", systemImage: "arrow.counterclockwise") }
            Button { model.decideClip(.discard) } label: { Label("Discard", systemImage: "trash") }
        }
    }
}
