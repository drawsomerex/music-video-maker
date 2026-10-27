// Every prompt is checked by a fast language model before it is sent to the picture or clip maker: anything that contradicts the scene (your own
// words) is taken out, except that an explicitly approved brightness rule wins over the scene (a stormy scene must never be drawn in golden-hour light because a style or a general line said so),
// and any other contradiction is settled. Everything else is kept exactly. If the check fails, the prompt goes as it was.
import Foundation

public enum PromptCheck {
    public enum Kind { case picture, clip }
    public static let model = "google/gemini-2.5-flash-lite"

    /// The checked prompt (or the original when the check can't be done).
    public static func fix(_ prompt: String, scene: String, kind: Kind, apiKey: String, rule: String? = nil) async -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines), sc = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !sc.isEmpty, ProcessInfo.processInfo.environment["MV_NO_PROMPT_CHECK"] == nil else { return prompt }
        let what = kind == .picture ? "an image generator" : "a video generator (it animates a still picture into a looping clip)"
        let rules = """
        You check a prompt just before it is sent to \(what). Return the same prompt, changed only where needed:
        0. \(rule.map { _ in "The AUTHOR'S RULE below was approved by the user and wins over everything, including the scene, on how bright and light the picture looks (the scene still decides the time of day, the weather and what happens): keep it, and remove anything in the prompt that contradicts it." } ?? "There is no author's rule.")
        1. The SCENE below is the user's own words and always wins over everything except the author's rule. Remove or rewrite anything in the prompt that contradicts it, above all about lighting, time of day, weather, season, sky and mood (for example delete "golden hour", "bright and cheerful", "evenly lit", "never dark or gloomy" or "a clear, cloudless sky" when the scene is a storm or a night; keep them when they agree).
        2. Settle any other contradiction in the most sensible way for the scene.
        3. Keep everything else exactly: the art medium and technique, every instruction about attached reference pictures, every "no …" exclusion, the camera instructions, the composition and the labelled lines (keep each label).
        4. Do not add new content, do not shorten needlessly, keep it in English.
        Reply with ONLY the final prompt, nothing before or after it.

        \(rule.map { "AUTHOR'S RULE: \($0)\n" } ?? "")SCENE: \(sc)

        PROMPT:
        \(prompt)
        """
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!); req.httpMethod = "POST"; req.timeoutInterval = 40
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "temperature": 0, "messages": [["role": "user", "content": rules]]] as [String: Any])
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ch = (j["choices"] as? [[String: Any]])?.first,
              var out = (ch["message"] as? [String: Any])?["content"] as? String else { return prompt }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") { out = out.components(separatedBy: "\n").dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n") }
        out = out.replacingOccurrences(of: #"^(PROMPT|Final prompt)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard out.count >= prompt.count / 2 else { return prompt }                  // a broken answer: send the original
        if ProcessInfo.processInfo.environment["MV_SHOW_PROMPT"] != nil { FileHandle.standardError.write(Data("CHECKED PROMPT:\n\(out)\n\n".utf8)) }
        return out
    }
}
