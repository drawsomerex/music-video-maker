// App entry point, menus and windows.
import SwiftUI
import MVCore
#if NATIVE_MLX
import MVNative
#endif

@main
struct MusicVideoApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = Updater()
    init() {
        #if NATIVE_MLX
        NativeEngine.register()
        #endif
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some Scene {
        WindowGroup("Music Video Maker") {
            RootView()
                .environmentObject(model)
                .environmentObject(updater)
                .task {
                    if Snapshots.directory != nil { FileHandle.standardError.write(Data("[snapshots] task start\n".utf8)); try? await Task.sleep(nanoseconds: 1_500_000_000); Snapshots.render(model: model); return }
                    Updater.log("task started; enabled=\(Updater.enabled) current=\(Updater.current)")
                    if Updater.env["MV_UPDATE_SELFTEST"] != nil {            // test hook: check, then install without asking
                        await updater.check(silent: false)
                        if let r = updater.available { FileHandle.standardError.write(Data("update found: \(r.version)\n".utf8)); await updater.install(r) }
                        else { FileHandle.standardError.write(Data("no update: \(updater.message ?? "")\n".utf8)) }
                    } else if updater.dueForAutoCheck { await updater.check(silent: true) }
                }
                .alert("Update available", isPresented: $updater.showAvailable, presenting: updater.available) { r in
                    Button("Install & Restart") { Task { await updater.install(r) } }
                    Button("Later", role: .cancel) {}
                } message: { r in Text("Music Video Maker \(r.version) is ready (you have \(Updater.current)).\n\n\(r.notes.prefix(600))") }
                .alert("Updates", isPresented: Binding(get: { updater.message != nil }, set: { if !$0 { updater.message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(updater.message ?? "") }
                .overlay(alignment: .bottom) {
                    if let p = updater.progress { VStack(spacing: 6) { Text("Downloading update…").font(.caption); ProgressView(value: p).frame(width: 220) }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 20) }
                }
                .sheet(isPresented: $model.showGuide) { QuickGuideView() }
                .frame(minWidth: 980, minHeight: 680)
                .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(model.errorMessage ?? "") }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("Quick Guide") { model.showGuide = true }.keyboardShortcut("?", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.check(silent: false) } }.disabled(!Updater.enabled)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 760)
        Settings { SettingsView().environmentObject(model) }
    }
}
