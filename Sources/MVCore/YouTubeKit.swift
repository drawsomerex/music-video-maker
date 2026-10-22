// Ready for YouTube: a thumbnail (1280×720, the title set on the quieter side of the picture) and a description written for search
// (title, description with keywords up front, chapters for long videos, tags and hashtags). Written on this Mac by the local model, free;
// if the model is not available a careful fixed description is written instead, so there is always one.
import Foundation
import CoreGraphics
import CoreText
import AppKit
import ImageIO

public enum YouTubeKit {
    public static let thumbW = 1280, thumbH = 720

    // MARK: thumbnail
    /// Draws the thumbnail: the picture filling the frame, a soft shade on the side the title goes, the title large (up to three lines),
    /// a small badge above it (e.g. "8 HOURS") and a short line below (e.g. "Study · Focus · Sleep"). The bottom right stays clear (YouTube puts the length there).
    public static func thumbnail(picture: URL, title: String, badge: String?, line: String?, output: URL) throws {
        guard let img = loadImage(picture, maxPixel: 2400) else { throw MVError("The picture for the thumbnail could not be read.") }
        let W = thumbW, H = thumbH, Wd = Double(W), Hd = Double(H)
        let ctx = makeContext(W, H)
        ctx.interpolationQuality = .high
        let iw = Double(img.width), ih = Double(img.height), s = max(Wd / iw, Hd / ih)
        ctx.draw(img, in: CGRect(x: (Wd - iw * s) / 2, y: (Hd - ih * s) / 2, width: iw * s, height: ih * s))

        // the title goes on the side with less going on (away from the people and main objects)
        let subjects = ImageScorer.subjects(image: img)
        let weight = subjects.isEmpty ? 0.5 : subjects.map { Double($0.x) }.reduce(0, +) / Double(subjects.count)
        let left = weight >= 0.5
        let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 0, alpha: 0.72), CGColor(gray: 0, alpha: 0.35), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(shade, start: CGPoint(x: left ? 0 : Wd, y: 0), end: CGPoint(x: left ? Wd * 0.68 : Wd * 0.32, y: 0), options: [])
        let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.35)] as CFArray, locations: [0.55, 1])!
        ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: Wd / 2, y: Hd / 2), startRadius: 0, endCenter: CGPoint(x: Wd / 2, y: Hd / 2), endRadius: Wd * 0.7, options: [.drawsAfterEndLocation])

        let margin = Wd * 0.06, maxW = Wd * 0.50
        let para = NSMutableParagraphStyle(); para.alignment = left ? .left : .right; para.lineSpacing = 0; para.lineHeightMultiple = 0.92
        // the largest title that fits in three lines
        var size = Hd * 0.16, titleImg: CGImage
        repeat {
            let a = NSAttributedString(string: title, attributes: [.font: roundedFont(size: size, weight: .heavy), .foregroundColor: NSColor.white, .paragraphStyle: para, .kern: size * -0.01])
            titleImg = renderTextImage(a, maxWidth: maxW, pad: Hd * 0.02, shadow: true, shadowBlur: Hd * 0.02)
            size *= 0.92
        } while Double(titleImg.height) > Hd * 0.52 && size > Hd * 0.06
        var badgeImg: CGImage? = nil, lineImg: CGImage? = nil
        if let b = badge, !b.isEmpty {
            let a = NSAttributedString(string: b.uppercased(), attributes: [.font: roundedFont(size: Hd * 0.055, weight: .black), .foregroundColor: NSColor(white: 0.08, alpha: 1), .kern: Hd * 0.004])
            badgeImg = renderTextImage(a, maxWidth: maxW, pad: Hd * 0.012, shadow: false, shadowBlur: 0)
        }
        if let l = line, !l.isEmpty {
            let a = NSAttributedString(string: l, attributes: [.font: roundedFont(size: Hd * 0.05, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.92), .paragraphStyle: para])
            lineImg = renderTextImage(a, maxWidth: maxW, pad: Hd * 0.012, shadow: true, shadowBlur: Hd * 0.012)
        }
        // stack them, centred vertically a little above the middle
        let gap = Hd * 0.018
        let total = Double(titleImg.height) + (badgeImg.map { Double($0.height) + gap * 1.6 } ?? 0) + (lineImg.map { Double($0.height) + gap } ?? 0)
        var y = (Hd + total) / 2 + Hd * 0.03                        // top of the block (Core Graphics measures from the bottom)
        func place(_ im: CGImage, inset: Double = 0) {
            let w = Double(im.width), h = Double(im.height)
            let x = left ? margin - inset : Wd - margin - w + inset
            ctx.draw(im, in: CGRect(x: x, y: y - h, width: w, height: h)); y -= h
        }
        if let b = badgeImg {
            let w = Double(b.width), h = Double(b.height), x = left ? margin + Hd * 0.01 : Wd - margin - w - Hd * 0.01
            ctx.setFillColor(CGColor(red: 1, green: 0.84, blue: 0.2, alpha: 1))
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y - h, width: w, height: h), cornerWidth: h * 0.25, cornerHeight: h * 0.25, transform: nil)); ctx.fillPath()
            ctx.draw(b, in: CGRect(x: x, y: y - h, width: w, height: h)); y -= h + gap * 1.6
        }
        place(titleImg, inset: Hd * 0.02)
        if let l = lineImg { y -= gap; place(l, inset: Hd * 0.012) }

        guard let out = ctx.makeImage() else { throw MVError("The thumbnail could not be drawn.") }
        // YouTube takes up to 2 MB
        var q = 0.92
        while true {
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw MVError("The thumbnail could not be saved.") }
            CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary); CGImageDestinationFinalize(dest)
            if data.length < 1_900_000 || q < 0.5 { try (data as Data).write(to: output); return }
            q -= 0.08
        }
    }

    // MARK: description
    public struct Listing { public var title: String; public var description: String; public var tags: [String]; public var hashtags: [String]
        /// As saved next to the video: ready to paste field by field into YouTube Studio.
        public var text: String {
            "TITLE\n\(title)\n\nDESCRIPTION\n\(description)\n\nTAGS (paste into the Tags box)\n\(tags.joined(separator: ", "))\n\nHASHTAGS (also at the end of the description)\n\(hashtags.joined(separator: " "))\n"
        }
    }

    static func clock(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }

    /// Chapters for a long loop: every hour (every quarter of an hour for a video of an hour or less). YouTube shows them on the timeline.
    static func loopChapters(hours: Double) -> String {
        let total = Int(hours * 3600), step = hours <= 1.01 ? 900 : 3600
        var out = ["0:00 Start"], t = step, n = 2
        while t < total - 60 { out.append("\(clock(t)) \(step == 3600 ? "Hour \(n)" : "\(t / 60) minutes")"); t += step; n += 1 }
        return out.joined(separator: "\n")
    }
    public static func hoursText(_ h: Double) -> String { h == h.rounded() ? "\(Int(h)) Hour\(h == 1 ? "" : "s")" : String(format: "%.1f Hours", h) }

    /// Asks the local model for title / description / tags / hashtags as JSON.
    static func ask(_ prompt: String, config: Config) async -> (title: String, description: String, tags: [String], hashtags: [String])? {
        let omlx = OMLX(config: config)
        guard (try? await omlx.ensureReady()) != nil, let r = try? await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 1200),
              let o = OMLX.json(from: r) as? [String: Any], let t = o["title"] as? String, let d = o["description"] as? String, t.count > 8, d.count > 80 else { return nil }
        let tags = (o["tags"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let hashtags = (o["hashtags"] as? [String] ?? []).map { "#" + $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).replacingOccurrences(of: " ", with: "") }.filter { $0.count > 1 }
        return (String(t.prefix(100)), d, tags, hashtags)
    }
    /// Tags fit YouTube's 500-character limit.
    static func fit(_ tags: [String]) -> [String] {
        var out: [String] = [], len = 0
        for t in tags where !out.contains(where: { $0.lowercased() == t.lowercased() }) { if len + t.count + 2 > 480 { break }; out.append(t); len += t.count + 2 }
        return out
    }

    /// The listing for a looping long music video. One song: no chapters. Several: chapters for the first time through the playlist (and a tracklist).
    /// It never says that anything loops or repeats. The description stays inside YouTube's 5,000 characters.
    public static func loopListing(_ p: LoopProject, plan: LoopAudio.Plan? = nil, config: Config = .load()) async -> Listing {
        let hours = hoursText(p.hours), scene = p.scene.isEmpty ? p.motion : p.scene
        let names = p.tracks.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.map { $0.isEmpty ? "Untitled" : $0 }
        let several = names.count > 1
        let music = several ? "\(names.count) songs (\(names.prefix(12).joined(separator: ", "))\(names.count > 12 ? ", …" : ""))" : "the song \"\(names.first ?? p.title)\""
        let prompt = """
        Write a YouTube listing that ranks well in search for a \(hours.lowercased()) video of calm music: \(music) over one peaceful scene. The video is called "\(p.title)".
        Scene: \(scene.isEmpty ? "(not described)" : scene)\(p.style.isEmpty ? "" : "\nLook: \(p.style)")
        Rules: the title is under 70 characters, starts with the strongest search words people use (for example "\(hours) of Study Music" or "Relaxing ... Ambience") and includes "\(p.title)" and the length;
        the description's first two lines (what shows before "more") hold the main keywords naturally; the description has 3 short paragraphs (about 90–150 words in all) on what you see and hear and what it is good for
        (studying, focus, reading, sleep, relaxing, working). Never say that the music or the video loops, repeats or is played again. No false claims and no health or medical claims (say "calm", not "reduces anxiety"),
        never "no lyrics" or "instrumental" (the songs may have words), at most 2 emojis, no links, no timestamps.
        Tags: 15 to 25 search phrases people really type, specific to this scene, this music and its uses. Every tag must be TRUE for this video: no rain, white noise, lofi, \
        piano, nature sounds or other sounds unless the scene or music above says so (the sound is the music only); never "loop" or "looping". Hashtags: exactly 3, no spaces, true for this video.
        Reply with ONLY JSON: {"title":"...","description":"...","tags":["..."],"hashtags":["..."]}
        """
        // chapters: the first time through the playlist only (YouTube needs at least three, the first at 0:00)
        var chapters = ""
        if several, let plan {
            let first = plan.firstRound
            if first.count >= 3 { chapters = "Chapters\n" + first.map { "\(clock(Int($0.start))) \(names[$0.track])" }.joined(separator: "\n") }
        }
        let tracklist = several && chapters.isEmpty ? "Songs\n" + names.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") : ""
        func assemble(_ body: String, _ tags: [String]) -> String {
            var parts = [body]; if !chapters.isEmpty { parts.append(chapters) }; if !tracklist.isEmpty { parts.append(tracklist) }
            parts.append(tags.prefix(3).joined(separator: " "))
            var d = parts.joined(separator: "\n\n")
            while d.count > 4900, chapters.contains("\n") {                         // too long for YouTube: drop chapters from the end
                var lines = chapters.components(separatedBy: "\n"); lines.removeLast(); chapters = lines.joined(separator: "\n")
                parts = [body, chapters, tags.prefix(3).joined(separator: " ")]; d = parts.joined(separator: "\n\n")
            }
            return String(d.prefix(4990))
        }
        if let a = await ask(prompt, config: config) {
            let clean = a.description.replacingOccurrences(of: "looping", with: "", options: .caseInsensitive)
            return Listing(title: a.title, description: assemble(clean, a.hashtags), tags: fit(a.tags.filter { !$0.lowercased().contains("loop") }), hashtags: Array(a.hashtags.prefix(3)))
        }
        // fallback: a careful fixed listing
        let what = scene.isEmpty ? "a peaceful scene" : scene.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let d = """
        \(hours) of calm music for studying, focus, reading and sleep: \(several ? "\(names.count) songs" : "\"\(names.first ?? p.title)\"") over \(what.prefix(1).lowercased() + what.dropFirst()).

        Put it on in the background while you study, work, read or wind down; nothing interrupts your focus.
        """
        let tags = ["\(p.title)", "study music", "\(hours.lowercased()) study music", "relaxing music", "focus music", "calm music", "background music", "sleep music", "music for studying", "music for reading", "music for work", "concentration music", "peaceful music"]
        let hashtags = ["#studymusic", "#relaxingmusic", "#calmmusic"]
        return Listing(title: String("\(p.title) – \(hours) of Calm Study Music".prefix(100)), description: assemble(d, hashtags), tags: fit(tags + names.prefix(8)), hashtags: hashtags)
    }

    /// The listing for a lyric music video (the full lyrics go at the end of the description: search engines read them).
    public static func lyricListing(_ plan: Plan, config: Config = .load()) async -> Listing {
        let lyrics = plan.lines.map(\.text).joined(separator: "\n")
        let prompt = """
        Write a YouTube listing that ranks well in search for the lyric music video of the song "\(plan.title)".
        What the song is about: \(plan.description.isEmpty ? plan.subject : plan.description)\(plan.setting.isEmpty ? "" : "\nSetting of the pictures: \(plan.setting)")
        First lines of the lyrics: \(plan.lines.prefix(6).map(\.text).joined(separator: " / "))
        Rules: the title is under 70 characters and is "\(plan.title) (Lyric Video)" or close to it, optionally with a short hook after a dash; the description's first two lines (shown before "more")
        hold the song title and the main keywords of its story naturally; then one short paragraph about the story and the pictures. No false claims, at most 2 emojis, no links.         Every tag must be true for this song: only people, places, events and eras named in the information above (never others from history), no genre or artist you cannot see there. Do not call it \"official\".
        Tags: 15 to 25 search phrases (song title, "lyrics", the story's people, places and era, the genre if obvious). Hashtags: exactly 3, no spaces.
        Reply with ONLY JSON: {"title":"...","description":"...","tags":["..."],"hashtags":["..."]}
        """
        if let a = await ask(prompt, config: config) {
            return Listing(title: a.title, description: a.description + "\n\nLyrics\n" + lyrics + "\n\n" + a.hashtags.prefix(3).joined(separator: " "), tags: fit([plan.title, "\(plan.title) lyrics"] + a.tags), hashtags: Array(a.hashtags.prefix(3)))
        }
        let about = plan.description.isEmpty ? plan.subject : plan.description
        let tag = plan.title.replacingOccurrences(of: " ", with: "").filter { $0.isLetter || $0.isNumber }
        let d = "\(plan.title) — lyric video.\(about.isEmpty ? "" : " " + about)\n\nLyrics\n\(lyrics)\n\n#\(tag) #lyrics #lyricvideo"
        return Listing(title: String("\(plan.title) (Lyric Video)".prefix(100)), description: d, tags: fit([plan.title, "\(plan.title) lyrics", "\(plan.title) lyric video", "lyrics", "lyric video", "song with lyrics"]), hashtags: ["#\(tag)", "#lyrics", "#lyricvideo"])
    }

    /// Writes "<video name> – thumbnail.jpg" and "<video name> – YouTube.txt" next to the video. Returns both files.
    @discardableResult
    public static func writeFiles(beside video: URL, picture: URL, thumbTitle: String, badge: String?, line: String?, listing: Listing) throws -> (thumbnail: URL, description: URL) {
        let base = video.deletingPathExtension().lastPathComponent, dir = video.deletingLastPathComponent()
        let thumb = dir.appendingPathComponent("\(base) – thumbnail.jpg"), desc = dir.appendingPathComponent("\(base) – YouTube.txt")
        try thumbnail(picture: picture, title: thumbTitle, badge: badge, line: line, output: thumb)
        try listing.text.write(to: desc, atomically: true, encoding: .utf8)
        return (thumb, desc)
    }
}
