// HeyGen video clips through OpenRouter: one picture in (the first frame), a few seconds of video out.
import Foundation
import AVFoundation

public enum OpenRouterVideo {
    public static let model = "heygen/heygen-video-1"
    public static let resolution = "768p"
    public static let minSeconds = 5, maxSeconds = 15
    public static let fallbackPricePerSecond = 0.036            // the list price at 768p; HeyGen has been billing half of it during a promotion

    public struct Clip { public var data: Data; public var costUSD: Double?; public var jobID: String }

    /// The list price per second from OpenRouter (so the number shown before spending is the real list price).
    public static func pricePerSecond() async -> Double {
        guard let url = URL(string: "https://openrouter.ai/api/v1/videos/models"), let (d, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let arr = j["data"] as? [[String: Any]],
              let m = arr.first(where: { ($0["id"] as? String) == model }), let sk = m["pricing_skus"] as? [String: Any],
              let p = (sk["duration_seconds_\(resolution)"] as? String).flatMap(Double.init) else { return fallbackPricePerSecond }
        return p
    }

    public static func formatPrice(_ usd: Double) -> String { usd < 1 ? String(format: "$%.2f", usd) : String(format: "$%.2f", usd) }

    /// Clip length for a section: its length rounded up to whole seconds, between 5 and 15.
    public static func clipSeconds(forSectionSeconds s: Double) -> Int { guard s.isFinite else { return maxSeconds }; return Int(min(Double(maxSeconds), max(Double(minSeconds), ceil(s - 0.001)))) }

    /// Makes one clip from a first-frame picture. `onPhase` reports progress text. Records accepted jobs before polling. A local Stop does not cancel a provider charge.
    /// `exactPrompt`: HeyGen follows the prompt word for word instead of rewriting it first (its "prompt enhancement" off), for a fully written brief.
    public static func generate(prompt: String, firstFrameJPEG: Data, seconds: Int, apiKey: String, resolution res: String = OpenRouterVideo.resolution, seed: Int? = nil, exactPrompt: Bool = false,
                                onJob: ((String) throws -> Void)? = nil, onPhase: ((String) -> Void)? = nil) async throws -> Clip {
        guard (minSeconds...maxSeconds).contains(seconds) else { throw MVError("HeyGen orders must be between 5 and 15 seconds.") }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MVError("Enter your OpenRouter API key first.") }
        func request(_ method: String, _ url: String, body: [String: Any]? = nil) async throws -> (Int, Data) {
            guard let endpoint = URL(string: url), trustedAPI(endpoint) else { throw MVError("The video service returned an untrusted polling address. Your paid job is kept for recovery.") }
            var r = URLRequest(url: endpoint); r.httpMethod = method; r.timeoutInterval = 120
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("Music Video Maker", forHTTPHeaderField: "X-Title")
            if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
            let (d, resp) = try await URLSession.shared.data(for: r)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0, d)
        }
        func message(_ d: Data) -> String {
            if let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let e = j["error"] as? [String: Any], let m = e["message"] as? String { return m }
            return String(data: d, encoding: .utf8)?.prefix(200).description ?? "unknown error"
        }
        var body: [String: Any] = [
            "model": model, "prompt": prompt, "duration": seconds, "resolution": res, "aspect_ratio": "16:9", "generate_audio": true,   // HeyGen always renders sound; the song replaces it
            "frame_images": [["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + firstFrameJPEG.base64EncodedString()], "frame_type": "first_frame"]]]
        if let seed { body["seed"] = seed }
        if exactPrompt { body["provider"] = ["options": ["heygen": ["parameters": ["prompt_enhancement": "disabled"]]]] }
        onPhase?("Sending the picture to HeyGen…")
        let (st, d) = try await request("POST", "https://openrouter.ai/api/v1/videos", body: body)
        guard (200..<300).contains(st), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let id = j["id"] as? String else {
            if st == 402 { throw MVError(OpenRouter.creditMessage) }
            throw MVError("The clip request did not complete. Check OpenRouter activity before ordering again: \(message(d))")
        }
        do { try onJob?(id) } catch { throw MVError("HeyGen accepted job \(id), but its recovery record could not be saved: \(error.localizedDescription). Keep this job ID and check OpenRouter activity before trying again.") }
        let poll = (j["polling_url"] as? String) ?? "https://openrouter.ai/api/v1/videos/\(id)"
        let started = Date()
        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 8_000_000_000)
            let (statusCode, pd) = try await request("GET", poll)
            guard (200..<300).contains(statusCode) else { throw MVError("Could not check paid job \(id) (HTTP \(statusCode)). It remains available for recovery; do not order it again.") }
            guard let pj = try? JSONSerialization.jsonObject(with: pd) as? [String: Any] else { continue }
            let status = pj["status"] as? String ?? ""
            onPhase?("HeyGen is making the clip (\(Int(Date().timeIntervalSince(started))) s)…")
            if status == "failed" || status == "cancelled" || status == "expired" { throw MVError("The clip \(status): \(message(pd)). Check your OpenRouter activity before trying again.") }
            if status == "completed" {
                let cost = ((pj["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue
                guard let location = downloadLocation(pj) else { throw MVError("The clip finished but no download link came back.") }
                onPhase?("Downloading the clip…")
                let data = try await download(location.url, authenticated: location.authenticated, apiKey: key)
                return Clip(data: data, costUSD: cost, jobID: id)
            }
            if Date().timeIntervalSince(started) > 1200 { throw MVError("The clip is taking too long (job \(id)). It may still finish; check your OpenRouter activity.") }
        }
    }

    static func downloadLocation(_ object: [String: Any]) -> (url: URL, authenticated: Bool)? {
        if let value = (object["unsigned_urls"] as? [String])?.first, let url = URL(string: value) { return (url, true) }
        if let value = (object["urls"] as? [String])?.first, let url = URL(string: value) { return (url, false) }
        return nil
    }

    static func trustedAPI(_ url: URL) -> Bool { url.scheme == "https" && url.host?.lowercased() == "openrouter.ai" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) }

    /// Unsigned API downloads need authentication; signed storage links must never receive the API key.
    static func download(_ url: URL, authenticated: Bool, apiKey: String, session: URLSession = .shared) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil, !authenticated || trustedAPI(url) else { throw MVError("The clip download address is not trusted.") }
        var req = URLRequest(url: url); req.timeoutInterval = 300
        if authenticated { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: req)
        try await validateDownload(data, response: response)
        return data
    }

    /// Byte count alone accepts HTML error pages. Require HTTP success and a decodable video frame before retaining a paid result.
    static func validateDownload(_ data: Data, response: URLResponse) async throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 1000 else { throw MVError("The clip download failed. The paid job is kept so you can recover it without ordering again.") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("clip-check-" + UUID().uuidString + ".mp4")
        try data.write(to: file, options: .atomic); defer { try? FileManager.default.removeItem(at: file) }
        let asset = AVURLAsset(url: file)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0,
              let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else { throw MVError("The download did not contain a readable video. Its paid job is kept for recovery.") }
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 64, height: 64)
        do { _ = try await generator.image(at: .zero) } catch { throw MVError("The downloaded clip cannot be decoded. Its paid job is kept for recovery.") }
    }

    public enum JobResult { case finished(Data, Double?), running, failed, unknown }

    /// Looks once at a job that was ordered earlier: finished (the clip is downloaded), still running, failed, or not reachable right now.
    public static func fetchFinished(jobID: String, apiKey: String) async -> JobResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let url = URL(string: "https://openrouter.ai/api/v1/videos/\(jobID)") else { return .unknown }
        var r = URLRequest(url: url); r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); r.timeoutInterval = 60
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return .unknown }
        switch j["status"] as? String ?? "" {
        case "completed":
            guard let location = downloadLocation(j) else { return .unknown }
            guard let data = try? await download(location.url, authenticated: location.authenticated, apiKey: key) else { return .unknown }
            return .finished(data, ((j["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue)
        case "failed", "cancelled", "expired": return .failed
        default: return .running
        }
    }
}
