// The workflow: plan (transcribe, sync, split, write prompts), attach pictures, render videos and Shorts, project folders.
import Foundation
import ImageIO
import AVFoundation

public enum Pipeline {
    public static func workDir(output: URL, title: String) -> URL {
        let safe = title.replacingOccurrences(of: "/", with: "-")
        let d = output.appendingPathComponent("\(safe) – project")
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("full"), withIntermediateDirectories: true)
        return d
    }

    public static let projectFileName = "project.mvproj"
    /// The save file. Older projects used plan.json; reading falls back to it.
    /// Adds up what picture generation has cost across every song saved under `root` (each project keeps its own running total).
    public static func totalSpent(in root: URL) -> (usd: Double, pictures: Int, songs: Int) {
        var usd = 0.0, pics = 0, songs = 0
        let fm = FileManager.default
        for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for sub in ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []) + [dir] {
                let f = sub.appendingPathComponent(projectFileName)
                guard let d = try? Data(contentsOf: f), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                let c = (o["totalGenerationCostUSD"] as? Double) ?? 0
                usd += c; pics += (o["imagesGeneratedCount"] as? Int) ?? 0; if c > 0 { songs += 1 }
            }
        }
        return (usd, pics, songs)
    }

    public static func planURL(_ work: URL) -> URL { work.appendingPathComponent(projectFileName) }
    public static func transcriptURL(_ work: URL) -> URL { work.appendingPathComponent("transcript.txt") }
    public static func syncedLyricsURL(_ work: URL) -> URL { work.appendingPathComponent("lyrics_synced.txt") }

    /// The project's own copy of the song (so the folder is self-contained), falling back to the original path.
    public static func audioURL(_ plan: Plan, work: URL) -> URL {
        let own = work.appendingPathComponent(plan.audioFile)
        if !plan.audioFile.isEmpty, FileManager.default.fileExists(atPath: own.path) { return own }
        return URL(fileURLWithPath: plan.audioPath)
    }

    /// True if `folder` is a project (has a save file).
    public static func isProject(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(projectFileName).path) || FileManager.default.fileExists(atPath: folder.appendingPathComponent("plan.json").path)
    }
    public static func promptsURL(_ work: URL) -> URL { work.appendingPathComponent("prompts.md") }

    public static func loadPlan(_ work: URL) throws -> Plan {
        let legacy = work.appendingPathComponent("plan.json")
        let url = FileManager.default.fileExists(atPath: planURL(work).path) ? planURL(work) : legacy
        var plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: url))
        // Make older projects self-contained: copy the song in.
        if plan.audioFile.isEmpty, FileManager.default.fileExists(atPath: plan.audioPath) {
            let src = URL(fileURLWithPath: plan.audioPath); let name = "audio." + (src.pathExtension.isEmpty ? "mp3" : src.pathExtension.lowercased())
            if (try? FileManager.default.copyItem(at: src, to: work.appendingPathComponent(name))) != nil || FileManager.default.fileExists(atPath: work.appendingPathComponent(name).path) { plan.audioFile = name }
        }
        return plan
    }
    public static func savePlan(_ plan: Plan, _ work: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(plan).write(to: planURL(work), options: .atomic)
        try? promptsMarkdown(plan).write(to: promptsURL(work), atomically: true, encoding: .utf8)
        try? syncedLyricsText(plan).write(to: syncedLyricsURL(work), atomically: true, encoding: .utf8)
    }

    // MARK: Step 1 — plan

    /// Transcribes (Parakeet via oMLX), syncs your lyrics, splits the song into image sections and writes a prompt for each.
    public static func plan(audioPath: String, title: String, subject: String, lyrics: String, work: URL, imageInterval: Double = 15,
                            preferredStyle: String = "", setting: String = "", config: Config = .load(), progress: ProgressHandler? = nil) async throws -> Plan {
        let duration = try await audioDuration(path: audioPath)
        guard duration > 5 else { throw MVError("Couldn't read the audio file (or it's shorter than 5 seconds).") }

        // Keep a copy of the song with the project so it can be reopened and edited anywhere.
        let srcURL = URL(fileURLWithPath: audioPath)
        let audioName = "audio." + (srcURL.pathExtension.isEmpty ? "mp3" : srcURL.pathExtension.lowercased())
        let ownAudio = work.appendingPathComponent(audioName)
        if !FileManager.default.fileExists(atPath: ownAudio.path) { try? FileManager.default.copyItem(at: srcURL, to: ownAudio) }

        let omlx = OMLX(config: config)
        progress?("Connecting to AI engine", 0)
        try await omlx.ensureReady()
        try Task.checkCancellation()
        let parsed = LyricAligner.parse(lyrics)
        guard !parsed.lines.isEmpty else { throw MVError("Paste the lyrics first.") }

        // 1) Exact word timestamps from the user's Parakeet model, run on oMLX's own runtime (cached per audio file).
        //    2) If that runtime isn't available, fall back to timing inferred from short overlapping HTTP windows (less precise).
        let attrs = try? FileManager.default.attributesOfItem(atPath: audioPath)
        let stamp = "\(attrs?[.size] ?? 0)|\(attrs?[.modificationDate] ?? Date())"
        var aligned: (lines: [LyricLine], coverage: Double)
        var timing = "exact"
        let wordsCache = work.appendingPathComponent("transcript_words.json")
        struct WordCache: Codable { var key: String; var words: [TimedWord] }
        var heard: [TimedWord]? = nil
        if let c = try? JSONDecoder().decode(WordCache.self, from: Data(contentsOf: wordsCache)), c.key == "\(omlx.stt)|\(stamp)" { heard = c.words; progress?("Using saved word timings", 0.5) }
        else {
            progress?("Listening with Parakeet (exact word timing)", 0.1)
            if let w = try? await OMLXRuntime.wordTimes(audioPath: audioPath, modelID: omlx.stt), w.count > 5 {
                heard = w; try? JSONEncoder().encode(WordCache(key: "\(omlx.stt)|\(stamp)", words: w)).write(to: wordsCache)
            }
        }
        try Task.checkCancellation()
        if let words = heard {
            progress?("Syncing lyrics", 0.55)
            aligned = LyricAligner.align(lines: parsed.lines, words: words, songDuration: duration)
            let readable = words.map(\.text).joined(separator: " ").replacingOccurrences(of: #"([.!?])\s+(?=[A-Z])"#, with: "$1\n", options: .regularExpression)
            try? ("\(title) — transcript (speech recognition, unedited)\n\n" + readable + "\n").write(to: transcriptURL(work), atomically: true, encoding: .utf8)
        } else {
            timing = "windows"
            let cacheURL = work.appendingPathComponent("timing_windows.json")
            struct Cache: Codable { var key: String; var windows: [TranscriptWindow] }
            var windows: [TranscriptWindow]
            let key = "\(omlx.stt)|\(Transcriber.windowLength)|\(Transcriber.hop)|\(stamp)"
            if let c = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL)), c.key == key { windows = c.windows }
            else {
                windows = try await Transcriber.transcribe(audioPath: audioPath, omlx: omlx) { progress?($0, $1) }
                try? JSONEncoder().encode(Cache(key: key, windows: windows)).write(to: cacheURL)
            }
            if !FileManager.default.fileExists(atPath: transcriptURL(work).path), let text = try? await Transcriber.fullText(audioPath: audioPath, omlx: omlx), !text.isEmpty {
                let readable = text.replacingOccurrences(of: #"([.!?])\s+(?=[A-Z])"#, with: "$1\n", options: .regularExpression)
                try? ("\(title) — transcript (speech recognition, unedited)\n\n" + readable + "\n").write(to: transcriptURL(work), atomically: true, encoding: .utf8)
            }
            progress?("Syncing lyrics", 0.58)
            aligned = LyricAligner.align(lines: parsed.lines, windows: windows, windowLength: Transcriber.windowLength, songDuration: duration)
        }
        try Task.checkCancellation()
        let lines = aligned.lines

        // Pre-compute and cache waveform peaks and beat timestamps while the 16kHz PCM is already in memory.
        let savedAudioPath = FileManager.default.fileExists(atPath: ownAudio.path) ? ownAudio.path : audioPath
        _ = try? await Transcriber.waveform(audioPath: savedAudioPath, work: work)
        _ = await BeatDetector.beats(audioPath: savedAudioPath, start: 0, end: duration, work: work)

        // Sections
        // Your own parts (`---`) win; otherwise your verse marks (blank lines, [Chorus] tags) cut the lyrics, unless that would make absurdly short pictures.
        let explicitParts = !parsed.partBreaks.isEmpty
        let verseOK = parsed.stanzaBreaks.count + 1 <= max(2, Int(duration / 6))
        let cuts = explicitParts ? parsed.partBreaks : (verseOK ? parsed.stanzaBreaks : [])
        var sections = Planner.plan(lines: lines, stanzaBreaks: parsed.stanzaBreaks, partBreaks: cuts, songDuration: duration, opts: .init(imageInterval: imageInterval))
        let first = lines.first?.start ?? duration
        // Title card plays over the song's instrumental intro when there's room; otherwise a short silent pre-roll.
        let introDur = first >= 3.3 ? min(6.0, first - 0.6) : 4.5
        let offset = first >= 3.3 ? 0.0 : introDur
        var intro = PhotoSection(id: -1, start: 0, end: introDur, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 42)

        // Repeated lyrics (choruses) → point at the first occurrence so the same picture can be reused.
        func words(_ s: PhotoSection) -> Set<String> { Set(s.lineIDs.flatMap { lines[$0].text.lowercased().split { !$0.isLetter }.map(String.init) }) }
        for i in sections.indices where !sections[i].lineIDs.isEmpty {
            let a = words(sections[i])
            for j in 0..<i where sections[j].repeatOf == nil && !sections[j].lineIDs.isEmpty {
                let b = words(sections[j])
                if Double(a.intersection(b).count) / Double(max(1, a.union(b).count)) >= 0.85 { sections[i].repeatOf = j; break }
            }
        }

        // Description of the song (from the lyrics), then prompts driven by it
        let writer = PromptWriter(omlx: omlx)
        progress?("Local AI is reading the lyrics", 0.62)
        let settingNote = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = try await writer.describe(title: title, lyrics: lines.map(\.text), hint: ([subject, settingNote.isEmpty ? "" : "The video is set in: \(settingNote)"].filter { !$0.isEmpty }).joined(separator: ". "))
        try Task.checkCancellation()
        progress?("Local AI is writing the image prompts", 0.75)
        let written = try await writer.write(sections: [intro] + sections, lines: lines, title: title, subject: description, preferredStyle: preferredStyle, setting: settingNote) { phase, f in
            progress?(phase, 0.75 + 0.22 * f)
        }
        try Task.checkCancellation()
        intro.prompt = written.prompts[-1] ?? "A wide establishing scene that captures the setting of \"\(title)\"."
        for i in sections.indices { sections[i].prompt = written.prompts[sections[i].id] ?? "A scene illustrating: " + sections[i].lineIDs.map { lines[$0].text }.joined(separator: " / ") }

        var plan = Plan(title: title, subject: subject, audioPath: audioPath,
                        audioFile: FileManager.default.fileExists(atPath: ownAudio.path) ? audioName : "", songDuration: duration, lines: lines, intro: intro, sections: sections, description: description, style: written.style, introDuration: introDur, audioOffset: offset,
                        alignmentCoverage: aligned.coverage)
        plan.timing = timing
        plan.partStarts = cuts.sorted()
        plan.partsFromVerses = !explicitParts && !cuts.isEmpty
        plan.setting = settingNote
        plan.shorts = autoShorts(plan: plan)
        try savePlan(plan, work)
        progress?("Done", 1)
        return plan
    }

    /// Plain-text lyrics with the time each line is sung — easy to read, edit or paste elsewhere.
    public static func syncedLyricsText(_ plan: Plan) -> String {
        func ts(_ x: Double) -> String { String(format: "%d:%04.1f", Int(x) / 60, x - Double(Int(x) / 60 * 60)) }
        return "\(plan.title)\n\n" + plan.lines.map { "[\(ts($0.start))] \($0.text)" }.joined(separator: "\n") + "\n"
    }

    /// Re-times an existing project with exact word timestamps, keeping its pictures, prompts and Shorts.
    /// Section edges move to the midpoint of the gaps between the re-timed lines.
    public static func resync(plan: inout Plan, work: URL, config: Config = .load(), progress: ProgressHandler? = nil) async throws -> Double {
        let omlx = OMLX(config: config)
        progress?("Listening with Parakeet (exact word timing)", 0.1)
        let audio = audioURL(plan, work: work).path
        let words = try await OMLXRuntime.wordTimes(audioPath: audio, modelID: omlx.stt)
        guard words.count > 5 else { throw MVError("The speech model heard almost nothing.") }
        progress?("Syncing lyrics", 0.7)
        let res = LyricAligner.align(lines: plan.lines.map(\.text), words: words, songDuration: plan.songDuration)
        plan.lines = res.lines; plan.alignmentCoverage = res.coverage; plan.timing = "exact"
        plan.sections = Planner.rebound(plan.sections, lines: plan.lines, duration: plan.songDuration)
        try? JSONEncoder().encode(WordCacheFile(key: "", words: words)).write(to: work.appendingPathComponent("transcript_words.json"))
        try savePlan(plan, work)
        progress?("Done", 1)
        return res.coverage
    }
    struct WordCacheFile: Codable { var key: String; var words: [TimedWord] }

    /// Shifts a single lyric line's timing by `delta` seconds (clamped safely against song edges and neighbouring lines) and updates section bounds.
    public static func shiftLine(plan: inout Plan, lineIndex: Int, delta: Double, work: URL) {
        guard plan.lines.indices.contains(lineIndex), !plan.lines[lineIndex].words.isEmpty else { return }
        let line = plan.lines[lineIndex]
        let dur = max(0.15, line.end - line.start)
        let minStart = lineIndex > 0 ? max(0, plan.lines[lineIndex - 1].start + 0.15) : 0
        let maxStart = lineIndex + 1 < plan.lines.count ? max(minStart, plan.lines[lineIndex + 1].end - dur - 0.15) : max(0, plan.songDuration - dur)
        let newStart = min(maxStart, max(minStart, line.start + delta))
        let actualDelta = newStart - line.start
        guard abs(actualDelta) > 0.001 else { return }
        for k in plan.lines[lineIndex].words.indices {
            plan.lines[lineIndex].words[k].start = max(0, min(plan.songDuration, plan.lines[lineIndex].words[k].start + actualDelta))
            plan.lines[lineIndex].words[k].end = max(plan.lines[lineIndex].words[k].start + 0.08, min(plan.songDuration, plan.lines[lineIndex].words[k].end + actualDelta))
        }
        // Trim any slight overlap with the previous or next line
        if lineIndex > 0, !plan.lines[lineIndex - 1].words.isEmpty {
            let cap = max(plan.lines[lineIndex - 1].start + 0.12, newStart - 0.02)
            for k in plan.lines[lineIndex - 1].words.indices {
                if plan.lines[lineIndex - 1].words[k].end > cap { plan.lines[lineIndex - 1].words[k].end = cap }
                if plan.lines[lineIndex - 1].words[k].start > cap - 0.05 { plan.lines[lineIndex - 1].words[k].start = max(0, cap - 0.05) }
            }
        }
        if lineIndex + 1 < plan.lines.count, !plan.lines[lineIndex + 1].words.isEmpty {
            let floor = min(plan.lines[lineIndex + 1].end - 0.12, plan.lines[lineIndex].end + 0.02)
            for k in plan.lines[lineIndex + 1].words.indices {
                if plan.lines[lineIndex + 1].words[k].start < floor { plan.lines[lineIndex + 1].words[k].start = floor }
                if plan.lines[lineIndex + 1].words[k].end < plan.lines[lineIndex + 1].words[k].start + 0.08 {
                    plan.lines[lineIndex + 1].words[k].end = plan.lines[lineIndex + 1].words[k].start + 0.08
                }
            }
        }
        plan.sections = Planner.rebound(plan.sections, lines: plan.lines, duration: plan.songDuration)
        try? savePlan(plan, work)
    }

    // MARK: Prompts

    /// What to paste into the image generator for one section (section index −1 = title card).
    public static func fullPrompt(_ plan: Plan, section index: Int) -> String {
        let s = index < 0 ? plan.intro : plan.sections[index]
        let style = plan.style.isEmpty ? "" : " Style: \(plan.style)"
        let setting = plan.setting.trimmingCharacters(in: .whitespacesAndNewlines)
        let stated = setting.isEmpty || s.prompt.lowercased().contains(setting.lowercased())
        return "\(stated ? "" : "Setting: \(setting). ")\(s.prompt)\(style) Bright, vivid, evenly lit with cheerful colours (never dark or gloomy). Widescreen 16:9 landscape composition, no text, no lettering, no watermark."
    }

    public static func promptsMarkdown(_ plan: Plan) -> String {
        func t(_ x: Double) -> String { String(format: "%d:%02d", Int(x) / 60, Int(x) % 60) }
        var md = "# \(plan.title) — image prompts\n\n"
        if !plan.setting.isEmpty { md += "**Setting and theme (in every prompt):** \(plan.setting)\n\n" }
        if !plan.description.isEmpty { md += "**Song description (written from the lyrics):** \(plan.description)\n\n" }
        md += "**Shared style (used in every prompt):** \(plan.style)\n\n"
        md += "Generate each picture at 16:9 (1920×1080 or larger is best), then load it into the matching slot. File names that start with the number (`00.png`, `01.png`, …) are matched automatically.\n\n---\n\n"
        for idx in -1..<plan.sections.count {
            let s = idx < 0 ? plan.intro : plan.sections[idx]
            let name = idx < 0 ? "00 · Title card" : String(format: "%02d", idx + 1) + " · " + (s.lineIDs.isEmpty ? "Instrumental (music only)" : "Section")
            let when = idx < 0 ? "opening" : "\(t(s.start + plan.audioOffset))–\(t(s.end + plan.audioOffset)) (\(Int(s.duration)) s)"
            md += "## \(name) — \(when)\n"
            if !s.lineIDs.isEmpty { md += "\n> " + s.lineIDs.map { plan.lines[$0].text }.joined(separator: "\n> ") + "\n" }
            if let r = s.repeatOf { md += "\n*Same lyrics as section \(String(format: "%02d", r + 1)) — you can reuse that picture, or make a fresh take with the prompt below.*\n" }
            md += "\n**Prompt:**\n\n\(fullPrompt(plan, section: idx))\n\n"
        }
        return md
    }

    /// Rewrites the song description from the lyrics (optionally steered by a hint) and, if asked, all prompts from it.
    public static func redescribe(plan: inout Plan, hint: String = "", config: Config = .load(), progress: ProgressHandler? = nil) async throws {
        progress?("Connecting to AI engine", 0.05)
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        progress?("Reading lyrics & rewriting song description", 0.25)
        let withSetting = ([hint, plan.setting.isEmpty ? "" : "The video is set in: \(plan.setting)"].filter { !$0.isEmpty }).joined(separator: ". ")
        plan.description = try await PromptWriter(omlx: omlx).describe(title: plan.title, lyrics: plan.lines.map(\.text), hint: withSetting)
        progress?("Done", 1.0)
    }

    /// Regenerates the style and every prompt from the (possibly edited) song description. Pictures already loaded are kept.
    public static func regeneratePrompts(plan: inout Plan, keepStyle: Bool = false, config: Config = .load(), progress: ProgressHandler? = nil) async throws {
        progress?("Connecting to AI engine", 0.05)
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        progress?("Writing image prompts for \(plan.sections.count + 1) sections", 0.20)
        let w = try await PromptWriter(omlx: omlx).write(sections: [plan.intro] + plan.sections, lines: plan.lines, title: plan.title, subject: plan.description, preferredStyle: keepStyle ? plan.style : "", setting: plan.setting) { p, f in
            progress?(p, 0.25 + 0.70 * f)
        }
        if !keepStyle || plan.style.isEmpty { plan.style = w.style }
        if let p = w.prompts[-1] { plan.intro.prompt = p }
        for i in plan.sections.indices { if let p = w.prompts[plan.sections[i].id] { plan.sections[i].prompt = p } }
        progress?("Done", 1.0)
    }

    /// True when the song starts with music that has no picture of its own (older projects): the first words begin ≥ 3 s after the title card ends.
    public static func needsInstrumentalIntro(_ plan: Plan) -> Bool {
        guard plan.audioOffset == 0, let first = plan.lines.first?.start, first >= 3.3, let sec = plan.sections.first, !sec.lineIDs.isEmpty else { return false }
        return first - plan.introDuration >= 3.0
    }

    /// Adds a section (and its own unique prompt) for the music before the first words. Existing pictures stay with their sections.
    public static func addInstrumentalIntro(plan: inout Plan, config: Config = .load(), progress: ProgressHandler? = nil) async throws {
        guard needsInstrumentalIntro(plan), let first = plan.lines.first?.start else { return }
        progress?("Connecting to AI engine", 0.1)
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        var intro = PhotoSection(id: 0, start: 0, end: first, lineIDs: [], queries: [], candidates: [], selected: -1, seed: 0xA11CE)
        plan.sections[0].start = first
        for i in plan.sections.indices { plan.sections[i].id += 1; if let r = plan.sections[i].repeatOf { plan.sections[i].repeatOf = r + 1 } }
        progress?("Writing a picture idea for the music before the words", 0.4)
        let others = [plan.intro.prompt] + plan.sections.map(\.prompt)
        intro.prompt = try await PromptWriter(omlx: omlx).rewriteDistinct(section: intro, lines: plan.lines, title: plan.title, subject: plan.description, style: plan.style, current: "", others: others, setting: plan.setting)
        plan.sections.insert(intro, at: 0)
        progress?("Done", 1.0)
    }

    public static func rewritePrompt(plan: inout Plan, section index: Int, config: Config = .load(), progress: ProgressHandler? = nil) async throws {
        progress?("Connecting to AI engine", 0.1)
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        let s = index < 0 ? plan.intro : plan.sections[index]
        progress?("Writing a fresh take for \(index < 0 ? "Title card" : "Section \(index + 1)")", 0.35)
        let others = ([plan.intro.prompt] + plan.sections.map(\.prompt)).filter { $0 != s.prompt }
        let p = try await PromptWriter(omlx: omlx).rewriteDistinct(section: s, lines: plan.lines, title: plan.title, subject: plan.description, style: plan.style, current: s.prompt, others: others, salt: index + 2, setting: plan.setting)
        if index < 0 { plan.intro.prompt = p } else { plan.sections[index].prompt = p }
        progress?("Done", 1.0)
    }

    // MARK: Step 2 — load your pictures

    public static let videoExtensions = ["mp4", "mov", "m4v"]

    /// Loads a video clip into a section. The clip is copied into the project; a still frame from it serves as the thumbnail and poster.
    /// While the section is on screen the clip plays (looping if it is shorter than the section); the song's own sound is kept, the clip's sound is not used.
    static func attachVideo(_ url: URL, section index: Int, plan: inout Plan, work: URL) throws -> String? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw MVError("“\(url.lastPathComponent)” isn't a video I can read. Try an MP4 or MOV file.") }
        let size = track.naturalSize.applying(track.preferredTransform)
        let w = Int(abs(size.width)), h = Int(abs(size.height))
        let secs = CMTimeGetSeconds(asset.duration)
        let n = index + 1, stamp = Int(Date().timeIntervalSince1970 * 1000)
        let vid = "full/section_\(n)_\(stamp).\(url.pathExtension.lowercased())", poster = "full/section_\(n)_\(stamp).jpg", thumb = "thumbs/section_\(n)_\(stamp).jpg"
        let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 1920, height: 1920)
        let at = CMTime(seconds: min(0.5, max(0, secs / 2)), preferredTimescale: 600)
        guard let frame = try? gen.copyCGImage(at: at, actualTime: nil) else { throw MVError("Couldn't read a picture from “\(url.lastPathComponent)”.") }
        func writeJPEG(_ img: CGImage, _ rel: String, _ q: Double) {
            if let d = CGImageDestinationCreateWithURL(work.appendingPathComponent(rel) as CFURL, "public.jpeg" as CFString, 1, nil) {
                CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary); CGImageDestinationFinalize(d) }
        }
        try? FileManager.default.createDirectory(at: work.appendingPathComponent("full"), withIntermediateDirectories: true)
        let dst = work.appendingPathComponent(vid); try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: url, to: dst)
        writeJPEG(frame, poster, 0.92); writeJPEG(frame, thumb, 0.8)
        var c = ImageCandidate(id: "video:\(n)", provider: "Video", thumbURL: "", fullURL: "", pageURL: "", width: w, height: h, credit: url.lastPathComponent, query: "", rank: 0)
        c.thumbFile = thumb; c.fullFile = poster; c.videoFile = vid; c.videoLength = secs
        if index < 0 { plan.intro.candidates = [c]; plan.intro.selected = 0 } else { plan.sections[index].candidates = [c]; plan.sections[index].selected = 0 }
        cleanupUnreferencedImages(plan: plan, work: work)
        try? savePlan(plan, work)
        var notes: [String] = []
        if w > 0, h > 0, Double(w) / Double(h) < 1.5 { notes.append("isn't widescreen (\(w)×\(h)); the video will crop it to 16:9") }
        if secs > 0, let s = (index < 0 ? plan.intro : plan.sections[index]) as PhotoSection?, secs + 0.5 < s.duration, index >= 0 { notes.append("is only \(Int(secs)) s long, so it will repeat to fill the \(Int(s.duration)) s part") }
        return notes.isEmpty ? nil : "“\(url.lastPathComponent)” " + notes.joined(separator: " and ") + "."
    }

    /// Deletes any orphaned `section_*` image/thumbnail files in `full/` and `thumbs/` no longer referenced by any section in `plan`.
    public static func cleanupUnreferencedImages(plan: Plan, work: URL) {
        let allSecs = [plan.intro] + plan.sections
        let usedFull = Set(allSecs.flatMap { [$0.selectedCandidate?.fullFile, $0.selectedCandidate?.videoFile].compactMap { $0 } })
        let usedThumb = Set(allSecs.compactMap { $0.selectedCandidate?.thumbFile })
        let fm = FileManager.default
        for (sub, used) in [("full", usedFull), ("thumbs", usedThumb)] {
            let dir = work.appendingPathComponent(sub)
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.lastPathComponent.hasPrefix("section_") {
                let rel = "\(sub)/\(f.lastPathComponent)"
                if !used.contains(rel) { try? fm.removeItem(at: f) }
            }
        }
    }

    /// Loads a picture into a section (−1 = title card). Copies it into the work folder, makes a thumbnail and finds its focal point for the Ken Burns move.
    @discardableResult
    public static func attach(imageAt url: URL, section index: Int, plan: inout Plan, work: URL) throws -> String? {
        if videoExtensions.contains(url.pathExtension.lowercased()) { return try attachVideo(url, section: index, plan: &plan, work: work) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { throw MVError("“\(url.lastPathComponent)” isn't an image I can read.") }
        let n = index + 1
        let ext = url.pathExtension.lowercased().isEmpty ? "png" : url.pathExtension.lowercased()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let full = "full/section_\(n)_\(stamp).\(ext)", thumb = "thumbs/section_\(n)_\(stamp).jpg"
        let dst = work.appendingPathComponent(full)
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: url, to: dst)
        guard let t = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(work.appendingPathComponent(thumb) as CFURL, "public.jpeg" as CFString, 1, nil) else { throw MVError("Couldn't make a thumbnail of “\(url.lastPathComponent)”.") }
        CGImageDestinationAddImage(dest, t, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary); CGImageDestinationFinalize(dest)
        var c = ImageCandidate(id: "manual:\(n)", provider: "Manual", thumbURL: "", fullURL: "", pageURL: "", width: w, height: h, credit: url.lastPathComponent, query: "", rank: 0)
        c.thumbFile = thumb; c.fullFile = full
        if let a = ImageScorer.analyze(fileURL: work.appendingPathComponent(thumb)) { c.focusX = Double(a.focus.x); c.focusY = Double(a.focus.y) }
        if index < 0 { plan.intro.candidates = [c]; plan.intro.selected = 0 } else { plan.sections[index].candidates = [c]; plan.sections[index].selected = 0 }
        cleanupUnreferencedImages(plan: plan, work: work)
        try? savePlan(plan, work)
        let aspect = Double(w) / Double(h)
        if aspect < 1.5 { return "“\(url.lastPathComponent)” isn't widescreen (\(w)×\(h)); the video will crop it to 16:9." }
        if w < 1200 { return "“\(url.lastPathComponent)” is only \(w) px wide; it may look soft at 1080p." }
        return nil
    }

    public static func removeImage(section index: Int, plan: inout Plan, work: URL) {
        if index < 0 { plan.intro.candidates = []; plan.intro.selected = -1 } else { plan.sections[index].candidates = []; plan.sections[index].selected = -1 }
        cleanupUnreferencedImages(plan: plan, work: work)
        try? savePlan(plan, work)
    }

    /// Loads every image in a folder whose file name starts with a section number (00 / intro = title card, 01 = first section, …).
    public static func attachFolder(_ folder: URL, plan: inout Plan, work: URL, progress: ProgressHandler? = nil) -> (loaded: [Int], warnings: [String]) {
        let allFiles = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let files = allFiles.filter { ["png", "jpg", "jpeg", "webp", "heic", "tiff", "mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
        var loaded: [Int] = []; var warnings: [String] = []
        for (k, f) in files.enumerated() {
            progress?("Loading & analyzing \(f.lastPathComponent) (\(k + 1) of \(files.count))", Double(k) / Double(max(1, files.count)))
            let name = f.deletingPathExtension().lastPathComponent.lowercased()
            let digits = name.prefix(while: { $0.isNumber })
            let idx: Int
            if name.hasPrefix("intro") || name.hasPrefix("title") { idx = -1 }
            else if let n = Int(digits) { idx = n - 1 }                // "01" → first section, "00" → title card (−1)
            else { warnings.append("Skipped “\(f.lastPathComponent)” (name should start with a section number)."); continue }
            guard idx >= -1 && idx < plan.sections.count else { warnings.append("Skipped “\(f.lastPathComponent)” (no section \(idx + 1))."); continue }
            do { if let w = try attach(imageAt: f, section: idx, plan: &plan, work: work) { warnings.append(w) }; loaded.append(idx) }
            catch { warnings.append(error.localizedDescription) }
        }
        progress?("Done", 1.0)
        return (loaded, warnings)
    }

    /// Section indices (−1 = title card) that still have no picture.
    public static func missing(_ plan: Plan) -> [Int] {
        var m: [Int] = []
        if plan.intro.selectedCandidate?.fullFile == nil { m.append(-1) }
        for (i, s) in plan.sections.enumerated() where s.selectedCandidate?.fullFile == nil { m.append(i) }
        return m
    }

    /// Generates a 16:9 Medium image for `section` (−1 = title card) via OpenRouter (`openai/gpt-image-2.5-sunburst`),
    /// attaches it to the project, and records the cost in `plan.totalGenerationCostUSD` (saved to `project.mvproj`).
    @discardableResult
    public static func generateSectionImage(section index: Int, plan: inout Plan, work: URL, config: Config = .load()) async throws -> OpenRouter.GeneratedImage {
        let prompt = fullPrompt(plan, section: index)
        let est = plan.lastImageCostUSD ?? OpenRouter.defaultEstimatedCostPerImage
        let gen = try await OpenRouter.generateImage(prompt: prompt, apiKey: config.openRouterKey, fallbackCostEstimate: est)
        let tmpName = String(format: "%02d_sunburst.%@", index + 1, gen.fileExtension)
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("mv_\(UUID().uuidString)_\(tmpName)")
        defer { try? FileManager.default.removeItem(at: tmpURL) }
        try gen.data.write(to: tmpURL)
        _ = try attach(imageAt: tmpURL, section: index, plan: &plan, work: work)

        let label = "gpt-image-2.5-sunburst (\(OpenRouter.formatUSD(gen.costUSD)))"
        if index < 0 {
            if !plan.intro.candidates.isEmpty {
                plan.intro.candidates[0].provider = "OpenRouter"
                plan.intro.candidates[0].credit = label
            }
        } else if plan.sections.indices.contains(index), !plan.sections[index].candidates.isEmpty {
            plan.sections[index].candidates[0].provider = "OpenRouter"
            plan.sections[index].candidates[0].credit = label
        }

        plan.totalGenerationCostUSD += gen.costUSD
        plan.imagesGeneratedCount += 1
        plan.lastImageCostUSD = gen.costUSD
        try savePlan(plan, work)
        return gen
    }

    // MARK: YouTube Shorts

    /// Where finished videos go: the chosen output folder, or beside the project folder.
    public static func outputFolder(for work: URL, config: Config = .load()) -> URL {
        let d = config.outputFolder.isEmpty ? work.deletingLastPathComponent() : URL(fileURLWithPath: (config.outputFolder as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    public static func videoURL(plan: Plan, work: URL, config: Config = .load()) -> URL {
        outputFolder(for: work, config: config).appendingPathComponent("\(plan.title.replacingOccurrences(of: "/", with: "-")).mp4")
    }

    /// Shorts are saved in the same folder as the main video, named "<Song title> – <clip name>.mp4" so several songs can share one folder.
    public static func shortsFolder(_ work: URL, config: Config = .load()) -> URL { outputFolder(for: work, config: config) }

    public static func shortURL(plan: Plan, work: URL, name: String, config: Config = .load()) -> URL {
        func clean(_ t: String) -> String { t.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        let title = clean(plan.title), n = clean(name)
        let file = n.lowercased().hasPrefix(title.lowercased()) ? n : "\(title) – \(n)"
        return shortsFolder(work, config: config).appendingPathComponent("\(file).mp4")
    }

    /// Automatically creates 4–7 ~30-second Shorts that break cleanly at stanza / section boundaries and vocal pauses between lyric lines.
    /// Shorts built from the parts the user divided by hand: whole parts are grouped to about `target` seconds, and a Short never cuts through a part
    /// unless that single part is far longer than a Short (then it is split at the pauses nearest the target length).
    static func shortsFromParts(plan: Plan, target: Double = 30.0) -> [ShortClip] {
        let L = plan.lines
        let starts = ([0] + plan.partStarts.filter { $0 > 0 && $0 < L.count }).sorted()
        var parts: [(Int, Int)] = []
        for (k, a) in starts.enumerated() { parts.append((a, (k + 1 < starts.count ? starts[k + 1] : L.count) - 1)) }
        func span(_ a: Int, _ b: Int) -> Double { L[b].end - L[a].start }
        var groups: [(Int, Int)] = []
        var cur: (Int, Int)? = nil
        for p in parts {
            guard let c = cur else { cur = p; continue }
            let now = span(c.0, c.1), joined = span(c.0, p.1)
            if now < target * 0.7 || (abs(joined - target) < abs(now - target) && joined <= target * 1.5) { cur = (c.0, p.1) } else { groups.append(c); cur = p }
        }
        if let c = cur { groups.append(c) }
        // a part that is much longer than a Short: split at the pauses nearest the ideal piece length
        var pieces: [(Int, Int)] = []
        for g in groups {
            let dur = span(g.0, g.1)
            if dur <= target * 1.6 || g.1 == g.0 { pieces.append(g); continue }
            let k = Int((dur / target).rounded()), ideal = dur / Double(max(2, k))
            var a = g.0
            for m in 1..<max(2, k) {
                let want = L[g.0].start + ideal * Double(m)
                var best = a, bestScore = Double.infinity
                for j in a..<g.1 { let s = abs(L[j].end - want) - min(2.0, max(0, L[j + 1].start - L[j].end)) * 1.5; if s < bestScore { bestScore = s; best = j } }
                pieces.append((a, best)); a = best + 1
            }
            pieces.append((a, g.1))
        }
        return pieces.enumerated().map { (idx, r) in
            let snippet = String(L[r.0].text.prefix(26)).trimmingCharacters(in: .whitespacesAndNewlines)
            var c = clip(plan: plan, lines: r.0, to: r.1, name: "Short \(idx + 1) — \(snippet)", lead: 1.8, tail: 2.0)
            c.end = min(c.end, c.start + ShortClip.maxDuration)
            c.styleSeed = UInt64(101 + idx * 37); c.loop = true
            return c
        }
    }

    public static func autoShorts(plan: Plan, targetSeconds: Double = 30.0, minCount: Int = 4, maxCount: Int = 7) -> [ShortClip] {
        if !plan.partStarts.isEmpty, plan.lines.count >= 2 { return shortsFromParts(plan: plan, target: targetSeconds) }
        let L = plan.lines
        let total = max(1.0, plan.songDuration)
        let maxPossible = max(1, Int(total / 14.0))
        let rawCount = Int((total / targetSeconds).rounded())
        let count = min(maxCount, max(min(minCount, maxPossible), rawCount))

        guard L.count >= count else {
            let step = min(targetSeconds, total / Double(max(1, count)))
            return (0..<count).map { i in
                let s = Double(i) * (total - step) / Double(max(1, count - 1))
                let e = min(total, s + step)
                var c = ShortClip(name: "Short \(i + 1) — \(plan.title)", start: s, end: e)
                c.styleSeed = UInt64(101 + i * 37)
                return c
            }
        }

        let sectionEnds = Set(plan.sections.compactMap { $0.lineIDs.last })
        func boundaryBonus(_ i: Int) -> Double {
            guard i >= 0 && i + 1 < L.count else { return 0 }
            let gap = max(0, L[i + 1].start - L[i].end)
            let sec = sectionEnds.contains(i) ? 2.2 : 0.0
            let punct = L[i].text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".!?".contains($0) ? 0.6 : 0.0 } ?? 0.0
            return min(3.5, gap * 1.4) + sec + punct
        }

        // Partition lines 0..<L.count into `count` contiguous groups using DP to balance ~30s duration and natural stanza/breath breaks.
        let n = L.count
        let firstT = L.first?.start ?? 0
        let lastT = L.last?.end ?? total
        let idealSpan = min(targetSeconds, max(16.0, (lastT - firstT) / Double(count)))
        let negInf = -1e9
        var dp = Array(repeating: Array(repeating: negInf, count: n), count: count)
        var parent = Array(repeating: Array(repeating: 0, count: n), count: count)

        for i in 0..<n {
            let span = L[i].end - L[0].start
            let diff = (span - idealSpan) / 8.0
            dp[0][i] = -(diff * diff) * 1.5 + (i < n - 1 ? boundaryBonus(i) : 0)
        }
        if count > 1 {
            for k in 1..<count {
                for i in k..<n {
                    var bestScore = negInf
                    var bestPrev = k - 1
                    for prev in (k - 1)..<i {
                        let span = L[i].end - L[prev + 1].start
                        let diff = (span - idealSpan) / 8.0
                        let pen = -(diff * diff) * 1.5 - (span < 10.0 ? 6.0 : 0.0)
                        let bonus = (i < n - 1) ? boundaryBonus(i) : 0.0
                        let cand = dp[k - 1][prev] + pen + bonus
                        if cand > bestScore { bestScore = cand; bestPrev = prev }
                    }
                    dp[k][i] = bestScore
                    parent[k][i] = bestPrev
                }
            }
        }

        var ranges: [(Int, Int)] = []
        var curEnd = n - 1
        for k in stride(from: count - 1, through: 0, by: -1) {
            let startIdx = k == 0 ? 0 : parent[k][curEnd] + 1
            ranges.append((startIdx, curEnd))
            curEnd = parent[k][curEnd]
        }
        ranges.reverse()

        // Build each ~30s ShortClip from its line range, trimming to ~30s at the best internal stanza/pause break if a segment is longer than 34s.
        return ranges.enumerated().map { (idx, r) in
            var a = r.0, b = r.1
            if L[b].end - L[a].start > 34.0, b > a {
                var bestEnd = a
                var bestVal = negInf
                for j in a...b {
                    let dur = L[j].end - L[a].start
                    if dur > 35.0 && j > a { break }
                    let score = -abs(dur - targetSeconds) * 0.35 + boundaryBonus(j)
                    if score > bestVal { bestVal = score; bestEnd = j }
                }
                b = bestEnd
            }
            let snippet = String(L[a].text.prefix(26)).trimmingCharacters(in: .whitespacesAndNewlines)
            var c = clip(plan: plan, lines: a, to: b, name: "Short \(idx + 1) — \(snippet)", lead: 1.8, tail: 2.0)
            if c.duration > 35.0 {
                c.end = min(plan.songDuration, c.start + 32.0)
            }
            c.styleSeed = UInt64(101 + idx * 37)
            c.loop = true
            return c
        }
    }

    /// The whole song as Shorts: one clip if it fits in 3:00, otherwise the fewest equal-ish parts that each fit,
    /// with every cut placed in the biggest lyric gap near the ideal split point. Parts never loop; the last one fades out.
    public static func wholeSongClips(plan: Plan) -> [ShortClip] {
        let total = plan.songDuration, cap = ShortClip.maxDuration - 1.0
        let n = max(1, Int((total / cap).rounded(.up)))
        var cuts: [Double] = [0]
        if n > 1 {
            // Gaps between lines: midpoint of each gap, weighted by its length.
            let gaps: [(t: Double, len: Double)] = (0..<max(0, plan.lines.count - 1)).map { i in
                let a = plan.lines[i].end, b = plan.lines[i + 1].start; return ((a + b) / 2, max(0, b - a)) }
            for k in 1..<n {
                let ideal = total * Double(k) / Double(n), lo = max(cuts.last! + 30, ideal - 25), hi = min(ideal + 25, cuts.last! + cap)
                let pick = gaps.filter { $0.t >= lo && $0.t <= hi }.max { ($0.len, -abs($0.t - ideal)) < ($1.len, -abs($1.t - ideal)) }
                cuts.append(pick?.t ?? min(ideal, cuts.last! + cap))
            }
        }
        cuts.append(total)
        return (0..<n).map { i in
            var c = ShortClip(name: n == 1 ? "Whole song — \(plan.title)" : "Whole song — \(plan.title) (part \(i + 1) of \(n))", start: cuts[i], end: cuts[i + 1])
            c.loop = false; return c
        }
    }

    /// A clip covering exactly lyric lines `first...last`, with up to `lead` / `tail` seconds of music-only time around them.
    /// The edges never reach into a neighbouring line: with a real gap the cut sits just inside it; with no gap it sits on the line edge.
    public static func clip(plan: Plan, lines first: Int, to last: Int, name: String? = nil, lead: Double = 3.0, tail: Double = 3.0) -> ShortClip {
        let L = plan.lines
        let a = max(0, min(first, last)), b = min(L.count - 1, max(first, last))
        var start = L[a].start - lead
        if a > 0 {
            let prevEnd = L[a - 1].end, gap = L[a].start - prevEnd
            start = max(start, gap >= 0.5 ? prevEnd + 0.15 : (prevEnd + L[a].start) / 2)
        }
        var end = L[b].end + tail
        if b + 1 < L.count {
            let nextStart = L[b + 1].start, gap = nextStart - L[b].end
            end = min(end, gap >= 0.5 ? nextStart - 0.15 : (L[b].end + nextStart) / 2)
        }
        start = max(0, min(start, L[a].start - 0.05)); end = min(plan.songDuration, max(end, L[b].end + 0.05))
        return ShortClip(name: name ?? "Short — " + String(L[a].text.prefix(28)), start: start, end: end)
    }

    /// Last line index (≥ `first`) that still fits in `seconds` starting at line `first` — used to pick a sensible end when only a start was chosen.
    public static func lastLine(plan: Plan, from first: Int, within seconds: Double = 30) -> Int {
        var last = first
        while last + 1 < plan.lines.count, plan.lines[last + 1].end - plan.lines[first].start <= seconds { last += 1 }
        return last
    }
    public static func firstLine(plan: Plan, to last: Int, within seconds: Double = 30) -> Int {
        var first = last
        while first - 1 >= 0, plan.lines[last].end - plan.lines[first - 1].start <= seconds { first -= 1 }
        return first
    }

    /// Quiet moments between words (midpoints of gaps ≥ 60 ms) — good places to cut the music.
    public static func cutPoints(_ plan: Plan) -> [Double] {
        let words = plan.lines.flatMap(\.words)
        var pts: [Double] = [0, plan.songDuration]
        for i in 0..<max(0, words.count - 1) { let g = words[i + 1].start - words[i].end; if g >= 0.06 { pts.append(words[i].end + g / 2) } }
        return pts.sorted()
    }

    public static func snap(_ t: Double, plan: Plan, maxDistance: Double = 0.6) -> Double {
        guard let n = cutPoints(plan).min(by: { abs($0 - t) < abs($1 - t) }), abs(n - t) <= maxDistance else { return t }
        return n
    }

    /// Lines that are in the clip: those with more than half of their duration inside it.
    public static func lineRange(plan: Plan, clip c: ShortClip) -> ClosedRange<Int>? {
        let idx = plan.lines.indices.filter { i in
            let l = plan.lines[i], dur = max(0.01, l.end - l.start)
            return (min(l.end, c.end) - max(l.start, c.start)) / dur > 0.5
        }
        guard let f = idx.first, let l = idx.last else { return nil }; return f...l
    }

    /// Writes a hook for the clip with the local AI (falls back to nothing, so the first lyric words are used).
    public static func writeHook(plan: Plan, clip c: ShortClip, config: Config = .load()) async -> String? {
        guard let omlx = Optional(OMLX(config: config)), (try? await omlx.ensureReady()) != nil else { return nil }
        let lyr = plan.lines.filter { $0.end > c.start && $0.start < c.end }.map(\.text)
        return try? await PromptWriter(omlx: omlx).hook(title: plan.title, description: plan.description, lyrics: lyr)
    }

    /// Renders the Short and (best effort) saves upload metadata next to it as `<name>.txt`.
    public static func renderShort(plan: Plan, work: URL, clip c: ShortClip, suffix: String = "", config: Config = .load(), progress: ProgressHandler? = nil) async throws -> URL {
        let out = shortURL(plan: plan, work: work, name: c.name + suffix, config: config)
        try await VideoRenderer.render(plan: plan, work: work, output: out, settings: .short(), short: c, progress: progress)
        let lyr = plan.lines.filter { $0.end > c.start && $0.start < c.end }.map(\.text)
        let omlx = OMLX(config: config)
        if (try? await omlx.ensureReady()) != nil,
           let meta = try? await PromptWriter(omlx: omlx).metadata(title: plan.title, description: plan.description, lyrics: lyr, hook: c.hook.isEmpty ? plan.title : c.hook, cta: c.cta) {
            let style = ShortStyle.make(seed: c.styleSeed, clip: c)
            let text = "\(meta)\n\n— look: \(style.summary) · seed \(c.styleSeed)\n"
            try? text.write(to: out.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        }
        // A plain range file next to the video: which part of the song it is and the exact word times, for other tools (e.g. ffmpeg).
        let words = plan.lines.flatMap(\.words).filter { $0.end > c.start && $0.start < c.end }.map { ["word": $0.text, "start": ($0.start * 1000).rounded() / 1000, "end": ($0.end * 1000).rounded() / 1000] as [String: Any] }
        let range: [String: Any] = ["clip_id": c.id.uuidString, "title": c.name, "source": plan.title, "start_time": (c.start * 1000).rounded() / 1000, "end_time": (c.end * 1000).rounded() / 1000,
                                    "duration": ((c.end - c.start) * 1000).rounded() / 1000, "lyrics_included": words]
        if let d = try? JSONSerialization.data(withJSONObject: range, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.deletingPathExtension().appendingPathExtension("json")) }
        return out
    }
}
