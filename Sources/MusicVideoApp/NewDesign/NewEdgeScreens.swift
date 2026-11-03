// The New Design's first-launch setup (3i), update dialog (3j) and the Settings look (3h).
import SwiftUI
import MVCore

/// One-time setup: choose a size, download once, then it all runs on this Mac.
struct NewSetupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Music Video Maker").font(Classical.heading(22)).foregroundStyle(Classical.neutral700)
            ClassicalHeading(text: "One-time setup", size: 38)
            Text("Listening to your song and writing picture ideas happen on this Mac. Choose a size. It downloads once, then works offline.").font(Classical.body(14)).foregroundStyle(Classical.neutral700).fixedSize(horizontal: false, vertical: true)
            if model.settingUp {
                ProgressPanel(fraction: model.setupProgress, phase: model.setupPhase, started: model.setupStarted)
                ModelRows()
            } else {
                VStack(spacing: 0) {
                    Hairline()
                    ForEach([("small", "Small", "fastest, plainer ideas", "1.5 GB"), ("balanced", "Balanced", "Gemma 4 E2B, recommended", "4.1 GB"), ("best", "Best", "richest ideas, needs 16 GB", "6.5 GB")], id: \.0) { id, name, note, size in
                        Button { model.nativeTier = id } label: {
                            HStack(spacing: 12) {
                                ZStack { Circle().stroke(model.nativeTier == id ? Classical.accent : Classical.neutral300, lineWidth: 1).frame(width: 16, height: 16); if model.nativeTier == id { Circle().fill(Classical.accent).frame(width: 8, height: 8) } }
                                Text(name).font(Classical.body(14, weight: .semibold)); Text("· " + note).font(Classical.body(13)).foregroundStyle(Classical.neutral700)
                                Spacer(); Text(size).font(Classical.body(13).monospacedDigit()).foregroundStyle(Classical.neutral700)
                            }.padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Bigger models write better picture ideas but need more space and time to download. Balanced is right for most Macs.")
                        Hairline()
                    }
                }
                Text("Every size includes Parakeet Ultra (0.5 GB) for word-accurate lyric timing.").font(Classical.body(12)).foregroundStyle(Classical.neutral600)
                ModelRows()
                Button("Download & set up") { model.runNativeSetup() }.buttonStyle(.classicalPrimary).help("Downloads the AI models (one time, needs internet). The progress is shown here.")
            }
        }.frame(maxWidth: 560).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) { Button { model.helpScreen = "First-time setup (downloading models)"; model.showHelp = true } label: { Image(systemName: "questionmark.circle") }.buttonStyle(.plain).foregroundStyle(Classical.neutral700).padding(20) }
    }
}

/// Settings, written in the New Design's look: the same groups and the same switches, quieter.
struct NewSettingsStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(Classical.body(13)).tint(Classical.accent).scrollContentBackground(.hidden).background(Classical.bg).environment(\.colorScheme, .light)
    }
}
extension View { @ViewBuilder func newDesignSettings(_ on: Bool) -> some View { if on { modifier(NewSettingsStyle()) } else { self } } }

/// The update dialog (design 3j): what's new, then Later, Skip this version or Install & restart.
struct NewUpdateSheet: View {
    @EnvironmentObject var updater: Updater
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let r = updater.available {
                ClassicalHeading(text: "Update \(r.version)", note: "You have \(Updater.current)", size: 30)
                Text("What's new").font(Classical.body(12, weight: .semibold)).foregroundStyle(Classical.neutral700)
                ScrollView { Text(r.notes.isEmpty ? "Improvements and fixes." : r.notes).font(Classical.body(13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(height: 220).padding(12).background(Classical.paper).overlay(RoundedRectangle(cornerRadius: 4).stroke(Classical.divider, lineWidth: 1))
                if updater.isInstalling {
                    VStack(alignment: .leading, spacing: 6) { Text(updater.phase).font(Classical.body(12, weight: .semibold)); ProgressView(value: updater.progress ?? 0).tint(Classical.accent) }
                } else {
                    Text("Updating takes about a minute and keeps your songs, pictures and settings. The open project is backed up first, and the app restarts by itself.").font(Classical.body(12)).foregroundStyle(Classical.neutral700).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Later") { dismiss() }.buttonStyle(.classical).disabled(updater.isInstalling).help("Keep using this version. The Update tag stays at the top.")
                    Button("Skip this version") { updater.skip(r.version); dismiss() }.buttonStyle(.classicalGhost).help("Do not prompt for this release again. Later versions are still offered.")
                    Spacer()
                    Button("Install & restart") { Task { await updater.install(r) } }.buttonStyle(.classicalPrimary).keyboardShortcut(.defaultAction).disabled(updater.isInstalling)
                }
            } else {
                ClassicalHeading(text: "You're up to date", size: 30)
                HStack { Spacer(); Button("OK") { dismiss() }.buttonStyle(.classicalPrimary).keyboardShortcut(.defaultAction) }
            }
        }.padding(26).frame(width: 540).background(Classical.bg).environment(\.colorScheme, .light)
    }
}
