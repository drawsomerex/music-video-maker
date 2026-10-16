// Starts/stops oMLX's engine hidden (no window) with isolated settings, and shuts it down when idle.
import Foundation

/// Runs oMLX's engine headless (no window, no menu-bar app) when nothing is already serving, and shuts it down when idle
/// so its model doesn't sit in memory while the app renders. If the oMLX app is already running, that server is used instead.
public final class OMLXServer: @unchecked Sendable {
    public static let shared = OMLXServer()
    public private(set) var sessionURL: URL?
    public private(set) var sessionKey: String?
    private var process: Process?
    private var idleWork: DispatchWorkItem?
    private let lock = NSLock()
    public static let port = 8817

    static var cliURL: URL? {
        let fm = FileManager.default
        for p in [NSHomeDirectory() + "/.omlx/bin/omlx", "/Applications/oMLX.app/Contents/MacOS/omlx-cli", NSHomeDirectory() + "/Applications/oMLX.app/Contents/MacOS/omlx-cli"]
        where fm.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }

    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }

    /// Stops whatever is listening on our private port (the process renames itself, so pkill-by-name can miss it).
    static func killListener(on port: Int) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof"); p.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        p.waitUntilExit()
        let pids = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").compactMap { Int32($0) }
        for pid in pids { kill(pid, SIGTERM) }
        if !pids.isEmpty { usleep(400_000) }
    }

    public var ownsServer: Bool { process?.isRunning ?? false }

    /// Starts `omlx serve` hidden. Safe to call repeatedly.
    public func start() async throws {
        if locked({ process?.isRunning ?? false }) { return }
        guard let cli = OMLXServer.cliURL else { throw MVError("oMLX isn't installed. Install oMLX (the app that runs your local models) and try again.") }
        let key = "mv-" + UUID().uuidString.prefix(12)
        let url = URL(string: "http://127.0.0.1:\(OMLXServer.port)")!
        let p = Process(); p.executableURL = cli
        let lowMem = ProcessInfo.processInfo.physicalMemory <= 17 * 1_073_741_824      // 16 GB Macs: leave headroom for rendering
        var args = ["serve", "--host", "127.0.0.1", "--port", "\(OMLXServer.port)", "--api-key", String(key), "--log-level", "warning",
                    "--memory-guard", lowMem ? "safe" : "balanced", "--max-concurrent-requests", lowMem ? "2" : "4"]
        if let dir = OMLXRuntime.primaryModelDir { args += ["--model-dir", dir.path] }
        p.arguments = args
        // Isolated base path: `omlx serve` writes its flags into settings.json, which must never be the user's own oMLX settings.
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicVideo/omlx-engine")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var env = ProcessInfo.processInfo.environment; env["OMLX_BASE_PATH"] = base.path
        p.environment = env
        OMLXServer.killListener(on: OMLXServer.port)        // clear a stale engine of ours from an earlier crash
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run()
        locked { process = p; sessionURL = url; sessionKey = String(key) }
        // wait until it answers
        for _ in 0..<90 {
            var r = URLRequest(url: url.appendingPathComponent("v1/models")); r.timeoutInterval = 2
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if let (_, resp) = try? await HTTP.session.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 { return }
            if !p.isRunning { break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        shutdown()
        throw MVError("oMLX's engine didn't start. Try opening the oMLX app once, then retry.")
    }

    /// Call after each request: restarts the idle countdown.
    public func touch() {
        lock.lock(); defer { lock.unlock() }
        guard process?.isRunning == true else { return }
        idleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.shutdown() }
        idleWork = w
        DispatchQueue.global().asyncAfter(deadline: .now() + 75, execute: w)      // free the model's memory 75 s after the last request
    }

    public func shutdown() {
        lock.lock(); defer { lock.unlock() }
        idleWork?.cancel(); idleWork = nil
        if let p = process, p.isRunning { p.terminate(); p.waitUntilExit() }
        process = nil; sessionURL = nil; sessionKey = nil
        OMLXServer.killListener(on: OMLXServer.port)
    }
}

extension OMLXRuntime {
    /// oMLX's first configured model folder.
    static var primaryModelDir: URL? {
        if let d = try? Data(contentsOf: URL(fileURLWithPath: NSHomeDirectory() + "/.omlx/settings.json")),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let m = o["model"] as? [String: Any] {
            if let dirs = m["model_dirs"] as? [String], let f = dirs.first { return URL(fileURLWithPath: (f as NSString).expandingTildeInPath) }
            if let one = m["model_dir"] as? String { return URL(fileURLWithPath: (one as NSString).expandingTildeInPath) }
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/.omlx/models")
    }
}
