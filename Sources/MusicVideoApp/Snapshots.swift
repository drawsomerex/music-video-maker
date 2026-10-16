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
        func save(_ name: String, _ size: CGSize, _ view: some View) {
            let r = ImageRenderer(content: view.environmentObject(model).frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        save("setup", CGSize(width: 1120, height: 760), SetupView())
        save("guide", CGSize(width: 600, height: 560), QuickGuideView())
        save("settings", CGSize(width: 600, height: 560), SettingsView())
        if model.plan != nil {
            save("plan", CGSize(width: 1120, height: 760), PlanView())
        }
        NSApplication.shared.terminate(nil)
    }
}
