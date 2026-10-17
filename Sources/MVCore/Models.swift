// Data model: Config (settings), Plan/Section (the save file), ShortClip and VideoSettings.
import Foundation
import CoreGraphics

public struct TimedWord: Codable, Hashable {
    public var text: String
    public var start: Double
    public var end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}

public struct LyricLine: Codable, Identifiable, Hashable {
    public var id: Int
    public var text: String
    public var words: [TimedWord]
    public var start: Double { words.first?.start ?? 0 }
    public var end: Double { words.last?.end ?? 0 }
    public init(id: Int, text: String, words: [TimedWord]) { self.id = id; self.text = text; self.words = words }
}

public struct ImageCandidate: Codable, Identifiable, Hashable {
    public var id: String                 // "<provider>:<id>"
    public var provider: String
    public var thumbURL: String
    public var fullURL: String
    public var pageURL: String
    public var width: Int
    public var height: Int
    public var credit: String
    public var query: String
    public var rank: Int
    public var score: Double = 0
    public var focusX: Double = 0.5       // 0...1 from left (saliency)
    public var focusY: Double = 0.5       // 0...1 from top
    /// A camera move chosen by hand: the view travels from `camStart` to `camEnd` (0…1 across and down the picture). nil = the app decides.
    public var camStartX: Double? = nil, camStartY: Double? = nil, camEndX: Double? = nil, camEndY: Double? = nil
    public var camZoom: Int = 0           // 0 = moves closer, 1 = stays level, 2 = moves wider
    public var cameraPath: CameraPath? {
        guard let a = camStartX, let b = camStartY, let c = camEndX, let d = camEndY else { return nil }
        return CameraPath(start: CGPoint(x: a, y: b), end: CGPoint(x: c, y: d), zoom: camZoom)
    }
    public var tags: String = ""         // provider keywords / alt text, shown to the local LLM
    public var thumbFile: String? = nil   // relative to work dir
    public var fullFile: String? = nil
    /// A video clip used instead of a still picture (relative to the work dir). `fullFile`/`thumbFile` then hold a still frame from it.
    public var videoFile: String? = nil
    public var videoLength: Double? = nil      // length of the whole clip in seconds
    public var videoStart: Double = 0          // where in the clip it begins playing (seconds)
    public var videoEnd: Double? = nil         // where it stops (nil = the end of the clip)

    enum CodingKeys: String, CodingKey { case id, provider, thumbURL, fullURL, pageURL, width, height, credit, query, rank, score, focusX, focusY, tags, thumbFile, fullFile, camStartX, camStartY, camEndX, camEndY, camZoom, videoFile, videoLength, videoStart, videoEnd }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        thumbURL = try c.decodeIfPresent(String.self, forKey: .thumbURL) ?? ""
        fullURL = try c.decodeIfPresent(String.self, forKey: .fullURL) ?? ""
        pageURL = try c.decodeIfPresent(String.self, forKey: .pageURL) ?? ""
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        credit = try c.decodeIfPresent(String.self, forKey: .credit) ?? ""
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        rank = try c.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        score = try c.decodeIfPresent(Double.self, forKey: .score) ?? 0
        focusX = try c.decodeIfPresent(Double.self, forKey: .focusX) ?? 0.5
        focusY = try c.decodeIfPresent(Double.self, forKey: .focusY) ?? 0.5
        tags = try c.decodeIfPresent(String.self, forKey: .tags) ?? ""
        thumbFile = try c.decodeIfPresent(String.self, forKey: .thumbFile)
        fullFile = try c.decodeIfPresent(String.self, forKey: .fullFile)
        camStartX = try c.decodeIfPresent(Double.self, forKey: .camStartX); camStartY = try c.decodeIfPresent(Double.self, forKey: .camStartY)
        camEndX = try c.decodeIfPresent(Double.self, forKey: .camEndX); camEndY = try c.decodeIfPresent(Double.self, forKey: .camEndY)
        camZoom = try c.decodeIfPresent(Int.self, forKey: .camZoom) ?? 0
        videoFile = try c.decodeIfPresent(String.self, forKey: .videoFile)
        videoLength = try c.decodeIfPresent(Double.self, forKey: .videoLength)
        videoStart = try c.decodeIfPresent(Double.self, forKey: .videoStart) ?? 0
        videoEnd = try c.decodeIfPresent(Double.self, forKey: .videoEnd)
    }

    public init(id: String, provider: String, thumbURL: String, fullURL: String, pageURL: String,
                width: Int, height: Int, credit: String, query: String, rank: Int, tags: String = "") {
        self.tags = tags
        self.id = id; self.provider = provider; self.thumbURL = thumbURL; self.fullURL = fullURL
        self.pageURL = pageURL; self.width = width; self.height = height; self.credit = credit
        self.query = query; self.rank = rank
    }
}

public struct PhotoSection: Codable, Identifiable {
    public var id: Int                    // -1 = intro
    public var start: Double              // song time
    public var end: Double
    public var lineIDs: [Int]
    public var queries: [String]
    public var candidates: [ImageCandidate]
    public var selected: Int              // index into candidates, -1 = gradient fallback
    public var seed: UInt64
    public var prompt: String = ""          // suggested image-generation prompt
    public var repeatOf: Int? = nil        // index of an earlier section with the same lyrics (e.g. a repeated chorus)
    public var note: String? = nil
    enum CodingKeys: String, CodingKey { case id, start, end, lineIDs, queries, candidates, selected, seed, prompt, repeatOf, note }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); start = try c.decode(Double.self, forKey: .start); end = try c.decode(Double.self, forKey: .end)
        lineIDs = try c.decodeIfPresent([Int].self, forKey: .lineIDs) ?? []
        queries = try c.decodeIfPresent([String].self, forKey: .queries) ?? []
        candidates = try c.decodeIfPresent([ImageCandidate].self, forKey: .candidates) ?? []
        selected = try c.decodeIfPresent(Int.self, forKey: .selected) ?? -1
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 7
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        repeatOf = try c.decodeIfPresent(Int.self, forKey: .repeatOf)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
    public init(id: Int, start: Double, end: Double, lineIDs: [Int], queries: [String], candidates: [ImageCandidate], selected: Int, seed: UInt64) {
        self.id = id; self.start = start; self.end = end; self.lineIDs = lineIDs; self.queries = queries; self.candidates = candidates; self.selected = selected; self.seed = seed
    }
    public var duration: Double { end - start }
    public var selectedCandidate: ImageCandidate? {
        candidates.indices.contains(selected) ? candidates[selected] : nil
    }
    public var hasImage: Bool { selectedCandidate?.fullFile != nil }
}

public struct Plan: Codable {
    public var title: String
    public var subject: String
    public var audioPath: String           // original location (fallback)
    public var audioFile: String = ""       // copy kept inside the project folder
    public var songDuration: Double
    public var lines: [LyricLine]
    public var intro: PhotoSection
    public var sections: [PhotoSection]
    public var description: String = ""       // AI-written description of the song (drives the prompts)
    public var style: String = ""            // shared visual style appended to every prompt
    public var introDuration: Double
    public var audioOffset: Double        // silence before the song starts (title card pre-roll)
    public var alignmentCoverage: Double  // fraction of lyric words matched to the transcript
    public var shorts: [ShortClip] = []   // YouTube Shorts cut from this song
    public var timing: String = "windows"  // "exact" = true word timestamps; "windows" = inferred (±0.3 s)
    public var captionY: Double? = nil      // caption position for the full video (fraction of height from the bottom)
    public var totalGenerationCostUSD: Double = 0.0  // cumulative OpenRouter USD spent generating/rerolling images for this song
    public var imagesGeneratedCount: Int = 0         // total AI image generations/rerolls run for this song
    public var lastImageCostUSD: Double? = nil       // most recent actual per-image cost returned by OpenRouter
    /// Seconds added to every caption time when drawing (negative = captions appear sooner). Seen from the audience's side, captions that
    /// land exactly on the sound feel late, so new and old projects start slightly early; the user can fine-tune it per song.
    public var captionShift: Double = Plan.defaultCaptionShift
    /// Lyric-line numbers where the user's own parts start (empty = the app divided the song itself). Drives pictures and Shorts.
    public var partStarts: [Int] = []
    /// A setting/theme you typed (e.g. “Brightly lit colonial Philadelphia”). Every prompt follows it and states it explicitly.
    public var setting: String = ""
    /// True when `partStarts` came from the user's own verse breaks (blank lines / [Chorus] tags) rather than `---` dividers.
    public var partsFromVerses = false
    public static let defaultCaptionShift = -0.06

    enum CodingKeys: String, CodingKey {
        case title, subject, audioPath, audioFile, songDuration, lines, intro, sections, description, style, introDuration, audioOffset, alignmentCoverage, shorts, timing, captionY
        case totalGenerationCostUSD, imagesGeneratedCount, lastImageCostUSD, captionShift, partStarts, setting, partsFromVerses
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        audioPath = try c.decodeIfPresent(String.self, forKey: .audioPath) ?? ""
        audioFile = try c.decodeIfPresent(String.self, forKey: .audioFile) ?? ""
        songDuration = try c.decode(Double.self, forKey: .songDuration)
        lines = try c.decode([LyricLine].self, forKey: .lines)
        intro = try c.decode(PhotoSection.self, forKey: .intro)
        sections = try c.decode([PhotoSection].self, forKey: .sections)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        introDuration = try c.decodeIfPresent(Double.self, forKey: .introDuration) ?? 4.5
        audioOffset = try c.decodeIfPresent(Double.self, forKey: .audioOffset) ?? 0
        alignmentCoverage = try c.decodeIfPresent(Double.self, forKey: .alignmentCoverage) ?? 1
        shorts = try c.decodeIfPresent([ShortClip].self, forKey: .shorts) ?? []
        timing = try c.decodeIfPresent(String.self, forKey: .timing) ?? "windows"
        captionY = try c.decodeIfPresent(Double.self, forKey: .captionY)
        totalGenerationCostUSD = try c.decodeIfPresent(Double.self, forKey: .totalGenerationCostUSD) ?? 0.0
        imagesGeneratedCount = try c.decodeIfPresent(Int.self, forKey: .imagesGeneratedCount) ?? 0
        lastImageCostUSD = try c.decodeIfPresent(Double.self, forKey: .lastImageCostUSD)
        captionShift = try c.decodeIfPresent(Double.self, forKey: .captionShift) ?? Plan.defaultCaptionShift
        partStarts = try c.decodeIfPresent([Int].self, forKey: .partStarts) ?? []
        setting = try c.decodeIfPresent(String.self, forKey: .setting) ?? ""
        partsFromVerses = try c.decodeIfPresent(Bool.self, forKey: .partsFromVerses) ?? false
    }
    public init(title: String, subject: String, audioPath: String, audioFile: String, songDuration: Double, lines: [LyricLine], intro: PhotoSection, sections: [PhotoSection],
                description: String, style: String, introDuration: Double, audioOffset: Double, alignmentCoverage: Double) {
        self.title = title; self.subject = subject; self.audioPath = audioPath; self.audioFile = audioFile; self.songDuration = songDuration; self.lines = lines
        self.intro = intro; self.sections = sections; self.description = description; self.style = style; self.introDuration = introDuration
        self.audioOffset = audioOffset; self.alignmentCoverage = alignmentCoverage
    }
}

public struct VideoSettings {
    public var width: Int
    public var height: Int
    public var fps: Int = 30
    public var hevc: Bool = false
    public var vertical: Bool { height > width }
    public var bitrate: Int { Int(Double(width * height) / (1920.0 * 1080.0) * 6_000_000 * (hevc ? 0.7 : 1)) }
    /// Landscape 16:9 at the given height (720 / 1080 / 1440 / 2160).
    public init(height: Int = 1080, fps: Int = 30, hevc: Bool = false) { self.height = height; self.width = height * 16 / 9; self.fps = fps; self.hevc = hevc }
    /// YouTube Shorts: vertical 9:16, 1080×1920.
    public static func short(fps: Int = 30) -> VideoSettings { var s = VideoSettings(height: 1920, fps: fps); s.width = 1080; return s }
}

/// A vertical clip cut from the song: a time range (song seconds) the user picked and fine-tuned, plus its look.
public struct ShortClip: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var start: Double          // song seconds
    public var end: Double
    public var dynamic: Bool = true   // dynamic style kit (hook title, multi-crop shots, beat pulses, word-pop text, loop ending)
    public var styleSeed: UInt64 = UInt64.random(in: 1...UInt64(UInt32.max))   // same seed → same look
    public var hook: String = ""      // big opening title (blank = use the first words of the lyrics)
    public var cta: String = ""       // optional closing text, e.g. "Full song on YouTube ▶"
    public var loop: Bool = true      // last half-second dissolves back into the first frame
    public var motion: String = "calm"        // "calm" (one smooth camera path, soft cuts) or "punchy" (multi-angle cuts, shake, beat pulses)
    public var textStyle: String = "pill"     // "pill", "pop", "stack", "sweep" or "auto" (from the seed)
    public var accent: String = "Hot pink"    // a palette name, or "Auto"
    public var pulse: Bool = false            // gentle zoom pulse on beats (calm mode)
    public var captionY: Double? = nil        // caption block's bottom edge as a fraction of the frame height (nil = default)
    public var fadeOut: Double? = nil         // how long the picture and music fade at the end, in seconds (nil = the style's default; used when the ending does not loop)
    public var duration: Double { end - start }
    /// Hard limit for a YouTube Short, in seconds.
    public static let maxDuration = 180.0
    /// True when the clip covers the whole song (a full-length vertical video rather than a short excerpt).
    public func isWhole(of songDuration: Double) -> Bool { start <= 0.05 && end >= songDuration - 0.05 }
    public init(name: String, start: Double, end: Double) { self.name = name; self.start = start; self.end = end }

    enum CodingKeys: String, CodingKey { case id, name, start, end, dynamic, styleSeed, hook, cta, loop, motion, textStyle, accent, pulse, captionY, fadeOut }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        start = try c.decode(Double.self, forKey: .start); end = try c.decode(Double.self, forKey: .end)
        dynamic = try c.decodeIfPresent(Bool.self, forKey: .dynamic) ?? true
        styleSeed = try c.decodeIfPresent(UInt64.self, forKey: .styleSeed) ?? UInt64.random(in: 1...UInt64(UInt32.max))
        hook = try c.decodeIfPresent(String.self, forKey: .hook) ?? ""
        cta = try c.decodeIfPresent(String.self, forKey: .cta) ?? ""
        loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? true
        motion = try c.decodeIfPresent(String.self, forKey: .motion) ?? "calm"
        textStyle = try c.decodeIfPresent(String.self, forKey: .textStyle) ?? "pill"
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "Hot pink"
        pulse = try c.decodeIfPresent(Bool.self, forKey: .pulse) ?? false
        captionY = try c.decodeIfPresent(Double.self, forKey: .captionY)
        fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut)
    }
}

public struct MVError: LocalizedError {
    public var message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
}

/// Progress callback: (phase label, 0...1 within the phase)
public typealias ProgressHandler = @Sendable (String, Double) -> Void

public struct Config: Codable {
    // oMLX (local AI server). Blank values fall back to defaults / oMLX's own settings file.
    public var omlxURL: String = ""
    public var omlxKey: String = ""
    public var sttModel: String = ""
    public var llmModel: String = ""
    public var projectsFolder: String = ""    // where project folders are created (blank = ~/Movies/Music Videos)
    public var outputFolder: String = ""      // where finished videos & Shorts go (blank = next to each project)
    public var openRouterKey: String = ""     // OpenRouter API key for image generation (openai/gpt-image-2.5-sunburst)
    public var effectiveOpenRouterKey: String { openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    public init() {}

    enum CodingKeys: String, CodingKey { case omlxURL, omlxKey, sttModel, llmModel, projectsFolder, outputFolder, openRouterKey }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        omlxURL = try c.decodeIfPresent(String.self, forKey: .omlxURL) ?? ""
        omlxKey = try c.decodeIfPresent(String.self, forKey: .omlxKey) ?? ""
        sttModel = try c.decodeIfPresent(String.self, forKey: .sttModel) ?? ""
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? ""
        projectsFolder = try c.decodeIfPresent(String.self, forKey: .projectsFolder) ?? ""
        outputFolder = try c.decodeIfPresent(String.self, forKey: .outputFolder) ?? ""
        openRouterKey = try c.decodeIfPresent(String.self, forKey: .openRouterKey) ?? ""
    }

    /// Folder that holds project folders.
    public var projectsRoot: URL {
        let u = projectsFolder.isEmpty ? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Music Videos")
                                       : URL(fileURLWithPath: (projectsFolder as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    public static var url: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicVideo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }
    public static func load() -> Config {
        var c = (try? JSONDecoder().decode(Config.self, from: Data(contentsOf: url))) ?? Config()
        let env = ProcessInfo.processInfo.environment
        if let v = env["OMLX_API_KEY"], !v.isEmpty { c.omlxKey = v }
        if let v = env["OMLX_URL"], !v.isEmpty { c.omlxURL = v }
        if let v = env["OPENROUTER_API_KEY"], !v.isEmpty, c.openRouterKey.isEmpty { c.openRouterKey = v }
        c.omlxKey = c.omlxKey.trimmingCharacters(in: .whitespacesAndNewlines)
        c.openRouterKey = c.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return c
    }
    public func save() throws {
        var s = self
        s.omlxKey = omlxKey.trimmingCharacters(in: .whitespacesAndNewlines)
        s.openRouterKey = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try JSONEncoder().encode(s).write(to: Config.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.url.path)
    }
}

/// A named picture style that is added to every picture prompt. Built-in presets can be edited or removed and you can add your own (see `StyleLibrary`).
public struct StylePreset: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var prompt: String
    public var builtIn: Bool = false
    public init(id: String? = nil, name: String, prompt: String, builtIn: Bool = false) {
        self.name = name; self.prompt = prompt; self.builtIn = builtIn
        self.id = id ?? StylePreset.slug(name)
    }
    static func slug(_ n: String) -> String { n.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// Every style in the order shown: "AI Auto" first, then the library (built-in and your own).
    public static var all: [StylePreset] { StyleLibrary.shared.all }
    public static let autoID = "aiautomatchthesong"
}

