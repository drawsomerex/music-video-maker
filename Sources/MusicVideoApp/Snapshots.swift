// Developer aid: `MV_SNAPSHOT_DIR=/some/folder` renders the main screens to PNG files and quits (used to check layouts without a display).
import SwiftUI
import AppKit

@MainActor
enum Snapshots {
    static var directory: URL? { ProcessInfo.processInfo.environment["MV_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) } }

    static func render(model: AppModel) {
        guard let dir = directory else { return }
        FileHandle.standardError.write(Data("[snapshots] rendering to \(dir.path)\n".utf8))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        model.title = "Highway Lights"; model.subject = "A song for the open road"
        model.lyrics = "The road is wide and the sky is high\nWe're chasing the sun as the day goes by\n\nHighway lights, hold me tight"
        if model.plan != nil { model.plan?.totalGenerationCostUSD = 0.432; model.plan?.imagesGeneratedCount = 9; model.plan?.sections[2].candidates = []; model.plan?.sections[2].selected = -1; model.plan?.sections[5].candidates = []; model.plan?.sections[5].selected = -1 }
        let updater = Updater()
        updater.available = Updater.Release(version: "9.9.9", notes: "• Easier screens\n• Captions now follow the singing more closely\n• Bug fixes", zip: URL(string: "https://example.com/x.zip")!, sha256: nil, page: nil)
        func save(_ name: String, _ size: CGSize, _ view: some View) {
            let r = ImageRenderer(content: view.environmentObject(model).environmentObject(updater).frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        model.lyrics = "The road is wide and the sky is high\nWe're chasing the sun as the day goes by\n---\nHighway lights, hold me tight\nThrough the quiet of the night\nHeadlights flicker, engines hum\n---\nWhen the morning light has come\nWe will find our way back home"
        save("divide", CGSize(width: 520, height: 560), LyricDividerView(scrollable: false).padding())
        save("setup", CGSize(width: 1120, height: 760), SetupView())
        save("setup-small", CGSize(width: 860, height: 560), SetupView())
        save("cost-bar", CGSize(width: 1000, height: 40), CostBar())
        save("cost-bar-small", CGSize(width: 700, height: 40), CostBar())
        save("style-sheet", CGSize(width: 640, height: 700), StyleSheet(inProject: true))
        save("help", CGSize(width: 720, height: 620), HelpCenterView())
        save("ideas", CGSize(width: 560, height: 380), SettingIdeasSheet(applyToProject: false))
        save("update-strip", CGSize(width: 1120, height: 70), UpdateStrip())
        save("update-sheet", CGSize(width: 520, height: 420), UpdateSheet())
        save("recording-fix", CGSize(width: 560, height: 360), RecordingFixSheet())
        save("first-run", CGSize(width: 760, height: 620), NativeSetupView())
        save("guide", CGSize(width: 600, height: 560), QuickGuideView())
        save("settings", CGSize(width: 600, height: 560), SettingsView())
        if model.plan != nil {
            save("plan", CGSize(width: 1120, height: 760), PlanView())
            save("plan-small", CGSize(width: 860, height: 560), PlanView())
        }
        NSApplication.shared.terminate(nil)
    }
}
