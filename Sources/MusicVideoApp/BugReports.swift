// "Report a problem": anyone can tell the author about a bug from inside the app, and later see here whether it is fixed.
//
// How it works: the report is sent to a tiny relay (relay/worker.js on Cloudflare) that files it as a GitHub Issue — so the sender needs no
// account and no secret is stored in the app. The author closes the issue (with a comment) to mark it completed. The app reads the issue's
// public status from GitHub (no login) and shows it under "My reports". Only what the person types plus the app/macOS/Mac type is sent.
import SwiftUI
import AppKit

struct SentReport: Codable, Identifiable, Equatable {
    var id: Int { number }
    var number: Int
    var title: String
    var date: Date
    var state = "open"            // "open" or "closed"
    var inProgress = false
    var reply = ""                // the author's latest comment
    var notified = false          // the person has been told it is done
}

@MainActor
final class ReportCenter: ObservableObject {
    @Published var reports: [SentReport] = []
    @Published var sending = false
    @Published var checking = false
    @Published var error: String?

    static var endpoint: URL? { let baked = Updater.info["MVReportURL"] as? String ?? ""; let s = baked.isEmpty ? (ProcessInfo.processInfo.environment["MV_REPORT_URL"] ?? "") : baked; return s.isEmpty ? nil : URL(string: s) }
    static var repo: String { Updater.repo ?? "drawsomerex/music-video-maker" }
    private var file: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicVideo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reports.json")
    }
    init() { load() }
    func load() { if let d = try? Data(contentsOf: file), let r = try? JSONDecoder().decode([SentReport].self, from: d) { reports = r } }
    func save() { if let d = try? JSONEncoder().encode(reports) { try? d.write(to: file, options: .atomic) } }

    static func technical() -> [String: String] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
        var m = [CChar](repeating: 0, count: max(1, size)); sysctlbyname("hw.model", &m, &size, nil, 0)
        let ram = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        return ["version": Updater.current, "macos": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", "mac": "\(String(cString: m)), \(ram) GB"]
    }

    /// Sends a report. Returns true when it was filed.
    func send(text: String, screen: String, includeTechnical: Bool) async -> Bool {
        guard let url = Self.endpoint else { return false }
        sending = true; error = nil; defer { sending = false }
        var body: [String: String] = ["text": text]
        if includeTechnical { body.merge(Self.technical()) { a, _ in a }; body["screen"] = screen }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let n = o?["number"] as? Int else {
                error = (o?["error"] as? String) ?? "The report could not be sent. Please try again in a little while."; return false }
            if n > 0 { reports.insert(SentReport(number: n, title: String(text.split(separator: "\n").first?.prefix(70) ?? "Report"), date: Date()), at: 0); save() }
            return true
        } catch { self.error = "The report could not be sent. Check your internet connection and try again."; return false }
    }

    /// Asks GitHub (public data, no login) how each report is doing. Returns the reports that were just completed.
    @discardableResult
    func refresh() async -> [SentReport] {
        guard !checking, !reports.isEmpty else { return [] }
        checking = true; defer { checking = false }
        var done: [SentReport] = []
        for original in reports where !(original.state == "closed" && original.notified) {
            var report = original
            let n = report.number, base = "https://api.github.com/repos/\(Self.repo)/issues/\(n)"
            guard let u = URL(string: base), let (d, r) = try? await URLSession.shared.data(from: u), (r as? HTTPURLResponse)?.statusCode == 200,
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            report.state = o["state"] as? String ?? "open"
            report.inProgress = ((o["labels"] as? [[String: Any]]) ?? []).contains { ($0["name"] as? String) == "in-progress" }
            if let cu = URL(string: base + "/comments"), let (cd, _) = try? await URLSession.shared.data(from: cu),
               let arr = (try? JSONSerialization.jsonObject(with: cd)) as? [[String: Any]],
               let last = arr.last(where: { (($0["user"] as? [String: Any])?["login"] as? String)?.lowercased() == Self.repo.split(separator: "/").first?.lowercased() }) {
                report.reply = (last["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let i = reports.firstIndex(where: { $0.number == n }) {
                report.notified = reports[i].notified
                reports[i] = report
                if report.state == "closed", !report.notified { done.append(report) }
            }
        }
        save(); return done
    }
    func markNotified() { for i in reports.indices where reports[i].state == "closed" { reports[i].notified = true }; save() }
}

struct ReportSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var center: ReportCenter
    init(center: ReportCenter, tab: Int = 0) { self.center = center; _tab = State(initialValue: tab) }
    @Environment(\.dismiss) var dismiss
    @State private var tab = 0
    @State private var text = ""
    @State private var includeTech = true
    @State private var sent = false
    @State private var hidden = ""            // bots fill this in; people never see it (the relay ignores such reports)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "ladybug.fill").font(.system(size: 26)).foregroundStyle(.tint)
                Text("Report a problem").font(.title2.bold())
                Spacer()
                Picker("", selection: $tab) { Text("New report").tag(0); Text("My reports\(center.reports.isEmpty ? "" : " (\(center.reports.count))")").tag(1) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 250)
                    .help("“New report” tells the author about a problem. “My reports” shows whether the problems you reported are fixed.")
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).help("Close this window.")
            }
            if tab == 0 { form } else { list }
        }
        .padding(22).frame(minWidth: 560, idealWidth: 620, minHeight: 420, idealHeight: 500)
        .onAppear { if text.isEmpty { text = model.reportPrefill }; if !center.reports.isEmpty { Task { await center.refresh() } } }
    }

    var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sent {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                    Text("Thank you — your report was sent.").font(.title3.bold())
                    Text("You can see here whether it has been fixed: press “My reports”. You do not need to do anything else.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("See my reports") { tab = 1; sent = false; text = "" }.buttonStyle(.borderedProminent).help("Shows the problems you reported and whether they are fixed.")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("What went wrong? Write it in your own words — what you pressed and what happened instead.").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                    .help("Describe the problem. The more detail, the easier it is to fix.")
                TextField("", text: $hidden).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
                Toggle("Include the app version and the type of Mac (helps find the cause)", isOn: $includeTech).toggleStyle(.checkbox)
                    .help("Sends the app version, macOS version and Mac model. Never your songs, lyrics, files, folders or keys.")
                Text("Your songs, lyrics, files and keys are never sent.").font(.caption).foregroundStyle(.tertiary)
                if let e = center.error { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
                HStack {
                    if ReportCenter.endpoint == nil {
                        Text("Sending is not set up in this copy of the app.").font(.callout).foregroundStyle(.orange)
                        Button("Copy my report") { copyReport() }.help("Copies your report so you can paste it into an email or message to the author.")
                        Button("Open the bug page") { openIssuePage() }.help("Opens the public bug list in your web browser (needs a free GitHub account).")
                    }
                    Spacer()
                    if center.sending { ProgressView().controlSize(.small) }
                    Button { Task { if hidden.isEmpty, await center.send(text: text, screen: model.screenName, includeTechnical: includeTech) { sent = true; model.reportPrefill = "" } } } label: { Label("Send report", systemImage: "paperplane.fill").padding(.horizontal, 8) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 || center.sending || ReportCenter.endpoint == nil)
                        .help("Sends your report to the author. It takes a few seconds.")
                }
            }
        }
    }

    var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            if center.reports.isEmpty {
                Text("You have not reported anything yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("Each report shows whether it has been fixed.").foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await center.refresh() } } label: { Label(center.checking ? "Checking…" : "Check again", systemImage: "arrow.clockwise") }
                        .disabled(center.checking).help("Asks the internet whether any of your reports have been fixed.")
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(center.reports) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r.title).font(.headline).lineLimit(2)
                                    Spacer()
                                    statusPill(r)
                                }
                                Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.tertiary)
                                if !r.reply.isEmpty { Label(r.reply, systemImage: "bubble.left.fill").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                        }
                    }
                }
            }
        }
        .onAppear { center.markNotified() }
    }

    func statusPill(_ r: SentReport) -> some View {
        let (t, c): (String, Color) = r.state == "closed" ? ("Done ✓", .green) : (r.inProgress ? ("Being worked on", .orange) : ("Received", .blue))
        return Text(t).font(.callout.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(c.opacity(0.18))).foregroundStyle(c)
            .help(r.state == "closed" ? "This problem has been dealt with." : (r.inProgress ? "The author is working on this." : "The author has received it and will look at it."))
    }

    func reportText() -> String {
        let t = ReportCenter.technical()
        return text + (includeTech ? "\n\n(App \(t["version"] ?? "") · macOS \(t["macos"] ?? "") · \(t["mac"] ?? "") · screen: \(model.screenName))" : "")
    }
    func copyReport() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reportText(), forType: .string) }
    func openIssuePage() {
        var c = URLComponents(string: "https://github.com/\(ReportCenter.repo)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: String(text.prefix(70))), URLQueryItem(name: "body", value: reportText())]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }
}
