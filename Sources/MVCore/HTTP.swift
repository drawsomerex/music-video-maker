// Shared URLSession settings for the oMLX client and the transcriber.
import Foundation

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30; c.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: c)
    }()

    static func get(_ url: URL, headers: [String: String] = [:], retries: Int = 3) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("MusicVideoMaker/1.0 (personal use)", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        var attempt = 0
        while true {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 { return data }
            if (code == 429 || code >= 500) && attempt < retries {
                let wait = Double((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(2 << attempt)
                try await Task.sleep(nanoseconds: UInt64(min(wait, 20) * 1e9)); attempt += 1; continue
            }
            throw MVError("HTTP \(code) for \(url.host ?? "") \(url.path)")
        }
    }
}

