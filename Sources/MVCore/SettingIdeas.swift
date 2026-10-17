// "Suggest 10 ideas": different settings (place, era, mood) for the whole video, written by the local AI from the lyrics.
import Foundation

extension PromptWriter {
    public func suggestSettings(title: String, lyrics: [String], description: String = "", avoid: [String] = []) async throws -> [String] {
        let desc = description.isEmpty ? "" : "Song description: \(description)\n"
        let avoidText = avoid.isEmpty ? "" : "Do not repeat these earlier ideas: " + avoid.joined(separator: "; ") + "."
        let prompt = """
        Song title: “\(title)”
        \(desc)Lyrics:
        \(lyrics.prefix(60).joined(separator: "\n"))

        Suggest 10 DIFFERENT settings for the pictures of a music video for this song. Each one is a short phrase of 4 to 12 words naming a place, an era or time, and a mood or light, for example "Brightly lit colonial Philadelphia, 1776" or "A misty fishing village at dawn".
        Make them clearly different from one another (different places, eras and moods) while each one still suits what the lyrics are about. No text, names of living people or brand names. \(avoidText)
        Reply with ONLY a JSON array of 10 strings.
        """
        let reply = try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 500)
        var out: [String] = []
        if let a = OMLX.json(from: reply) as? [String] { out = a }
        else if let o = OMLX.json(from: reply) as? [String: Any], let a = o.values.compactMap({ $0 as? [String] }).first { out = a }
        if out.count < 3 {                                       // numbered / bulleted list fallback
            out = reply.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\"“”,0123456789.)")) }.filter { $0.count >= 8 && $0.count <= 120 }
        }
        var seen = Set(avoid.map { $0.lowercased() }); var clean: [String] = []
        for t in out.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"“”.")) }) where t.count >= 6 && !seen.contains(t.lowercased()) { seen.insert(t.lowercased()); clean.append(t) }
        guard !clean.isEmpty else { throw MVError("The AI didn't return any ideas this time. Please press the button again.") }
        return Array(clean.prefix(10))
    }
}
