// What you see when a new version exists: a strip across the top of the window, a details sheet, and the Settings section.
import SwiftUI

/// A strip at the top of the window: "Update available" with one clear button; shows progress while it installs.
struct UpdateStrip: View {
    @EnvironmentObject var updater: Updater
    var visible: Bool { updater.isInstalling || (updater.available != nil && !updater.bannerDismissed) }
    var body: some View {
        if visible, let r = updater.available {
            HStack(spacing: 14) {
                Image(systemName: updater.isInstalling ? "arrow.down.circle" : "gift.fill").font(.title2).foregroundStyle(.white)
                if updater.isInstalling {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(updater.phase).font(.headline).foregroundStyle(.white)
                        ProgressView(value: updater.progress ?? 0).tint(.white).frame(maxWidth: 360)
                    }
                    Spacer()
                    Text("The app will restart by itself").font(.callout).foregroundStyle(.white.opacity(0.85))
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update available — version \(r.version)").font(.headline).foregroundStyle(.white)
                        Text("You have version \(Updater.current). Updating takes about a minute and keeps all your work.").font(.callout).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Button("What's new") { updater.showAvailable = true }
                        .buttonStyle(.bordered).tint(.white).controlSize(.large)
                        .help("Read what has changed in this version.")
                    Button { Task { await updater.install(r) } } label: { Label("Update now", systemImage: "arrow.down.circle.fill").font(.headline) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.blue).controlSize(.large)
                        .help("Downloads the new version, installs it and restarts the app. Your songs, pictures and settings are kept.")
                    Button("Later") { updater.bannerDismissed = true }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.9))
                        .help("Hides this message until you open the app again. You can always update from the Help menu.")
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .leading, endPoint: .trailing))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Details of the new version with the release notes and the Update button.
struct UpdateSheet: View {
    @EnvironmentObject var updater: Updater
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let r = updater.available {
                HStack(spacing: 12) {
                    Image(systemName: "gift.fill").font(.system(size: 30)).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update available").font(.title.bold())
                        Text("Version \(r.version) is ready. You have version \(Updater.current).").foregroundStyle(.secondary)
                    }
                }
                Text("What's new").font(.headline)
                ScrollView {
                    Text(r.notes.isEmpty ? "Improvements and fixes." : r.notes).font(.callout).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(height: 220).padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
                if updater.isInstalling {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(updater.phase).font(.callout.weight(.medium))
                        ProgressView(value: updater.progress ?? 0)
                    }
                } else {
                    Text("Your songs, pictures and settings are kept. The app restarts by itself when it is done.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Skip this version") { updater.skip(r.version); dismiss() }.help("Do not prompt for this release again. Later versions are still offered.")
                    Spacer()
                    Button("Not now") { dismiss() }.disabled(updater.isInstalling).help("Keep using this version. The “Update available” message stays at the top until you update.")
                    Button { Task { await updater.install(r) } } label: { Label("Update now", systemImage: "arrow.down.circle.fill").padding(.horizontal, 6) }
                        .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction).disabled(updater.isInstalling)
                        .help("Downloads and installs the new version, then restarts the app.")
                }
            } else {
                Text("You're up to date").font(.title.bold())
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 520)
    }
}

/// Settings ▸ Updates.
struct UpdatesSettingsSection: View {
    @EnvironmentObject var updater: Updater
    var body: some View {
        Section("Updates") {
            LabeledContent("This version") { Text(Updater.current) }
            LabeledContent("Status") { Text(updater.statusText).foregroundStyle(updater.available == nil ? Color.secondary : Color.blue) }
            LabeledContent("") {
                HStack {
                    Button("Versions & rollback…") { updater.showVersions = true }.disabled(updater.isInstalling).help("Choose a version, revert, stay on a version or manage skipped releases.")
                    if updater.available != nil {
                        Button("Update now…") { updater.showAvailable = true }.buttonStyle(.borderedProminent)
                            .help("Shows what is new and installs the update.")
                    }
                    Button(updater.busy && !updater.isInstalling ? "Checking…" : "Check for updates") { Task { await updater.check(silent: false) } }
                        .disabled(!Updater.enabled || updater.busy)
                        .help("Looks online for a newer version of Music Video Maker.")
                }
            }
            HStack {
                Button("Stay on this version") { updater.holdCurrent() }.disabled(!updater.heldVersion.isEmpty).help("Keep this release until you choose to resume update prompts.")
                if !updater.heldVersion.isEmpty { Button("Resume updates") { updater.resumeUpdates() }.help("Allow update notifications again.") }
            }
            if let t = updater.lastChecked { Text("Last checked \(t.formatted(date: .abbreviated, time: .shortened)). The app also checks by itself about once a day.").font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct VersionsSheet: View {
    @EnvironmentObject var updater: Updater
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Updater.Release?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("App versions").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.help("Close version management.") }
            Text("Installed: \(Updater.current)").font(.headline)
            HStack {
                if updater.heldVersion.isEmpty {
                    Button("Stay on this version") { updater.holdCurrent() }.help("Stop update prompts until you choose to resume them.")
                } else {
                    Text("Staying on \(updater.heldVersion)")
                    Button("Resume update notifications") { updater.resumeUpdates() }.help("Allow the app to notify you about newer versions again.")
                }
                Spacer()
                Button("Refresh list") { Task { await updater.loadVersions() } }.disabled(updater.busy).help("Fetch available standalone versions from GitHub.")
            }
            Text("Changing versions saves a backup of your open project. Earlier apps may lack these editing and version controls; use their Check for Updates command to return to a newer release.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if updater.isInstalling { Text(updater.phase); ProgressView(value: updater.progress ?? 0) }
            else if updater.busy { ProgressView("Loading versions…") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(updater.releases) { r in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Version \(r.version)").font(.headline)
                                if r.version == Updater.current { Text("Installed").foregroundStyle(.secondary) }
                                if updater.skippedVersions.contains(r.version) { Text("Skipped").foregroundStyle(.secondary) }
                                Spacer()
                                if r.version != Updater.current {
                                    Button(Updater.isNewer(Updater.current, than: r.version) ? "Revert to this version…" : "Install this version…") { selected = r }
                                        .disabled(updater.busy).help("Review and install exactly version \(r.version). The app will restart.")
                                }
                            }
                            DisclosureGroup("Release notes") { Text(r.notes.isEmpty ? "No release notes were supplied." : r.notes).textSelection(.enabled).font(.body).padding(.vertical, 6) }
                                .help("Read the changes included in this version.")
                            if r.version != Updater.current {
                                Button(updater.skippedVersions.contains(r.version) ? "Stop skipping this version" : "Skip this version") {
                                    if updater.skippedVersions.contains(r.version) { updater.unskip(r.version) } else { updater.skip(r.version) }
                                }.disabled(updater.busy).help("A skipped release will not produce automatic prompts. Later releases are still offered.")
                            }
                        }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if !updater.skippedVersions.isEmpty {
                Text("Skipped: " + updater.skippedVersions.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                Button("Clear skipped versions") { updater.skippedVersions = [] }.help("Allow update prompts for all versions again. Staying on a version is a separate setting.")
            }
        }.padding(20).frame(minWidth: 740, idealWidth: 820, minHeight: 480, idealHeight: 620)
        .task { await updater.loadVersions() }
        .confirmationDialog("Install version \(selected?.version ?? "") and restart?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
            Button("Install and restart") { if let r = selected { Task { await updater.install(r) } }; selected = nil }
            Button("Cancel", role: .cancel) { selected = nil }
        } message: { Text("Your open project is backed up first. Reverting to an earlier version automatically pauses update notifications.") }
    }
}
