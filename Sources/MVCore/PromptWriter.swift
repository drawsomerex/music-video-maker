// Asks the language model for the song description, shared style and per-picture prompts, with retries and fallbacks.
import Foundation

/// Uses the local LLM (oMLX) to propose one consistent visual style and a self-contained image-generation prompt per section.
public struct PromptWriter {
    let omlx: OMLX
    public init(omlx: OMLX) { self.omlx = omlx }

    static func theme(title: String, subject: String) -> String {
        subject.trimmingCharacters(in: .whitespaces).isEmpty ? "Song: “\(title)”" : "Song: “\(title)”.\nSong description: \(subject)"
    }

    /// Reads the lyrics and writes a concise description of the song: setting, era, story, mood and recurring imagery.
    public func describe(title: String, lyrics: [String], hint: String = "") async throws -> String {
        let prompt = """
        Song title: “\(title)”
        \(hint.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "Author's note: \(hint)\n")
        Lyrics:
        \(lyrics.joined(separator: "\n"))

        Write a description of this song that an illustrator could use to picture it. In 3–5 sentences cover: the concrete setting (place, era, landscape), the story or subject, \
        the mood and emotional arc, and the recurring people/objects/images worth keeping consistent. Be specific and visual; do not quote the lyrics or list the verses. \
        Reply with ONLY the description text.
        """
        func looksBad(_ s: String) -> Bool {
            let l = s.lowercased()
            return s.count < 40 || l.hasPrefix("the user") || l.contains("reply with only") || l.contains("3–5 sentences") || l.contains("3-5 sentences")
        }
        var r = try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 400).trimmingCharacters(in: .whitespacesAndNewlines)
        if looksBad(r) {
            // Small models sometimes echo the instructions. Retry with a plainer, completion-style prompt.
            let plain = """
            Song: “\(title)”
            Lyrics:
            \(lyrics.joined(separator: "\n"))

            In four sentences, describe where and when this song is set, what happens in it, its mood, and the main objects and scenery that appear. Plain prose.

            Description:
            """
            r = try await omlx.chat(model: omlx.llm, parts: [.text(plain)], maxTokens: 350).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if looksBad(r) {
            // Last resort: a usable description assembled from the song itself.
            let opening = lyrics.prefix(6).joined(separator: " ")
            r = "A song called “\(title)”. It opens: \(opening) The imagery follows the story the lyrics tell, with a consistent setting, era and mood throughout."
        }
        return r
    }

    /// Returns (style, prompt per section id). Section id −1 is the opening title card.
    public func write(sections: [PhotoSection], lines: [LyricLine], title: String, subject: String) async throws -> (style: String, prompts: [Int: String]) {
        var body = """
        \(PromptWriter.theme(title: title, subject: subject))

        We are making a lyric music video. Use the song description below as the single source of truth for setting, era, mood and recurring subjects. A human will paste each prompt below into an AI image generator and load the pictures back in, so the images must look like they belong together.
        1. Invent ONE visual style line that suits this song and keeps every image consistent: medium (e.g. cinematic photograph / oil painting / vintage illustration), \
        colour palette, lighting, era, mood. 20–35 words.
        2. For each numbered section write a vivid, concrete, self-contained image prompt (1–2 sentences, 25–45 words) depicting what that section's lyrics describe or evoke: \
        setting, subject, composition (wide or medium shot, no close-ups of faces), time of day, weather. Keep places, era and recurring subjects consistent from section to section. If a section's lyrics repeat an earlier one (a chorus), show a different moment or camera angle of the same story beat. \
        NO text, lettering, signs or logos in the image. Do not repeat the style line inside the prompts. Section -1 is the opening title-card background: an establishing scene for the whole song.
        Reply with ONLY JSON: {"style":"...","sections":[{"i":-1,"prompt":"..."},{"i":0,"prompt":"..."}, ...]}

        """
        for s in sections {
            let t = s.lineIDs.isEmpty ? "(instrumental break — an establishing scene for the song's setting)" : s.lineIDs.map { lines[$0].text }.joined(separator: " / ")
            body += "\(s.id): \(t)\n"
        }
        let reply = try await omlx.chat(model: omlx.llm, parts: [.text(body)], maxTokens: 4000)
        guard let o = OMLX.json(from: reply) as? [String: Any], let arr = o["sections"] as? [[String: Any]] else {
            throw MVError("The language model didn't return usable prompts (it said: “\(reply.prefix(160).replacingOccurrences(of: "\n", with: " "))…”). Try again, or use a larger model.")
        }
        var out: [Int: String] = [:]
        for e in arr { if let i = e["i"] as? Int ?? Int("\(e["i"] ?? "")"), let p = e["prompt"] as? String { out[i] = p.trimmingCharacters(in: .whitespacesAndNewlines) } }
        return ((o["style"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines), out)
    }

    /// Rewrites one section's prompt (the user asked for another take).
    public func rewrite(section: PhotoSection, lines: [LyricLine], title: String, subject: String, style: String, current: String) async throws -> String {
        let t = section.lineIDs.isEmpty ? "(instrumental break)" : section.lineIDs.map { lines[$0].text }.joined(separator: " / ")
        let prompt = """
        \(PromptWriter.theme(title: title, subject: subject))
        Shared visual style (do not repeat it): \(style)
        Lyrics for this section: \(t)
        Current prompt: \(current)

        Write a different, vivid, concrete, self-contained image-generation prompt (1–2 sentences, 25–45 words) for this section. Wide or medium shot, no close-ups of faces, no text or logos. \
        Reply with ONLY the prompt text.
        """
        return try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 200).trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”"))
    }

    /// A punchy 3–6 word on-screen hook for the opening of a Short.
    public func hook(title: String, description: String, lyrics: [String]) async throws -> String {
        let prompt = """
        \(PromptWriter.theme(title: title, subject: description))
        These are the lyrics of a 30-second YouTube Short cut from the song:
        \(lyrics.joined(separator: "\n"))

        Write the big on-screen hook title shown during the first 2 seconds. 3–6 words, plain and intriguing (a mini-headline or question that makes someone stay), \
        no emojis, no hashtags, no quotation marks, don't copy a whole lyric line. Examples of the feel: "The day oil changed everything", "Nobody saw this coming". \
        Reply with ONLY the hook.
        """
        let r = try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 40)
        let t = r.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”'.")).replacingOccurrences(of: "\n", with: " ")
        guard t.count >= 3 else { throw MVError("No hook returned.") }
        return t
    }

    /// Title, description and hashtags for uploading a Short.
    public func metadata(title: String, description: String, lyrics: [String], hook: String, cta: String) async throws -> String {
        let prompt = """
        \(PromptWriter.theme(title: title, subject: description))
        Lyrics in this YouTube Short:
        \(lyrics.joined(separator: "\n"))
        On-screen hook: \(hook)

        Write upload metadata. Reply in exactly this format:
        TITLE: <under 70 characters, curiosity-driven, mentions the song or its subject, no clickbait lies, no hashtags>
        DESCRIPTION: <2 short sentences about the song/story\(cta.isEmpty ? "" : ", ending with: \(cta)")>
        HASHTAGS: <#Shorts plus 4–5 relevant hashtags, space-separated>
        """
        return try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 300).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
