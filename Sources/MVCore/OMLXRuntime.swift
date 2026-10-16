import Foundation

/// Runs the user's own Parakeet model with oMLX's bundled Python/MLX runtime to get true word timestamps
/// (oMLX's HTTP endpoint returns text only). No extra installs or downloads: it uses the same model files oMLX serves.
public enum OMLXRuntime {
    static let candidates = ["/Applications/oMLX.app", NSHomeDirectory() + "/Applications/oMLX.app"]

    public static var appURL: URL? { candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) } }

    public static var pythonURL: URL? {
        guard let app = appURL else { return nil }
        let p = app.appendingPathComponent("Contents/Resources/Python/cpython-3.11/bin/python3")
        return FileManager.default.isExecutableFile(atPath: p.path) ? p : nil
    }

    /// The model folder for an oMLX model id (e.g. `parakeet-ultra-mlx`), searched in oMLX's configured model directories.
    public static func modelDir(id: String) -> URL? {
        var roots = [NSHomeDirectory() + "/.omlx/models"]
        if let d = try? Data(contentsOf: URL(fileURLWithPath: NSHomeDirectory() + "/.omlx/settings.json")),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let m = o["model"] as? [String: Any] {
            roots += (m["model_dirs"] as? [String]) ?? []
            if let one = m["model_dir"] as? String { roots.append(one) }
        }
        let fm = FileManager.default
        for r in roots {
            let root = URL(fileURLWithPath: (r as NSString).expandingTildeInPath)
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for case let u as URL in en {
                if u.lastPathComponent == id, fm.fileExists(atPath: u.appendingPathComponent("config.json").path) { return u }
                if en.level > 3 { en.skipDescendants() }
            }
        }
        return nil
    }

    /// `scripts/word_timing.py`, from the app bundle or the project folder.
    public static var scriptURL: URL? {
        let fm = FileManager.default
        var found: [URL] = []
        if let r = Bundle.main.resourceURL { found.append(r.appendingPathComponent("word_timing.py")) }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 { found.append(dir.appendingPathComponent("scripts/word_timing.py")); dir.deleteLastPathComponent() }
        found.append(URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Programs/Music Video/scripts/word_timing.py"))
        return found.first { fm.fileExists(atPath: $0.path) }
    }

    public static func wordTimes(audioPath: String, modelID: String) async throws -> [TimedWord] {
        if let native = NativeHooks.wordTimes { return try await native(audioPath) }
        guard let py = pythonURL, let script = scriptURL else { throw MVError("oMLX's runtime or the timing script wasn't found.") }
        guard let model = modelDir(id: modelID) else { throw MVError("Couldn't find the “\(modelID)” model files on disk.") }
        // Hand the model a clean 16 kHz mono WAV of the whole song.
        let pcm = try await Transcriber.loadMono16k(path: audioPath)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mv-\(UUID().uuidString).wav")
        try Transcriber.wav(pcm[...]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process(); p.executableURL = py
                p.arguments = [script.path, tmp.path, model.path]
                var env = ProcessInfo.processInfo.environment; env["PYTHONUNBUFFERED"] = "1"; env["HF_HUB_OFFLINE"] = "1"; env["TOKENIZERS_PARALLELISM"] = "false"
                p.environment = env
                let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
                var outData = Data(), errData = Data(); let g = DispatchGroup()
                g.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                g.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                do { try p.run() } catch { cont.resume(throwing: error); return }
                p.waitUntilExit(); g.wait()
                guard p.terminationStatus == 0 else { cont.resume(throwing: MVError("Word timing failed: \(String(decoding: errData.suffix(400), as: UTF8.self))")); return }
                struct W: Decodable { var text: String; var start: Double; var end: Double }
                do { cont.resume(returning: try JSONDecoder().decode([W].self, from: outData).map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }) }
                catch { cont.resume(throwing: MVError("Couldn't read the word timings.")) }
            }
        }
    }
}
