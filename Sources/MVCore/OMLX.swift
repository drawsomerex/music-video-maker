// Client for oMLX's OpenAI-compatible local API (models, chat, transcription).
import Foundation
import AVFoundation

/// Client for the local oMLX server (OpenAI-compatible): Parakeet speech-to-text, text LLM, and vision LLM.
public struct OMLX {
    public static let defaultURL = "http://127.0.0.1:8000"
    public static let defaultSTT = "parakeet-ultra-mlx"
    public static let defaultLLM = "Qwen3.5-9B-MLX-4bit"

    private let configURL: URL, configKey: String
    public let stt: String, llm: String
    /// While the app runs its own hidden engine, requests go there; otherwise to the configured (or running) oMLX server.
    public var baseURL: URL { OMLXServer.shared.sessionURL ?? configURL }
    public var apiKey: String { OMLXServer.shared.sessionKey ?? configKey }

    public init(config: Config) {
        configURL = URL(string: config.omlxURL.isEmpty ? OMLX.defaultURL : config.omlxURL) ?? URL(string: OMLX.defaultURL)!
        configKey = config.omlxKey.isEmpty ? OMLX.keyFromLocalSettings() : config.omlxKey
        stt = config.sttModel.isEmpty ? OMLX.defaultSTT : config.sttModel
        llm = config.llmModel.isEmpty ? OMLX.defaultLLM : config.llmModel
    }

    /// oMLX keeps its API key in ~/.omlx/settings.json; reading it means no copy/paste setup on the same Mac.
    static func keyFromLocalSettings() -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".omlx/settings.json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let auth = o["auth"] as? [String: Any], let k = auth["api_key"] as? String else { return "" }
        return k
    }

    func request(_ path: String, method: String = "GET", timeout: TimeInterval = 120) -> URLRequest {
        OMLXServer.shared.touch()
        var r = URLRequest(url: baseURL.appendingPathComponent(path)); r.httpMethod = method; r.timeoutInterval = timeout
        if !apiKey.isEmpty { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return r
    }

    /// Model ids the server currently exposes.
    public func models() async throws -> [String] {
        let (data, resp) = try await HTTP.session.data(for: request("v1/models", timeout: 8))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw MVError("oMLX rejected the API key. Add it under Settings → Local AI.") }
        guard code == 200, let o = try JSONSerialization.jsonObject(with: data) as? [String: Any], let arr = o["data"] as? [[String: Any]] else { throw MVError("oMLX returned an unexpected response (HTTP \(code)).") }
        return arr.compactMap { $0["id"] as? String }
    }

    /// Makes sure an oMLX server is reachable — using the running one, or starting oMLX's engine hidden — and that the models we need exist.
    public func ensureReady() async throws {
        if NativeHooks.active { if let problem = NativeHooks.isReady?() { throw MVError(problem) }; return }
        var ids: [String]?
        do { ids = try await models() }
        catch let e as MVError where e.message.contains("API key") { throw e }
        catch {
            // Nothing is serving: start the engine without any window.
            try await OMLXServer.shared.start()
            ids = try await models()
        }
        guard let ids else { throw MVError("Can't reach oMLX.") }
        for (role, id) in [("speech", stt), ("language", llm)] where !ids.contains(id) {
            throw MVError("oMLX doesn't have the \(role) model “\(id)”. Pick another in Settings → Local AI (available: \(ids.joined(separator: ", "))).")
        }
    }

    // MARK: Speech

    public func transcribe(wav: Data, timeout: TimeInterval = 180) async throws -> String {
        let boundary = "mv" + UUID().uuidString
        var body = Data()
        func field(_ n: String, _ v: String) { body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!) }
        field("model", stt)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav); body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var r = request("v1/audio/transcriptions", method: "POST", timeout: timeout)
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        let (data, resp) = try await HTTP.session.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw MVError("oMLX transcription failed: \(String(decoding: data.prefix(300), as: UTF8.self))") }
        return ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["text"] as? String) ?? ""
    }

    // MARK: Chat

    public enum Part { case text(String); case jpeg(Data) }

    /// One chat completion. Thinking is disabled (fast, JSON-only answers).
    public func chat(model: String, parts: [Part], maxTokens: Int = 400) async throws -> String {
        if let native = NativeHooks.chat {
            let text = parts.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n")
            return try await native(text, maxTokens)
        }
        var content: [[String: Any]] = []
        for p in parts {
            switch p {
            case .text(let t): content.append(["type": "text", "text": t])
            case .jpeg(let d): content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + d.base64EncodedString()]])
            }
        }
        var r = request("v1/chat/completions", method: "POST", timeout: 300)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": [["role": "user", "content": content]], "max_tokens": maxTokens, "temperature": 0.2,
            "chat_template_kwargs": ["enable_thinking": false],
        ] as [String: Any])
        let (data, resp) = try await HTTP.session.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw MVError("oMLX chat failed: \(String(decoding: data.prefix(300), as: UTF8.self))") }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any], let ch = (o["choices"] as? [[String: Any]])?.first,
              let msg = ch["message"] as? [String: Any], let text = msg["content"] as? String else { throw MVError("Unexpected chat response") }
        return text
    }

    /// Extracts the first JSON object/array from a model reply (models like to wrap it in ```json fences).
    static func json(from text: String) -> Any? {
        let s = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        for (open, close) in [("{", "}"), ("[", "]")] {
            if let a = s.firstIndex(of: Character(open)), let b = s.lastIndex(of: Character(close)), a < b,
               let o = try? JSONSerialization.jsonObject(with: Data(s[a...b].utf8)) { return o }
        }
        return nil
    }
}
