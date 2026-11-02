// Waits and tries again when OpenRouter is busy, so a brief problem does not stop an automatic run.
import Foundation

public enum OpenRouterRetry {
    /// `retrying`: the answers worth another try. Paid clip orders pass only 429, which means the order was not accepted.
    public static func data(for request: URLRequest, session: URLSession = .shared, retrying: Set<Int> = [429, 500, 502, 503, 504], retries: Int = 3, firstWait: Double = 2) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            guard let code = http?.statusCode, retrying.contains(code), attempt < retries else { return (data, response) }
            let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? firstWait * pow(2, Double(attempt))
            try await Task.sleep(nanoseconds: UInt64(min(max(0, wait), 20) * 1e9))
            attempt += 1
        }
    }
    /// A paid job keeps being checked through these; anything else (a bad key, an unknown job) is reported at once.
    public static func isBriefProblem(status: Int) -> Bool { status == 408 || status == 429 || status >= 500 }
    public static func isBriefProblem(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        return e.code != .cancelled && e.code != .badURL && e.code != .unsupportedURL
    }
    public static let busyMessage = "OpenRouter is very busy right now. Please try again in a few minutes."
}
