import Foundation
import MVCore
import MLX
import MLXNN
import MLXAudioSTT
import MLXLMCommon

extension NativeEngine {
    /// One-time setup: gets the two models into the app's own folder.
    ///  • Parakeet Ultra (1.25 GB bf16) is downloaded, shrunk to 4-bit (≈0.5 GB, word timings unchanged) and the original deleted.
    ///  • The language model for the chosen tier is downloaded as-is (already 4-bit).
    /// `speechFrom` / `llmFrom` copy from a local folder instead of downloading (e.g. models already on disk).
    public static func setup(tier: Tier, speechFrom: URL? = nil, llmFrom: URL? = nil, progress: @escaping @Sendable (String, Double) -> Void) async throws {
        let fm = FileManager.default
        let raw = home.appendingPathComponent("parakeet-ultra-bf16-tmp")

        if !speechInstalled {
            try? fm.removeItem(at: raw)
            if let from = speechFrom {
                progress("Copying the speech model", 0.02)
                try fm.copyItem(at: from, to: raw)
            } else {
                try await HFDownload.fetch(repo: speechRepo, into: raw, wanted: { ["config.json", "model.safetensors"].contains($0) }) { progress("Downloading Parakeet Ultra", $0 * 0.6) }
            }
            progress("Shrinking Parakeet to 4-bit", 0.62)
            try slimParakeet(from: raw, to: speechDir)
            try? fm.removeItem(at: raw)
            progress("Speech model ready", 0.7)
        }

        if !llmInstalled {
            try? fm.removeItem(at: llmDir)
            if let from = llmFrom {
                progress("Copying the language model", 0.72)
                try fm.copyItem(at: from, to: llmDir)
            } else {
                try await HFDownload.fetch(repo: tier.llmRepo, into: llmDir, wanted: { name in
                    name.hasSuffix(".safetensors") || name.hasSuffix(".json") || name.hasSuffix(".jinja") || name.hasSuffix(".txt") || name.hasSuffix(".model")
                }) { progress("Downloading the language model (\(tier.rawValue))", 0.7 + $0 * 0.3) }
            }
        }
        progress("Done", 1)
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
        let files = siblings.compactMap { s -> (String, Int)? in
            guard let n = s["rfilename"] as? String, wanted(n) else { return nil }
            return (n, (s["size"] as? Int) ?? 0)
        }
        let total = max(1, files.reduce(0) { $0 + $1.1 })
        var done = 0
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, size) in files {
            let dst = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let have = (try? FileManager.default.attributesOfItem(atPath: dst.path))?[.size] as? Int, have == size, size > 0 { done += size; progress(Double(done) / Double(total)); continue }
            let base = done
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(name)")!
            try await download(url, to: dst) { got in progress(Double(base + got) / Double(total)) }
            done += size
        }
        progress(1)
    }

    static func download(_ url: URL, to dst: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            let progress: @Sendable (Int) -> Void; let dst: URL
            var cont: CheckedContinuation<Void, Error>?
            init(dst: URL, progress: @escaping @Sendable (Int) -> Void) { self.dst = dst; self.progress = progress }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite _: Int64) { progress(Int(w)) }
            func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
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
