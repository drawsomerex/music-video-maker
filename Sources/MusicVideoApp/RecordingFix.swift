// Repairs the "Screen & System Audio Recording" permission, which macOS ties to the exact app and can leave stale after an update.
import SwiftUI
import CoreGraphics

enum RecordingPermission {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.drawsomerex.musicvideomaker"

    /// Forgets the old permission entry for this app, asks macOS for it again, and opens the right Settings page.
    static func reset() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil"); p.arguments = ["reset", "ScreenCapture", bundleID]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        _ = CGRequestScreenCaptureAccess()
        openSettings()
    }
    static func openSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(u) }
    }
    /// Quits and reopens the app; macOS only applies a new Screen Recording permission to a freshly started app.
    static func relaunch() {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApplication.shared.terminate(nil)
    }
}

struct RecordingFixSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var didReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic").font(.system(size: 30)).foregroundStyle(.tint)
                Text("Let's fix recording").font(.title.bold())
            }
            Text("After an update, macOS can show the permission switch as ON while still blocking the new version of the app. Clearing the old entry and allowing the app again fixes it. It takes three clicks.")
                .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                step("1", "Press “Fix it for me”. A System Settings page opens.", done: didReset)
                step("2", "Switch “Music Video Maker” ON in the list (or press Allow if macOS asks).", done: false)
                step("3", "Come back and press “Restart the app”. Then try recording again.", done: false)
            }
            HStack {
                Button("Use microphone instead") { model.recordSource = .microphone; dismiss() }
                    .help("Skips the fix and records through a microphone or audio input instead of the computer's own sound.")
                Spacer()
                Button("Close") { dismiss() }
                Button { RecordingPermission.reset(); didReset = true } label: { Label("Fix it for me", systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .help("Clears the old permission entry, asks macOS again and opens the right System Settings page.")
                Button { RecordingPermission.relaunch() } label: { Label("Restart the app", systemImage: "arrow.clockwise") }
                    .controlSize(.large).disabled(!didReset)
                    .help("Closes and reopens Music Video Maker so the new permission takes effect. Your work is saved automatically.")
            }
        }
        .padding(24).frame(width: 640)
    }
    func step(_ n: String, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack { Circle().fill(done ? Color.green : Color.accentColor.opacity(0.18)).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) } else { Text(n).font(.callout.weight(.bold)).foregroundStyle(.tint) } }
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
