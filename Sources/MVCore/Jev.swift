// Jev: TypeSafe's "decision model", reached through OpenRouter's Decisions API. It never writes text. It is given a piece of text and a question with fixed
// answers (yes/no, or pick one of a few) and answers with probabilities, in about a fifth of a second, for a few thousandths of a cent.
// The app uses it only to advise or to choose between options the app itself made; every use has a plain fallback and never blocks work.
import Foundation

public struct JevQuestion {
    public enum Kind { case yesNo(yes: String, no: String); case choice([String: String]) }
    public var id: String
    public var instructions: String
    public var kind: Kind
    public init(id: String, instructions: String, kind: Kind) { self.id = id; self.instructions = instructions; self.kind = kind }
}

public struct JevAnswer: Equatable {
    public var yes: Double?                  // yes/no: the probability of yes
    public var choice: String?               // choice: the option picked
    public var confidence: Double?
    public var probabilities: [String: Double] = [:]
}

public enum Jev {
    public static let endpoint = URL(string: "https://openrouter.ai/api/alpha/decisions")!
    /// The newest release first, then a named one in case the alias is not known.
    public static let models = ["~typesafe/jev-latest", "typesafe/jev-1.13"]
    /// Where requests go (replaced in tests).
    nonisolated(unsafe) public static var send: (URLRequest) async throws -> (Data, URLResponse) = { try await OpenRouterRetry.data(for: $0, retrying: [429, 500, 502, 503, 504], retries: 1, firstWait: 1) }

    /// Asks the questions about `state`. Returns nil when it could not (no key, offline, busy, unexpected answer): callers then do what they did before.
    public static func decide(state: [String: String], _ questions: [JevQuestion], apiKey: String, timeout: TimeInterval = 12) async -> [String: JevAnswer]? {
        guard !apiKey.isEmpty, !questions.isEmpty else { return nil }
        for model in models {
            guard let body = try? JSONSerialization.data(withJSONObject: request(model: model, state: state, questions)) else { return nil }
            var req = URLRequest(url: endpoint, timeoutInterval: timeout)
            req.httpMethod = "POST"; req.httpBody = body
            req.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let (data, resp) = try? await send(req), let status = (resp as? HTTPURLResponse)?.statusCode else { return nil }
            if (200..<300).contains(status) { return parse(data, expecting: questions) }
            if [401, 402, 403, 408, 429].contains(status) || status >= 500 { return nil }       // a key, credit or busy problem: another model name would not help
        }
        return nil
    }

    static func request(model: String, state: [String: String], _ questions: [JevQuestion]) -> [String: Any] {
        var qs: [String: Any] = [:]
        for q in questions {
            switch q.kind {
            case .yesNo(let yes, let no): qs[q.id] = ["type": "noul", "instructions": q.instructions, "criteria": ["true": yes, "false": no]]
            case .choice(let options): qs[q.id] = ["type": "choice", "instructions": q.instructions, "criteria": options]
            }
        }
        return ["model": model, "state": state, "questions": qs]
    }

    static func parse(_ data: Data, expecting questions: [JevQuestion]) -> [String: JevAnswer]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let answers = root["answers"] as? [String: Any] else { return nil }
        var out: [String: JevAnswer] = [:]
        for q in questions {
            guard let a = answers[q.id] as? [String: Any] else { return nil }
            var r = JevAnswer()
            switch q.kind {
            case .yesNo: guard let y = (a["noul"] as? NSNumber)?.doubleValue, (0...1).contains(y) else { return nil }; r.yes = y
            case .choice(let options):
                guard let c = a["choice"] as? String, options[c] != nil else { return nil }
                r.choice = c; r.confidence = (a["confidence"] as? NSNumber)?.doubleValue
                r.probabilities = (a["probabilities"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
            }
            out[q.id] = r
        }
        return out
    }
}
