// Under a picture: choose Ken Burns (the default) or a HeyGen video clip, make clips (one, or the whole section back to back), and watch each one.
import SwiftUI
import AVKit
import MVCore

struct ClipPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(16.0 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear { player = AVPlayer(url: url) }
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
            if let j = job { jobView(j) }
            else if sec.clips.isEmpty { makeButtons }
            else { clipList }
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
        } message: { Text("The picture stays. You can make new clips later (that costs again).") }
    }

    func price(_ chain: Bool) -> Double { model.clipPriceUSD(model.clipSeconds(section: section, chain: chain)) }
    var confirmTitle: String { confirmChain == true ? "Make the whole section as video?" : "Make a video clip?" }
    func confirmMessage(_ chain: Bool) -> String {
        let l = model.clipSeconds(section: section, chain: chain)
        let cr = model.openRouterCredits.map { " Your OpenRouter credit: \(OpenRouter.formatCredits($0))." } ?? ""
        return chain ? "\(l.count) clip\(l.count == 1 ? "" : "s") (\(l.map { "\($0) s" }.joined(separator: " + "))) at HeyGen's list price of \(OpenRouter.formatUSD(model.videoPricePerSecond)) per second. Each clip starts on the last frame of the one before, and you watch each one before the next is made.\(cr)"
                     : "A \(l.first ?? 0)-second clip starting from this picture, at HeyGen's list price of \(OpenRouter.formatUSD(model.videoPricePerSecond)) per second.\(cr) HeyGen has been charging half of the list price during a promotion."
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
                    Button { confirmChain = true } label: { Label("Make the whole section as video (\(many.count) clips ≈ \(OpenRouterVideo.formatPrice(model.clipPriceUSD(many))))", systemImage: "film.stack") }
                        .disabled(model.busy)
                        .help("Covers the whole section with back-to-back clips, each starting on the last frame of the one before. You watch each clip before the next is made.")
                }
            }
            Text("Ken Burns stays unless you choose video. Prices are HeyGen's list price (half while their promotion runs); the real cost is shown afterwards.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                    Button { confirmChain = true } label: { Label("Continue with more video (\(more.count) clip\(more.count == 1 ? "" : "s") ≈ \(OpenRouterVideo.formatPrice(model.clipPriceUSD(more))))", systemImage: "film.stack") }
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
        } else if j.waiting, let c = sec.clips.last, let w = work {
            VStack(alignment: .leading, spacing: 8) {
                Text(j.chain ? "Clip \(j.index + 1) of \(j.secondsList.count) is ready — watch it" : "Your clip is ready — watch it").font(.callout.weight(.semibold))
                ClipPlayer(url: w.appendingPathComponent(c.file)).frame(maxWidth: 420)
                Text(j.chain ? "It is already in use. Redo it if you don't like it." : "It is already switched on, with Ken Burns carrying on after it. Redo or discard it if you don't like it.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let warn = c.warning { Label("Realism check: \(warn)", systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Text("Cost: \(OpenRouter.formatUSD(c.costUSD))").font(.caption).foregroundStyle(.secondary)
                let nextPrice = model.clipPriceUSD(Array(j.secondsList.dropFirst(j.index + 1).prefix(1)))
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
        let again = OpenRouter.formatUSD(model.clipPriceUSD([j.secondsList[min(j.index, j.secondsList.count - 1)]]))
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
