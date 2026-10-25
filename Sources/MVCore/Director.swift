// Automatic mode's director: plans the whole video the way a music-video director writes a treatment, then the app carries it out.
//
// How artistic music videos are planned (from directors' treatment practice): a one-sentence logline and ONE clear concept; a defined visual
// language (one medium, a restricted palette of a few named colours, texture); one to three recurring motifs that evolve through the video; few
// locations, so the video is one world; the picture follows the song's structure (verses build, every chorus returns to a visual "rhyme" of the
// same composition or motif, the bridge breaks the pattern, the ending answers the opening); images that complement the song with metaphor
// rather than illustrating each lyric word literally; restraint (one idea per picture); varied shots (wide, medium, close, detail; different angles).
import Foundation

/// The director's plan for a music video.
public struct Treatment: Codable, Sendable {
    public var logline = ""
    public var concept = ""
    public var palette = ""
    public var motifs: [String] = []
    public var style = ""                         // the medium and technique (no lighting)
    public var reference: String? = nil           // words to search for a photo of the recurring place, building or subject (nil = none)
    public var keep: NextFocus = .place
    public var pictures: [Int: String] = [:]      // section index (−1 = title card) → picture idea
    public var summary: String {
        "\(logline)\n\nConcept: \(concept)\nPalette: \(palette)\nMotifs: \(motifs.joined(separator: "; "))\nStyle: \(style)"
    }
}

/// The director's plan for a looping video: a few scenes of one world.
public struct LoopTreatment: Codable, Sendable {
    public var logline = ""
    public var style = ""
    public var reference: String? = nil
    public var keep: NextFocus = .place
    public var scenes: [String] = []              // the first scene, then the next ones (same place, building or subject; something new)
}

public enum Director {
    public static let model = "google/gemini-2.5-flash"

    /// The rules every plan follows (what makes a music video artistic rather than a slideshow).
    static let craft = """
    Work like an acclaimed music-video director writing a treatment:
    - ONE clear concept, stated as a logline of 15–30 words. The images COMPLEMENT the song with visual metaphor and story; never illustrate each lyric word literally.
    - A defined visual language: ONE medium and technique (for example "hand-painted gouache illustration on textured paper", "35mm film photograph with natural grain", "impasto oil painting"), and a restricted palette of 3–4 named colours. The style never mentions lighting, time of day or weather (each picture decides those).
    - 1–3 recurring MOTIFS (an object, a colour, a gesture or a place) that return and change as the story moves on.
    - Few locations (one to three), so the video is one world. The same people keep the same look.
    - Follow the song's structure: verses build the story; every repeated chorus returns to a visual RHYME (the same composition, motif or place, a little changed each time); a bridge or instrumental break shows a contrast; the last picture answers the first.
    - Restraint: one clear idea per picture. Vary the shots: wide, medium, close-up and detail, from different angles and heights.
    - Every picture idea is one vivid sentence of 20–45 words: what we see, where, the moment, the light and weather of that moment, and the shot. No text, signs or lettering in pictures.
    """

    static func ask(_ prompt: String, config: Config) async throws -> (json: [String: Any], cost: Double) {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!); req.httpMethod = "POST"; req.timeoutInterval = 180
        req.setValue("Bearer \(config.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "temperature": 0.8, "response_format": ["type": "json_object"], "usage": ["include": true],
                                                                   "messages": [["role": "user", "content": prompt]]] as [String: Any])
        let (d, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let ch = (j["choices"] as? [[String: Any]])?.first,
              var msg = (ch["message"] as? [String: Any])?["content"] as? String else { throw MVError("The director didn't answer. Check your OpenRouter key and credit, then try again.") }
        msg = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.hasPrefix("```") { msg = msg.components(separatedBy: "\n").dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n") }
        guard let data = msg.data(using: .utf8), let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MVError("The director's plan couldn't be read. Try again.") }
        return (obj, ((j["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue ?? 0)
    }
    static func focus(_ s: Any?) -> NextFocus { NextFocus(rawValue: (s as? String ?? "").lowercased()) ?? .place }

    /// Plans a music video: the treatment and one picture idea for every part of the song.
    public static func musicVideo(_ plan: Plan, config: Config = .load()) async throws -> (Treatment, Double) {
        func time(_ x: Double) -> String { String(format: "%d:%02d", Int(x) / 60, Int(x) % 60) }
        var parts = ["-1 | title card (opening) | an establishing picture for the whole video"]
        for (i, s) in plan.sections.enumerated() {
            var line = "\(i) | \(time(s.start))–\(time(s.end)) | \(PromptWriter.context(for: s, lines: plan.lines))"
            if let r = s.repeatOf { line += " | (same words as \(r): a visual rhyme of it)" }
            parts.append(line)
        }
        let prompt = """
        You are the director of a music video for the song "\(plan.title)".\(plan.description.isEmpty ? "" : " What the song is about: \(plan.description)")\(plan.songNotes.isEmpty ? "" : " The author's notes: \(plan.songNotes)")\(plan.setting.isEmpty ? "" : " Setting and theme fixed by the author: \(plan.setting).")
        Each part of the song below gets ONE still picture (it is slowly panned and zoomed while that part plays).

        \(craft)

        Also decide whether the video is built around ONE real recurring place, building or subject that a photo would help to get right (for example a real landmark, a type of animal, a ship); if so give a short web image search for it (2–5 words) and say what to keep from it: "place", "building" or "subject". Otherwise "reference": null.

        The parts (index | time | words):
        \(parts.joined(separator: "\n"))

        Reply with ONLY this JSON: {"logline":"...","concept":"...","palette":"...","motifs":["...","..."],"style":"...","reference":"search words" or null,"keep":"place|building|subject","pictures":[{"i":-1,"idea":"..."},{"i":0,"idea":"..."}, ...]} with one picture for EVERY index above.
        """
        let (j, cost) = try await ask(prompt, config: config)
        var t = Treatment()
        t.logline = j["logline"] as? String ?? ""; t.concept = j["concept"] as? String ?? ""; t.palette = (j["palette"] as? String) ?? (j["palette"] as? [String])?.joined(separator: ", ") ?? ""
        t.motifs = j["motifs"] as? [String] ?? []; t.style = StylePreset.withoutLighting(j["style"] as? String ?? "")
        t.reference = (j["reference"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.lowercased() == "null" ? nil : $0 }
        t.keep = focus(j["keep"])
        for p in j["pictures"] as? [[String: Any]] ?? [] {
            guard let idea = (p["idea"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !idea.isEmpty else { continue }
            let i = (p["i"] as? Int) ?? Int(p["i"] as? String ?? "") ?? -99
            if i == -1 || plan.sections.indices.contains(i) { t.pictures[i] = idea }
        }
        guard t.pictures.count >= max(1, (plan.sections.count + 1) / 2) else { throw MVError("The director's plan missed most of the pictures. Try again.") }
        return (t, cost)
    }

    /// Plans a looping video: one world in a few scenes that loop well.
    public static func looping(_ p: LoopProject, scenes: Int, config: Config = .load()) async throws -> (LoopTreatment, Double) {
        let songs = p.tracks.map(\.title).filter { !$0.isEmpty }.prefix(30).joined(separator: "; ")
        let prompt = """
        You are the director of a long, calm looping music video (study and relaxation music) called "\(p.title)".\(p.about.isEmpty ? "" : " About the music: \(p.about).")\(songs.isEmpty ? "" : " The songs: \(songs).")
        The video is \(scenes) scene\(scenes == 1 ? "" : "s"); each is ONE still picture brought to life as a 15-second clip that loops seamlessly, with a completely still camera.

        Work like an acclaimed director: ONE world and one clear concept (a logline of 15–30 words); ONE medium and technique with a restricted palette, never mentioning lighting, time of day or weather; the scenes are the SAME place (or building, or subject) at different moments, each with one clear change (another time of day, weather, season, or a calm new element), so together they feel like a journey through one world.
        Every scene must loop beautifully: gentle motion that repeats in place (water, rain, snow, mist, fire, smoke, flickering light, swaying plants); nothing walking or travelling across the picture; no people in the foreground; no text. Each scene is one vivid sentence of 20–40 words: what we see, where, the moment, the light and weather, and what moves.
        Also decide whether ONE real recurring place, building or subject would be helped by a photo (a real landmark, a kind of animal); if so give a short web image search for it (2–5 words) and what to keep from it: "place", "building" or "subject". Otherwise "reference": null.

        Reply with ONLY this JSON: {"logline":"...","style":"...","reference":"search words" or null,"keep":"place|building|subject","scenes":["first scene","next scene", ...]} with exactly \(scenes) scene\(scenes == 1 ? "" : "s").
        """
        let (j, cost) = try await ask(prompt, config: config)
        var t = LoopTreatment()
        t.logline = j["logline"] as? String ?? ""; t.style = StylePreset.withoutLighting(j["style"] as? String ?? "")
        t.reference = (j["reference"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.lowercased() == "null" ? nil : $0 }
        t.keep = focus(j["keep"])
        t.scenes = (j["scenes"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count > 10 }
        guard !t.scenes.isEmpty else { throw MVError("The director's plan had no scenes. Try again.") }
        return (t, cost)
    }

    /// Finds a reference photo for the plan and shapes it to widescreen (the middle is kept). Returns its file name in `dir`, or nil.
    public static func findReference(_ words: String, into dir: URL) async -> String? {
        for h in await SubjectPicture.search(words).prefix(4) {
            guard let f = try? await SubjectPicture.download(h, to: FileManager.default.temporaryDirectory) else { continue }
            let name = "reference-\(Int(Date().timeIntervalSince1970)).jpg"
            let a = PictureFit.aspect(f) ?? PictureFit.target
            if (try? PictureFit.crop(f, rect: PictureFit.cropRect(aspect: a), output: dir.appendingPathComponent(name))) != nil { return name }
        }
        return nil
    }
}
