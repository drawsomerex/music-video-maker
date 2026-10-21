// Making video clips for a section (HeyGen via OpenRouter): the first frame is the section's picture, or the last frame of the clip before.
import Foundation
import ImageIO
import AVFoundation
import CoreGraphics

extension Pipeline {
    /// A picture cropped to fill 1366×768 (16:9) as JPEG: the first frame sent to the video model.
    static func firstFrameJPEG(file: URL) -> Data? {
        guard let img = loadImage(file, maxPixel: 2400) else { return nil }
        let W = 1366, H = 768
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let iw = Double(img.width), ih = Double(img.height), s = max(Double(W) / iw, Double(H) / ih)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: (Double(W) - iw * s) / 2, y: (Double(H) - ih * s) / 2, width: iw * s, height: ih * s))
        guard let out = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, out, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Makes ONE clip of `seconds` from `firstFrame` (a file in the project folder). Saves it, its last frame and the cost; the caller adds it to the section.
    public static func makeClip(plan: inout Plan, section index: Int, seconds: Int, prompt: String, firstFrame: String, offset: Double, work: URL, config: Config = .load(),
                                onJob: ((String) -> Void)? = nil, onPhase: ((String) -> Void)? = nil) async throws -> SectionClip {
        guard let frame = firstFrameJPEG(file: work.appendingPathComponent(firstFrame)) else { throw MVError("Couldn't read the picture to start the clip from.") }
        let result = try await OpenRouterVideo.generate(prompt: prompt, firstFrameJPEG: frame, seconds: seconds, apiKey: config.openRouterKey, onJob: onJob, onPhase: onPhase)
        let fm = FileManager.default
        try fm.createDirectory(at: work.appendingPathComponent("clips"), withIntermediateDirectories: true)
        try fm.createDirectory(at: work.appendingPathComponent("frames"), withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let file = "clips/section_\(index + 1)_\(stamp).mp4", last = "frames/section_\(index + 1)_\(stamp)_last.jpg"
        try result.data.write(to: work.appendingPathComponent(file))
        let asset = AVURLAsset(url: work.appendingPathComponent(file))
        let dur = max(0.5, CMTimeGetSeconds(asset.duration))
        let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        guard let lastImg = try? gen.copyCGImage(at: CMTime(seconds: max(0, dur - 0.06), preferredTimescale: 600), actualTime: nil),
              let dest = CGImageDestinationCreateWithURL(work.appendingPathComponent(last) as CFURL, "public.jpeg" as CFString, 1, nil) else { throw MVError("Couldn't read the last frame of the clip.") }
        CGImageDestinationAddImage(dest, lastImg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary); CGImageDestinationFinalize(dest)
        var c = SectionClip()
        c.file = file; c.lastFrame = last; c.seconds = dur; c.offset = offset; c.prompt = prompt
        c.costUSD = result.costUSD ?? Double(seconds) * OpenRouterVideo.fallbackPricePerSecond
        plan.totalVideoCostUSD += c.costUSD
        // keep a record of every paid job, so a clip can always be traced on OpenRouter
        let rec = "{\"time\":\"\(Date())\",\"section\":\(index),\"job\":\"\(result.jobID)\",\"seconds\":\(seconds),\"cost\":\(c.costUSD)}\n"
        if let h = try? FileHandle(forWritingTo: work.appendingPathComponent("video_jobs.jsonl")) { h.seekToEndOfFile(); h.write(Data(rec.utf8)); try? h.close() }
        else { try? rec.write(to: work.appendingPathComponent("video_jobs.jsonl"), atomically: true, encoding: .utf8) }
        try savePlan(plan, work)
        return c
    }

    /// A cheap cloud vision check (about a tenth of a cent): five frames across the clip, looking only for physically impossible things.
    /// Returns a short warning, or nil when nothing looked wrong. Never throws and never redoes anything.
    public static func realismWarning(clipFile: URL, idea: String, config: Config = .load()) async -> (warning: String?, costUSD: Double) {
        let asset = AVURLAsset(url: clipFile); let dur = max(1, CMTimeGetSeconds(asset.duration))
        let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 640, height: 640)
        var content: [[String: Any]] = [["type": "text", "text": "These are 5 frames spread evenly across one AI-generated video clip, in order. Do NOT compare it with any description: judge only whether it looks physically possible.\nDoes the clip contain PHYSICAL IMPOSSIBILITIES or obvious AI glitches: wrong number of limbs or fingers, duplicated or merging people or objects, things passing through solid things, floating or teleporting objects, liquids behaving wrongly, unnatural walking, clothing changing, the main subject changing identity, melting or warping shapes? Flag only clear impossibilities (angle changes and tiny facial details are fine). Reply with ONLY JSON: {\"ok\": true or false, \"problems\": \"one short sentence, or empty\"}"]]
        for k in 0..<5 {
            guard let cg = try? gen.copyCGImage(at: CMTime(seconds: dur * (Double(k) + 0.5) / 5, preferredTimescale: 600), actualTime: nil) else { continue }
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary); CGImageDestinationFinalize(dest)
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + (data as Data).base64EncodedString()]])
        }
        guard content.count > 2 else { return (nil, 0) }
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!); req.httpMethod = "POST"; req.timeoutInterval = 90
        req.setValue("Bearer \(config.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": "google/gemini-2.5-flash-lite", "temperature": 0, "usage": ["include": true], "messages": [["role": "user", "content": content]]] as [String: Any])
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ch = (j["choices"] as? [[String: Any]])?.first, let msg = (ch["message"] as? [String: Any])?["content"] as? String else { return (nil, 0) }
        let cost = ((j["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue ?? 0
        guard let o = OMLX.json(from: msg) as? [String: Any], (o["ok"] as? Bool) == false else { return (nil, cost) }
        let p = (o["problems"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (p.isEmpty ? "Something in this clip may look physically wrong." : p, cost)
    }
}

extension PromptWriter {
    /// Motion prompts (camera and action) for `lyricsPerClip.count` back-to-back clips that continue from the section's picture. Local model; falls back to the idea itself.
    public func clipShots(idea: String, lyricsPerClip: [String], title: String, subject: String, setting: String = "") async -> [String] {
        let n = lyricsPerClip.count
        let fallback = (0..<n).map { _ in "\(idea) A gentle, slow camera move; the same subject keeps moving naturally through the scene." }
        guard n >= 1 else { return [] }
        let segs = lyricsPerClip.enumerated().map { "\($0.offset + 1). lyrics: \($0.element.isEmpty ? "(music only)" : $0.element)" }.joined(separator: "\n")
        let prompt = """
        \(PromptWriter.theme(title: title, subject: subject))
        \(PromptWriter.settingBlock(setting))The first frame of the first clip is this picture: \(idea)
        Write \(n) consecutive video clip prompts. Each clip starts exactly on the last frame of the one before, so every prompt CONTINUES the same scene: same subject, place, light and style; only the action and camera change, gradually, moving the story forward with the lyrics of that clip:
        \(segs)
        Rules: 1–2 concrete sentences each about motion and camera. Everything must be physically possible (gravity, liquids, solid things, normal human and animal motion). Keep the subject in a medium or wide shot with the whole body in frame; no hand gestures, no close-ups, no crowds, no explosions. Bright and well lit. No text on screen.
        Reply with ONLY JSON: {"shots":["...","..."]} with exactly \(n) items.
        """
        guard let reply = try? await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 900), let o = OMLX.json(from: reply) as? [String: Any], let arr = o["shots"] as? [String], arr.count == n,
              !arr.contains(where: { $0.count < 15 }) else { return fallback }
        return arr
    }
}
