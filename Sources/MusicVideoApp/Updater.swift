import SwiftUI
import CryptoKit

@MainActor
final class Updater: ObservableObject {
    struct Release: Identifiable {
        var id: String { version }
        var version: String
        var notes: String
        var zip: URL
        var sha256: String?
        var page: URL?
        var checksumURL: URL? = nil
    }
    @Published var available: Release?
    @Published var releases: [Release] = []
    @Published var showAvailable = false
    @Published var showVersions = false
    @Published var message: String?
    @Published var progress: Double?
    @Published var busy = false
    @Published private(set) var restartPending = false
    @Published var phase = ""
    @Published var lastChecked: Date? = Updater.defaults.object(forKey: "lastUpdateCheckDate") as? Date
    @Published var bannerDismissed = false
    @Published var heldVersion = Updater.defaults.string(forKey: "heldAppVersion") ?? "" {
        didSet { Self.defaults.set(heldVersion, forKey: "heldAppVersion") }
    }
    @Published var skippedVersions = Updater.defaults.stringArray(forKey: "skippedAppVersions") ?? [] {
        didSet { Self.defaults.set(skippedVersions, forKey: "skippedAppVersions") }
    }
    var beforeInstall: (() throws -> Void)?
    var isInstalling: Bool { restartPending || (busy && progress != nil) }
    var statusText: String {
        if isInstalling { return phase }
        if busy { return "Checking…" }
        if !heldVersion.isEmpty { return "Staying on version \(heldVersion)" }
        if let r = available { return "Version \(r.version) is available (you have \(Self.current))" }
        if !Self.enabled { return "Updates are not set up for this copy" }
        return "Installed version \(Self.current)"
    }
    static var defaults: UserDefaults { env["MV_TEST_PREFS"].flatMap(UserDefaults.init(suiteName:)) ?? .standard }
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static func log(_ s: String) { if env["MV_UPDATE_SELFTEST"] != nil { FileHandle.standardError.write(Data(("[updater] " + s + "\n").utf8)) } }
    static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var current: String { info["CFBundleShortVersionString"] as? String ?? "0" }
    static var repo: String? { let r = (info["MVUpdateRepo"] as? String) ?? ""; return r.isEmpty ? nil : r }
    static var isNativeFlavor: Bool { (info["MVFlavor"] as? String) == "native" }
    static var enabled: Bool { env["MV_UPDATE_API"] != nil || (isNativeFlavor && repo != nil) }
    static var apiURL: URL? { env["MV_UPDATE_API"].flatMap(URL.init(string:)) ?? repo.flatMap { URL(string: "https://api.github.com/repos/\($0)/releases/latest") } }
    var dueForAutoCheck: Bool {
        Self.enabled && heldVersion.isEmpty && Date().timeIntervalSince1970 - Self.defaults.double(forKey: "lastUpdateCheck") > 20 * 3600
    }
    func holdCurrent() {
        heldVersion = Self.current; available = nil; bannerDismissed = true
        // Also quiet versions released before the Versions screen existed after a rollback.
        Self.defaults.set(Date.distantFuture.timeIntervalSince1970, forKey: "lastUpdateCheck")
    }
    func resumeUpdates() {
        heldVersion = ""; Self.defaults.removeObject(forKey: "lastUpdateCheck")
        Task { await check(silent: false) }
    }
    func skip(_ version: String) {
        if !skippedVersions.contains(version) { skippedVersions.append(version) }
        if available?.version == version { available = nil; showAvailable = false }
    }
    func unskip(_ version: String) { skippedVersions.removeAll { $0 == version } }
    private func json(_ url: URL) async throws -> Any {
        var req = URLRequest(url: url); req.timeoutInterval = 20
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MusicVideoMaker", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MVUpdateError("GitHub could not be reached. Try again later.") }
        return try JSONSerialization.jsonObject(with: data)
    }
    private func release(_ o: [String: Any]) -> Release? {
        guard o["draft"] as? Bool != true, o["prerelease"] as? Bool != true else { return nil }
        let tag = ((o["tag_name"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard !tag.isEmpty else { return nil }
        let assets = (o["assets"] as? [[String: Any]]) ?? []
        guard let zipAsset = assets.first(where: { let n = ($0["name"] as? String) ?? ""; return n.hasSuffix("-native.zip") }),
              let name = zipAsset["name"] as? String, let path = zipAsset["browser_download_url"] as? String, let zip = URL(string: path),
              let hashAsset = assets.first(where: { ($0["name"] as? String) == name + ".sha256" }),
              let hashPath = hashAsset["browser_download_url"] as? String, let hashURL = URL(string: hashPath) else { return nil }
        return Release(version: tag, notes: (o["body"] as? String) ?? "", zip: zip, sha256: nil, page: (o["html_url"] as? String).flatMap(URL.init(string:)), checksumURL: hashURL)
    }
    func check(silent: Bool) async {
        guard !busy, Self.enabled, let url = Self.apiURL else { return }
        if silent && !heldVersion.isEmpty { return }
        busy = true; defer { busy = false }
        Self.defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        do {
            guard let o = try await json(url) as? [String: Any] else { throw MVUpdateError("Couldn't read the release information.") }
            lastChecked = Date(); Self.defaults.set(lastChecked, forKey: "lastUpdateCheckDate")
            available = nil
            if let r = release(o), Self.isNewer(r.version, than: Self.current), (heldVersion.isEmpty || !silent), (!skippedVersions.contains(r.version) || !silent) {
                available = r; bannerDismissed = false; showAvailable = !silent
            } else if !silent { message = "You have version \(Self.current). Open Versions to choose another release or manage skipped versions." }
        } catch { if !silent { message = error.localizedDescription } }
    }
    func loadVersions() async {
        guard !busy, Self.enabled else { return }
        busy = true; defer { busy = false }
        do {
            let url: URL?
            if let override = Self.env["MV_UPDATE_API"] { url = URL(string: override)?.deletingLastPathComponent().appendingPathComponent("releases") }
            else { url = Self.repo.flatMap { URL(string: "https://api.github.com/repos/\($0)/releases?per_page=100") } }
            guard let url, let arr = try await json(url) as? [[String: Any]] else { throw MVUpdateError("Couldn't read the available versions.") }
            releases = arr.compactMap(release).sorted { Self.isNewer($0.version, than: $1.version) }
            if releases.isEmpty { message = "No standalone releases with checksums are available yet." }
        } catch { message = error.localizedDescription }
    }
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) { let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0; if p != q { return p > q } }
        return false
    }
    func install(_ r: Release) async {
        guard !busy, r.version != Self.current else { return }
        busy = true; progress = 0; phase = "Downloading version \(r.version)…"; showAvailable = false; showVersions = false
        defer { if !restartPending { busy = false; progress = nil; phase = "" } }
        var cleanup: URL?
        do {
            var want = r.sha256
            if want == nil, let hashURL = r.checksumURL {
                let (data, response) = try await URLSession.shared.data(from: hashURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MVUpdateError("Could not verify this version's checksum.") }
                want = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            }
            guard let want, want.count == 64, want.allSatisfy({ $0.isHexDigit }) else { throw MVUpdateError("This version has no valid checksum. It was not installed.") }
            let fm = FileManager.default, work = FileManager.default.temporaryDirectory.appendingPathComponent("mv-update-\(UUID().uuidString)")
            cleanup = work; try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try await download(r.zip, to: zip) { [weak self] f in Task { @MainActor in self?.progress = f * 0.85 } }
            phase = "Checking the download…"
            let got = try await Task.detached { () throws -> String in
                var h = SHA256(); let fh = try FileHandle(forReadingFrom: zip); defer { try? fh.close() }
                while let chunk = try fh.read(upToCount: 1 << 20), !chunk.isEmpty { h.update(data: chunk) }
                return h.finalize().map { String(format: "%02x", $0) }.joined()
            }.value
            guard got == want.lowercased() else { throw MVUpdateError("The download didn't match its checksum. Your app was not changed.") }
            phase = "Unpacking…"
            let stage = work.appendingPathComponent("stage"); try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            try await Task.detached { try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, stage.path]) }.value
            guard let newApp = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
                  let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
                  plist["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  plist["CFBundleShortVersionString"] as? String == r.version,
                  plist["MVFlavor"] as? String == "native",
                  fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/MusicVideoApp").path) else { throw MVUpdateError("The download is not the requested standalone Music Video Maker version.") }
            if let minimum = plist["LSMinimumSystemVersion"] as? String {
                let os = ProcessInfo.processInfo.operatingSystemVersion
                guard !Self.isNewer(minimum, than: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)") else { throw MVUpdateError("This version needs macOS \(minimum) or newer.") }
            }
            try await Task.detached { try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) }.value
            let dest = Bundle.main.bundleURL
            guard fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else { throw MVUpdateError("Move this app to a writable Applications folder and try again.") }
            try beforeInstall?() // captures any edits made during the download; refuses to interrupt a render.
            let rollback = Self.isNewer(Self.current, than: r.version)
            phase = "Installing and restarting…"; progress = 0.97
            let script = work.appendingPathComponent("swap.sh")
            try """
            #!/bin/sh
            PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$4"; WORK="$5"; TESTROOT="$6"; TESTPREFS="$7"
            launch() {
              if [ -n "$TESTROOT" ]; then
                open -n "$DEST" --env "MV_EDITOR_SELFTEST=ui" --env "MV_TEST_ROOT=$TESTROOT" --env "MV_TEST_PREFS=$TESTPREFS" --env "MV_DEMO_PLAN=$TESTROOT/project"
              else open "$DEST"; fi
            }
            while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
            if mv "$DEST" "$BACKUP"; then
              if mv "$NEW" "$DEST"; then
                if launch; then rm -rf "$BACKUP"; else mv "$DEST" "$WORK/failed.app"; mv "$BACKUP" "$DEST"; launch; fi
              else mv "$BACKUP" "$DEST"; launch; fi
            else launch; fi
            rm -rf "$WORK"
            """.write(to: script, atomically: true, encoding: .utf8)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path, "\(ProcessInfo.processInfo.processIdentifier)", newApp.path, dest.path, dest.path + ".backup-" + UUID().uuidString, work.path, Self.env["MV_EDITOR_SELFTEST"] != nil ? (Self.env["MV_TEST_ROOT"] ?? "") : "", Self.env["MV_TEST_PREFS"] ?? ""]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run()
            if rollback || !heldVersion.isEmpty {
                heldVersion = r.version; Self.defaults.set(Date.distantFuture.timeIntervalSince1970, forKey: "lastUpdateCheck")
            }
            cleanup = nil; restartPending = true
            // AppKit refuses termination while a modal sheet is still attached. Let SwiftUI finish dismissing it.
            try? await Task.sleep(nanoseconds: 350_000_000)
            NSApplication.shared.terminate(nil)
        } catch { message = "Version \(r.version) was not installed: \(error.localizedDescription)" }
        if let cleanup { try? FileManager.default.removeItem(at: cleanup) }
    }
    nonisolated private static func run(_ exe: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw MVUpdateError("The download could not be unpacked or verified.") }
    }
    private func download(_ url: URL, to dst: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        final class D: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let dst: URL, progress: @Sendable (Double) -> Void; var cont: CheckedContinuation<Void, Error>?
            init(_ dst: URL, _ p: @escaping @Sendable (Double) -> Void) { self.dst = dst; progress = p }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) { if e > 0 { progress(Double(w) / Double(e)) } }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
                do {
                    guard (t.response as? HTTPURLResponse)?.statusCode == 200 else { throw MVUpdateError("The download server returned an error.") }
                    try FileManager.default.moveItem(at: loc, to: dst); cont?.resume()
                } catch { cont?.resume(throwing: error) }; cont = nil
            }
            func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) { if let e { cont?.resume(throwing: e); cont = nil } }
        }
        let d = D(dst, progress)
        // Delegate state belongs to this download session only.
        let downloading = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        defer { downloading.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in d.cont = c; downloading.downloadTask(with: url).resume() }
    }
}

private struct MVUpdateError: LocalizedError { var text: String; init(_ text: String) { self.text = text }; var errorDescription: String? { text } }
