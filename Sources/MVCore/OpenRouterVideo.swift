// HeyGen video clips through OpenRouter: one picture in (the first frame), a few seconds of video out.
import Foundation

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
    public static func clipSeconds(forSectionSeconds s: Double) -> Int { min(maxSeconds, max(minSeconds, Int(ceil(s - 0.001)))) }

    /// Makes one clip from a first-frame picture. `onPhase` reports progress text. Throws on any refusal (a refused request is never charged).
    public static func generate(prompt: String, firstFrameJPEG: Data, seconds: Int, apiKey: String, onJob: ((String) -> Void)? = nil, onPhase: ((String) -> Void)? = nil) async throws -> Clip {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MVError("Enter your OpenRouter API key first.") }
        func request(_ method: String, _ url: String, body: [String: Any]? = nil) async throws -> (Int, Data) {
            var r = URLRequest(url: URL(string: url)!); r.httpMethod = method; r.timeoutInterval = 120
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
        let body: [String: Any] = [
            "model": model, "prompt": prompt, "duration": seconds, "resolution": resolution, "aspect_ratio": "16:9", "generate_audio": true,   // HeyGen always renders sound; the song replaces it
            "frame_images": [["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + firstFrameJPEG.base64EncodedString()], "frame_type": "first_frame"]]]
        onPhase?("Sending the picture to HeyGen…")
        let (st, d) = try await request("POST", "https://openrouter.ai/api/v1/videos", body: body)
        guard (200..<300).contains(st), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let id = j["id"] as? String else {
            throw MVError("HeyGen refused the clip (nothing was charged): \(message(d))")
        }
        onJob?(id)
        let poll = (j["polling_url"] as? String) ?? "https://openrouter.ai/api/v1/videos/\(id)"
        let started = Date()
        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 8_000_000_000)
            let (_, pd) = try await request("GET", poll)
            guard let pj = try? JSONSerialization.jsonObject(with: pd) as? [String: Any] else { continue }
            let status = pj["status"] as? String ?? ""
            onPhase?("HeyGen is making the clip (\(Int(Date().timeIntervalSince(started))) s)…")
            if status == "failed" || status == "cancelled" || status == "expired" { throw MVError("The clip \(status): \(message(pd)). Check your OpenRouter activity before trying again.") }
            if status == "completed" {
                let cost = ((pj["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue
                guard let urlStr = ((pj["unsigned_urls"] as? [String])?.first ?? (pj["urls"] as? [String])?.first), let url = URL(string: urlStr) else { throw MVError("The clip finished but no download link came back.") }
                var dl = URLRequest(url: url); dl.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); dl.timeoutInterval = 300
                onPhase?("Downloading the clip…")
                let (data, _) = try await URLSession.shared.data(for: dl)
                guard data.count > 10_000 else { throw MVError("The downloaded clip was empty.") }
                return Clip(data: data, costUSD: cost, jobID: id)
            }
            if Date().timeIntervalSince(started) > 1200 { throw MVError("The clip is taking too long (job \(id)). It may still finish; check your OpenRouter activity.") }
        }
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
            guard let urlStr = ((j["unsigned_urls"] as? [String])?.first ?? (j["urls"] as? [String])?.first), let u = URL(string: urlStr) else { return .unknown }
            var dl = URLRequest(url: u); dl.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); dl.timeoutInterval = 300
            guard let (data, _) = try? await URLSession.shared.data(for: dl), data.count > 10_000 else { return .unknown }
            return .finished(data, ((j["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue)
        case "failed", "cancelled", "expired": return .failed
        default: return .running
        }
    }
}
