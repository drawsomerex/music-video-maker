// Making video clips for a section (HeyGen via OpenRouter): the first frame is the section's picture, or the last frame of the clip before.
import Foundation
import ImageIO
import AVFoundation
import CoreGraphics

extension Pipeline {
    /// A picture cropped to fill 1366×768 (16:9) as JPEG: the first frame sent to the video model.
    public static func firstFrameJPEG(file: URL, sharp: Bool = false) -> Data? {
        guard let img = loadImage(file, maxPixel: 2400) else { return nil }
        let W = sharp ? 2560 : 1366, H = sharp ? 1440 : 768
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

    /// A clip that has been ordered (and so paid for) but not yet saved. It is written to disk the moment HeyGen accepts the order, so a clip is never lost
    /// if the app is closed while it is being made.
    public struct PendingClipJob: Codable { public var job: String; public var section: Int; public var seconds: Int; public var offset: Double; public var prompt: String; public var started: Date; public var usedSeconds: Int? = nil; public var sharp: Bool? = nil }
    static let pendingVideoLock = NSRecursiveLock()
    static func pendingURL(_ work: URL) -> URL { work.appendingPathComponent("pending_video_jobs.json") }
    public static func pendingClipJobs(work: URL) -> [PendingClipJob] {
        pendingVideoLock.lock(); defer { pendingVideoLock.unlock() }
        guard let d = try? Data(contentsOf: pendingURL(work)) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([PendingClipJob].self, from: d)) ?? []
    }
    static func savePending(_ jobs: [PendingClipJob], work: URL) throws {
        pendingVideoLock.lock(); defer { pendingVideoLock.unlock() }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if jobs.isEmpty { if FileManager.default.fileExists(atPath: pendingURL(work).path) { try FileManager.default.removeItem(at: pendingURL(work)) } }
        else { try enc.encode(jobs).write(to: pendingURL(work), options: .atomic) }
    }

    static func recordPending(_ job: PendingClipJob, work: URL) throws {
        pendingVideoLock.lock(); defer { pendingVideoLock.unlock() }
        let file = pendingURL(work)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var jobs = FileManager.default.fileExists(atPath: file.path) ? try decoder.decode([PendingClipJob].self, from: Data(contentsOf: file)) : []
        if !jobs.contains(where: { $0.job == job.job }) { jobs.append(job) }
        try savePending(jobs, work: work)
    }

    /// Saves a finished clip into the project: the video, its last frame, the two most prominent features on that frame, and the cost.
    static func finalizeClip(plan: inout Plan, section index: Int, data: Data, costUSD: Double?, jobID: String, seconds: Int, prompt: String, offset: Double, work: URL, config: Config, usedSeconds: Int? = nil, sharp: Bool = false) async throws -> SectionClip {
        guard index >= -1, index < plan.sections.count else { throw MVError("The original picture section is no longer available; the paid job is kept for recovery.") }
        let section = index < 0 ? plan.intro : plan.sections[index]
        if let existing = (section.clips + section.retainedClips).first(where: { $0.jobID == jobID }) { return existing }
        let taskBase = plan
        let fm = FileManager.default
        try fm.createDirectory(at: work.appendingPathComponent("clips"), withIntermediateDirectories: true)
        try fm.createDirectory(at: work.appendingPathComponent("frames"), withIntermediateDirectories: true)
        let stamp = LoopVideo.stableSeed(jobID)
        let file = "clips/section_\(index + 1)_\(stamp).mp4", last = "frames/section_\(index + 1)_\(stamp)_last.jpg"
        try data.write(to: work.appendingPathComponent(file))
        let asset = AVURLAsset(url: work.appendingPathComponent(file))
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else { throw MVError("The finished clip could not be read; its paid job is kept.") }
        let dur = max(0.5, duration)
        let usedEnd = min(dur, Double(usedSeconds ?? seconds))
        let gen = AVAssetImageGenerator(asset: asset); gen.appliesPreferredTrackTransform = true; gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        guard let lastImg = try? gen.copyCGImage(at: CMTime(seconds: max(0, usedEnd - 0.06), preferredTimescale: 600), actualTime: nil),
              let dest = CGImageDestinationCreateWithURL(work.appendingPathComponent(last) as CFURL, "public.jpeg" as CFString, 1, nil) else { throw MVError("Couldn't read the last frame of the clip.") }
        CGImageDestinationAddImage(dest, lastImg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary); CGImageDestinationFinalize(dest)
        var c = SectionClip()
        c.jobID = jobID; c.trimEnd = usedSeconds == 3 ? usedEnd : nil
        c.file = file; c.lastFrame = last; c.seconds = dur; c.offset = offset; c.prompt = prompt
        c.costUSD = costUSD ?? Double(seconds) * (sharp ? 0.10 : OpenRouterVideo.fallbackPricePerSecond)
        plan.totalVideoCostUSD += c.costUSD
        // a copy in the shared Pictures folder, named after the picture it was made from
        let pic = (index < 0 ? plan.intro : plan.sections[index]).selectedCandidate?.libraryName
        c.libraryName = PictureLibrary.saveClip(work.appendingPathComponent(file), pictureName: pic, title: plan.title, config: config)
        // the two most prominent features on the last frame (a cheap look at the picture, a fraction of a cent); the camera moves from the first to the second
        if let loc = await locateFocalPoints(file: work.appendingPathComponent(last), names: [], config: config) {
            c.focalAX = Double(loc.points[0].x); c.focalAY = Double(loc.points[0].y); c.focalBX = Double(loc.points[1].x); c.focalBY = Double(loc.points[1].y)
            plan.totalVideoCostUSD += loc.cost
        }
        // keep a record of every paid job, so a clip can always be traced on OpenRouter
        let rec = "{\"time\":\"\(Date())\",\"section\":\(index),\"job\":\"\(jobID)\",\"seconds\":\(seconds),\"cost\":\(c.costUSD)}\n"
        if let h = try? FileHandle(forWritingTo: work.appendingPathComponent("video_jobs.jsonl")) { h.seekToEndOfFile(); h.write(Data(rec.utf8)); try? h.close() }
        else { try? rec.write(to: work.appendingPathComponent("video_jobs.jsonl"), atomically: true, encoding: .utf8) }
        // Attach the original before removing the recovery record, even if the app closes before the approval screen appears.
        if index < 0 { plan.intro.retainedClips = TimelineEditor.uniqueClips(plan.intro.retainedClips + [c]) }
        else { plan.sections[index].retainedClips = TimelineEditor.uniqueClips(plan.sections[index].retainedClips + [c]) }
        try saveMediaResult(plan, startedFrom: taskBase, section: index, work: work, artwork: false)
        return c
    }

    /// Makes ONE clip of `seconds` from `firstFrame` (a file in the project folder). Saves it, its last frame and the cost; the caller adds it to the section.
    public static func makeClip(plan: inout Plan, section index: Int, seconds: Int, prompt: String, firstFrame: String, offset: Double, work: URL, config: Config = .load(),
                                onJob: ((String) -> Void)? = nil, onPhase: ((String) -> Void)? = nil, options: ClipOptions = ClipOptions()) async throws -> SectionClip {
        guard let frame = firstFrameJPEG(file: work.appendingPathComponent(firstFrame), sharp: options.sharp) else { throw MVError("Couldn't read the picture to start the clip from.") }
        let result = try await OpenRouterVideo.generate(prompt: prompt, firstFrameJPEG: frame, seconds: seconds, apiKey: config.openRouterKey, resolution: options.resolution, onJob: { id in
            try recordPending(PendingClipJob(job: id, section: index, seconds: seconds, offset: offset, prompt: prompt, started: Date(), usedSeconds: options.seconds, sharp: options.sharp), work: work)
            onJob?(id)
        }, onPhase: onPhase)
        let c = try await finalizeClip(plan: &plan, section: index, data: result.data, costUSD: result.costUSD, jobID: result.jobID, seconds: seconds, prompt: prompt, offset: offset, work: work, config: config, usedSeconds: options.seconds, sharp: options.sharp)
        return c
    }

    /// Clips that were ordered but never saved (the app was closed or crashed while they were being made): collects every one that has finished and adds it to its section.
    /// Returns a plain sentence for each clip recovered. A section is not switched to video by this; the owner decides.
    public static func recoverPendingClips(plan: inout Plan, work: URL, config: Config = .load(), fetch: ((String, String) async -> OpenRouterVideo.JobResult)? = nil) async -> [String] {
        var notes: [String] = []
        let originalJobs = pendingClipJobs(work: work)
        var left = originalJobs
        for job in originalJobs {
            let status: OpenRouterVideo.JobResult
            if let fetch { status = await fetch(job.job, config.openRouterKey) } else { status = await OpenRouterVideo.fetchFinished(jobID: job.job, apiKey: config.openRouterKey) }
            switch status {
            case .finished(let data, let cost):
                guard job.section < plan.sections.count, let c = try? await finalizeClip(plan: &plan, section: job.section, data: data, costUSD: cost, jobID: job.job, seconds: job.seconds, prompt: job.prompt, offset: job.offset, work: work, config: config, usedSeconds: job.usedSeconds, sharp: job.sharp ?? false) else { continue }
                // The UI acknowledges this job only after its live state has also saved the retained original.
                notes.append("A video clip for picture \(job.section + 1) that was still being made when the app closed has been saved (\(OpenRouter.formatUSD(c.costUSD))). Choose “Video clip” under that picture to use it.")
            case .failed: left.removeAll { $0.job == job.job }
            case .running, .unknown: break // Never silently abandon an accepted paid job because a day has passed.
            }
        }
        let failedIDs = Set(originalJobs.map(\.job)).subtracting(Set(left.map(\.job)))
        pendingVideoLock.lock(); defer { pendingVideoLock.unlock() }
        do { try savePending(pendingClipJobs(work: work).filter { !failedIDs.contains($0.job) }, work: work) } catch { notes.append("Could not save clip recovery status: \(error.localizedDescription). The job record is retained.") }
        return notes
    }

    /// Called after the live project save. A canceled task cannot erase its recovery record before the UI retained its original.
    public static func acknowledgeClip(_ id: String, work: URL) throws {
        projectWriteLock.lock(); defer { projectWriteLock.unlock() }
        let saved = try loadPlan(work)
        pendingVideoLock.lock(); defer { pendingVideoLock.unlock() }
        guard TimelineEditor.allMediaSections([saved.intro] + saved.sections).flatMap({ $0.clips + $0.retainedClips }).contains(where: { $0.jobID == id && FileManager.default.fileExists(atPath: work.appendingPathComponent($0.file).path) }) else { return }
        try savePending(pendingClipJobs(work: work).filter { $0.job != id }, work: work)
    }

    /// A cheap cloud vision check (about a tenth of a cent): five frames across the clip, looking only for physically impossible things.
    /// Returns a short warning, or nil when nothing looked wrong. Never throws and never redoes anything.
    public static func realismWarning(clipFile: URL, idea: String, config: Config = .load()) async -> (warning: String?, costUSD: Double) {
        guard !config.effectiveOpenRouterKey.isEmpty else { return (nil, 0) }
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

extension Pipeline {
    /// Finds the two focal points in a finished picture with a cheap cloud vision call (about 0.03 cent). With `names` it locates those two things;
    /// without, it picks two clearly different focal points itself. Coordinates are fractions across and down (origin top-left). Never throws; nil when it could not.
    public static func locateFocalPoints(file: URL, names: [String], config: Config = .load()) async -> (points: [CGPoint], names: [String], cost: Double)? {
        guard !config.effectiveOpenRouterKey.isEmpty else { return nil }
        if let r = await locateOnce(file: file, names: names, config: config) { return r }
        return await locateOnce(file: file, names: names, config: config)        // one more try: a cloud call can fail now and then
    }

    static func locateOnce(file: URL, names: [String], config: Config) async -> (points: [CGPoint], names: [String], cost: Double)? {
        guard let img = loadImage(file, maxPixel: 768) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary); CGImageDestinationFinalize(dest)
        let ask = names.count >= 2
            ? "Find these two focal points in the picture and give the centre of each: 1) \(names[0]) 2) \(names[1])."
            : "Choose the TWO main focal points of this picture: clearly different things, as far apart as the scene allows, and give the centre of each."
        let text = ask + " Coordinates are fractions of the picture: x from the left edge (0) to the right edge (1), y from the top edge (0) to the bottom edge (1). Aim at the head and chest of a person, the middle of an object. Reply with ONLY JSON: {\"points\":[{\"name\":\"...\",\"x\":0.3,\"y\":0.5},{\"name\":\"...\",\"x\":0.7,\"y\":0.55}]}"
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!); req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue("Bearer \(config.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let content: [[String: Any]] = [["type": "text", "text": text], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + (data as Data).base64EncodedString()]]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": "google/gemini-2.5-flash-lite", "temperature": 0, "usage": ["include": true], "messages": [["role": "user", "content": content]]] as [String: Any])
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ch = (j["choices"] as? [[String: Any]])?.first, let msg = (ch["message"] as? [String: Any])?["content"] as? String,
              let o = OMLX.json(from: msg) as? [String: Any], let arr = o["points"] as? [[String: Any]], arr.count >= 2 else { return nil }
        let cost = ((j["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue ?? 0
        var pts: [CGPoint] = [], nm: [String] = []
        for e in arr.prefix(2) {
            guard let x = (e["x"] as? NSNumber)?.doubleValue, let y = (e["y"] as? NSNumber)?.doubleValue, (0...1).contains(x), (0...1).contains(y) else { return nil }
            pts.append(CGPoint(x: min(0.92, max(0.08, x)), y: min(0.92, max(0.1, y)))); nm.append((e["name"] as? String) ?? "")
        }
        // two points on top of each other would give no movement: push the second away
        if hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y) < 0.15 { pts[1] = CGPoint(x: pts[0].x < 0.5 ? min(0.85, pts[0].x + 0.3) : max(0.15, pts[0].x - 0.3), y: pts[1].y) }
        return (pts, nm, cost)
    }
}

extension PromptWriter {
    /// Motion prompts (camera and action) for `lyricsPerClip.count` back-to-back clips that continue from the section's picture. Local model; falls back to the idea itself.
    public func clipShots(idea: String, lyricsPerClip: [String], title: String, subject: String, setting: String = "", focal: [String] = []) async -> [String] {
        let n = lyricsPerClip.count
        let fallback = (0..<n).map { _ in "\(idea) A gentle, slow camera move; the same subject keeps moving naturally through the scene." }
        guard n >= 1 else { return [] }
        let segs = lyricsPerClip.enumerated().map { "\($0.offset + 1). lyrics: \($0.element.isEmpty ? "(music only)" : $0.element)" }.joined(separator: "\n")
        let prompt = """
        \(PromptWriter.theme(title: title, subject: subject))
        \(PromptWriter.settingBlock(setting))The first frame of the first clip is this picture: \(idea)
        \(focal.count >= 2 ? "The picture has two focal points: 1) \(focal[0]) 2) \(focal[1]). The action and the camera move from the first focal point toward the second across the clips, animating the first focal point as it goes (a person walks or turns toward it, an animal moves, smoke or water drifts), and the second comes into focus at the end.\n" : "")Write \(n) consecutive video clip prompts. Each clip starts exactly on the last frame of the one before, so every prompt CONTINUES the same scene: same subject, place, light and style; only the action and camera change, gradually, moving the story forward with the lyrics of that clip:
        \(segs)
        Rules: 1–2 concrete sentences each about motion and camera. Everything must be physically possible (gravity, liquids, solid things, normal human and animal motion). Keep the subject in a medium or wide shot with the whole body in frame; no hand gestures, no close-ups, no crowds, no explosions. Bright and well lit. No text on screen.
        Reply with ONLY JSON: {"shots":["...","..."]} with exactly \(n) items.
        """
        guard let reply = try? await omlx.chat(model: omlx.llm, parts: [.text(prompt)], maxTokens: 900), let o = OMLX.json(from: reply) as? [String: Any], let arr = o["shots"] as? [String], arr.count == n,
              !arr.contains(where: { $0.count < 15 }) else { return fallback }
        return arr
    }
}
