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

public struct LoopProject: Codable, Equatable {
    public var id = UUID().uuidString
    public var title = ""
    public var screenTitle = ""                 // the title screen at the start (empty = the song title)
    public var songFile = ""                    // the song, copied into the project folder
    public var songSeconds = 0.0
    public var scene = ""                       // what the scene shows
    public var style = ""                       // the look (an art style), optional
    public var pictures: [String] = []          // every picture made or added, oldest first
    public var picture: String?                 // the one the clip starts from
    public var clips: [String] = []             // every loop clip made or added
    public var clip: String?                    // the one in use
    public var sharpClip = false                // 2K instead of 768p (sharper, about three times the price)
    public var pendingJob: String?              // a HeyGen job that was paid for but not collected yet (the app was closed)
    public var hours = 1.0
    public var imagesUSD = 0.0, videoUSD = 0.0, pictureCount = 0
    public var output: String?                  // the last long video made (full path)
    public init() {}
    public var shownTitle: String { screenTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : screenTitle }

    enum CodingKeys: String, CodingKey { case id, title, screenTitle, songFile, songSeconds, scene, style, pictures, picture, clips, clip, sharpClip, pendingJob, hours, imagesUSD, videoUSD, pictureCount, output }
    public init(from d: Decoder) throws {                          // every field has a default, so older loop projects always open
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""; screenTitle = try c.decodeIfPresent(String.self, forKey: .screenTitle) ?? ""
        songFile = try c.decodeIfPresent(String.self, forKey: .songFile) ?? ""; songSeconds = try c.decodeIfPresent(Double.self, forKey: .songSeconds) ?? 0
        scene = try c.decodeIfPresent(String.self, forKey: .scene) ?? ""; style = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        pictures = try c.decodeIfPresent([String].self, forKey: .pictures) ?? []; picture = try c.decodeIfPresent(String.self, forKey: .picture)
        clips = try c.decodeIfPresent([String].self, forKey: .clips) ?? []; clip = try c.decodeIfPresent(String.self, forKey: .clip)
        sharpClip = try c.decodeIfPresent(Bool.self, forKey: .sharpClip) ?? false; pendingJob = try c.decodeIfPresent(String.self, forKey: .pendingJob)
        hours = try c.decodeIfPresent(Double.self, forKey: .hours) ?? 1
        imagesUSD = try c.decodeIfPresent(Double.self, forKey: .imagesUSD) ?? 0; videoUSD = try c.decodeIfPresent(Double.self, forKey: .videoUSD) ?? 0
        pictureCount = try c.decodeIfPresent(Int.self, forKey: .pictureCount) ?? 0; output = try c.decodeIfPresent(String.self, forKey: .output)
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

    // MARK: project folder
    public static func isLoopProject(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(fileName).path) }
    public static func load(_ dir: URL) throws -> LoopProject { try JSONDecoder().decode(LoopProject.self, from: Data(contentsOf: dir.appendingPathComponent(fileName))) }
    public static func save(_ p: LoopProject, _ dir: URL) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(p).write(to: dir.appendingPathComponent(fileName), options: .atomic)
        SpendLedger.record(p.id, SpendLedger.Entry(title: p.title + " (looping video)", path: dir.path, imagesUSD: p.imagesUSD, videoUSD: p.videoUSD, pictures: p.pictureCount))
    }

    /// A new looping project for a song: its own folder "<title> – looping video" (never overwriting another), with the song copied in.
    public static func create(song: URL, title: String, config: Config = .load()) async throws -> (LoopProject, URL) {
        let fm = FileManager.default
        let base = (title.isEmpty ? song.deletingPathExtension().lastPathComponent : title).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var dir = config.projectsRoot.appendingPathComponent("\(base) – looping video"), n = 2
        while fm.fileExists(atPath: dir.path) { dir = config.projectsRoot.appendingPathComponent("\(base) – looping video \(n)"); n += 1 }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var p = LoopProject(); p.title = title.isEmpty ? base : title
        p.songFile = "song." + (song.pathExtension.isEmpty ? "mp3" : song.pathExtension.lowercased())
        try fm.copyItem(at: song, to: dir.appendingPathComponent(p.songFile))
        p.songSeconds = (try? await AVURLAsset(url: dir.appendingPathComponent(p.songFile)).load(.duration)).map(CMTimeGetSeconds) ?? 0
        save(p, dir)
        return (p, dir)
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
    public static func suggestScenes(title: String, style: String, avoid: [String] = [], config: Config = .load()) async throws -> [String] {
        let omlx = OMLX(config: config); try await omlx.ensureReady()
        let prompt = """
        A song called "\(title)" will play for hours as calm background (study) music over ONE looping video scene.\(style.isEmpty ? "" : " The look: \(style).")
        Suggest 10 different scenes that loop beautifully: a fixed viewpoint with gentle, continuous, repeating motion (rain on a window, a crackling fireplace, drifting clouds, \
        a river, falling snow, swaying grass, steam from a cup, city lights in the rain, waves, candle light). No people walking in or out, no text.
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
            "elements that can move gently and endlessly (water, light, weather, smoke, leaves). Widescreen 16:9 landscape composition, no text, no lettering, no watermark."
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
        p.clips.append(name); p.clip = name; save(p, dir)
    }

    /// Written for a seamless loop: the camera never moves, the motion is gentle and cyclical, nothing enters or leaves, the light stays the same.
    public static func clipPrompt(scene: String) -> String {
        "\(scene) A seamless looping shot: the camera is completely still (locked-off tripod, no zoom, no pan). Only gentle, continuous, repeating natural motion " +
        "(such as water, rain, snow, clouds, fire, smoke, leaves or light flickering) moving at a steady pace for the whole clip. Nothing enters or leaves the frame, " +
        "no sudden events, the lighting stays the same, and the last moment looks like the first. Calm, peaceful, no text."
    }
    public static func clipPrice(sharp: Bool, perSecond768: Double) -> Double { Double(clipSeconds) * (sharp ? 0.10 : perSecond768) }

    /// Makes the 15-second loop clip from the picture in use. The order is recorded the moment it is placed, so a paid clip is never lost.
    public static func makeClip(_ p: inout LoopProject, dir: URL, config: Config = .load(), onPhase: ((String) -> Void)? = nil) async throws {
        guard let pic = p.picture, let frame = Pipeline.firstFrameJPEG(file: dir.appendingPathComponent(pic)) else { throw MVError("Make or add the picture first. The clip starts from it.") }
        let scene = p.scene.trimmingCharacters(in: .whitespacesAndNewlines)
        var saved = p
        let clip = try await OpenRouterVideo.generate(prompt: clipPrompt(scene: scene.isEmpty ? "A calm scene." : scene), firstFrameJPEG: frame, seconds: clipSeconds, apiKey: config.openRouterKey,
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

    // MARK: making the long video
    /// The size of the finished file, in bytes.
    public static func estimatedBytes(hours: Double) -> Int64 { Int64(hours * 3600 * Double(videoBitrate + audioBitrate) / 8 * 1.03) }

    /// Free space on the disk that holds `folder`.
    public static func freeBytes(at folder: URL) -> Int64? {
        (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// The song as one seamless loop: the silence at both ends cut off, and the last `songBlend` seconds blended into the beginning.
    final class SongLoop {
        let samples: [Float]          // interleaved stereo, 48 kHz
        let length: Int               // frames in the trimmed song
        let blend: Int                // frames of overlap
        var period: Int { length - blend }
        init(url: URL) async throws {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw MVError("The song has no sound to use.") }
            let reader = try AVAssetReader(asset: asset)
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                                                                              AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false])
            reader.add(out); reader.startReading()
            var all: [Float] = []
            while let sb = out.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
                let n = CMBlockBufferGetDataLength(bb)
                var chunk = [Float](repeating: 0, count: n / 4)
                chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: n, destination: $0.baseAddress!) }
                all += chunk
            }
            // trim the silence at both ends (quieter than about −50 dB), keeping 50 ms
            let frames = all.count / 2, threshold: Float = 0.003
            var first = 0, last = frames - 1
            while first < frames && max(abs(all[first * 2]), abs(all[first * 2 + 1])) < threshold { first += 1 }
            while last > first && max(abs(all[last * 2]), abs(all[last * 2 + 1])) < threshold { last -= 1 }
            first = max(0, first - 2400); last = min(frames - 1, last + 2400)
            guard last - first > 48000 * 4 else { throw MVError("The song is too short or silent to loop.") }
            samples = Array(all[(first * 2)...(last * 2 + 1)])
            length = last - first + 1
            blend = min(Int(songBlend * 48000), length / 4)
        }
        /// Fills `out` with `count` stereo frames of the endless loop starting at frame `start` (equal-power blend at every seam).
        func fill(_ out: inout [Float], start: Int, count: Int) {
            for i in 0..<count {
                let n = start + i, k = n / period, j = n % period
                var l = samples[j * 2], r = samples[j * 2 + 1]
                if k > 0 && j < blend {                                       // the next play fades in while the previous one fades out
                    let x = Double(j) / Double(blend)
                    let fin = Float(sin(x * .pi / 2)), fout = Float(cos(x * .pi / 2))
                    l = l * fin + samples[(j + period) * 2] * fout; r = r * fin + samples[(j + period) * 2 + 1] * fout
                }
                out[i * 2] = l; out[i * 2 + 1] = r
            }
        }
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
    final class LoopPainter {
        let src: VideoClipSource
        let period: Double
        let W: Int, H: Int
        let intro: IntroLayer?
        init(clip: URL, W: Int, H: Int, title: String?) {
            src = VideoClipSource(url: clip, maxPixel: max(W, H))
            period = max(1, src.playSeconds - min(LoopVideo.clipBlend, src.playSeconds / 3))
            self.W = W; self.H = H
            intro = title.map { IntroLayer(title: $0, subject: "", W: W, H: H, end: 8) }
        }
        /// `t` is loop time (0 = the start of a period); the clip is always taken from its repeating part, so every period is identical.
        func draw(loopTime t: Double, ctx: CGContext, titleTime: Double? = nil, fadeToBlack: Double = 0, fadeFromBlack: Double = 0) {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let shot = src.looped(at: t + period, sceneLength: .infinity, blend: LoopVideo.clipBlend)
            func put(_ img: CGImage) {
                let iw = Double(img.width), ih = Double(img.height), target = Double(W) / Double(H)
                let rw = iw / ih > target ? ih * target : iw, rh = rw / target, s = Double(W) / rw
                ctx.draw(img, in: CGRect(x: -(iw - rw) / 2 * s, y: -(ih - rh) / 2 * s, width: iw * s, height: ih * s))
            }
            if let m = shot.main { put(m) }
            if let o = shot.over { ctx.saveGState(); ctx.setAlpha(CGFloat(shot.overAlpha)); put(o); ctx.restoreGState() }
            if let tt = titleTime, let intro, tt < 9 {                    // the title screen: holds, then fades into the loop
                let vis = tt < 6 ? 1.0 : max(0, 1 - (tt - 6) / 2.5)
                ctx.saveGState(); ctx.setAlpha(CGFloat(vis)); intro.draw(t: tt, ctx: ctx); ctx.restoreGState()
            }
            let black = max(fadeToBlack, fadeFromBlack)
            if black > 0 { ctx.setFillColor(CGColor(gray: 0, alpha: min(1, black))); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        }
    }

    /// The loop on its own (one period, no title, no sound), for watching in the app: it repeats exactly like it will in the long video.
    public static func makePreview(clip: URL, output: URL, width: Int = 960, height: Int = 540) async throws {
        let painter = LoopPainter(clip: clip, W: width, H: height, title: nil)
        let frames = Int((painter.period * Double(fps)).rounded())
        let enc = try PieceEncoder(W: width, H: height, bitrate: 2_500_000)
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

    /// Makes the long video: title screen → the loop for `hours` → fade-out, with the song looping seamlessly underneath.
    public static func render(_ p: LoopProject, dir: URL, output: URL, progress: @escaping (String, Double) -> Void) async throws {
        guard let clipName = p.clip else { throw MVError("Make or add the loop clip first.") }
        let need = estimatedBytes(hours: p.hours)
        if let free = freeBytes(at: output.deletingLastPathComponent()), free < need + 2_000_000_000 {
            throw MVError("This video needs about \(ByteCountFormatter.string(fromByteCount: need, countStyle: .file)) of free disk space, but only \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) is free. Free some space or choose fewer hours.")
        }
        progress("Preparing the song…", 0.01)
        let song = try await SongLoop(url: dir.appendingPathComponent(p.songFile))
        let painter = LoopPainter(clip: dir.appendingPathComponent(clipName), W: width, H: height, title: p.shownTitle)
        let periodFrames = max(fps, Int((painter.period * Double(fps)).rounded()))
        let introPeriods = max(1, Int(ceil(9.0 * Double(fps) / Double(periodFrames))))         // the title screen fits inside the opening piece
        let totalPeriods = max(introPeriods + 2, Int((p.hours * 3600 * Double(fps) / Double(periodFrames)).rounded()))
        let totalFrames = totalPeriods * periodFrames
        let introFrames = introPeriods * periodFrames

        // the three pieces: opening (with the title, rising from black), one plain loop, the ending (fading to black)
        let enc = try PieceEncoder(W: width, H: height, bitrate: videoBitrate)
        func piece(_ frames: Int, _ draw: (Int, CGContext) -> Void, label: String, from: Double, to: Double) throws -> [CMSampleBuffer] {
            for f in 0..<frames {
                try Task.checkCancellation()
                guard let pb = pixelBuffer(width, height) else { continue }
                paint(pb) { draw(f, $0) }
                enc.encode(pb, index: f, keyframe: f == 0)
                if f % 30 == 0 { progress(label, from + (to - from) * Double(f) / Double(frames)) }
            }
            return enc.finishPiece()
        }
        let t = { (f: Int) in Double(f % periodFrames) / Double(fps) }
        let opening = try piece(introFrames, { f, ctx in
            let s = Double(f) / Double(fps)
            painter.draw(loopTime: t(f), ctx: ctx, titleTime: s, fadeFromBlack: max(0, 1 - s / 1.5))
        }, label: "Drawing the title screen…", from: 0.02, to: 0.06)
        let middle = try piece(periodFrames, { f, ctx in painter.draw(loopTime: t(f), ctx: ctx) }, label: "Drawing the loop…", from: 0.06, to: 0.09)
        let ending = try piece(periodFrames, { f, ctx in
            let left = Double(periodFrames - f) / Double(fps)
            painter.draw(loopTime: t(f), ctx: ctx, fadeToBlack: max(0, 1 - left / 3.0))
        }, label: "Drawing the ending…", from: 0.09, to: 0.12)
        guard let fmt = middle.first.flatMap(CMSampleBufferGetFormatDescription), !opening.isEmpty, !ending.isEmpty else { throw MVError("The video encoder gave no pictures.") }
        for other in [opening.first, ending.first].compactMap({ $0.flatMap(CMSampleBufferGetFormatDescription) }) where !CMFormatDescriptionEqual(other, otherFormatDescription: fmt) {
            throw MVError("The video encoder changed its settings between the pieces of the loop. Please report this problem.")
        }

        // writing: the same encoded loop again and again, and the song generated continuously
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
        let totalAudio = Int((Double(totalFrames) / Double(fps) * 48000).rounded())
        let fadeIn = 48000, fadeOut = 48000 * 5
        var chunk = [Float](repeating: 0, count: 4800 * 2)
        func audioBuffer(start: Int, count: Int) -> CMSampleBuffer? {
            song.fill(&chunk, start: start, count: count)
            for i in 0..<count {
                let n = start + i
                var g: Float = 1
                if n < fadeIn { g = Float(n) / Float(fadeIn) }
                if n > totalAudio - fadeOut { g = min(g, Float(totalAudio - n) / Float(fadeOut)) }
                if g < 1 { chunk[i * 2] *= g; chunk[i * 2 + 1] *= g }
            }
            var block: CMBlockBuffer?
            let bytes = count * 8
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr, let block else { return nil }
            chunk.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
            var sb: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: afmt!, sampleCount: count, presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 48000), packetDescriptions: nil, sampleBufferOut: &sb)
            return sb
        }
        func videoSample(_ i: Int) -> CMSampleBuffer? {
            let src: CMSampleBuffer
            if i < introFrames { src = opening[min(i, opening.count - 1)] }
            else if i >= totalFrames - periodFrames { src = ending[min(i - (totalFrames - periodFrames), ending.count - 1)] }
            else { src = middle[min((i - introFrames) % periodFrames, middle.count - 1)] }
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(fps)), presentationTimeStamp: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)),
                                            decodeTimeStamp: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: src, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
            return copy
        }
        var vi = 0, ai = 0, vDone = false, aDone = false
        let started = Date()
        while vi < totalFrames || ai < totalAudio {
            // a finished track is closed at once: the writer otherwise waits for more of it before taking the other
            if vi >= totalFrames && !vDone { vIn.markAsFinished(); vDone = true }
            if ai >= totalAudio && !aDone { aIn.markAsFinished(); aDone = true }
            if Task.isCancelled { writer.cancelWriting(); try? FileManager.default.removeItem(at: output); throw CancellationError() }
            let vt = Double(vi) / Double(fps), at = Double(ai) / 48000
            var did = false
            let wantVideo = vi < totalFrames && (ai >= totalAudio || vt <= at)
            if wantVideo, vIn.isReadyForMoreMediaData, let sb = videoSample(vi) { vIn.append(sb); vi += 1; did = true }
            else if ai < totalAudio, aIn.isReadyForMoreMediaData, (vi >= totalFrames || at < vt + 2), let sb = audioBuffer(start: ai, count: min(4800, totalAudio - ai)) { aIn.append(sb); ai += min(4800, totalAudio - ai); did = true }
            else if vi < totalFrames, vIn.isReadyForMoreMediaData, vt < at + 2, let sb = videoSample(vi) { vIn.append(sb); vi += 1; did = true }
            if writer.status == .failed { throw MVError("Writing the video failed: \(writer.error?.localizedDescription ?? "unknown")") }
            if !did { try await Task.sleep(nanoseconds: 1_000_000) }
            if vi % (fps * 60) == 0 && did {
                let el = Date().timeIntervalSince(started), frac = Double(vi) / Double(totalFrames)
                let left = frac > 0.01 ? el / frac * (1 - frac) : 0
                progress("Writing the video: \(clock(vt)) of \(clock(Double(totalFrames) / Double(fps)))" + (left > 30 ? " · about \(Int(left / 60) + 1) min left" : ""), 0.12 + 0.88 * frac)
            }
        }
        if !vDone { vIn.markAsFinished() }
        if !aDone { aIn.markAsFinished() }
        await writer.finishWriting()
        if writer.status != .completed { throw MVError("The video could not be finished: \(writer.error?.localizedDescription ?? "unknown")") }
        progress("Done", 1)
    }

    static func clock(_ s: Double) -> String { String(format: "%d:%02d:%02d", Int(s) / 3600, (Int(s) / 60) % 60, Int(s) % 60) }

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
