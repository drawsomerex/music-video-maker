// Looping long music video: one song (any length) and one 15-second scene that loops seamlessly, made into a video of 1 to 12 hours (study music).
//
//   • the picture: drawn from your scene idea (or your own picture)            → the first frame of the clip
//   • the clip: one HeyGen clip with a locked-off camera and gentle, cyclical motion; its end blends into its start, so it repeats without a seam
//   • the song: silence trimmed at both ends, its last seconds blended into its beginning, so it repeats without a gap
//   • the video: a title screen that fades into the loop, the loop for hours, a fade-out at the very end
//
// Making hours of video fast: only three short pieces are drawn and encoded (the opening with the title, one loop, the ending). The long middle is the
// same encoded loop written again and again, and the song is generated sample by sample into one continuous audio track (so there is never a click).
import Foundation
import AVFoundation
import CoreGraphics
import VideoToolbox

/// The part of a clip that loops (seconds into the clip; end nil = to the end).
public struct ClipTrim: Codable, Equatable { public var start = 0.0; public var end: Double? = nil; public var blend: Double? = nil      // blend: the dissolve from the end back to the start (nil = 1.6 s)
    public var clean: [Double]? = nil          // the usable part of the clip [start, end] when it flips, cuts or turns the other way (nil = all of it); the slow dissolve stays inside it
    public init(start: Double = 0, end: Double? = nil, blend: Double? = nil, clean: [Double]? = nil) { self.start = start; self.end = end; self.blend = blend; self.clean = clean } }

/// Title cards: none (the default), only the video's title at the beginning, or the video's title and then a card for every song.
public enum LoopCards: String, Codable, CaseIterable { case none, beginning, everySong
    public var name: String { switch self { case .none: "None"; case .beginning: "Only at the beginning"; case .everySong: "Every song" } }
}

public struct LoopProject: Codable, Equatable {
    public var id = UUID().uuidString
    public var title = ""
    public var screenTitle = ""                 // the title screen at the start (empty = the song title)
    public var songFile = ""                    // older projects: their one song (now the first track)
    public var songSeconds = 0.0
    public var tracks: [LoopTrack] = []         // the music: one song or a playlist (up to 100), in playing order
    public var analysis: [String: TrackAnalysis] = [:]   // what listening to each song found (by file)
    public var transition: LoopTransition? = nil          // nil = the default for the number of songs
    public var crossfade = 6.0, gap = 2.0       // seconds, for Crossfade and Album gaps
    public var evenVolume: Bool? = nil          // nil = on for two or more songs
    public var shuffle = false                  // shuffle each time the playlist repeats (the first time through is in your order)
    public var playOnce = false                 // each song once: the video is as long as the album (or the one song)
    public var cards: LoopCards = .none
    public var effectiveTransition: LoopTransition { transition ?? (tracks.count > 1 ? .automatic : .seamless) }
    public var effectiveEvenVolume: Bool { evenVolume ?? (tracks.count > 1) }
    public var scene = ""                       // what the scene shows
    public var style = ""                       // the look (an art style), optional
    public var motion = ""                      // what moves in the loop clip (written from the picture; you can edit it)
    public var about = ""                       // "About the music": your own words; steers the scene ideas and the YouTube text
    public var pictures: [String] = []          // every picture made or added, oldest first
    public var picture: String?                 // the one the clip starts from
    public var clips: [String] = []             // every loop clip made or added
    public var clip: String?                    // the one in use
    public var sharpClip = false                // 2K instead of 768p (sharper, about three times the price)
    public var clearSky = true                  // new pictures are drawn with a cloudless sky (it loops most cleanly); older projects keep their clouds
    public var pendingJob: String?              // a HeyGen job that was paid for but not collected yet (the app was closed)
    public var hours = 1.0
    public var imagesUSD = 0.0, videoUSD = 0.0, pictureCount = 0
    public var output: String?                  // the last long video made (full path)
    public var thumbnail: String?, listing: String?     // the YouTube thumbnail and description beside it (full paths)
    public var trims: [String: ClipTrim] = [:]  // for each clip, the part that loops
    public var thumbText = ThumbnailText()       // what is written on the YouTube thumbnail
    public var clipWarning: String?             // what the check found in the clip in use (a mirror flip or a cut), if anything
    public var loopScores: [String: Double] = [:]   // for each clip, how closely the loop's end matches its start (1 = as close as two neighbouring frames)
    public var loopDrift: [String: Double] = [:]    // for each clip, the share of the picture that drifts one way and so gets the slow dissolve (0…1)
    public var trim: ClipTrim { clip.flatMap { trims[$0] } ?? ClipTrim() }
    public init() {}
    public var shownTitle: String { screenTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : screenTitle }

    enum CodingKeys: String, CodingKey { case id, title, screenTitle, about, songFile, songSeconds, tracks, analysis, transition, crossfade, gap, evenVolume, shuffle, playOnce, cards, scene, style, motion, pictures, picture, clips, clip, sharpClip, clearSky, pendingJob, hours, imagesUSD, videoUSD, pictureCount, output, thumbnail, listing, trims, clipWarning, loopScores, loopDrift, thumbText }
    public init(from d: Decoder) throws {                          // every field has a default, so older loop projects always open
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""; screenTitle = try c.decodeIfPresent(String.self, forKey: .screenTitle) ?? ""
        songFile = try c.decodeIfPresent(String.self, forKey: .songFile) ?? ""; songSeconds = try c.decodeIfPresent(Double.self, forKey: .songSeconds) ?? 0
        tracks = try c.decodeIfPresent([LoopTrack].self, forKey: .tracks) ?? []
        if tracks.isEmpty && !songFile.isEmpty { tracks = [LoopTrack(file: songFile, title: title, seconds: songSeconds)] }     // a project from before playlists
        analysis = try c.decodeIfPresent([String: TrackAnalysis].self, forKey: .analysis) ?? [:]
        transition = try c.decodeIfPresent(LoopTransition.self, forKey: .transition)
        crossfade = try c.decodeIfPresent(Double.self, forKey: .crossfade) ?? 6; gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 2
        evenVolume = try c.decodeIfPresent(Bool.self, forKey: .evenVolume); shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        playOnce = try c.decodeIfPresent(Bool.self, forKey: .playOnce) ?? false
        cards = try c.decodeIfPresent(LoopCards.self, forKey: .cards) ?? .none
        scene = try c.decodeIfPresent(String.self, forKey: .scene) ?? ""; style = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        motion = try c.decodeIfPresent(String.self, forKey: .motion) ?? ""
        about = try c.decodeIfPresent(String.self, forKey: .about) ?? ""
        pictures = try c.decodeIfPresent([String].self, forKey: .pictures) ?? []; picture = try c.decodeIfPresent(String.self, forKey: .picture)
        clips = try c.decodeIfPresent([String].self, forKey: .clips) ?? []; clip = try c.decodeIfPresent(String.self, forKey: .clip)
        sharpClip = try c.decodeIfPresent(Bool.self, forKey: .sharpClip) ?? false; pendingJob = try c.decodeIfPresent(String.self, forKey: .pendingJob)
        clearSky = try c.decodeIfPresent(Bool.self, forKey: .clearSky) ?? false
        hours = try c.decodeIfPresent(Double.self, forKey: .hours) ?? 1
        imagesUSD = try c.decodeIfPresent(Double.self, forKey: .imagesUSD) ?? 0; videoUSD = try c.decodeIfPresent(Double.self, forKey: .videoUSD) ?? 0
        pictureCount = try c.decodeIfPresent(Int.self, forKey: .pictureCount) ?? 0; output = try c.decodeIfPresent(String.self, forKey: .output)
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail); listing = try c.decodeIfPresent(String.self, forKey: .listing)
        trims = try c.decodeIfPresent([String: ClipTrim].self, forKey: .trims) ?? [:]; clipWarning = try c.decodeIfPresent(String.self, forKey: .clipWarning)
        loopScores = try c.decodeIfPresent([String: Double].self, forKey: .loopScores) ?? [:]
        loopDrift = try c.decodeIfPresent([String: Double].self, forKey: .loopDrift) ?? [:]
        thumbText = try c.decodeIfPresent(ThumbnailText.self, forKey: .thumbText) ?? ThumbnailText()
    }
}

public enum LoopVideo {
    public static let fileName = "loop.json"
    public static let clipSeconds = 15
    public static let fps = 30
    public static let width = 1920, height = 1080
    public static let videoBitrate = 3_500_000, audioBitrate = 192_000          // "1080p, efficient": about 1.7 GB per hour
    public static let songBlend = 3.0                                           // seconds of the song's end blended into its beginning
    public static let clipBlend = 1.6                                           // seconds of the clip's end dissolved into its beginning
    public static let cardSeconds = 5.0                                         // a song's title card: 1 s in, 3 s held, 1 s out
    public static let titleScreenEnd = 8.5                                      // the video's title has faded by then

    // MARK: project folder
    public static func isLoopProject(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(fileName).path) }
    public static func load(_ dir: URL) throws -> LoopProject { try JSONDecoder().decode(LoopProject.self, from: Data(contentsOf: dir.appendingPathComponent(fileName))) }
    public static func save(_ p: LoopProject, _ dir: URL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(p).write(to: dir.appendingPathComponent(fileName), options: .atomic)
        SpendLedger.record(p.id, SpendLedger.Entry(title: p.title + " (looping video)", path: dir.path, imagesUSD: p.imagesUSD, videoUSD: p.videoUSD, pictures: p.pictureCount))
    }

    /// A new looping project: its own folder "<title> – looping video" (never overwriting another), with the songs copied in.
    public static func create(songs: [URL], title: String, config: Config = .load()) async throws -> (LoopProject, URL) {
        let fm = FileManager.default
        guard let first = songs.first else { throw MVError("Choose at least one song.") }
        let base = (title.isEmpty ? first.deletingPathExtension().lastPathComponent : title).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var dir = config.projectsRoot.appendingPathComponent("\(base) – looping video"), n = 2
        while fm.fileExists(atPath: dir.path) { dir = config.projectsRoot.appendingPathComponent("\(base) – looping video \(n)"); n += 1 }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var p = LoopProject(); p.title = title.isEmpty ? base : title
        try await addTracks(&p, dir: dir, files: songs)
        return (p, dir)
    }
    public static func create(song: URL, title: String, config: Config = .load()) async throws -> (LoopProject, URL) { try await create(songs: [song], title: title, config: config) }

    public static let maxTracks = 100
    /// Copies songs into the project (in "tracks"), named after their files; their names default to the file name.
    public static func addTracks(_ p: inout LoopProject, dir: URL, files: [URL]) async throws {
        let fm = FileManager.default
        let folder = dir.appendingPathComponent("tracks")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let room = maxTracks - p.tracks.count
        guard room > 0 else { throw MVError("A looping video can have at most \(maxTracks) songs.") }
        for src in files.prefix(room) {
            var name = src.lastPathComponent, k = 2
            while fm.fileExists(atPath: folder.appendingPathComponent(name).path) { name = src.deletingPathExtension().lastPathComponent + " \(k)." + src.pathExtension; k += 1 }
            try fm.copyItem(at: src, to: folder.appendingPathComponent(name))
            let secs = (try? await AVURLAsset(url: folder.appendingPathComponent(name)).load(.duration)).map(CMTimeGetSeconds) ?? 0
            p.tracks.append(LoopTrack(file: "tracks/" + name, title: src.deletingPathExtension().lastPathComponent, seconds: secs))
        }
        if let f = p.tracks.first { p.songFile = f.file; p.songSeconds = f.seconds }
        save(p, dir)
        if files.count > room { throw MVError("Only \(room) more song\(room == 1 ? "" : "s") could be added: a looping video can have at most \(maxTracks).") }
    }

    /// Listens to every song not listened to yet (where its sound starts and ends, its loudness, how it ends and begins). Returns true if any was new.
    @discardableResult
    public static func ensureAnalysis(_ p: inout LoopProject, dir: URL, progress: ((String, Double) -> Void)? = nil) throws -> Bool {
        let todo = p.tracks.filter { (p.analysis[$0.file]?.version ?? 0) < TrackAnalysis.currentVersion }       // new songs, and songs measured the old way
        for (k, t) in todo.enumerated() {
            try Task.checkCancellation()
            progress?("Listening to “\(t.title)” (\(k + 1) of \(todo.count))…", Double(k) / Double(max(1, todo.count)))
            p.analysis[t.file] = try LoopAudio.analyze(dir.appendingPathComponent(t.file))
        }
        if !todo.isEmpty { save(p, dir) }
        return !todo.isEmpty
    }

    /// The same number every time for the same project (Swift's own hashes change on every launch), so the shuffle in the video and in its chapters always match.
    static func stableSeed(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h | 1
    }

    /// The plan of the music (needs every song listened to): which song plays when, the joins, and the exact length.
    public static func plan(_ p: LoopProject) -> LoopAudio.Plan? {
        let an = p.tracks.compactMap { p.analysis[$0.file] }
        guard !an.isEmpty, an.count == p.tracks.count else { return nil }
        return LoopAudio.plan(analyses: an, transition: p.effectiveTransition, crossfade: p.crossfade, gap: p.gap, evenVolume: p.effectiveEvenVolume,
                              shuffle: p.shuffle, minimum: p.hours * 3600, seed: stableSeed(p.id), onePass: p.playOnce)
    }

    /// Replaces the song of an open project.
    public static func replaceSong(_ p: inout LoopProject, dir: URL, song: URL) async throws {
        let fm = FileManager.default
        let name = "song-\(Int(Date().timeIntervalSince1970))." + (song.pathExtension.isEmpty ? "mp3" : song.pathExtension.lowercased())
        try fm.copyItem(at: song, to: dir.appendingPathComponent(name))
        if !p.songFile.isEmpty { try? fm.removeItem(at: dir.appendingPathComponent(p.songFile)) }
        p.songFile = name
        p.songSeconds = (try? await AVURLAsset(url: dir.appendingPathComponent(name)).load(.duration)).map(CMTimeGetSeconds) ?? 0
        save(p, dir)
    }

    // MARK: ideas, picture, clip
    /// Ten calm scenes that loop well, written by the local model from the song title (and the look, if chosen).
    public static func suggestScenes(title: String, style: String, about: String = "", avoid: [String] = [], config: Config = .load()) async throws -> [String] {
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        let prompt = """
        A song called "\(title)" will play for hours as calm background (study) music over ONE looping video scene.\(style.isEmpty ? "" : " The look: \(style).")\(about.isEmpty ? "" : " About the music, in the maker's words (the scenes must suit it): \(about)")
        Suggest 10 different scenes that loop beautifully: a fixed viewpoint with gentle, continuous, repeating motion (rain on a window, a crackling fireplace, a waterfall, \
        a river, falling snow, swaying grass, steam from a cup, city lights in the rain, waves, candle light). Motion that repeats in place, never something travelling across. No people walking in or out, no text.
        \(avoid.isEmpty ? "" : "Do not repeat these: " + avoid.prefix(20).joined(separator: " | ") + "\n")Each scene is one vivid sentence of 12–25 words. Reply with ONLY the 10 scenes, one per line, no numbers.
        """
        let r = try await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 900)
        let lines = r.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•*\"0123456789.)")) }.filter { $0.count > 20 }
        guard !lines.isEmpty else { throw MVError("No scene ideas came back. Try again.") }
        return Array(lines.prefix(10))
    }

    /// Draws the picture the clip starts from. Returns its cost.
    @discardableResult
    public static func makePicture(_ p: inout LoopProject, dir: URL, config: Config = .load()) async throws -> Double {
        let scene = p.scene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scene.isEmpty else { throw MVError("Describe the scene first (or press “Suggest scenes”).") }
        let prompt = "\(scene)\(p.style.isEmpty ? "" : " Style: \(p.style).") A calm, beautiful scene for a long looping background video: a fixed viewpoint, balanced composition, " +
            "elements that can move gently and endlessly (water, light, weather, smoke, leaves)." + (p.clearSky ? " A clear, cloudless sky." : "") + " Widescreen 16:9 landscape composition, no text, no lettering, no watermark."
        let gen = try await OpenRouter.generateImage(prompt: prompt, apiKey: config.openRouterKey)
        let name = "picture-\(Int(Date().timeIntervalSince1970)).\(gen.fileExtension)"
        try gen.data.write(to: dir.appendingPathComponent(name))
        _ = PictureLibrary.save(dir.appendingPathComponent(name), title: p.title, config: config)
        p.pictures.append(name); p.picture = name; p.imagesUSD += gen.costUSD; p.pictureCount += 1
        save(p, dir)
        return gen.costUSD
    }

    /// Uses a picture of your own.
    public static func addPicture(_ p: inout LoopProject, dir: URL, file: URL, config: Config = .load()) throws {
        let name = "picture-own-\(Int(Date().timeIntervalSince1970)).\(file.pathExtension.lowercased())"
        try FileManager.default.copyItem(at: file, to: dir.appendingPathComponent(name))
        _ = PictureLibrary.save(dir.appendingPathComponent(name), title: p.title, config: config)
        p.pictures.append(name); p.picture = name; save(p, dir)
    }

    /// Uses a video clip of your own as the loop.
    public static func addClip(_ p: inout LoopProject, dir: URL, file: URL, config: Config = .load()) throws {
        let name = "clip-own-\(Int(Date().timeIntervalSince1970)).\(file.pathExtension.lowercased())"
        try FileManager.default.copyItem(at: file, to: dir.appendingPathComponent(name))
        _ = PictureLibrary.save(dir.appendingPathComponent(name), title: p.title, config: config)
        p.clips.append(name); p.clip = name
        applyCheck(&p, clip: name, dir: dir)
        save(p, dir)
    }

    /// Written for a seamless loop: the camera never moves, everything that would really move does so naturally and evenly, in motion that repeats in place.
    /// Clouds billow softly where they are instead of sliding across (a slide never comes back, so it shows when the clip repeats); anything that turns or
    /// flows keeps the same direction; nothing enters or leaves; the light stays the same.
    public static func clipPrompt(scene: String, motion: String = "") -> String {
        let m = motion.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(scene.isEmpty ? "" : scene + " ")" +
        (m.isEmpty ? "Everything that would really move in this scene moves naturally (such as water, waves, rain, snow, clouds, fire, smoke, leaves or flickering light). "
                   : "What moves: \(m). Everything else that would naturally move moves gently too. ") +
        "A seamless looping shot: the camera is completely still (locked-off tripod, no zoom, no pan). The motion is continuous, even and repeating for the whole clip: " +
        "ripples, waves, flicker, swaying and falling things repeat in place. Clouds stay where they are and only billow softly, very slowly; they never slide across the sky. " +
        "Anything that turns or flows (a water wheel, a waterfall, a stream) keeps going the same way at the same speed the whole time and never reverses. " +
        "People and animals only move a little in place. Nothing enters or leaves the frame, no sudden events, the lighting stays the same, and the last moment looks like the first. Calm, peaceful, no text."
    }

    /// Looks at the picture once (a cheap cloud vision call, a fraction of a cent) and lists what should move in the loop clip. Returns the text and its cost.
    public static func describeMotion(file: URL, config: Config = .load()) async -> (text: String, cost: Double)? {
        guard let img = loadImage(file, maxPixel: 768) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary); CGImageDestinationFinalize(dest)
        let text = "This picture becomes a 15-second looping video with a completely still camera. Look carefully at THIS picture and list what in it should move, and how, " +
            "so it looks real. Name only things you can actually see in it, in the order of how much they matter. Moving water, waves, rain, snow, fire, smoke and flames move " +
            "naturally (for water, say how it moves near the shore or edge too); clouds and mist only billow softly where they are, very slowly, never drifting across; anything that turns or flows " +
            "(a water wheel, a waterfall, a stream) keeps the same direction the whole time (say which way); people and animals only make small movements in place " +
            "(never walking, riding or travelling across the picture, which would jump back when the clip repeats). Then say which large things stay still. The form, for a quite different picture " +
            "(a snowy cabin): \"snow falling gently, smoke curling from the chimney, firelight flickering in the window, clouds billowing softly in place; the cabin and the pines stay still\". " +
            "One line, 15–40 words. Reply with ONLY that line."
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!); req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue("Bearer \(config.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let content: [[String: Any]] = [["type": "text", "text": text], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + (data as Data).base64EncodedString()]]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": "google/gemini-2.5-flash-lite", "temperature": 0.2, "usage": ["include": true], "messages": [["role": "user", "content": content]]] as [String: Any])
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ch = (j["choices"] as? [[String: Any]])?.first,
              let msg = (ch["message"] as? [String: Any])?["content"] as? String else { return nil }
        let line = msg.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”.")).replacingOccurrences(of: "\n", with: " ")
        guard line.count > 10 else { return nil }
        return (line, ((j["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue ?? 0)
    }

    /// Fills in "what moves" for the picture in use (replacing the description of an earlier picture). Never throws: without it the clip uses the general wording.
    public static func refreshMotion(_ p: inout LoopProject, dir: URL, config: Config = .load()) async {
        guard let pic = p.picture, let r = await describeMotion(file: dir.appendingPathComponent(pic), config: config) else { return }
        p.motion = r.text; p.imagesUSD += r.cost; save(p, dir)
    }
    public static func clipPrice(sharp: Bool, perSecond768: Double) -> Double { Double(clipSeconds) * (sharp ? 0.10 : perSecond768) }

    /// Makes the 15-second loop clip from the picture in use. The order is recorded the moment it is placed, so a paid clip is never lost.
    public static func makeClip(_ p: inout LoopProject, dir: URL, config: Config = .load(), onPhase: ((String) -> Void)? = nil) async throws {
        guard let pic = p.picture, let frame = Pipeline.firstFrameJPEG(file: dir.appendingPathComponent(pic)) else { throw MVError("Make or add the picture first. The clip starts from it.") }
        let scene = p.scene.trimmingCharacters(in: .whitespacesAndNewlines)
        var saved = p
        let clip = try await OpenRouterVideo.generate(prompt: clipPrompt(scene: scene, motion: p.motion), firstFrameJPEG: frame, seconds: clipSeconds, apiKey: config.openRouterKey,
                                                      resolution: p.sharpClip ? "2K" : OpenRouterVideo.resolution,
                                                      onJob: { id in saved.pendingJob = id; save(saved, dir) }, onPhase: onPhase)
        p.pendingJob = nil
        try keepClip(&p, dir: dir, data: clip.data, cost: clip.costUSD ?? clipPrice(sharp: p.sharpClip, perSecond768: OpenRouterVideo.fallbackPricePerSecond), config: config)
    }

    static func keepClip(_ p: inout LoopProject, dir: URL, data: Data, cost: Double, config: Config) throws {
        let name = "clip-\(Int(Date().timeIntervalSince1970)).mp4"
        try data.write(to: dir.appendingPathComponent(name))
        _ = PictureLibrary.saveClip(dir.appendingPathComponent(name), pictureName: nil, title: p.title, config: config)
        p.clips.append(name); p.clip = name; p.videoUSD += cost; p.pendingJob = nil
        applyCheck(&p, clip: name, dir: dir)
        save(p, dir)
    }

    /// A clip that was ordered (and paid for) but not collected because the app was closed: fetch it now. Returns a sentence for the user, or nil.
    public static func recoverClip(_ p: inout LoopProject, dir: URL, config: Config = .load()) async -> String? {
        guard let job = p.pendingJob else { return nil }
        switch await OpenRouterVideo.fetchFinished(jobID: job, apiKey: config.openRouterKey) {
        case .finished(let data, let cost):
            do { try keepClip(&p, dir: dir, data: data, cost: cost ?? clipPrice(sharp: p.sharpClip, perSecond768: OpenRouterVideo.fallbackPricePerSecond), config: config); return "The loop clip that was being made when the app closed has been collected and is now in use." }
            catch { return nil }
        case .failed: p.pendingJob = nil; save(p, dir); return "The loop clip that was being made when the app closed failed at HeyGen. Check your OpenRouter activity before trying again."
        case .running: return "A loop clip ordered earlier is still being made by HeyGen; it is collected the next time you open this project."
        case .unknown: return nil
        }
    }

    /// Checks a clip that has not been checked yet (projects made before the check existed). Returns true when something changed.
    @discardableResult
    public static func checkIfNeeded(_ p: inout LoopProject, dir: URL) -> Bool {
        guard let c = p.clip, FileManager.default.fileExists(atPath: dir.appendingPathComponent(c).path) else { return false }
        if p.trims[c] == nil { applyCheck(&p, clip: c, dir: dir, turning: false); save(p, dir); return true }
        // clips from before the best-loop search: find it, unless you moved the markers yourself
        if p.loopScores[c] == nil, p.clipWarning == nil, p.trims[c] == ClipTrim() { applyBestLoop(&p, clip: c, dir: dir); save(p, dir); return true }
        // loops rated before the slow dissolve and the colour lock: rated again as they now look (the markers stay where they are)
        if p.loopScores[c] != nil, p.loopDrift[c] == nil { rateLoop(&p, clip: c, dir: dir); save(p, dir); return true }
        return false
    }

    // MARK: checking a clip
    /// What a clip check found: moments where the picture turns into its mirror image, cuts to a different shot, or something turning (a wheel)
    /// starts turning the other way, and the longest clean stretch.
    public struct ClipCheck { public var mirrors: [Double]; public var cuts: [Double]; public var turns: [Double] = []; public var best: ClipTrim?; public var length: Double }

    /// Looks through the whole clip (12 pictures a second, small): a sudden change between two pictures is a cut; if the new picture matches the
    /// previous one turned left to right (or upside down), it is a mirror flip. Generated video sometimes does this halfway through.
    public static func checkClip(_ url: URL, turning: Bool = true) -> ClipCheck {
        let asset = AVURLAsset(url: url)
        let length = CMTimeGetSeconds(asset.duration)
        guard let track = asset.tracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: asset) else { return ClipCheck(mirrors: [], cuts: [], best: nil, length: length) }
        let W = 96, H = 54
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        r.add(out); r.startReading()
        var frames: [(t: Double, px: [Float])] = []
        var lastT = -1.0
        while let sb = out.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            if t - lastT < 1.0 / 12 - 0.001 { continue }
            lastT = t
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), bpr = CVPixelBufferGetBytesPerRow(pb)
            var g = [Float](repeating: 0, count: W * H)
            for y in 0..<H { for x in 0..<W { let p = base + y * bpr + x * 4; g[y * W + x] = (Float(p[0]) + 2 * Float(p[1]) + Float(p[2])) / 4 } }
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            frames.append((t, g))
        }
        guard frames.count > 4 else { return ClipCheck(mirrors: [], cuts: [], best: nil, length: length) }
        func diff(_ a: [Float], _ b: [Float], mirrorX: Bool = false, mirrorY: Bool = false) -> Float {
            var s: Float = 0
            for y in 0..<H { for x in 0..<W {
                let bx = mirrorX ? W - 1 - x : x, by = mirrorY ? H - 1 - y : y
                s += abs(a[y * W + x] - b[by * W + bx])
            } }
            return s / Float(W * H)
        }
        let d = (1..<frames.count).map { diff(frames[$0].px, frames[$0 - 1].px) }
        let median = d.sorted()[d.count / 2]
        var mirrors: [Double] = [], cuts: [Double] = []
        for i in d.indices where d[i] > max(4 * median, median + 10) {
            let a = frames[i + 1].px, b = frames[i].px
            let flipped = min(diff(a, b, mirrorX: true), diff(a, b, mirrorY: true), diff(a, b, mirrorX: true, mirrorY: true))
            if flipped < d[i] * 0.5 { mirrors.append(frames[i + 1].t) } else { cuts.append(frames[i + 1].t) }
        }
        let turns = turning ? turnReversals(url) : []
        let events = (mirrors + cuts + turns).sorted()
        guard !events.isEmpty else { return ClipCheck(mirrors: [], cuts: [], best: nil, length: length) }
        // the longest stretch without a flip, a cut or a change of turning direction that faces the same way as the picture the clip started from
        // (after an odd number of flips it is mirrored); either turning direction may be the right one, so only the length counts there
        let bounds = [0.0] + events + [length]
        var best = ClipTrim(start: 0, end: events[0] - 0.1, clean: [0, events[0] - 0.1]), bestLen = 0.0
        var flips = 0
        for k in 0..<(bounds.count - 1) {
            if k > 0, mirrors.contains(bounds[k]) { flips += 1 }
            guard flips % 2 == 0 else { continue }
            let s = k == 0 ? 0 : bounds[k] + (turns.contains(bounds[k]) ? 0.5 : 0.1), e = k == bounds.count - 2 ? length : bounds[k + 1] - (turns.contains(bounds[k + 1]) ? 0.5 : 0.1)
            if e - s > bestLen { bestLen = e - s; best = ClipTrim(start: s, end: e >= length - 0.05 ? nil : e, clean: [s, e]) }
        }
        return ClipCheck(mirrors: mirrors, cuts: cuts, turns: turns, best: best, length: length)
    }

    /// The best loop inside `within` (seconds into the clip): the start and end where the picture AND the motion match most closely, so the
    /// dissolve from the end back to the start joins two nearly identical moments. Loops are kept at least 8 seconds long (shorter ones repeat
    /// too visibly). Parts that drift one way (clouds sliding across) can never match and get their own slow dissolve, so a second search leaves
    /// them out and matches the rest as closely as possible. Returns the trim (its end includes the dissolve) and a score: 1 ≈ as close as two
    /// neighbouring frames, higher is worse.
    public static func bestLoop(_ url: URL, within: ClipTrim = ClipTrim(), minLoop: Double = 8) -> (trim: ClipTrim, score: Double, share: Double)? {
        let fr = SmallFrames(url)
        guard fr.t.count > 24 else { return nil }
        let grey = fr.t.indices.map(fr.grey)
        let length = fr.length
        let lo = fr.t.firstIndex { $0 >= within.start - 0.001 } ?? 0
        let hi = fr.t.lastIndex { $0 <= (within.end ?? length) + 0.001 } ?? (fr.t.count - 1)
        let fps = 12.0, blend = Int((clipBlend * fps).rounded()), minGap = Int(minLoop * fps)
        let clean: [Double]? = within == ClipTrim() ? nil : [within.start, within.end ?? length]
        func d(_ a: Int, _ b: Int, _ w: [Float]?) -> Float {
            var s: Float = 0, n: Float = 0; let x = grey[a], y = grey[b]
            if let w { for k in 0..<x.count { s += abs(x[k] - y[k]) * w[k]; n += w[k] } } else { for k in 0..<x.count { s += abs(x[k] - y[k]) }; n = Float(x.count) }
            return s / max(n, 1)
        }
        // how much the scene changes by itself in one second (the yardstick: a join like half a second of natural change is invisible)
        let oneSecond = stride(from: lo, to: max(lo, hi - 12), by: 3).map { d($0, $0 + 12, nil) }.sorted()
        let typical = max(0.25, oneSecond.isEmpty ? 1 : oneSecond[oneSecond.count / 2])
        let iMax = min(hi - minGap - blend, lo + Int(4 * fps))                   // the loop starts within the first 4 seconds of the usable part
        guard iMax >= lo else { return nil }
        func search(_ w: [Float]?) -> (trim: ClipTrim, raw: Float)? {
            var best: (i: Int, j: Int, cost: Float)? = nil
            for i in lo...iMax {
                for j in (i + minGap)...(hi - blend) {
                    // both sides are on screen during the dissolve: compare the whole stretch, picture and motion
                    var c: Float = 0
                    for k in stride(from: 0, through: blend, by: 2) { c += d(i + k, j + k, w) }
                    c /= Float(blend / 2 + 1)
                    let cost = c - Float(j - i) * 0.002 * typical                     // a slight preference for longer loops
                    if best == nil || cost < best!.cost { best = (i, j, cost) }
                }
            }
            guard let b = best else { return nil }
            var raw: Float = 0
            for k in stride(from: 0, through: blend, by: 2) { raw += d(b.i + k, b.j + k, w) }
            raw /= Float(blend / 2 + 1)
            // the more the join differs, the longer (and so softer) the dissolve, as far as the clip allows
            let score = Double(raw / typical)
            let want = score <= 1.5 ? clipBlend : (score <= 3 ? 2.4 : 3.2)
            let room = min((clean?.last ?? length) - fr.t[b.j], (fr.t[b.j] - fr.t[b.i]) / 3)
            let blendUsed = max(clipBlend, min(want, room))
            let start = fr.t[b.i], end = min(length, fr.t[b.j] + blendUsed)
            return (ClipTrim(start: start, end: end >= length - 0.05 ? nil : end, blend: blendUsed, clean: clean), raw)
        }
        guard let first = search(nil) else { return nil }
        guard let b1 = loopBlend(fr, trim: first.trim) else { return (first.trim, Double(first.raw / typical), 0) }
        // the parts with the slow dissolve hardly matter at the join: search again, matching the rest
        if b1.share > 0.02 {
            let slow = Float(clipBlend / max(clipBlend, b1.slowSeconds))
            let w = b1.mask.map { 1 - $0 * (1 - slow) }
            if let second = search(w), let b2 = loopBlend(fr, trim: second.trim), b2.score < b1.score { return (second.trim, b2.score, b2.share) }
        }
        return (first.trim, b1.score, b1.share)
    }

    /// A score in words: how seamless the loop will look.
    public static func loopQuality(_ score: Double) -> String {
        score <= 1.5 ? "excellent — the end matches the start almost exactly" : (score <= 3 ? "good — the join is a soft dissolve that is hard to spot" : (score <= 5 ? "fair — a gentle dissolve may be noticeable" : "weak — the end and the start look quite different; try making another clip"))
    }

    /// Sets the clip's loop to its best stretch (inside the part without flips, cuts or a change of turning direction).
    public static func applyBestLoop(_ p: inout LoopProject, clip: String, dir: URL) {
        let cur = p.trims[clip] ?? ClipTrim()
        let clean = p.clipWarning != nil ? ClipTrim(start: cur.clean?.first ?? cur.start, end: cur.clean?.last ?? cur.end) : ClipTrim()
        guard let r = bestLoop(dir.appendingPathComponent(clip), within: clean) else { p.loopScores[clip] = 99; return }
        p.trims[clip] = r.trim; p.loopScores[clip] = r.score; p.loopDrift[clip] = r.share
    }

    /// The rating and the slowly dissolving share for the loop as it is now (after you move the markers, or for loops rated before the slow dissolve).
    public static func rateLoop(_ p: inout LoopProject, clip: String, dir: URL) {
        guard let b = loopBlend(dir.appendingPathComponent(clip), trim: p.trims[clip] ?? ClipTrim()) else { return }
        p.loopScores[clip] = b.score; p.loopDrift[clip] = b.share
    }

    /// Checks a new clip; if it flips, cuts or something in it starts turning the other way, the loop is set to the longest clean stretch and a warning is kept.
    static func applyCheck(_ p: inout LoopProject, clip: String, dir: URL, turning: Bool = true) {
        let c = checkClip(dir.appendingPathComponent(clip), turning: turning)
        guard let best = c.best else { p.clipWarning = nil; p.trims[clip] = ClipTrim(); applyBestLoop(&p, clip: clip, dir: dir); return }      // checked and clean: then its best loop
        func clock(_ s: Double) -> String { String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60)) }
        var what: [String] = []
        if !c.mirrors.isEmpty { what.append("turns into its mirror image at \(c.mirrors.map(clock).joined(separator: ", "))") }
        if !c.cuts.isEmpty { what.append("cuts to a different shot at \(c.cuts.map(clock).joined(separator: ", "))") }
        if !c.turns.isEmpty { what.append("has something turning (like a wheel) that starts turning the other way at \(c.turns.map(clock).joined(separator: ", "))") }
        let end = best.end ?? c.length
        p.trims[clip] = best
        p.clipWarning = "This clip " + what.joined(separator: " and ") + ". The loop now uses only \(clock(best.start))–\(clock(end)) (\(String(format: "%.1f", end - best.start)) s, the longest part without it). Move the markers below to change it, or make another clip."
        applyBestLoop(&p, clip: clip, dir: dir)                              // the best loop inside that part
    }

    // MARK: YouTube
    /// The thumbnail and description for the long video `video` (it does not have to exist yet: they go where it is saved).
    /// The thumbnail uses the picture; with only your own clip, its first frame.
    public static func makeYouTubeFiles(_ p: inout LoopProject, dir: URL, video: URL, config: Config = .load()) async throws {
        var source = p.picture.map { dir.appendingPathComponent($0) }
        if source == nil, let c = p.clip {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: dir.appendingPathComponent(c))); g.appliesPreferredTrackTransform = true
            if let img = try? g.copyCGImage(at: .zero, actualTime: nil), let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("thumbnail-source.jpg") as CFURL, "public.jpeg" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary); CGImageDestinationFinalize(dest)
                source = dir.appendingPathComponent("thumbnail-source.jpg")
            }
        }
        guard let pic = source else { throw MVError("Add the picture or the loop clip first: the thumbnail is made from it.") }
        try? ensureAnalysis(&p, dir: dir)
        let listing = await YouTubeKit.loopListing(p, plan: plan(p), config: config)
        let t = thumbWords(p)
        let f = try YouTubeKit.writeFiles(beside: video, picture: pic, thumbTitle: t.title, badge: t.badge, line: t.line, listing: listing)
        p.thumbnail = f.thumbnail.path; p.listing = f.description.path
        save(p, dir)
    }

    /// The automatic words for the thumbnail: the video's title, its length ("8 HOURS", "FULL ALBUM") and "Study · Focus · Relax".
    public static func thumbAuto(_ p: LoopProject) -> (title: String, badge: String, line: String) {
        (p.shownTitle, YouTubeKit.lengthBadge(p, total: plan(p)?.total), "Study · Focus · Relax")
    }
    static func thumbWords(_ p: LoopProject) -> (title: String?, badge: String?, line: String?) {
        let a = thumbAuto(p); return p.thumbText.resolved(title: a.title, badge: a.badge, line: a.line)
    }
    /// Draws the thumbnail again with the words chosen now (the description is not touched).
    public static func redrawThumbnail(_ p: LoopProject, dir: URL) throws {
        guard let path = p.thumbnail else { return }
        let pic = p.picture.map { dir.appendingPathComponent($0) } ?? dir.appendingPathComponent("thumbnail-source.jpg")
        let t = thumbWords(p)
        try YouTubeKit.thumbnail(picture: pic, title: t.title, badge: t.badge, line: t.line, output: URL(fileURLWithPath: path))
    }

    // MARK: making the long video
    /// The size of the finished file, in bytes.
    public static func estimatedBytes(hours: Double) -> Int64 { Int64(hours * 3600 * Double(videoBitrate + audioBitrate) / 8 * 1.03) }

    /// Free space on the disk that holds `folder`.
    public static func freeBytes(at folder: URL) -> Int64? {
        (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// Encodes pictures with the Mac's hardware encoder, a keyframe at the start of each piece, and keeps the encoded pictures in memory.
    final class PieceEncoder {
        private var session: VTCompressionSession?
        private var out: [CMSampleBuffer] = []
        private let lock = NSLock()
        private var next = 0                    // timestamps keep rising across pieces (the encoder needs that); they are set again when written
        let W: Int, H: Int
        init(W: Int, H: Int, bitrate: Int) throws {
            self.W = W; self.H = H
            var s: VTCompressionSession?
            let spec = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true] as CFDictionary
            guard VTCompressionSessionCreate(allocator: nil, width: Int32(W), height: Int32(H), codecType: kCMVideoCodecType_H264, encoderSpecification: spec, imageBufferAttributes: nil,
                                             compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &s) == noErr, let s else { throw MVError("The video encoder could not start.") }
            VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanFalse)
            VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
            VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)   // every picture depends only on earlier ones: a piece can follow any piece
            VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
            VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: LoopVideo.fps as CFNumber)
            VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (LoopVideo.fps * 4) as CFNumber)
            VTCompressionSessionPrepareToEncodeFrames(s)
            session = s
        }
        deinit { if let s = session { VTCompressionSessionInvalidate(s) } }
        func encode(_ pb: CVPixelBuffer, index _: Int, keyframe: Bool) {
            guard let s = session else { return }
            let index = next; next += 1
            let props = keyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
            VTCompressionSessionEncodeFrame(s, imageBuffer: pb, presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(LoopVideo.fps)),
                                            duration: CMTime(value: 1, timescale: CMTimeScale(LoopVideo.fps)), frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sb in
                guard status == noErr, let sb, let self else { return }
                self.lock.lock(); self.out.append(sb); self.lock.unlock()
            }
        }
        /// Everything encoded since the last call, in order.
        func finishPiece() -> [CMSampleBuffer] {
            if let s = session { VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid) }
            lock.lock(); let o = out; out = []; lock.unlock()
            return o.sorted { CMSampleBufferGetPresentationTimeStamp($0) < CMSampleBufferGetPresentationTimeStamp($1) }
        }
    }

    /// Draws one picture of the loop: the clip (repeating, its end dissolving into its start), plus the title screen or the final fade.
    /// Parts that drift one way dissolve slowly (over several seconds around the join) while the rest has the short dissolve, and the colour lock
    /// spreads any slow change of colour over the whole period.
    final class LoopPainter {
        let late: VideoClipSource, early: VideoClipSource       // the end of the loop and its beginning, each read in order
        let origin: Double                                       // clip time where both sources start
        let start: Double, period: Double, fade: Double          // the loop's start point in the clip, its length and the short dissolve
        let blend: LoopBlend?
        let W: Int, H: Int
        let intro: IntroLayer?
        init(clip: URL, W: Int, H: Int, title: String?, trim: ClipTrim = ClipTrim()) {
            let length = CMTimeGetSeconds(AVURLAsset(url: clip).duration)
            let (s, P, f) = LoopVideo.loopTimes(trim, length: length.isFinite && length > 0 ? length : 15)
            let b = LoopVideo.loopBlend(clip, trim: trim)
            let before = b?.before ?? 0, after = b?.after ?? 0
            origin = max(0, s - before)
            let end = s + P + max(f, after) + 1.0 / 30
            late = VideoClipSource(url: clip, maxPixel: max(W, H), start: origin, end: end)
            early = VideoClipSource(url: clip, maxPixel: max(W, H), start: origin, end: end)
            if let d = b?.drift, d != SIMD3(repeating: 1) {
                let g: (Double) -> SIMD3<Float> = { t in LoopVideo.colourGain(d, at: t, start: s, period: P) }
                late.gain = g; early.gain = g
            }
            start = s; period = P; fade = f; blend = b
            self.W = W; self.H = H
            intro = title.map { IntroLayer(title: $0, subject: "", W: W, H: H, end: 8) }
        }
        /// The picture `clipTime` seconds into the clip file.
        private func picture(_ src: VideoClipSource, _ clipTime: Double) -> CGImage? { src.frame(at: max(0, min(clipTime - origin, src.playSeconds - 0.02))) }
        /// One frame of the loop: the end side, the beginning side, and how much of the beginning shows (one number, or a map when parts dissolve slowly).
        func shot(_ t: Double) -> (late: CGImage?, early: CGImage?, alpha: Double, map: CGImage?) {
            let u0 = max(0, t.isFinite ? t : 0).truncatingRemainder(dividingBy: period)
            let u = u0 < period / 2 ? u0 : u0 - period                     // time from the loop's start point (negative: just before it comes round)
            func S(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
            let quick = u < 0 ? 0 : (u >= fade ? 1 : S(u / fade))
            guard let b = blend, b.slowSeconds > 0 else {
                if quick <= 0 { return (picture(late, start + period + u), nil, 0, nil) }
                if quick >= 1 { return (nil, picture(early, start + u), 1, nil) }
                return (picture(late, start + period + u), picture(early, start + u), quick, nil)
            }
            let slow = u <= -b.before ? 0 : (u >= b.after ? 1 : S((u + b.before) / b.slowSeconds))
            if quick == slow, quick <= 0 { return (picture(late, start + period + u), nil, 0, nil) }
            if quick == slow, quick >= 1 { return (nil, picture(early, start + u), 1, nil) }
            var px = b.mask.map { m -> UInt8 in UInt8(max(0, min(255, ((quick + Double(m) * (slow - quick)) * 255).rounded()))) }
            let map = px.withUnsafeMutableBytes { raw -> CGImage? in
                guard let data = CFDataCreate(nil, raw.bindMemory(to: UInt8.self).baseAddress, raw.count), let prov = CGDataProvider(data: data) else { return nil }
                return CGImage(width: LoopBlend.gw, height: LoopBlend.gh, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: LoopBlend.gw, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            }
            return (picture(late, start + period + u), picture(early, start + u), quick, map)
        }
        /// `t` is loop time (0 = the start of a period); the clip is always taken from its repeating part, so every period is identical.
        private var cardLayers: [String: IntroLayer] = [:]
        /// A song's title card: the same look as the title screen, drawn on top of the loop (the loop underneath is never changed).
        func card(_ text: String) -> IntroLayer {
            if let l = cardLayers[text] { return l }
            let l = IntroLayer(title: text, subject: "", W: W, H: H, end: 5); cardLayers[text] = l; return l
        }
        func draw(loopTime t: Double, ctx: CGContext, titleTime: Double? = nil, fadeToBlack: Double = 0, fadeFromBlack: Double = 0, cards: [(text: String, t: Double)] = []) {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let shot = shot(t)
            func frame(_ img: CGImage) -> CGRect {                   // filled to the frame, centred
                let iw = Double(img.width), ih = Double(img.height), target = Double(W) / Double(H)
                let rw = iw / ih > target ? ih * target : iw, rh = rw / target, s = Double(W) / rw
                return CGRect(x: -(iw - rw) / 2 * s, y: -(ih - rh) / 2 * s, width: iw * s, height: ih * s)
            }
            if let a = shot.late { ctx.draw(a, in: frame(a)) }
            if let b = shot.early {
                ctx.saveGState()
                if shot.late != nil {
                    if let map = shot.map { ctx.clip(to: frame(b), mask: map) } else { ctx.setAlpha(CGFloat(shot.alpha)) }
                }
                ctx.draw(b, in: frame(b)); ctx.restoreGState()
            }
            if let tt = titleTime, let intro, tt < 9 {                    // the title screen: holds, then fades into the loop
                let vis = tt < 6 ? 1.0 : max(0, 1 - (tt - 6) / 2.5)
                ctx.saveGState(); ctx.setAlpha(CGFloat(vis)); intro.draw(t: tt, ctx: ctx); ctx.restoreGState()
            }
            for c in cards where c.t >= 0 && c.t < LoopVideo.cardSeconds {     // fade in 1 s, hold 3 s, fade out 1 s
                let vis = c.t < 1 ? c.t : (c.t > LoopVideo.cardSeconds - 1 ? LoopVideo.cardSeconds - c.t : 1.0)
                ctx.saveGState(); ctx.setAlpha(CGFloat(max(0, min(1, vis)))); card(c.text).draw(t: c.t + 2.0, ctx: ctx); ctx.restoreGState()
            }
            let black = max(fadeToBlack, fadeFromBlack)
            if black > 0 { ctx.setFillColor(CGColor(gray: 0, alpha: min(1, black))); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        }
    }

    /// The loop on its own (one period, no title, no sound), for watching in the app: it repeats exactly like it will in the long video.
    /// Full size, so it can be watched full screen and zoomed into.
    public static func makePreview(clip: URL, output: URL, trim: ClipTrim = ClipTrim(), width: Int = 1920, height: Int = 1080) async throws {
        let painter = LoopPainter(clip: clip, W: width, H: height, title: nil, trim: trim)
        let frames = Int((painter.period * Double(fps)).rounded())
        let enc = try PieceEncoder(W: width, H: height, bitrate: width >= 1920 ? 10_000_000 : 2_500_000)
        for f in 0..<frames {
            try Task.checkCancellation()
            guard let pb = pixelBuffer(width, height) else { continue }
            paint(pb) { painter.draw(loopTime: Double(f) / Double(fps), ctx: $0) }
            enc.encode(pb, index: f, keyframe: f == 0)
        }
        let samples = enc.finishPiece()
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        guard let first = samples.first else { throw MVError("The preview could not be made.") }
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: CMSampleBufferGetFormatDescription(first))
        writer.add(vIn); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for sb in samples { while !vIn.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }; vIn.append(sb) }
        vIn.markAsFinished(); await writer.finishWriting()
        if writer.status != .completed { throw MVError("The preview could not be saved: \(writer.error?.localizedDescription ?? "unknown")") }
    }

    /// The size of the finished file for a video of `seconds`.
    public static func estimatedBytes(seconds: Double) -> Int64 { Int64(seconds * Double(videoBitrate + audioBitrate) / 8 * 1.03) }

    /// When each song's title card shows (only when cards are on for every song): as the song becomes the main sound, the first one after the video's title.
    public static func cardTimes(_ p: LoopProject, plan: LoopAudio.Plan) -> [(start: Double, text: String)] {
        guard p.cards == .everySong else { return [] }
        var out: [(Double, String)] = []
        for play in plan.plays where p.tracks.indices.contains(play.track) && p.tracks[play.track].cardOn {
            let s = max(play.start + play.fadeIn / 2, titleScreenEnd + 0.5)
            if s + cardSeconds > plan.songsEnd { continue }
            if let last = out.last, s < last.0 + cardSeconds + 0.5 { continue }          // a very short song: never two cards on top of each other
            let t = p.tracks[play.track].title.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append((s, t.isEmpty ? (p.tracks[play.track].file as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "" : t))
        }
        return out
    }

    /// A short sample of the long video, with sound, exactly as it will be (scene, music, joins, title cards), small enough to make in seconds.
    /// `from` and `seconds` are in the long video's own time.
    public static func renderPreview(_ p0: LoopProject, dir: URL, output: URL, from: Double, seconds: Double, W: Int = 1280, H: Int = 720, progress: ((Double) -> Void)? = nil) async throws {
        guard let clipName = p0.clip else { throw MVError("Make or add the loop clip first.") }
        var p = p0
        try ensureAnalysis(&p, dir: dir)
        guard let plan = plan(p), !plan.plays.isEmpty else { throw MVError("Add a song first.") }
        let start = max(0, min(from, plan.total - 1)), end = min(plan.total, start + seconds)
        let painter = LoopPainter(clip: dir.appendingPathComponent(clipName), W: W, H: H, title: p.cards == .none ? nil : p.shownTitle, trim: p.trim)
        let cards = cardTimes(p, plan: plan), showTitle = p.cards != .none
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
                                                                         AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000])
        vIn.expectsMediaDataInRealTime = false; aIn.expectsMediaDataInRealTime = false
        writer.add(vIn); writer.add(aIn)
        guard writer.startWriting() else { throw MVError("The preview could not be started.") }
        writer.startSession(atSourceTime: .zero)
        // the sound for the whole sample first (it is short), then the pictures
        let mixer = LoopAudio.Mixer(urls: p.tracks.map { dir.appendingPathComponent($0.file) }, plan: plan)
        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var afmt: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &afmt)
        let a0 = Int(start * 48000), aN = Int((end - start) * 48000)
        var chunk = [Float](repeating: 0, count: 4800 * 2)
        let frames = Int(((end - start) * Double(fps)).rounded())
        var vi = 0, ai = 0
        while vi < frames || ai < aN {
            try Task.checkCancellation()
            var did = false
            if ai < aN, aIn.isReadyForMoreMediaData, Double(ai) / 48000 <= Double(vi) / Double(fps) + 1 {
                let n = min(4800, aN - ai)
                try mixer.fill(&chunk, start: a0 + ai, count: n)
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n * 8, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: n * 8, flags: 0, blockBufferOut: &block)
                if let block {
                    chunk.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: n * 8) }
                    var sb: CMSampleBuffer?
                    CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: afmt!, sampleCount: n, presentationTimeStamp: CMTime(value: CMTimeValue(ai), timescale: 48000), packetDescriptions: nil, sampleBufferOut: &sb)
                    if let sb { aIn.append(sb) }
                }
                ai += n; did = true
                if ai >= aN { aIn.markAsFinished() }
            } else if vi < frames, vIn.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool {
                var pb: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                if let pb {
                    let s = start + Double(vi) / Double(fps)
                    let periodFrames = max(fps, Int((painter.period * Double(fps)).rounded()))
                    let f = Int((s * Double(fps)).rounded())
                    let active = cards.compactMap { c in s >= c.start && s < c.start + cardSeconds ? (text: c.text, t: s - c.start) : nil }
                    paint(pb) { painter.draw(loopTime: Double(f % periodFrames) / Double(fps), ctx: $0, titleTime: showTitle && s < 9 ? s : nil,
                                             fadeToBlack: max(0, min(1, (s - plan.songsEnd) / 3)), fadeFromBlack: max(0, 1 - s / 1.5), cards: active) }
                    adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(vi), timescale: CMTimeScale(fps)))
                }
                vi += 1; did = true
                if vi >= frames { vIn.markAsFinished() }
                if vi % 30 == 0 { progress?(Double(vi) / Double(max(1, frames))) }
            }
            if writer.status == .failed { throw MVError("The preview could not be made: \(writer.error?.localizedDescription ?? "unknown")") }
            if !did { try await Task.sleep(nanoseconds: 1_000_000) }
        }
        await writer.finishWriting()
        if writer.status != .completed { throw MVError("The preview could not be saved: \(writer.error?.localizedDescription ?? "unknown")") }
    }

    /// Where the previews start: the beginning, around the first song change (or the first time a single song starts again), and the end.
    public static func previewStarts(_ p: LoopProject) -> (start: Double, change: Double?, end: Double)? {
        guard let plan = plan(p), plan.plays.count >= 1 else { return nil }
        let change = plan.plays.count > 1 ? max(0, plan.plays[1].start - 20) : nil
        return (0, change, max(0, plan.total - 40))
    }

    /// Makes the long video: the loop for as long as the music plays (every song whole), title cards on top if chosen, and a fade to black after the last song.
    ///
    /// Only a few short pieces are drawn and encoded: the opening, one loop, a few seconds around each title card, and the ending. Everything else is the
    /// same encoded loop written again and again (it has a keyframe every two seconds, so a piece can start and stop on any of them without a seam).
    public static func render(_ p0: LoopProject, dir: URL, output: URL, progress: @escaping (String, Double) -> Void) async throws {
        guard let clipName = p0.clip else { throw MVError("Make or add the loop clip first.") }
        guard !p0.tracks.isEmpty else { throw MVError("Add a song first.") }
        var p = p0
        try ensureAnalysis(&p, dir: dir) { ph, f in progress(ph, 0.01 * f) }
        guard let plan = plan(p), !plan.plays.isEmpty else { throw MVError("The songs could not be read.") }
        let need = estimatedBytes(seconds: plan.total)
        if let free = freeBytes(at: output.deletingLastPathComponent()), free < need + 2_000_000_000 {
            throw MVError("This video needs about \(ByteCountFormatter.string(fromByteCount: need, countStyle: .file)) of free disk space, but only \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) is free. Free some space or choose a shorter length.")
        }
        let painter = LoopPainter(clip: dir.appendingPathComponent(clipName), W: width, H: height, title: p.cards == .none ? nil : p.shownTitle, trim: p.trim)
        let periodFrames = max(fps, Int((painter.period * Double(fps)).rounded()))
        let K = fps * 2                                                                   // a keyframe every two seconds of the loop
        let totalFrames = Int(ceil(plan.total * Double(fps)))
        let cards = cardTimes(p, plan: plan)
        let showTitle = p.cards != .none

        func ph(_ f: Int) -> Int { f % periodFrames }
        func onGrid(_ f: Int) -> Bool { ph(f) % K == 0 }
        func floorGrid(_ f: Int) -> Int { var g = max(0, min(f, totalFrames)); while g > 0 && !onGrid(g) { g -= 1 }; return g }
        func ceilGrid(_ f: Int) -> Int { var g = max(0, min(f, totalFrames)); while g < totalFrames && !onGrid(g) { g += 1 }; return g }
        // the drawn pieces: the opening (rising from black, with the title), each title card, the ending (fading to black)
        var ranges: [(Int, Int)] = [(0, ceilGrid(Int(((showTitle ? titleScreenEnd : 0) + 1.6) * Double(fps))))]
        for c in cards { ranges.append((floorGrid(Int(c.start * Double(fps))), ceilGrid(Int(ceil((c.start + cardSeconds) * Double(fps))) + 1))) }
        ranges.append((floorGrid(Int(plan.songsEnd * Double(fps)) - fps / 5), totalFrames))
        ranges.sort { $0.0 < $1.0 }
        var merged: [(Int, Int)] = []
        for r in ranges { if let l = merged.last, r.0 <= l.1 { merged[merged.count - 1].1 = max(l.1, r.1) } else { merged.append(r) } }

        let enc = try PieceEncoder(W: width, H: height, bitrate: videoBitrate)
        func drawFrame(_ f: Int, _ ctx: CGContext) {
            let s = Double(f) / Double(fps)
            let active = cards.compactMap { c in s >= c.start && s < c.start + cardSeconds ? (text: c.text, t: s - c.start) : nil }
            painter.draw(loopTime: Double(ph(f)) / Double(fps), ctx: ctx, titleTime: showTitle && s < 9 ? s : nil,
                         fadeToBlack: max(0, min(1, (s - plan.songsEnd) / 3)), fadeFromBlack: max(0, 1 - s / 1.5), cards: active)
        }
        func encodePiece(_ r: (Int, Int)) throws -> [CMSampleBuffer] {
            for f in r.0..<r.1 {
                try Task.checkCancellation()
                guard let pb = pixelBuffer(width, height) else { continue }
                paint(pb) { drawFrame(f, $0) }
                enc.encode(pb, index: f, keyframe: f == r.0)
            }
            return enc.finishPiece()
        }
        progress("Drawing the loop…", 0.02)
        for f in 0..<periodFrames {                                                       // one plain loop, a keyframe every two seconds
            try Task.checkCancellation()
            guard let pb = pixelBuffer(width, height) else { continue }
            paint(pb) { painter.draw(loopTime: Double(f) / Double(fps), ctx: $0) }
            enc.encode(pb, index: f, keyframe: f % K == 0)
        }
        let middle = enc.finishPiece()
        guard middle.count == periodFrames, let fmt = CMSampleBufferGetFormatDescription(middle[0]) else { throw MVError("The video encoder gave no pictures.") }

        // writing: pieces where something is drawn on top, the encoded loop everywhere else, and the music made continuously
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = false
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fmt)
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: audioBitrate])
        vIn.expectsMediaDataInRealTime = false; aIn.expectsMediaDataInRealTime = false
        writer.add(vIn); writer.add(aIn)
        guard writer.startWriting() else { throw MVError("The video file could not be started: \(writer.error?.localizedDescription ?? "unknown")") }
        writer.startSession(atSourceTime: .zero)

        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var afmt: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &afmt)
        let mixer = LoopAudio.Mixer(urls: p.tracks.map { dir.appendingPathComponent($0.file) }, plan: plan)
        let totalAudio = Int((Double(totalFrames) / Double(fps) * 48000).rounded())
        var chunk = [Float](repeating: 0, count: 4800 * 2)
        func audioBuffer(start: Int, count: Int) throws -> CMSampleBuffer? {
            try mixer.fill(&chunk, start: start, count: count)
            var block: CMBlockBuffer?
            let bytes = count * 8
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr, let block else { return nil }
            chunk.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
            var sb: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: afmt!, sampleCount: count, presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 48000), packetDescriptions: nil, sampleBufferOut: &sb)
            return sb
        }
        var rangeIndex = 0, pieceSamples: [CMSampleBuffer] = [], pieceStart = -1
        func videoSample(_ i: Int) throws -> CMSampleBuffer? {
            while rangeIndex < merged.count && merged[rangeIndex].1 <= i { rangeIndex += 1 }
            let src: CMSampleBuffer
            if rangeIndex < merged.count, i >= merged[rangeIndex].0 {
                if pieceStart != merged[rangeIndex].0 {
                    pieceSamples = try encodePiece(merged[rangeIndex]); pieceStart = merged[rangeIndex].0
                    if let f = pieceSamples.first.flatMap(CMSampleBufferGetFormatDescription), !CMFormatDescriptionEqual(f, otherFormatDescription: fmt) {
                        throw MVError("The video encoder changed its settings between the pieces of the loop. Please report this problem.")
                    }
                }
                guard !pieceSamples.isEmpty else { return nil }
                src = pieceSamples[min(i - pieceStart, pieceSamples.count - 1)]
            } else { src = middle[ph(i)] }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(fps)), presentationTimeStamp: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)),
                                            decodeTimeStamp: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: src, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
            return copy
        }
        var vi = 0, ai = 0, vDone = false, aDone = false
        let started = Date()
        while vi < totalFrames || ai < totalAudio {
            if vi >= totalFrames && !vDone { vIn.markAsFinished(); vDone = true }
            if ai >= totalAudio && !aDone { aIn.markAsFinished(); aDone = true }
            if Task.isCancelled { writer.cancelWriting(); try? FileManager.default.removeItem(at: output); throw CancellationError() }
            let vt = Double(vi) / Double(fps), at = Double(ai) / 48000
            var did = false
            let wantVideo = vi < totalFrames && (ai >= totalAudio || vt <= at)
            if wantVideo, vIn.isReadyForMoreMediaData, let sb = try videoSample(vi) { vIn.append(sb); vi += 1; did = true }
            else if ai < totalAudio, aIn.isReadyForMoreMediaData, (vi >= totalFrames || at < vt + 2), let sb = try audioBuffer(start: ai, count: min(4800, totalAudio - ai)) { aIn.append(sb); ai += min(4800, totalAudio - ai); did = true }
            else if vi < totalFrames, vIn.isReadyForMoreMediaData, vt < at + 2, let sb = try videoSample(vi) { vIn.append(sb); vi += 1; did = true }
            if writer.status == .failed { throw MVError("Writing the video failed: \(writer.error?.localizedDescription ?? "unknown")") }
            if !did { try await Task.sleep(nanoseconds: 1_000_000) }
            if vi % (fps * 60) == 0 && did {
                let el = Date().timeIntervalSince(started), frac = Double(vi) / Double(totalFrames)
                let left = frac > 0.01 ? el / frac * (1 - frac) : 0
                progress("Writing the video: \(clock(vt)) of \(clock(Double(totalFrames) / Double(fps)))" + (left > 30 ? " · about \(Int(left / 60) + 1) min left" : ""), 0.04 + 0.96 * frac)
            }
        }
        if !vDone { vIn.markAsFinished() }
        if !aDone { aIn.markAsFinished() }
        await writer.finishWriting()
        if writer.status != .completed { throw MVError("The video could not be finished: \(writer.error?.localizedDescription ?? "unknown")") }
        progress("Done", 1)
    }

    public static func clock(_ s: Double) -> String { String(format: "%d:%02d:%02d", Int(s) / 3600, (Int(s) / 60) % 60, Int(s) % 60) }

    static func pixelBuffer(_ W: Int, _ H: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, W, H, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        return pb
    }
    static func paint(_ pb: CVPixelBuffer, _ draw: (CGContext) -> Void) {
        CVPixelBufferLockBaseAddress(pb, []); defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb), bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        ctx.interpolationQuality = .high
        draw(ctx)
    }
}
