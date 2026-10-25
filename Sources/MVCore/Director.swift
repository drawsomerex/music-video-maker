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
    public var usesReference: [Int: Bool] = [:]   // section index → whether that picture shows the reference's place, building or subject
    public var mood: Brightness = .bright         // the director's suggestion; pictures stay bright unless you approve otherwise
    public var cast = ""                          // the recurring people, props and places, with the traits that must never change
    public var weather: LoopWeather = .any        // the director's suggestions for the pictures (any = each picture's idea decides)
    public var timeOfDay: LoopTimeOfDay = .any
    public var shot: ShotType = .any
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
    public var mood: Brightness = .bright
    public var weather: LoopWeather = .any
    public var timeOfDay: LoopTimeOfDay = .any
    public var shot: ShotType = .any
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
    - Bright and luminous by default: even night or storm scenes stay clearly visible. Suggest a darker mood only if the song truly calls for it.
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
    /// What the director is told about the song: the description first (the main basis), then the lyrics (their story).
    static func songBrief(description: String, notes: String, lyrics: String) -> String {
        var b = ""
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines), n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { b += "THE AUTHOR'S OWN WORDS ABOUT THE SONG (they outrank everything else): \(n)\n" }
        if !d.isEmpty { b += "THE SONG DESCRIPTION (base your decisions mainly on this): \(d)\n" }
        let l = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        b += l.isEmpty ? "The song has no words (instrumental)." : "THE LYRICS (use the story they tell as the second basis; never illustrate them word by word):\n\(String(l.prefix(6000)))"
        return b
    }
    static var conditionsAsk: String {
        "Suggest the weather for the pictures, one of: " + LoopWeather.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            + " (\"any\" = each picture decides, usually best), the time of day, one of: " + LoopTimeOfDay.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            + ", and one type of shot for every picture, one of: " + ShotType.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ") + " (\"any\" = varied shots, usually best for a music video)."
    }
    /// Listens (Parakeet) to the songs of a looping video that haven't been heard yet (up to six), so the director knows their words.
    public static func listen(_ p: inout LoopProject, dir: URL, config: Config = .load()) async {
        for k in p.tracks.indices.prefix(6) where p.tracks[k].lyrics == nil {
            p.tracks[k].lyrics = (try? await LiveSongRecorder.transcribeAudioFile(url: dir.appendingPathComponent(p.tracks[k].file), config: config)) ?? ""
        }
    }
    static func focus(_ s: Any?) -> NextFocus { NextFocus(rawValue: (s as? String ?? "").lowercased()) ?? .place }

    /// Plans a music video: the treatment and one picture idea for every part of the song.
    /// The director always reads the title, the song description and the lyrics: the decisions rest mainly on the description, then on the
    /// story the lyrics tell. A song without lyrics yet is listened to with Parakeet first (`work` = its folder).
    public static func musicVideo(_ plan: Plan, work: URL? = nil, config: Config = .load()) async throws -> (Treatment, Double) {
        func time(_ x: Double) -> String { String(format: "%d:%02d", Int(x) / 60, Int(x) % 60) }
        var lyrics = plan.lines.map(\.text).joined(separator: "\n")
        if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let w = work {
            lyrics = (try? await LiveSongRecorder.transcribeAudioFile(url: Pipeline.audioURL(plan, work: w), config: config)) ?? ""
        }
        var parts = ["-1 | title card (opening) | an establishing picture for the whole video"]
        for (i, s) in plan.sections.enumerated() {
            var line = "\(i) | \(time(s.start))–\(time(s.end)) | \(PromptWriter.context(for: s, lines: plan.lines))"
            if let r = s.repeatOf { line += " | (same words as \(r): a visual rhyme of it)" }
            parts.append(line)
        }
        let prompt = """
        You are the director of a music video for the song "\(plan.title)".
        \(songBrief(description: plan.description, notes: plan.songNotes, lyrics: lyrics))\(plan.setting.isEmpty ? "" : "\nSetting and theme fixed by the author: \(plan.setting).")
        Each part of the song below gets ONE still picture (it is slowly panned and zoomed while that part plays).

        \(craft)

        Also decide whether the video is built around ONE real recurring place, building or subject that a photo would help to get right (for example a real landmark, a type of animal, a ship); if so give a short web image search for it (2–5 words) and say what to keep from it: "place", "building" or "subject". Otherwise "reference": null.

        The parts (index | time | words):
        \(parts.joined(separator: "\n"))

        Also list the CAST: the recurring people, animals, props and places, each with the traits that must never change between pictures (age, hair, face, clothing and its colours; a prop's shape and colour; a place's landmarks), in one or two sentences. Empty if nothing recurs.
        Suggest the mood: "bright" (the default), "natural", "moody" or "dark".
        \(conditionsAsk)

        Reply with ONLY this JSON: {"logline":"...","concept":"...","palette":"...","motifs":["...","..."],"style":"...","mood":"bright","weather":"any","time":"any","shot":"any","cast":"...","reference":"search words" or null,"keep":"place|building|subject","pictures":[{"i":-1,"idea":"...","ref":true},{"i":0,"idea":"...","ref":false}, ...]} with one picture for EVERY index above; "ref" says whether that picture shows the reference's place, building or subject (false for pictures of something else, so they are not forced to look like the photo).
        """
        let (j, cost) = try await ask(prompt, config: config)
        var t = Treatment()
        t.logline = j["logline"] as? String ?? ""; t.concept = j["concept"] as? String ?? ""; t.palette = (j["palette"] as? String) ?? (j["palette"] as? [String])?.joined(separator: ", ") ?? ""
        t.motifs = j["motifs"] as? [String] ?? []; t.style = StylePreset.withoutLighting(j["style"] as? String ?? "")
        t.reference = (j["reference"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.lowercased() == "null" ? nil : $0 }
        t.keep = focus(j["keep"])
        t.mood = Brightness(rawValue: (j["mood"] as? String ?? "").lowercased()) ?? .bright
        t.cast = (j["cast"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        t.weather = LoopWeather(rawValue: j["weather"] as? String ?? "") ?? .any; t.timeOfDay = LoopTimeOfDay(rawValue: j["time"] as? String ?? "") ?? .any
        t.shot = ShotType(rawValue: j["shot"] as? String ?? "") ?? .any
        for p in j["pictures"] as? [[String: Any]] ?? [] {
            guard let idea = (p["idea"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !idea.isEmpty else { continue }
            let i = (p["i"] as? Int) ?? Int(p["i"] as? String ?? "") ?? -99
            if i == -1 || plan.sections.indices.contains(i) { t.pictures[i] = idea; if let r = p["ref"] as? Bool { t.usesReference[i] = r } }
        }
        guard t.pictures.count >= max(1, (plan.sections.count + 1) / 2) else { throw MVError("The director's plan missed most of the pictures. Try again.") }
        return (t, cost)
    }

    /// Plans a looping video: one world in a few scenes that loop well.
    public static func looping(_ p: LoopProject, scenes: Int, config: Config = .load()) async throws -> (LoopTreatment, Double) {
        let songs = p.tracks.map(\.title).filter { !$0.isEmpty }.prefix(30).joined(separator: "; ")
        let words = p.tracks.prefix(6).compactMap { t -> String? in
            guard let l = t.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines), l.count > 20 else { return nil }
            return "\"\(t.title)\":\n\(l.prefix(1500))"
        }.joined(separator: "\n\n")
        let prompt = """
        You are the director of a long, calm looping music video (study and relaxation music) called "\(p.title)".\(songs.isEmpty ? "" : " The songs: \(songs).")
        \(songBrief(description: p.about, notes: "", lyrics: words))
        The video is \(scenes) scene\(scenes == 1 ? "" : "s"); each is ONE still picture brought to life as a 15-second clip that loops seamlessly, with a completely still camera.

        Work like an acclaimed director: ONE world and one clear concept (a logline of 15–30 words); ONE medium and technique with a restricted palette, never mentioning lighting, time of day or weather; the scenes are the SAME place (or building, or subject) at different moments, each with one clear change (another time of day, weather, season, or a calm new element), so together they feel like a journey through one world.
        Every scene must loop beautifully: gentle motion that repeats in place (water, rain, snow, mist, fire, smoke, flickering light, swaying plants); nothing walking or travelling across the picture; no people in the foreground; no text. Each scene is one vivid sentence of 20–40 words: what we see, where, the moment, the light and weather, and what moves.
        Also decide whether ONE real recurring place, building or subject would be helped by a photo (a real landmark, a kind of animal); if so give a short web image search for it (2–5 words) and what to keep from it: "place", "building" or "subject". Otherwise "reference": null.

        Bright and luminous by default; suggest the mood: "bright" (the default), "natural", "moody" or "dark".
        \(conditionsAsk)
        Reply with ONLY this JSON: {"logline":"...","style":"...","mood":"bright","weather":"any","time":"any","shot":"any","reference":"search words" or null,"keep":"place|building|subject","scenes":["first scene","next scene", ...]} with exactly \(scenes) scene\(scenes == 1 ? "" : "s").
        """
        let (j, cost) = try await ask(prompt, config: config)
        var t = LoopTreatment()
        t.logline = j["logline"] as? String ?? ""; t.style = StylePreset.withoutLighting(j["style"] as? String ?? "")
        t.reference = (j["reference"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.lowercased() == "null" ? nil : $0 }
        t.keep = focus(j["keep"])
        t.mood = Brightness(rawValue: (j["mood"] as? String ?? "").lowercased()) ?? .bright
        t.weather = LoopWeather(rawValue: j["weather"] as? String ?? "") ?? .any; t.timeOfDay = LoopTimeOfDay(rawValue: j["time"] as? String ?? "") ?? .any
        t.shot = ShotType(rawValue: j["shot"] as? String ?? "") ?? .any
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
