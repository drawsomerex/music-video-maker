// One-time model setup: Hugging Face downloader and 4-bit shrinking of Parakeet.
import Foundation
import MVCore
import MLX
import MLXNN
import MLXAudioSTT
import MLXLMCommon
import CryptoKit

extension NativeEngine {
    /// One-time setup of both models (used by the command line); the app calls the two steps separately so each can show its own progress.
    public static func setup(tier: Tier, speechFrom: URL? = nil, llmFrom: URL? = nil, progress: @escaping @Sendable (String, Double) -> Void) async throws {
        try await installSpeech(from: speechFrom) { progress($0, $1 * 0.7) }
        try await installLanguageModel(tier: tier, from: llmFrom) { progress($0, 0.7 + $1 * 0.3) }
        progress("Done", 1)
    }

    /// Parakeet Ultra (1.25 GB bf16) is downloaded, shrunk to 4-bit (≈0.5 GB, word timings unchanged) and the original deleted.
    /// `force` re-does it even when it looks installed. `from` copies from a local folder instead of downloading.
    public static func installSpeech(from: URL? = nil, force: Bool = false, progress: @escaping @Sendable (String, Double) -> Void) async throws {
        let fm = FileManager.default
        let raw = home.appendingPathComponent("parakeet-ultra-bf16-tmp")
        if speechInstalled && !force { progress("Speech model ready", 1); return }
        try? fm.removeItem(at: raw)
        if let from {
            progress("Copying the speech model", 0.02)
            try fm.copyItem(at: from, to: raw)
        } else {
            try await HFDownload.fetch(repo: speechRepo, into: raw, wanted: { ["config.json", "model.safetensors"].contains($0) }) { progress("Downloading Parakeet Ultra", $0 * 0.85) }
        }
        progress("Shrinking Parakeet to 4-bit", 0.88)
        try slimParakeet(from: raw, to: speechDir)
        try? fm.removeItem(at: raw)
        progress("Speech model ready", 1)
    }

    /// The language model for the chosen tier, downloaded as-is (already 4-bit) and checked against Hugging Face's checksums.
    public static func installLanguageModel(tier: Tier, from: URL? = nil, force: Bool = false, progress: @escaping @Sendable (String, Double) -> Void) async throws {
        let fm = FileManager.default
        if llmInstalled && !force { progress("Language model ready", 1); return }
        try? fm.removeItem(at: llmDir)
        if let from {
            progress("Copying the language model", 0.02)
            try fm.copyItem(at: from, to: llmDir)
        } else {
            try await HFDownload.fetch(repo: tier.llmRepo, into: llmDir, wanted: { name in
                name.hasSuffix(".safetensors") || name.hasSuffix(".json") || name.hasSuffix(".jinja") || name.hasSuffix(".txt") || name.hasSuffix(".model")
            }) { progress("Downloading \(tier.displayName)", $0) }
        }
        try? JSONSerialization.data(withJSONObject: ["repo": tier.llmRepo, "tier": tier.rawValue, "name": tier.displayName]).write(to: llmDir.appendingPathComponent(".mv-model.json"))
        progress("Language model ready", 1)
    }

    /// Loads the full-precision Parakeet, quantizes its Linear layers to 4-bit, and writes a smaller copy.
    static func slimParakeet(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let model = try ParakeetModel.fromDirectory(src)
        quantize(model: model) { _, module in
            guard let lin = module as? Linear, let last = lin.weight.shape.last, last % 64 == 0 else { return nil }
            return BaseConfiguration.Quantization(groupSize: 64, bits: 4).asTuple
        }
        eval(model)
        let arrays = Dictionary(uniqueKeysWithValues: model.parameters().flattened().map { ($0.0, $0.1) })
        try save(arrays: arrays, url: dst.appendingPathComponent("model.safetensors"))
        var cfg = try JSONSerialization.jsonObject(with: Data(contentsOf: src.appendingPathComponent("config.json"))) as? [String: Any] ?? [:]
        cfg["quantization"] = ["group_size": 64, "bits": 4]
        cfg["mv_internal_layout"] = true
        try JSONSerialization.data(withJSONObject: cfg).write(to: dst.appendingPathComponent("config.json"))
        MLX.Memory.clearCache()
    }
}

/// Minimal Hugging Face file downloader with progress (public repos only).
enum HFDownload {
    static func fetch(repo: String, into dir: URL, wanted: (String) -> Bool, progress: @escaping @Sendable (Double) -> Void) async throws {
        let (data, resp) = try await URLSession.shared.data(from: URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let siblings = o["siblings"] as? [[String: Any]] else { throw MVError("Couldn't list \(repo) on Hugging Face (network down?).") }
        let files = siblings.compactMap { s -> (String, Int, String?)? in
            guard let n = s["rfilename"] as? String, wanted(n) else { return nil }
            return (n, (s["size"] as? Int) ?? 0, (s["lfs"] as? [String: Any])?["sha256"] as? String)
        }
        let total = max(1, files.reduce(0) { $0 + $1.1 })
        var done = 0
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, size, sha) in files {
            let dst = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let have = (try? FileManager.default.attributesOfItem(atPath: dst.path))?[.size] as? Int, have == size, size > 0 { done += size; progress(Double(done) / Double(total)); continue }
            let base = done
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(name)")!
            // Large files are checked against Hugging Face's checksum; a damaged copy is downloaded once more, then reported clearly.
            for attempt in 1...2 {
                try await download(url, to: dst) { got in progress(Double(base + got) / Double(total)) }
                guard let sha, size > 1_000_000 else { break }
                if (try? sha256(of: dst)) == sha { break }
                try? FileManager.default.removeItem(at: dst)
                if attempt == 2 { throw MVError("“\(name)” arrived damaged twice. Check your internet connection and try again.") }
            }
            done += size
        }
        progress(1)
        let manifest = Dictionary(uniqueKeysWithValues: files.map { ($0.0, $0.1) })      // so a later launch can tell if files went missing
        try? JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent(".mv-manifest.json"))
    }

    static func sha256(of url: URL) throws -> String {
        var h = SHA256(); let fh = try FileHandle(forReadingFrom: url); defer { try? fh.close() }
        while let chunk = try fh.read(upToCount: 4 << 20), !chunk.isEmpty { h.update(data: chunk) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func download(_ url: URL, to dst: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let progress: @Sendable (Int) -> Void; let dst: URL
            var cont: CheckedContinuation<Void, Error>?
            init(dst: URL, progress: @escaping @Sendable (Int) -> Void) { self.dst = dst; self.progress = progress }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite _: Int64) { progress(Int(w)) }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
                if let code = (t.response as? HTTPURLResponse)?.statusCode, code != 200 {       // an error page must never be saved as a model file
                    cont?.resume(throwing: MVError("Hugging Face answered “\(code)” for \(dst.lastPathComponent) (busy or temporarily blocking). Wait a minute and try again.")); cont = nil; return
                }
                do { try? FileManager.default.removeItem(at: dst); try FileManager.default.moveItem(at: loc, to: dst); cont?.resume(); cont = nil }
                catch { cont?.resume(throwing: error); cont = nil }
            }
            func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) { if let e { cont?.resume(throwing: e); cont = nil } }
        }
        let d = Delegate(dst: dst, progress: progress)
        let session = URLSession(configuration: .default, delegate: d, delegateQueue: nil)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in d.cont = c; session.downloadTask(with: url).resume() }
        session.finishTasksAndInvalidate()
    }
}
