// Asks the language model for the song description, shared style and per-picture prompts, with retries and fallbacks.
import Foundation

/// Uses the local LLM (oMLX) to propose one consistent visual style and a self-contained image-generation prompt per section.
public struct PromptWriter {
    let omlx: OMLX
    public init(omlx: OMLX) { self.omlx = omlx }

    static func theme(title: String, subject: String) -> String {
        (subject.trimmingCharacters(in: .whitespaces).isEmpty ? "Song: “\(title)”" : "Song: “\(title)”.\nSong description: \(subject)") + "\n" + brightRule
    }
    /// Every picture idea must look bright and inviting, whatever the lyrics are about.
    public static let brightRule = "LIGHTING RULE: every picture must be BRIGHT, colourful, cheerful and well lit (daylight, sunny, golden, pastel or glowing light). Never dark, gloomy, murky, grim, foggy, night-time or low-key; even when the lyrics are sad or serious, show it with warm, luminous light and clear colours."

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

    /// Words of the setting (“colonial Philadelphia”) that every prompt shares; ignored when judging whether two prompts are alike.
    static func settingWords(_ setting: String) -> Set<String> { Set(setting.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 }) }
    static func settingBlock(_ setting: String) -> String {
        let t = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : "SETTING AND THEME (fixed by the author): \"\(t)\". EVERY picture must take place in this setting and visibly show it (its place, era, architecture, light and mood). Only the moment, the camera angle and the details change from picture to picture. If the lyrics mention something that does not belong in this setting, show the closest thing that does belong there instead — never leave the setting. Mention the place in every prompt (for example its streets, buildings, light and clothing).\n"
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

    /// Makes sure a prompt states the setting out loud: left alone if it already names it, otherwise the setting is put in front.
    static func withSetting(_ prompt: String, _ setting: String) -> String {
        let t = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return prompt }
        let low = prompt.lowercased()
        if low.contains(t.lowercased()) { return prompt }
        let words = settingWords(t)
        if !words.isEmpty, Double(words.filter { low.contains($0) }.count) / Double(words.count) >= 0.67 { return prompt }
        return "\(t): \(prompt)"
    }

    /// Word-overlap similarity (0…1) between two prompts, ignoring short filler words.
    static func similarity(_ a: String, _ b: String, ignoring ignored: Set<String> = []) -> Double {
        func words(_ t: String) -> Set<String> { Set(t.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 5 && !ignored.contains($0) }) }
        let x = words(a), y = words(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }
    static let clashThreshold = 0.35
    /// Neighbouring pictures must be dramatically different, so they are held to a much stricter limit than pictures far apart.
    static let neighbourThreshold = 0.20

    /// The kind of shot an idea describes: two pictures in a row may not be the same kind.
    static func shotType(_ s: String) -> String {
        let t = s.lowercased()
        let table: [(String, [String])] = [("aerial", ["aerial", "overhead", "high vantage", "bird's-eye", "bird’s-eye", "from above"]), ("detail", ["close-up", "close up", "detail", "macro", "a boot", "hands "]),
                                          ("silhouette", ["silhouette"]), ("framed", ["framed through", "through a doorway", "through a window", "through an arch", "through the branches"]),
                                          ("reflection", ["reflection", "reflected"]), ("low", ["low-angle", "low angle", "ground level", "seen low", "from the ground"]),
                                          ("wide", ["wide", "establishing", "panoram", "vista", "sweeping"]), ("medium", ["medium shot", "medium view"])]
        for (name, keys) in table where keys.contains(where: { t.contains($0) }) { return name }
        return "other"
    }
    static func tooCloseToNeighbour(_ p: String, _ prev: String, ignoring ign: Set<String>) -> Bool {
        if prev.isEmpty { return false }
        let a = shotType(p), b = shotType(prev)
        if a != "other" && a == b { return true }
        return similarity(p, prev, ignoring: ign) >= neighbourThreshold
    }

    /// Small models sometimes start the prompt by repeating (the start of) the shared style line; drop that echo.
    static func stripStyleEcho(_ prompt: String, style: String) -> String {
        let st = style.lowercased()
        guard !st.isEmpty, let sep = prompt.firstIndex(where: { $0 == ":" || $0 == "." }), prompt.distance(from: prompt.startIndex, to: sep) > 12, prompt.distance(from: prompt.startIndex, to: sep) < 140 else { return prompt }
        let head = prompt[..<sep].lowercased().trimmingCharacters(in: .whitespaces)
        guard st.contains(head) else { return prompt }
        let rest = prompt[prompt.index(after: sep)...].trimmingCharacters(in: CharacterSet(charactersIn: " :.\n"))
        return rest.count > 20 ? rest : prompt
    }
    static let variations = ["in bright morning sun", "in bright midday sun", "in warm golden-hour light", "under a clear blue sky", "in soft pastel light", "in sparkling sunlight", "from a high vantage point", "seen low to the ground", "just after a sunny shower", "through the branches of a tree"]

    /// Returns (style, prompt per section id). Section id −1 is the opening title card.
    /// Resilient to truncated or slightly malformed LLM JSON: salvages partial entries and fills any missing sections individually.
    public func write(sections: [PhotoSection], lines: [LyricLine], title: String, subject: String, preferredStyle: String = "", setting: String = "", progress: ProgressHandler? = nil) async throws -> (style: String, prompts: [Int: String], focal: [Int: [String]]) {
        try Task.checkCancellation()
        let fixedStyle = preferredStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = """
        \(PromptWriter.theme(title: title, subject: subject))
        \(PromptWriter.settingBlock(setting))\(fixedStyle.isEmpty ? "" : "Chosen visual style: \(fixedStyle)\n")
        We are making a lyric music video. Use the song description below as the single source of truth for setting, era, mood and recurring subjects. A human will paste each prompt below into an AI image generator and load the pictures back in, so the images must look like they belong together.
        1. \(fixedStyle.isEmpty ? "Invent ONE visual style line that suits this song and keeps every image consistent: medium (e.g. cinematic photograph / oil painting / vintage illustration), colour palette, lighting, era, mood. 20–35 words." : "Use the chosen visual style above for the \"style\" field.")
        2. For each numbered section write a vivid, concrete, self-contained image prompt (1–2 sentences, 25–45 words) depicting what that section's lyrics describe or evoke: \
        setting, subject, composition (wide or medium shot, no close-ups of faces), time of day, weather. Keep places, era and recurring subjects consistent from section to section. The sections are CONSECUTIVE SCENES OF ONE STORY: each picture follows on from the picture before it (same world, time moving forward) and moves the narrative forward; never repeat or go back. BUT every picture must look DRAMATICALLY DIFFERENT from the one before it: change the main subject, the kind of shot (alternate between a sweeping wide view, a low ground-level view, a high aerial view, a detail of an object, a view framed through something, a silhouette), the scale, the dominant colours and the time of day. Never two wide landscapes, or two pictures of the same subject, in a row. If a section's lyrics repeat an earlier one (a chorus), show a different moment or camera angle of the same story beat. Each section ends with a [look: …] hint (time of day, weather, camera view): use it, so the pictures look different from one another while staying in the same setting. EVERY section needs its own unique picture: a different subject, place within the story, composition or time of day — never repeat or lightly reword another section's prompt. Music-only sections (instrumental intro, breaks, outro) also get their own prompt tied to the song's world. \
        NO text, lettering, signs or logos in the image. Do not repeat the style line inside the prompts. Section -1 is the opening title-card background: an establishing scene for the whole song.
        Every idea must contain TWO clearly different FOCAL POINTS placed apart in the frame (for example a main subject on one side and a second point of interest on the other side or in the distance); describe both in the idea. Focal points must be things you can SEE and point at (a person, an animal, a building, a machine, a boat, a tree), never light, weather or abstract qualities. A slow camera will travel from the first to the second.
        Reply with ONLY JSON: {"style":"...","sections":[{"i":-1,"prompt":"...","focal":["first focal point","second focal point"]},{"i":0,"prompt":"...","focal":["...","..."]}, ...]}

        """
        let hints = PromptVariety.hints(count: sections.count)
        for (i, s) in sections.enumerated() {
            body += "\(s.id): \(PromptWriter.context(for: s, lines: lines)) [look: \(hints[i])]\n"
        }
        var out: [Int: String] = [:]
        var focals: [Int: [String]] = [:]
        var styleOut = fixedStyle
        if let reply = try? await omlx.chat(model: omlx.llm, parts: [.text(body)], maxTokens: 4000) {
            if let o = OMLX.json(from: reply) as? [String: Any], let arr = o["sections"] as? [[String: Any]] {
                if styleOut.isEmpty { styleOut = (o["style"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                for e in arr {
                    if let i = e["i"] as? Int ?? Int("\(e["i"] ?? "")"), let p = e["prompt"] as? String {
                        let clean = p.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { out[i] = clean }
                        if let f = e["focal"] as? [String], f.count >= 2 { focals[i] = f.prefix(2).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
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
                if let p = try? await rewrite(section: s, lines: lines, title: title, subject: subject, style: styleOut, current: "", setting: setting), !p.isEmpty {
                    out[s.id] = p
                }
            }
        }
        // Every section must be different: rewrite any prompt that is nearly the same as another, then fall back to a changed time of day / viewpoint.
        for (n, s) in sections.enumerated() {
            guard var p = out[s.id] else { continue }
            let ign = PromptWriter.settingWords(setting)
            let prevID = n == 0 ? -1 : sections[n - 1].id
            func clash() -> Bool { PromptWriter.tooCloseToNeighbour(p, out[prevID] ?? "", ignoring: ign) || sections.contains { o in o.id != s.id && o.id < s.id && (out[o.id] ?? "").count > 0 && PromptWriter.similarity(p, out[o.id]!, ignoring: ign) >= PromptWriter.clashThreshold } }
            if clash() {
                try Task.checkCancellation()
                progress?("Making picture \(n + 1) different from the others…", Double(n) / Double(max(1, sections.count)))
                let others = sections.filter { $0.id != s.id }.compactMap { out[$0.id] }
                p = (try? await rewriteDistinct(section: s, lines: lines, title: title, subject: subject, style: styleOut, current: p, others: others, salt: n, setting: setting, previous: out[prevID] ?? "")) ?? p
            }
            out[s.id] = PromptWriter.withSetting(p, setting)
        }
        return (styleOut, out, focals)
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
    public func rewrite(section: PhotoSection, lines: [LyricLine], title: String, subject: String, style: String, current: String, avoid: [String] = [], setting: String = "", previous: String = "", next: String = "") async throws -> String {
        let t = PromptWriter.context(for: section, lines: lines)
        let avoidText = avoid.isEmpty ? "" : "\nThese pictures already exist; the new one must clearly differ from every one of them in subject, place, composition and time of day:\n" + avoid.prefix(24).map { "- " + $0 }.joined(separator: "\n") + "\n"
        let prompt = """
        \(PromptWriter.theme(title: title, subject: subject))
        \(PromptWriter.settingBlock(setting))Shared visual style (do not repeat it): \(style)
        Lyrics for this section: \(t)
        Look for this picture (use it): \(PromptVariety.hint())
        Current prompt: \(current)\(avoidText)
        \(previous.isEmpty ? "" : "Previous picture in the story (this one must FOLLOW ON from it and move the story forward, yet look DRAMATICALLY DIFFERENT: a different main subject, a different kind of shot, a different scale, different dominant colours and time of day): \(previous)\n")\(next.isEmpty ? "" : "Next picture in the story (do not pre-empt it): \(next)\n")
        Write a different, vivid, concrete, self-contained image-generation prompt (1–2 sentences, 25–45 words) for this section. It must contain TWO clearly different focal points placed apart in the frame (a main subject and a second point of interest). Wide or medium shot, no close-ups of faces, no text or logos. \
        Reply with ONLY the prompt text.
        """
        var r = try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 200).trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”"))
        return PromptWriter.withSetting(PromptWriter.stripStyleEcho(r, style: style), setting)
    }

    /// Like `rewrite`, but keeps asking until the result is clearly different from `others` (then, as a last resort, changes time of day / viewpoint).
    public func rewriteDistinct(section: PhotoSection, lines: [LyricLine], title: String, subject: String, style: String, current: String, others: [String], salt: Int = 0, setting: String = "", previous: String = "", next: String = "") async throws -> String {
        var p = current
        var tries = 0
        let ign = PromptWriter.settingWords(setting)
        func clashes(_ t: String) -> Bool { t.isEmpty || PromptWriter.tooCloseToNeighbour(t, previous, ignoring: ign) || others.contains { PromptWriter.similarity(t, $0, ignoring: ign) >= PromptWriter.clashThreshold } }
        repeat {
            try Task.checkCancellation()
            if let r = try? await rewrite(section: section, lines: lines, title: title, subject: subject, style: style, current: p, avoid: others, setting: setting, previous: previous, next: next), !r.isEmpty { p = r }
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

    // MARK: story logic pass (local model)

    /// The "logic pass": reads the picture ideas in order, with the lyrics of each section, and fixes any idea that is physically impossible,
    /// does not follow on from the idea before it, or does not fit the song at that moment. Ideas you wrote yourself (`manual`) are never changed.
    /// `only` limits the fixing to some sections (the others are shown as context). Returns the corrected prompts and a short note per changed section.
    public func logicPass(items: [(id: Int, prompt: String, lyrics: String, manual: Bool)], only: Set<Int>? = nil, title: String, subject: String, setting: String = "") async -> (prompts: [Int: String], notes: [Int: String]) {
        guard items.count >= 1 else { return ([:], [:]) }
        let list = items.map { "\($0.id): \($0.prompt)\n   lyrics: \($0.lyrics.isEmpty ? "(music only)" : $0.lyrics)" }.joined(separator: "\n")
        let canFix = items.filter { !$0.manual && (only == nil || only!.contains($0.id)) }.map { String($0.id) }.joined(separator: ", ")
        guard !canFix.isEmpty else { return ([:], [:]) }
        let prompt = """
        \(PromptWriter.theme(title: title, subject: subject))
        \(PromptWriter.settingBlock(setting))These are the picture ideas of a lyric music video, in story order. Each picture is the next scene of ONE story.
        \(list)

        Check the ideas numbered \(canFix) (the others are context only). An idea FAILS if (1) it shows something physically impossible, (2) it does not follow on from the idea before it (the place, people or time jump without reason), or (3) it does not fit the lyrics or the story of the song at that moment, or goes backwards in the story, or (4) it looks too much like the idea before it (the same kind of subject, shot, scale or colours): neighbouring pictures must look dramatically different.
        Rewrite ONLY failing ideas: 1–2 vivid, concrete sentences (25–45 words), same style as the others, bright and well lit, no close-ups of faces, no text. Keep ideas that are fine exactly as they are.
        Most ideas are fine: only rewrite an idea that clearly fails, and then name the failed test. Reply with ONLY JSON: {"fixed":[{"i":3,"problem":"physics or continuity or story or too-similar","why":"what exactly is wrong, in one short sentence","prompt":"the rewritten idea"}]}. If everything is fine reply {"fixed":[]}.
        """
        guard let reply = try? await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 1800), let o = OMLX.json(from: reply) as? [String: Any], let arr = o["fixed"] as? [[String: Any]] else { return ([:], [:]) }
        var out: [Int: String] = [:], notes: [Int: String] = [:]
        let allowed = Set(items.filter { !$0.manual && (only == nil || only!.contains($0.id)) }.map(\.id))
        for e in arr {
            guard let i = e["i"] as? Int ?? Int("\(e["i"] ?? "")"), allowed.contains(i), let p = e["prompt"] as? String,
                  let problem = (e["problem"] as? String)?.lowercased(), ["physics", "continuity", "story", "similar"].contains(where: { problem.contains($0) }) else { continue }
            let old = items.first(where: { $0.id == i })?.prompt ?? ""
            let clean = PromptWriter.withSetting(p.trimmingCharacters(in: .whitespacesAndNewlines), setting)
            if clean.count >= 20, PromptWriter.similarity(old, clean, ignoring: []) < 0.8 {           // a rewrite that barely differs is not a real fix
                out[i] = clean
                notes[i] = "[\(problem)] " + (e["why"] as? String ?? "adjusted to follow the story").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return (out, notes)
    }

    /// The two focal points of a picture idea (short noun phrases): the first is the main subject, the second a clearly different one. Local model.
    public func focalPoints(of idea: String) async -> [String] {
        let prompt = """
        Picture idea: \(idea)
        Name the TWO main focal points of this picture as short noun phrases (2–5 words each). They must be clearly different VISIBLE things (a person, animal, building, machine, tree, object), never light, weather or feelings, placed apart in the frame. If the idea names only one, choose a plausible second point of interest that belongs in the same scene.
        Reply with ONLY JSON: {"focal":["first","second"]}
        """
        guard let reply = try? await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 80), let o = OMLX.json(from: reply) as? [String: Any],
              let f = o["focal"] as? [String], f.count >= 2 else { return [] }
        return f.prefix(2).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
