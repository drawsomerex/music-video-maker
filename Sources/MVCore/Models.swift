import Foundation

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
    public var tags: String = ""         // provider keywords / alt text, shown to the local LLM
    public var thumbFile: String? = nil   // relative to work dir
    public var fullFile: String? = nil

    enum CodingKeys: String, CodingKey { case id, provider, thumbURL, fullURL, pageURL, width, height, credit, query, rank, score, focusX, focusY, tags, thumbFile, fullFile }
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

    enum CodingKeys: String, CodingKey { case title, subject, audioPath, audioFile, songDuration, lines, intro, sections, description, style, introDuration, audioOffset, alignmentCoverage, shorts, timing, captionY }
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
    public var duration: Double { end - start }
    /// Hard limit for a YouTube Short, in seconds.
    public static let maxDuration = 180.0
    /// True when the clip covers the whole song (a full-length vertical video rather than a short excerpt).
    public func isWhole(of songDuration: Double) -> Bool { start <= 0.05 && end >= songDuration - 0.05 }
    public init(name: String, start: Double, end: Double) { self.name = name; self.start = start; self.end = end }

    enum CodingKeys: String, CodingKey { case id, name, start, end, dynamic, styleSeed, hook, cta, loop, motion, textStyle, accent, pulse, captionY }
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
    public init() {}

    enum CodingKeys: String, CodingKey { case omlxURL, omlxKey, sttModel, llmModel, projectsFolder, outputFolder }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        omlxURL = try c.decodeIfPresent(String.self, forKey: .omlxURL) ?? ""
        omlxKey = try c.decodeIfPresent(String.self, forKey: .omlxKey) ?? ""
        sttModel = try c.decodeIfPresent(String.self, forKey: .sttModel) ?? ""
        llmModel = try c.decodeIfPresent(String.self, forKey: .llmModel) ?? ""
        projectsFolder = try c.decodeIfPresent(String.self, forKey: .projectsFolder) ?? ""
        outputFolder = try c.decodeIfPresent(String.self, forKey: .outputFolder) ?? ""
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
        c.omlxKey = c.omlxKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return c
    }
    public func save() throws {
        var s = self; s.omlxKey = omlxKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try JSONEncoder().encode(s).write(to: Config.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.url.path)
    }
}
