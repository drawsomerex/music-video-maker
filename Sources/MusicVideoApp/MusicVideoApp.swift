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
        if Updater.env["MV_REPORT_TEST"] != nil {          // developer test: send one report, check its status, print what happened
            Task { @MainActor in
                let c = ReportCenter()
                let ok = await c.send(text: "Test report: the Make button did nothing.\nSecond line", screen: "Test screen", includeTechnical: true)
                let done = await c.refresh()
                FileHandle.standardError.write(Data("report sent=\(ok) error=\(c.error ?? "-") saved=\(c.reports.map { "\($0.number):\($0.state)" }) done=\(done.count)\n".utf8))
                NSApplication.shared.terminate(nil)
            }
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some Scene {
        WindowGroup("Music Video Maker") {
            RootView()
                .environmentObject(model)
                .environmentObject(updater)
                .task {
                    if let mode = Updater.env["MV_EDITOR_SELFTEST"] {
                        if mode == "check" { await EditorChecks.run(model: model, updater: updater); NSApplication.shared.terminate(nil) }
                        else if mode == "update" || mode == "rollback" || mode == "bad-checksum" {
                            if mode == "rollback" { await updater.loadVersions(); updater.available = updater.releases.last }
                            else { await updater.check(silent: false) }
                            if let r = updater.available { await updater.install(r) }
                            if let error = updater.message { FileHandle.standardError.write(Data(("UPDATER RESULT: " + error + "\n").utf8)); NSApplication.shared.terminate(nil) }
                        }
                        return
                    }
                    if let f = Updater.env["MV_HELP_TEST"] {          // developer check of the help assistant: one question per line, answers go to stderr
                        let status = model.helpStatus(screen: Updater.env["MV_HELP_SCREEN"] ?? model.screenName)
                        FileHandle.standardError.write(Data("STATUS:\n\(status)\n\n".utf8))
                        for q in ((try? String(contentsOfFile: f, encoding: .utf8)) ?? "").components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                            let a = await HelpAssistant.answer(question: q, status: status, config: model.config)
                            FileHandle.standardError.write(Data("Q: \(q)\nA: \(a.text)\n[ai=\(a.fromAI) sources=\(a.sources.joined(separator: " | ")) notes=\(a.notes)]\n\n".utf8))
                        }
                        NSApplication.shared.terminate(nil); return
                    }
                    if Snapshots.directory != nil { FileHandle.standardError.write(Data("[snapshots] task start\n".utf8)); try? await Task.sleep(nanoseconds: 1_500_000_000); Snapshots.render(model: model); return }
                    Updater.log("task started; enabled=\(Updater.enabled) current=\(Updater.current)")
                    if Updater.env["MV_UPDATE_SELFTEST"] != nil {            // test hook: check, then install without asking
                        await updater.check(silent: false)
                        if let r = updater.available { FileHandle.standardError.write(Data("update found: \(r.version)\n".utf8)); await updater.install(r) }
                        else { FileHandle.standardError.write(Data("no update: \(updater.message ?? "")\n".utf8)) }
                    } else if updater.dueForAutoCheck { await updater.check(silent: true) }
                    let fixed = await model.reportCenter.refresh()
                    if let f = fixed.first { model.notice = "Good news: the problem you reported (“\(f.title)”) is fixed." + (f.reply.isEmpty ? "" : "\n\n\(f.reply)") + "\n\nSee Help ▸ Report a Problem ▸ My reports." }
                }
                .onAppear { updater.beforeInstall = {
                    guard !model.busy, !model.listening, model.stage != .rendering, model.videoJob == nil, model.stage != .working, model.shortProgress == nil, !model.timelineDragging else { throw MVError("Finish or cancel the current task before changing app versions.") }
                    try await model.backupForVersionChange()
                } }
                .sheet(isPresented: $updater.showVersions) { VersionsSheet().environmentObject(updater) }
                .sheet(isPresented: $updater.showAvailable) { UpdateSheet().environmentObject(updater) }
                .alert("Updates", isPresented: Binding(get: { updater.message != nil }, set: { if !$0 { updater.message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(updater.message ?? "") }
                .sheet(isPresented: $model.showGuide) { QuickGuideView() }
                .sheet(isPresented: $model.showHelp) { HelpCenterView().environmentObject(model) }
                .sheet(isPresented: $model.showReport) { ReportSheet(center: model.reportCenter).environmentObject(model) }
                .sheet(isPresented: $model.showRecordingFix) { RecordingFixSheet().environmentObject(model) }
                .frame(minWidth: 860, minHeight: 560)
                .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK", role: .cancel) {}
                    Button("Report this problem") { model.reportPrefill = "I saw this message: " + (model.errorMessage ?? "") + "\n\nI was trying to: "; model.showReport = true }
                } message: { Text(model.errorMessage ?? "") }
        }
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button(model.editUndo.last.map { "Undo " + $0.name } ?? "Undo") {
                    if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable, text.undoManager?.canUndo == true { text.undoManager?.undo() } else { model.undoEdit() }
                }.keyboardShortcut("z", modifiers: .command)
                    .disabled(updater.isInstalling || !model.historyAvailable || (model.editUndo.isEmpty && (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canUndo != true))
                Button("Redo") {
                    if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable, text.undoManager?.canRedo == true { text.undoManager?.redo() } else { model.redoEdit() }
                }.keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(updater.isInstalling || !model.historyAvailable || (model.editRedo.isEmpty && (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canRedo != true))
            }
            CommandGroup(after: .newItem) {
                Button("Projects…") { model.showProjects = true }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                Button("Help & Questions…") { model.helpScreen = model.screenName; model.showHelp = true }.keyboardShortcut("?", modifiers: .command)
                Button("Quick Guide") { model.showGuide = true }
                Button("Report a Problem…") { model.showReport = true }
                Divider()
                Button(updater.available.map { "Update to Version \($0.version)…" } ?? "Check for Updates…") {
                    if updater.available != nil { updater.showAvailable = true } else { Task { await updater.check(silent: false) } }
                }.disabled(!Updater.enabled || updater.isInstalling)
            }
            CommandGroup(after: .appInfo) {
                Button("Versions & Rollback…") { updater.showVersions = true }.disabled(updater.isInstalling)
                Button(updater.available.map { "Update to Version \($0.version)…" } ?? "Check for Updates…") {
                    if updater.available != nil { updater.showAvailable = true } else { Task { await updater.check(silent: false) } }
                }.disabled(!Updater.enabled || updater.isInstalling)
            }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        Settings { SettingsView().environmentObject(model).environmentObject(updater) }
    }
}
