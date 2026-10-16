import SwiftUI
import CryptoKit

/// Self-update from GitHub Releases. Works with an unpaid (ad-hoc) signature and needs no extra framework:
/// check the latest release → download the zip → verify its SHA-256 → unpack → swap the app bundle after quitting → relaunch.
/// Files fetched by the app itself aren't quarantined, so the updated app opens without Gatekeeper warnings.
@MainActor
final class Updater: ObservableObject {
    struct Release: Identifiable { var id: String { version }; var version: String; var notes: String; var zip: URL?; var tag: String = ""; var sha256: String?; var page: URL? }

    @Published var available: Release?
    @Published var showAvailable = false
    @Published var message: String?
    @Published var progress: Double?
    @Published var busy = false

    /// The repo is private, so the app asks GitHub's CLI (signed in as you) for the release instead of reading it anonymously.
    nonisolated static var gh: String? { ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) } }
    nonisolated static func runGH(_ args: [String]) -> Data? {
        guard let exe = gh else { return nil }
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }

    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static func log(_ s: String) { if env["MV_UPDATE_SELFTEST"] != nil { FileHandle.standardError.write(Data(("[updater] " + s + "\n").utf8)) } }
    static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var current: String { info["CFBundleShortVersionString"] as? String ?? "0" }
    static var repo: String? { let r = (info["MVUpdateRepo"] as? String) ?? ""; return r.isEmpty ? nil : r }
    static var isNativeFlavor: Bool { (info["MVFlavor"] as? String) == "native" }
    /// Releases only ship the standalone (native) app; the oMLX flavor is built from source. MV_UPDATE_API is a test override.
    static var enabled: Bool { env["MV_UPDATE_API"] != nil || (isNativeFlavor && repo != nil) }
    static var apiURL: URL? { env["MV_UPDATE_API"].flatMap(URL.init(string:)) ?? repo.flatMap { URL(string: "https://api.github.com/repos/\($0)/releases/latest") } }

    private let lastCheckKey = "lastUpdateCheck"
    var dueForAutoCheck: Bool {
        guard Updater.enabled else { return false }
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        return Date().timeIntervalSince1970 - last > 20 * 3600
    }

    // MARK: check

    /// `silent`: automatic check — only speaks up if there is an update.
    func check(silent: Bool) async {
        guard Updater.enabled, let url = Updater.apiURL else { if !silent { message = "Updates aren't set up for this copy of the app." }; return }
        Updater.log("checking \(url)")
        busy = true; defer { busy = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        do {
            if Updater.env["MV_UPDATE_API"] == nil, let repo = Updater.repo {
                guard Updater.gh != nil else { if !silent { message = "Updates come from a private GitHub repo. Install GitHub's CLI (brew install gh) and sign in with “gh auth login”." }; return }
                let data = await Task.detached { Updater.runGH(["api", "repos/\(repo)/releases/latest"]) }.value
                guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if !silent { message = "Couldn't reach the private release. Is GitHub's CLI signed in? (gh auth login)" }; return }
                let tag = ((o["tag_name"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                guard Updater.isNewer(tag, than: Updater.current) else { if !silent { message = "You're up to date — version \(Updater.current)." }; return }
                available = Release(version: tag, notes: (o["body"] as? String) ?? "", zip: nil, tag: (o["tag_name"] as? String) ?? "v\(tag)", sha256: nil, page: (o["html_url"] as? String).flatMap(URL.init(string:)))
                showAvailable = true; return
            }
            var req = URLRequest(url: url); req.timeoutInterval = 15
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept"); req.setValue("MusicVideoMaker", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            Updater.log("got \(data.count) bytes")
            guard (resp as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true, let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if !silent { message = "Couldn't read the release information from GitHub." }; return }
            let tag = ((o["tag_name"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let assets = (o["assets"] as? [[String: Any]]) ?? []
            func asset(_ test: (String) -> Bool) -> URL? { assets.first { test(($0["name"] as? String) ?? "") }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) } }
            guard Updater.isNewer(tag, than: Updater.current) else { if !silent { message = "You're up to date — version \(Updater.current)." }; return }
            guard let zip = asset({ $0.hasSuffix(".zip") && $0.contains("native") }) ?? asset({ $0.hasSuffix(".zip") }) else {
                if !silent { message = "Version \(tag) exists but has no download attached yet." }; return }
            var hash: String?
            if let h = asset({ $0.hasSuffix(".sha256") }), let (d, _) = try? await URLSession.shared.data(from: h) {
                hash = String(decoding: d, as: UTF8.self).split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            }
            available = Release(version: tag, notes: (o["body"] as? String) ?? "", zip: zip, tag: "", sha256: hash?.lowercased(), page: (o["html_url"] as? String).flatMap(URL.init(string:)))
            showAvailable = true
        } catch { Updater.log("check failed: \(error)"); if !silent { message = "Couldn't check for updates (\(error.localizedDescription))." } }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) { let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0; if p != q { return p > q } }
        return false
    }

    // MARK: install

    func install(_ r: Release) async {
        busy = true; progress = 0; defer { busy = false; progress = nil }
        do {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("mv-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            var wantHash = r.sha256
            if let url = r.zip {
                try await download(url, to: zip) { [weak self] f in Task { @MainActor in self?.progress = f * 0.9 } }
            } else if let repo = Updater.repo {
                progress = 0.3
                let ok = await Task.detached { Updater.runGH(["release", "download", r.tag, "--repo", repo, "--pattern", "*native*.zip", "--pattern", "*native*.zip.sha256", "--dir", work.path, "--clobber"]) != nil }.value
                guard ok, let got = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "zip" }) else {
                    throw NSError(domain: "Updater", code: 5, userInfo: [NSLocalizedDescriptionKey: "Couldn't download the update from your private GitHub repo."]) }
                try fm.moveItem(at: got, to: zip)
                if let sh = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "sha256" }) {
                    wantHash = (try? String(contentsOf: sh, encoding: .utf8))?.split(whereSeparator: { $0.isWhitespace }).first.map { String($0).lowercased() }
                }
                progress = 0.9
            }

            if let want = wantHash {
                var h = SHA256(); let fh = try FileHandle(forReadingFrom: zip)
                while let chunk = try fh.read(upToCount: 1 << 20), !chunk.isEmpty { h.update(data: chunk) }
                let got = h.finalize().map { String(format: "%02x", $0) }.joined()
                guard got == want else { throw NSError(domain: "Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: "The download didn't match its checksum, so it was discarded."]) }
            }
            let stage = work.appendingPathComponent("stage"); try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, stage.path])
            guard let newApp = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
                  let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
                  plist["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/MusicVideoApp").path) else {
                throw NSError(domain: "Updater", code: 2, userInfo: [NSLocalizedDescriptionKey: "The downloaded update isn't a valid Music Video Maker app."]) }
            let dest = Bundle.main.bundleURL
            guard fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
                throw NSError(domain: "Updater", code: 3, userInfo: [NSLocalizedDescriptionKey: "This app is somewhere macOS won't let it update itself (\(dest.deletingLastPathComponent().path)). Move it to Applications and try again."]) }
            progress = 0.97

            // A helper waits for this process to quit, swaps the bundle (keeping a backup until the swap succeeds), and relaunches.
            let script = work.appendingPathComponent("swap.sh")
            try """
            #!/bin/sh
            PID="$1"; NEW="$2"; DEST="$3"
            while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
            rm -rf "$DEST.old"
            if mv "$DEST" "$DEST.old" && mv "$NEW" "$DEST"; then rm -rf "$DEST.old"; else [ -d "$DEST.old" ] && mv "$DEST.old" "$DEST"; fi
            xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
            open "$DEST"
            """.write(to: script, atomically: true, encoding: .utf8)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path, "\(ProcessInfo.processInfo.processIdentifier)", newApp.path, dest.path]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run()
            NSApplication.shared.terminate(nil)
        } catch { Updater.log("install failed: \(error.localizedDescription)"); message = "The update didn't install: \(error.localizedDescription)" }
    }

    private func run(_ exe: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw NSError(domain: "Updater", code: 4, userInfo: [NSLocalizedDescriptionKey: "Couldn't unpack the update."]) }
    }

    private func download(_ url: URL, to dst: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        final class D: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let dst: URL, progress: @Sendable (Double) -> Void; var cont: CheckedContinuation<Void, Error>?
            init(_ dst: URL, _ p: @escaping @Sendable (Double) -> Void) { self.dst = dst; progress = p }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) { if e > 0 { progress(Double(w) / Double(e)) } }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
                do { try? FileManager.default.removeItem(at: dst); try FileManager.default.moveItem(at: loc, to: dst); cont?.resume() } catch { cont?.resume(throwing: error) }; cont = nil }
            func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) { if let e { cont?.resume(throwing: e); cont = nil } }
        }
        let d = D(dst, progress); let session = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in d.cont = c; session.downloadTask(with: url).resume() }
        session.finishTasksAndInvalidate()
    }
}
