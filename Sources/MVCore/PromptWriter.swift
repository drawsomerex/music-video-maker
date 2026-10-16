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

    /// What the model is told about a section: its lyrics, or — for music-only sections — where in the song it falls and the words around it,
    /// so every instrumental picture gets its own idea instead of the same generic "establishing scene".
    static func context(for s: PhotoSection, lines: [LyricLine]) -> String {
        if s.id == -1 { return "(opening title-card background — a wide establishing scene for the whole song)" }
        if !s.lineIDs.isEmpty { return s.lineIDs.compactMap { lines.indices.contains($0) ? lines[$0].text : nil }.joined(separator: " / ") }
        let prev = lines.last { $0.end <= s.start + 0.6 }, next = lines.first { $0.start >= s.end - 0.6 }
        let secs = Int((s.end - s.start).rounded())
        switch (prev, next) {
        case (nil, let n?):
            return "(music only, \(secs) s, BEFORE the first words: the world before the story starts — a calm, atmospheric scene that sets up the place and mood. The first words are “\(n.text)”. Do not copy the title-card scene)"
        case (let p?, nil):
            return "(music only, \(secs) s, AFTER the last words: a closing, reflective scene — the story's aftermath, the place at rest. The last words were “\(p.text)”)"
        case (let p?, let n?):
            return "(music only, \(secs) s, between “\(p.text)” and “\(n.text)”: a quiet beat linking those two moments — a different place, detail or time of day than the lines around it)"
        default:
            return "(music only, \(secs) s: an atmospheric scene from the song's world)"
        }
    }

    /// Word-overlap similarity (0…1) between two prompts, ignoring short filler words.
    static func similarity(_ a: String, _ b: String) -> Double {
        func words(_ t: String) -> Set<String> { Set(t.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 }) }
        let x = words(a), y = words(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }
    static let clashThreshold = 0.35

    /// Small models sometimes start the prompt by repeating (the start of) the shared style line; drop that echo.
    static func stripStyleEcho(_ prompt: String, style: String) -> String {
        let st = style.lowercased()
        guard !st.isEmpty, let sep = prompt.firstIndex(where: { $0 == ":" || $0 == "." }), prompt.distance(from: prompt.startIndex, to: sep) > 12, prompt.distance(from: prompt.startIndex, to: sep) < 140 else { return prompt }
        let head = prompt[..<sep].lowercased().trimmingCharacters(in: .whitespaces)
        guard st.contains(head) else { return prompt }
        let rest = prompt[prompt.index(after: sep)...].trimmingCharacters(in: CharacterSet(charactersIn: " :.\n"))
        return rest.count > 20 ? rest : prompt
    }
    static let variations = ["at dawn with low mist", "in bright midday sun", "in warm golden-hour light", "at dusk with long shadows", "under moonlight", "in drifting fog", "from a high vantage point", "seen low to the ground", "in light rain", "through the branches of a tree"]

    /// Returns (style, prompt per section id). Section id −1 is the opening title card.
    /// Resilient to truncated or slightly malformed LLM JSON: salvages partial entries and fills any missing sections individually.
    public func write(sections: [PhotoSection], lines: [LyricLine], title: String, subject: String, preferredStyle: String = "", progress: ProgressHandler? = nil) async throws -> (style: String, prompts: [Int: String]) {
        try Task.checkCancellation()
        let fixedStyle = preferredStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = """
        \(PromptWriter.theme(title: title, subject: subject))
        \(fixedStyle.isEmpty ? "" : "Chosen visual style: \(fixedStyle)\n")
        We are making a lyric music video. Use the song description below as the single source of truth for setting, era, mood and recurring subjects. A human will paste each prompt below into an AI image generator and load the pictures back in, so the images must look like they belong together.
        1. \(fixedStyle.isEmpty ? "Invent ONE visual style line that suits this song and keeps every image consistent: medium (e.g. cinematic photograph / oil painting / vintage illustration), colour palette, lighting, era, mood. 20–35 words." : "Use the chosen visual style above for the \"style\" field.")
        2. For each numbered section write a vivid, concrete, self-contained image prompt (1–2 sentences, 25–45 words) depicting what that section's lyrics describe or evoke: \
        setting, subject, composition (wide or medium shot, no close-ups of faces), time of day, weather. Keep places, era and recurring subjects consistent from section to section. If a section's lyrics repeat an earlier one (a chorus), show a different moment or camera angle of the same story beat. EVERY section needs its own unique picture: a different subject, place within the story, composition or time of day — never repeat or lightly reword another section's prompt. Music-only sections (instrumental intro, breaks, outro) also get their own prompt tied to the song's world. \
        NO text, lettering, signs or logos in the image. Do not repeat the style line inside the prompts. Section -1 is the opening title-card background: an establishing scene for the whole song.
        Reply with ONLY JSON: {"style":"...","sections":[{"i":-1,"prompt":"..."},{"i":0,"prompt":"..."}, ...]}

        """
        for s in sections {
            body += "\(s.id): \(PromptWriter.context(for: s, lines: lines))\n"
        }
        var out: [Int: String] = [:]
        var styleOut = fixedStyle
        if let reply = try? await omlx.chat(model: omlx.llm, parts: [.text(body)], maxTokens: 4000) {
            if let o = OMLX.json(from: reply) as? [String: Any], let arr = o["sections"] as? [[String: Any]] {
                if styleOut.isEmpty { styleOut = (o["style"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                for e in arr {
                    if let i = e["i"] as? Int ?? Int("\(e["i"] ?? "")"), let p = e["prompt"] as? String {
                        let clean = p.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { out[i] = clean }
                    }
                }
            } else {
                let salvaged = Self.salvage(from: reply)
                if styleOut.isEmpty, !salvaged.style.isEmpty { styleOut = salvaged.style }
                out = salvaged.prompts
            }
        }
        if styleOut.isEmpty {
            styleOut = "Cinematic widescreen illustration with warm natural lighting, rich atmospheric depth and cohesive color grading."
        }
        // Fill any missing sections individually so truncated JSON never aborts the plan.
        let missing = sections.filter { (out[$0.id] ?? "").count < 12 }
        if !missing.isEmpty {
            for (idx, s) in missing.enumerated() {
                try Task.checkCancellation()
                progress?("Writing prompt \(idx + 1) of \(missing.count)…", Double(idx) / Double(max(1, missing.count)))
                if let p = try? await rewrite(section: s, lines: lines, title: title, subject: subject, style: styleOut, current: ""), !p.isEmpty {
                    out[s.id] = p
                }
            }
        }
        // Every section must be different: rewrite any prompt that is nearly the same as another, then fall back to a changed time of day / viewpoint.
        for (n, s) in sections.enumerated() {
            guard var p = out[s.id] else { continue }
            func clash() -> Bool { sections.contains { o in o.id != s.id && o.id < s.id && (out[o.id] ?? "").count > 0 && PromptWriter.similarity(p, out[o.id]!) >= PromptWriter.clashThreshold } }
            if clash() {
                try Task.checkCancellation()
                progress?("Making picture \(n + 1) different from the others…", Double(n) / Double(max(1, sections.count)))
                let others = sections.filter { $0.id != s.id }.compactMap { out[$0.id] }
                p = (try? await rewriteDistinct(section: s, lines: lines, title: title, subject: subject, style: styleOut, current: p, others: others, salt: n)) ?? p
            }
            out[s.id] = p
        }
        return (styleOut, out)
    }

    /// Extracts style and section prompts from truncated or slightly malformed JSON / numbered text.
    static func salvage(from text: String) -> (style: String, prompts: [Int: String]) {
        var style = ""
        var prompts: [Int: String] = [:]
        if let rx = try? NSRegularExpression(pattern: #""style"\s*:\s*"((?:[^"\\]|\\.)*)""#),
           let m = rx.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text) {
            style = String(text[r]).replacingOccurrences(of: "\\\"", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let rx = try? NSRegularExpression(pattern: #""i"\s*:\s*"?(-?\d+)"?\s*,\s*"prompt"\s*:\s*"((?:[^"\\]|\\.)*)""#) {
            for m in rx.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let ir = Range(m.range(at: 1), in: text), let pr = Range(m.range(at: 2), in: text), let i = Int(text[ir]) {
                    let p = String(text[pr]).replacingOccurrences(of: "\\\"", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !p.isEmpty { prompts[i] = p }
                }
            }
        }
        if prompts.isEmpty, let rx = try? NSRegularExpression(pattern: #"(?m)^\s*(-?\d+)\s*[:.)]\s*(.+)$"#) {
            for m in rx.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let ir = Range(m.range(at: 1), in: text), let pr = Range(m.range(at: 2), in: text), let i = Int(text[ir]) {
                    let p = String(text[pr]).trimmingCharacters(in: CharacterSet(charactersIn: " \"“”"))
                    if p.count >= 15 { prompts[i] = p }
                }
            }
        }
        return (style, prompts)
    }

    /// Rewrites one section's prompt (the user asked for another take).
    public func rewrite(section: PhotoSection, lines: [LyricLine], title: String, subject: String, style: String, current: String, avoid: [String] = []) async throws -> String {
        let t = PromptWriter.context(for: section, lines: lines)
        let avoidText = avoid.isEmpty ? "" : "\nThese pictures already exist; the new one must clearly differ from every one of them in subject, place, composition and time of day:\n" + avoid.prefix(24).map { "- " + $0 }.joined(separator: "\n") + "\n"
        let prompt = """
        \(PromptWriter.theme(title: title, subject: subject))
        Shared visual style (do not repeat it): \(style)
        Lyrics for this section: \(t)
        Current prompt: \(current)\(avoidText)

        Write a different, vivid, concrete, self-contained image-generation prompt (1–2 sentences, 25–45 words) for this section. Wide or medium shot, no close-ups of faces, no text or logos. \
        Reply with ONLY the prompt text.
        """
        var r = try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 200).trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”"))
        return PromptWriter.stripStyleEcho(r, style: style)
    }

    /// Like `rewrite`, but keeps asking until the result is clearly different from `others` (then, as a last resort, changes time of day / viewpoint).
    public func rewriteDistinct(section: PhotoSection, lines: [LyricLine], title: String, subject: String, style: String, current: String, others: [String], salt: Int = 0) async throws -> String {
        var p = current
        var tries = 0
        func clashes(_ t: String) -> Bool { t.isEmpty || others.contains { PromptWriter.similarity(t, $0) >= PromptWriter.clashThreshold } }
        repeat {
            try Task.checkCancellation()
            if let r = try? await rewrite(section: section, lines: lines, title: title, subject: subject, style: style, current: p, avoid: others), !r.isEmpty { p = r }
            tries += 1
        } while clashes(p) && tries < 3
        if clashes(p) { p = p.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) + ", " + PromptWriter.variations[(salt + others.count) % PromptWriter.variations.count] + "." }
        return p
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
