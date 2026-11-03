// Stage 4 · Export (design 2h): what to make, the checks, the last video made, and Activity beside it.
import SwiftUI
import AVKit
import MVCore

struct NewExportStage: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nd: NewDesignState
    @State private var confirmMissing = false

    var plan: Plan? { model.plan }
    var health: ExportHealth? { plan.flatMap { p in model.workDir.map { ExportHealth.music(p, work: $0, height: model.quality) } } }
    var shortsCount: Int { plan?.shorts.count ?? 0 }
    var running: Bool { model.videoJob != nil }

    var body: some View {
        if model.stage == .loop { LoopView(part: .export) } else if plan == nil { NewMusicSongStage() } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        what
                        Hairline()
                        checks
                        if lastMade != nil { Hairline(); lastMadeView }
                        Hairline()
                        youtube
                    }.frame(maxWidth: 760).padding(30).frame(maxWidth: .infinity, alignment: .leading)
                }
                footer
            }
            .confirmationDialog("Some pictures are still blank", isPresented: $confirmMissing, titleVisibility: .visible) {
                Button("Make the video anyway") { model.render() }
                Button("Not yet", role: .cancel) {}
            } message: { Text("\(model.missing.count) of the pictures are blank. They get a plain background colour in the video.") }
        }
    }

    // MARK: what to make
    var what: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClassicalHeading(text: "What to make")
            HStack(spacing: 14) {
                check(true, locked: true) {}
                Text("Full video").font(Classical.body(14, weight: .semibold))
                HStack(spacing: 0) { ForEach([(720, "720p"), (1080, "1080p"), (2160, "4K")], id: \.0) { q, t in
                    Button { model.quality = q } label: { Text(t).font(Classical.body(12)).foregroundStyle(model.quality == q ? Classical.accent700 : Classical.neutral700).padding(.horizontal, 12).padding(.vertical, 5).background(model.quality == q ? Classical.accent100 : .clear) }.buttonStyle(.plain)
                } }.overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                    .help("1080p HD is right for YouTube. 4K is sharper but takes much longer and makes a bigger file.")
            }
            HStack(spacing: 14) {
                check(model.autoRenderShorts && shortsCount > 0) { model.autoRenderShorts.toggle() }.disabled(shortsCount == 0)
                Text(shortsCount == 0 ? "No Shorts yet" : "\(shortsCount) Short\(shortsCount == 1 ? "" : "s")").font(Classical.body(14, weight: .semibold))
                Text(shortsCount == 0 ? "choose some in stage 3" : "from stage 3").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
            }.help("Also make the YouTube Shorts when the main video is made.")
            HStack(spacing: 14) {
                check(true, locked: true) {}
                Text("YouTube thumbnail & description").font(Classical.body(14, weight: .semibold))
                Text("made with the video").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
            }
        }
    }
    func check(_ on: Bool, locked: Bool = false, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            ZStack { RoundedRectangle(cornerRadius: 3).stroke(on ? Classical.accent : Classical.neutral300, lineWidth: 1).frame(width: 16, height: 16)
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Classical.accent700) } }
        }.buttonStyle(.plain).opacity(locked ? 0.7 : 1)
    }

    // MARK: checks
    var checks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClassicalHeading(text: "Checks")
            let h = health
            let songOK = !(h?.errors.contains { $0.contains("song file") } ?? false)
            line(songOK, songOK ? "Song and every picture found" : (h?.errors.first ?? "Something is missing"))
            line((model.plan?.timing == "exact"), ((model.plan?.timing == "exact")) ? "Word timing is exact" : "Word timing is rough")
            if model.plan?.timing != "exact" { CLink(title: "Fix it") { model.resync() } }
            line(model.clipJob == nil, model.clipJob == nil ? "No paid clips waiting" : "A paid clip is still being made")
            line(true, "Nothing to pay. Rendering runs on this Mac.")
            ForEach(h?.warnings ?? [], id: \.self) { w in Text("Note: " + w).font(Classical.body(12)).foregroundStyle(Classical.accent800) }
            if !model.missing.isEmpty { line(false, "\(model.missing.count) picture\(model.missing.count == 1 ? " is" : "s are") still blank") }
        }
    }
    func line(_ ok: Bool, _ t: String) -> some View {
        HStack(spacing: 8) { Image(systemName: ok ? "checkmark" : "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(ok ? Classical.ok : Classical.warn); Text(t).font(Classical.body(13)) }
    }

    // MARK: last made
    var lastMade: URL? { model.outputURL }
    var lastMadeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClassicalHeading(text: "Last made")
            if let u = lastMade {
                Text(u.lastPathComponent + (model.renderedShorts.isEmpty ? "" : " + \(model.renderedShorts.count) Short\(model.renderedShorts.count == 1 ? "" : "s")")).font(Classical.body(13)).foregroundStyle(Classical.neutral800)
                HStack(spacing: 10) {
                    Button("Watch") { FullScreenPlayer.show(u, title: model.plan?.title ?? "Video", loop: false, muted: false) }.buttonStyle(.classical)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u] + model.renderedShorts) }.buttonStyle(.classical)
                    ShareLink(item: u) { Text("Share") }.buttonStyle(.classical)
                }
                HStack(spacing: 8) {
                    Text("Words look early or late?").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                    CLink(title: "Show sooner") { model.nudgeCaptions(by: -0.1) }; CLink(title: "Show later") { model.nudgeCaptions(by: 0.1) }
                }
            }
        }
    }

    // MARK: YouTube files
    var youtube: some View {
        YouTubeFilesRow(files: model.lyricYouTubeFiles, busy: model.youtubeBusy,
                        text: Binding(get: { model.plan?.thumbText ?? ThumbnailText() }, set: { model.setLyricThumbText($0) }),
                        auto: model.plan.map { model.lyricThumbAuto($0) } ?? ("", nil, nil), revision: model.thumbRevision) { model.remakeYouTubeFiles() }
    }

    // MARK: footer
    var footer: some View {
        CFooter {
            Text(running ? "Making your video… you can keep working." : "About 4 minutes on this Mac. You can keep working while it runs.").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
        } right: {
            Button { model.missing.isEmpty ? model.render() : (confirmMissing = true) } label: {
                Text(model.autoRenderShorts && shortsCount > 0 ? "Make video & \(shortsCount) Short\(shortsCount == 1 ? "" : "s")" : "Make video")
            }.buttonStyle(.classicalPrimary).disabled(model.busy || running).keyboardShortcut(.return, modifiers: .command)
                .help(model.autoRenderShorts ? "Creates the finished video and the YouTube Shorts. You can watch the progress and cancel at any time." : "Creates the finished video file.")
        }
    }
}
