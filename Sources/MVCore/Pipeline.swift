import Foundation
import ImageIO

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
                            config: Config = .load(), progress: ProgressHandler? = nil) async throws -> Plan {
        let duration = try await audioDuration(path: audioPath)
        guard duration > 5 else { throw MVError("Couldn't read the audio file (or it's shorter than 5 seconds).") }

        // Keep a copy of the song with the project so it can be reopened and edited anywhere.
        let srcURL = URL(fileURLWithPath: audioPath)
        let audioName = "audio." + (srcURL.pathExtension.isEmpty ? "mp3" : srcURL.pathExtension.lowercased())
        let ownAudio = work.appendingPathComponent(audioName)
        if !FileManager.default.fileExists(atPath: ownAudio.path) { try? FileManager.default.copyItem(at: srcURL, to: ownAudio) }

        let omlx = OMLX(config: config)
        progress?("Connecting to oMLX", 0)
        try await omlx.ensureReady()
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
        let lines = aligned.lines

        // Sections
        var sections = Planner.plan(lines: lines, stanzaBreaks: parsed.stanzaBreaks, songDuration: duration, opts: .init(imageInterval: imageInterval))
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
        let description = try await writer.describe(title: title, lyrics: lines.map(\.text), hint: subject)
        progress?("Local AI is writing the image prompts", 0.75)
        let written = try await writer.write(sections: [intro] + sections, lines: lines, title: title, subject: description)
        intro.prompt = written.prompts[-1] ?? "A wide establishing scene that captures the setting of \"\(title)\"."
        for i in sections.indices { sections[i].prompt = written.prompts[sections[i].id] ?? "A scene illustrating: " + sections[i].lineIDs.map { lines[$0].text }.joined(separator: " / ") }

        var plan = Plan(title: title, subject: subject, audioPath: audioPath,
                        audioFile: FileManager.default.fileExists(atPath: ownAudio.path) ? audioName : "", songDuration: duration, lines: lines, intro: intro, sections: sections, description: description, style: written.style, introDuration: introDur, audioOffset: offset,
                        alignmentCoverage: aligned.coverage)
        plan.timing = timing
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

    // MARK: Prompts

    /// What to paste into the image generator for one section (section index −1 = title card).
    public static func fullPrompt(_ plan: Plan, section index: Int) -> String {
        let s = index < 0 ? plan.intro : plan.sections[index]
        let style = plan.style.isEmpty ? "" : " Style: \(plan.style)"
        return "\(s.prompt)\(style) Widescreen 16:9 landscape composition, no text, no lettering, no watermark."
    }

    public static func promptsMarkdown(_ plan: Plan) -> String {
        func t(_ x: Double) -> String { String(format: "%d:%02d", Int(x) / 60, Int(x) % 60) }
        var md = "# \(plan.title) — image prompts\n\n"
        if !plan.description.isEmpty { md += "**Song description (written from the lyrics):** \(plan.description)\n\n" }
        md += "**Shared style (used in every prompt):** \(plan.style)\n\n"
        md += "Generate each picture at 16:9 (1920×1080 or larger is best), then load it into the matching slot. File names that start with the number (`00.png`, `01.png`, …) are matched automatically.\n\n---\n\n"
        for idx in -1..<plan.sections.count {
            let s = idx < 0 ? plan.intro : plan.sections[idx]
            let name = idx < 0 ? "00 · Title card" : String(format: "%02d", idx + 1) + " · " + (s.lineIDs.isEmpty ? "Instrumental" : "Section")
            let when = idx < 0 ? "opening" : "\(t(s.start + plan.audioOffset))–\(t(s.end + plan.audioOffset)) (\(Int(s.duration)) s)"
            md += "## \(name) — \(when)\n"
            if !s.lineIDs.isEmpty { md += "\n> " + s.lineIDs.map { plan.lines[$0].text }.joined(separator: "\n> ") + "\n" }
            if let r = s.repeatOf { md += "\n*Same lyrics as section \(String(format: "%02d", r + 1)) — you can reuse that picture, or make a fresh take with the prompt below.*\n" }
            md += "\n**Prompt:**\n\n\(fullPrompt(plan, section: idx))\n\n"
        }
        return md
    }

    /// Rewrites the song description from the lyrics (optionally steered by a hint) and, if asked, all prompts from it.
    public static func redescribe(plan: inout Plan, hint: String = "", config: Config = .load()) async throws {
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        plan.description = try await PromptWriter(omlx: omlx).describe(title: plan.title, lyrics: plan.lines.map(\.text), hint: hint)
    }

    /// Regenerates the style and every prompt from the (possibly edited) song description. Pictures already loaded are kept.
    public static func regeneratePrompts(plan: inout Plan, config: Config = .load()) async throws {
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        let w = try await PromptWriter(omlx: omlx).write(sections: [plan.intro] + plan.sections, lines: plan.lines, title: plan.title, subject: plan.description)
        plan.style = w.style
        if let p = w.prompts[-1] { plan.intro.prompt = p }
        for i in plan.sections.indices { if let p = w.prompts[plan.sections[i].id] { plan.sections[i].prompt = p } }
    }

    public static func rewritePrompt(plan: inout Plan, section index: Int, config: Config = .load()) async throws {
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        let s = index < 0 ? plan.intro : plan.sections[index]
        let p = try await PromptWriter(omlx: omlx).rewrite(section: s, lines: plan.lines, title: plan.title, subject: plan.description, style: plan.style, current: s.prompt)
        if index < 0 { plan.intro.prompt = p } else { plan.sections[index].prompt = p }
    }

    // MARK: Step 2 — load your pictures

    /// Loads a picture into a section (−1 = title card). Copies it into the work folder, makes a thumbnail and finds its focal point for the Ken Burns move.
    @discardableResult
    public static func attach(imageAt url: URL, section index: Int, plan: inout Plan, work: URL) throws -> String? {
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
        try? savePlan(plan, work)
        let aspect = Double(w) / Double(h)
        if aspect < 1.5 { return "“\(url.lastPathComponent)” isn't widescreen (\(w)×\(h)); the video will crop it to 16:9." }
        if w < 1200 { return "“\(url.lastPathComponent)” is only \(w) px wide; it may look soft at 1080p." }
        return nil
    }

    public static func removeImage(section index: Int, plan: inout Plan, work: URL) {
        if index < 0 { plan.intro.candidates = []; plan.intro.selected = -1 } else { plan.sections[index].candidates = []; plan.sections[index].selected = -1 }
        try? savePlan(plan, work)
    }

    /// Loads every image in a folder whose file name starts with a section number (00 / intro = title card, 01 = first section, …).
    public static func attachFolder(_ folder: URL, plan: inout Plan, work: URL) -> (loaded: [Int], warnings: [String]) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var loaded: [Int] = []; var warnings: [String] = []
        for f in files where ["png", "jpg", "jpeg", "webp", "heic", "tiff"].contains(f.pathExtension.lowercased()) {
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
        return (loaded, warnings)
    }

    /// Section indices (−1 = title card) that still have no picture.
    public static func missing(_ plan: Plan) -> [Int] {
        var m: [Int] = []
        if plan.intro.selectedCandidate?.fullFile == nil { m.append(-1) }
        for (i, s) in plan.sections.enumerated() where s.selectedCandidate?.fullFile == nil { m.append(i) }
        return m
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

    /// Shorts go to `<output folder>/Shorts` when an output folder is chosen, otherwise inside the project.
    public static func shortsFolder(_ work: URL, config: Config = .load()) -> URL {
        let d = (config.outputFolder.isEmpty ? work : outputFolder(for: work, config: config)).appendingPathComponent("Shorts")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
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
        let safe = (c.name + suffix).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let out = shortsFolder(work).appendingPathComponent("\(safe).mp4")
        try await VideoRenderer.render(plan: plan, work: work, output: out, settings: .short(), short: c, progress: progress)
        let lyr = plan.lines.filter { $0.end > c.start && $0.start < c.end }.map(\.text)
        let omlx = OMLX(config: config)
        if (try? await omlx.ensureReady()) != nil,
           let meta = try? await PromptWriter(omlx: omlx).metadata(title: plan.title, description: plan.description, lyrics: lyr, hook: c.hook.isEmpty ? plan.title : c.hook, cta: c.cta) {
            let style = ShortStyle.make(seed: c.styleSeed, clip: c)
            let text = "\(meta)\n\n— look: \(style.summary) · seed \(c.styleSeed)\n"
            try? text.write(to: out.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        }
        return out
    }
}
