// Frame composition and the video writer: parallel Core Graphics frames into hardware H.264 + AAC.
import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics

/// Composes any frame of the video from the plan; stateless per call, so frames render in parallel.
public final class FrameComposer: @unchecked Sendable {
    let W: Int, H: Int
    let hasIntro: Bool
    let dyn: Bool                       // dynamic Shorts style kit
    let style: ShortStyle
    let scenes: [PhotoScene]            // [intro,] s0, s1, …
    let bounds: [Double]                // bounds[i] = video time of the transition scene i-1 → i (bounds[0] unused)
    let kinds: [TransitionKind]
    let lyrics: LyricRendering
    let intro: IntroLayer?
    let hook: HookTitleLayer?
    let cta: CTALayer?
    let beats: [Double]
    let loop: Bool
    /// Caption block position (fraction of height from the bottom). Read on every frame, so it can change live in the preview.
    public var captionBottom: Double? { didSet { lyrics.bottom = captionBottom; loopLock.lock(); loopFirstImage = nil; loopLock.unlock() } }
    let D: Double
    let fadeIn: Double, fadeOut: Double
    public let totalDuration: Double
    private var loopFirstImage: CGImage?
    private let loopLock = NSLock()

    /// `short` renders only that song range (vertical, no title card, times shifted to start at 0).
    public init(plan fullPlan: Plan, work: URL, settings: VideoSettings, short: ShortClip? = nil, beats: [Double] = []) {
        W = settings.width; H = settings.height
        let plan = short.map { FrameComposer.clip(fullPlan, to: $0) } ?? fullPlan
        hasIntro = short == nil
        dyn = short?.dynamic ?? false
        style = ShortStyle.make(seed: short?.styleSeed ?? 1, clip: short)
        self.beats = beats
        let whole = short?.isWhole(of: fullPlan.songDuration) ?? false
        loop = dyn && (short?.loop ?? false)
        D = dyn ? (style.calm ? 0.65 : 0.40) : 1.1
        fadeIn = short == nil ? 0.6 : (dyn ? 0 : 0.25)
        fadeOut = short == nil ? 1.5 : (loop && dyn ? 0 : (short?.fadeOut ?? (whole && !loop ? 1.5 : (dyn ? 0.4 : 0.5))))
        let off = plan.audioOffset
        var b: [Double] = hasIntro ? [0, plan.introDuration] : [0]
        for (i, s) in plan.sections.enumerated() where i > 0 { b.append(s.start + off) }
        totalDuration = plan.songDuration + off
        bounds = b
        // A 16:9 picture shown in a 9:16 frame is cropped to its height, so it must be decoded ~H·zoom tall (long side ≈ that × 16/9).
        // Calm motion never zooms past ~1.45×, so it needs far fewer pixels (and megabytes) than punchy.
        let maxPx = settings.vertical ? Int(Double(settings.height) * (dyn && !style.calm ? 1.7 : 1.45) * 16.0 / 9.0) : Int(Double(settings.width) * 1.85)
        let all = hasIntro ? [plan.intro] + plan.sections : plan.sections
        // Pictures are decoded lazily (when their section starts) and released afterwards; see `releaseImages`.
        let boxes: [ImageBox?] = all.map { s in s.selectedCandidate?.fullFile.map { ImageBox(url: work.appendingPathComponent($0), maxPixel: maxPx) } }
        var sc: [PhotoScene] = []
        var prevMode = -1
        for i in all.indices {
            let a = i == 0 ? 0 : b[i] - D / 2
            let e = i + 1 < b.count ? b[i + 1] + D / 2 : totalDuration
            let c = all[i].selectedCandidate
            let sceneSeed = all[i].seed &+ UInt64(i)
            var modeRng = SeededRNG(sceneSeed &+ 99)
            // Default: sweep across the whole picture towards the subject (left→right if it sits on the right, else right→left), never the same direction twice running.
            // Roughly one scene in five is a diagonal glide for variety.
            var candidateMode = (c?.focusX ?? 0.5) >= 0.5 ? 2 : 3
            if modeRng.next() % 5 == 0 { candidateMode = 4 }
            else if candidateMode == prevMode { candidateMode = candidateMode == 2 ? 3 : 2 }
            prevMode = candidateMode
            let sec = all[i]
            let useClips = sec.useClips && !sec.clips.isEmpty
            if useClips { candidateMode = 0 }                                  // after the clips the last frame holds, then a gentle push-in
            let sceneBox: ImageBox? = useClips ? (sec.clips.last.map { ImageBox(url: work.appendingPathComponent($0.lastFrame), maxPixel: maxPx) } ?? boxes[i]) : boxes[i]
            let scene = PhotoScene(box: sceneBox, a: a, b: max(e, a + 1), seed: sceneSeed,
                                 focus: CGPoint(x: c?.focusX ?? 0.5, y: c?.focusY ?? 0.5), vertical: settings.vertical,
                                 shotInterval: dyn ? style.shotInterval : nil, shake: dyn && style.shake, calm: dyn && style.calm,
                                 video: useClips ? nil : c?.videoFile.map { VideoClipSource(url: work.appendingPathComponent($0), maxPixel: maxPx, start: c?.videoStart ?? 0, end: c?.videoEnd) }, beats: beats, preferredMode: candidateMode, camera: useClips ? nil : c?.cameraPath)
            if useClips {
                scene.clipTrack = sec.clips.map { ClipSegment(source: VideoClipSource(url: work.appendingPathComponent($0.file), maxPixel: maxPx), offset: $0.offset, seconds: $0.seconds) }
                if let last = sec.clips.last { scene.kbStart = a + last.offset + last.seconds }
            }
            // the subjects the automatic camera travels between (people first); for the frame after a video clip, from the clip's last frame
            let subjectFile = useClips ? sec.clips.last?.lastFrame : (c?.thumbFile ?? c?.fullFile)
            scene.subjects = subjectFile.map { ImageScorer.subjects(fileURL: work.appendingPathComponent($0)) } ?? []
            scene.tail = useClips
            sc.append(scene)
        }
        scenes = sc
        var rng = SeededRNG((dyn ? short!.styleSeed : 0xC0FFEE) ^ UInt64(plan.title.hashValue & 0xFFFF)); var last = -1; var ks: [TransitionKind] = []
        for _ in all.indices {
            let (k, id) = dyn ? TransitionKind.short(&rng, pool: style.cuts, calm: style.calm, avoiding: last) : TransitionKind.random(&rng, avoiding: last)
            ks.append(k); last = id
        }
        kinds = ks
        if dyn && style.textMode != .sweep {
            let mode: WordLayer.Mode = style.textMode == .pill ? .pill : (style.textMode == .stack ? .stack : .pop)
            lyrics = WordLayer(lines: plan.lines, W: W, H: H, timeOffset: off + fullPlan.captionShift, mode: mode, accent: style.accent, window: 0...totalDuration)
        } else {
            lyrics = LyricLayer(lines: plan.lines, W: W, H: H, timeOffset: off + fullPlan.captionShift, vertical: settings.vertical, window: 0...totalDuration)
        }
        captionBottom = short?.captionY ?? fullPlan.captionY
        lyrics.bottom = captionBottom
        intro = hasIntro ? IntroLayer(title: plan.title, subject: plan.subject, W: W, H: H, end: plan.introDuration) : nil
        if dyn, let sh = short {
            // The opening title is the song's title (unless the user typed something else).
            var text = sh.hook.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { text = plan.title }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?—-"))
            hook = HookTitleLayer(text: text, W: W, H: H, mode: style.titleMode, accent: style.accent)
            cta = sh.cta.isEmpty ? nil : CTALayer(text: sh.cta, W: W, H: H, start: max(2.5, totalDuration - 2.6), accent: style.accent)
        } else { hook = nil; cta = nil }
    }

    /// The song cut to [start, end]: sections clipped and shifted, lyrics shifted, no title card.
    static func clip(_ p: Plan, to c: ShortClip) -> Plan {
        var q = p
        q.songDuration = c.duration; q.audioOffset = 0; q.introDuration = 0
        q.lines = p.lines.map { l in var l = l; l.words = l.words.map { var w = $0; w.start -= c.start; w.end -= c.start; return w }; return l }
        q.sections = p.sections.filter { $0.end > c.start && $0.start < c.end }.map { s in
            var s = s; s.start = max(s.start, c.start) - c.start; s.end = min(s.end, c.end) - c.start; return s }
        if q.sections.isEmpty { q.sections = [p.sections.first ?? p.intro] }
        // No picture change in the first/last 3 s: the title and the ending sit on one steady picture.
        if q.sections.count > 1, q.sections[0].duration < 3.0 { q.sections.removeFirst(); q.sections[0].start = 0 }
        if q.sections.count > 1, let l = q.sections.last, l.duration < 3.0 { q.sections.removeLast(); q.sections[q.sections.count - 1].end = c.duration }
        return q
    }

    /// Frees the pictures of scenes that are finished (called by the renderer between batches).
    public func releaseImages(before t: Double) {
        if loop, loopFirstImage == nil, t > 1.0 { _ = cachedLoopFirstFrame() }
        for s in scenes where s.b + 1.5 < t { s.box?.unload() }
    }

    private func cachedLoopFirstFrame() -> CGImage? {
        loopLock.lock()
        if let img = loopFirstImage { loopLock.unlock(); return img }
        loopLock.unlock()
        let first = makeContext(W, H)
        renderBase(t: 0, ctx: first)
        let img = first.makeImage()
        loopLock.lock()
        loopFirstImage = img
        loopLock.unlock()
        return img
    }

    func drawScene(_ i: Int, t: Double, ctx: CGContext) {
        scenes[i].draw(t: t, ctx: ctx, W: W, H: H)
        if i == 0, let intro { intro.draw(t: t, ctx: ctx) }
    }

    func pulseScale(_ t: Double) -> Double {
        var s = 1.0
        if dyn {
            let settle = style.calm ? 1.1 : 0.85, amt = style.calm ? 0.025 : 0.055
            if t < settle {
                let p = 0.5 * (1.0 + cos(.pi * (t / settle)))
                s *= 1 + amt * p
            }
            if style.pulse > 0 {
                let attack = 0.045
                let decay = 0.16
                var env = 0.0
                for b in beats {
                    let dt = t - (b - attack)
                    if dt >= 0 && dt < attack {
                        env = max(env, smooth(dt / attack))
                    } else if dt >= attack && dt < attack + 0.55 {
                        env = max(env, exp(-(dt - attack) / decay))
                    }
                }
                s *= 1 + style.pulse * env
            }
        }
        return s
    }

    func renderBase(t: Double, ctx: CGContext) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.saveGState()
        let ps = pulseScale(t)
        if ps != 1 { ctx.translateBy(x: Double(W) / 2, y: Double(H) / 2); ctx.scaleBy(x: ps, y: ps); ctx.translateBy(x: -Double(W) / 2, y: -Double(H) / 2) }
        var tr = -1
        for i in 1..<max(1, bounds.count) where t >= bounds[i] - D / 2 && t < bounds[i] + D / 2 { tr = i; break }
        if tr > 0 {
            let p = (t - (bounds[tr] - D / 2)) / D
            Transition.draw(kinds[tr], p: p, ctx: ctx, W: W, H: H,
                            drawA: { self.drawScene(tr - 1, t: t, ctx: ctx) }, drawB: { self.drawScene(tr, t: t, ctx: ctx) })
        } else {
            var cur = 0
            for i in 1..<max(1, bounds.count) where t >= bounds[i] + D / 2 { cur = i }
            drawScene(cur, t: t, ctx: ctx)
        }
        ctx.restoreGState()
        if let hook, hook.dimAmount(t: t) > 0 { ctx.setFillColor(CGColor(gray: 0, alpha: hook.dimAmount(t: t))); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        let vis = lyrics.visibleAmount(t: t)
        lyrics.drawScrim(ctx: ctx, strength: 0.42 + 0.58 * vis)
        lyrics.draw(t: t, ctx: ctx)
        hook?.draw(t: t, ctx: ctx)
        cta?.draw(t: t, ctx: ctx, captionBottom: captionBottom)
        var fade = 0.0
        if fadeIn > 0 { fade = max(fade, 1 - clamp01(t / fadeIn)) }
        if fadeOut > 0 { fade = max(fade, clamp01((t - (totalDuration - fadeOut)) / fadeOut)) }
        if fade > 0 { ctx.setFillColor(CGColor(gray: 0, alpha: fade)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
    }

    public func render(t: Double, ctx: CGContext) {
        renderBase(t: t, ctx: ctx)
        // Loop ending: dissolve back into the cached opening frame so the replay is seamless.
        let ld = 0.5
        if loop && t > totalDuration - ld {
            if let img = cachedLoopFirstFrame() {
                ctx.saveGState(); ctx.setAlpha(smooth((t - (totalDuration - ld)) / ld))
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H)); ctx.restoreGState()
            }
        }
    }

    public func still(at t: Double) -> CGImage {
        let ctx = makeContext(W, H); render(t: t, ctx: ctx); return ctx.makeImage()!
    }
}

extension LyricLayer {
    func visibleAmount(t: Double) -> Double {
        var vis = 0.0
        for v in visuals where t >= v.show && t <= v.hide {
            vis = max(vis, min(smooth((t - v.show) / 0.3), 1 - smooth((t - (v.hide - 0.22)) / 0.22)))
        }
        return vis
    }
}

public enum VideoRenderer {
    public static func render(plan: Plan, work: URL, output: URL, settings: VideoSettings = .init(), short: ShortClip? = nil, progress: ProgressHandler? = nil) async throws {
        if let s = short, s.duration > ShortClip.maxDuration + 0.05 { throw MVError("A YouTube Short can't be longer than 3:00 (this clip is \(Int(s.duration / 60)):\(String(format: "%02d", Int(s.duration) % 60))). Shorten it, or use Whole song to split it into parts.") }
        progress?("Preparing frames", 0)
        let wantsBeats = short.map {
            let st = ShortStyle.make(seed: $0.styleSeed, clip: $0)
            return $0.dynamic && (st.pulse > 0 || !st.calm)
        } ?? false
        let beats: [Double] = wantsBeats ? await BeatDetector.beats(audioPath: Pipeline.audioURL(plan, work: work).path, start: short!.start, end: short!.end, work: work) : []
        try Task.checkCancellation()
        let composer = FrameComposer(plan: plan, work: work, settings: settings, short: short, beats: beats)
        let W = settings.width, H = settings.height, fps = settings.fps
        let total = Int(ceil(composer.totalDuration * Double(fps)))

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true      // moov atom first → YouTube-friendly fast start

        var comp: [String: Any] = [
            AVVideoAverageBitRateKey: settings.bitrate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoAllowFrameReorderingKey: true,
        ]
        if !settings.hevc { comp[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let vSettings: [String: Any] = [
            AVVideoCodecKey: settings.hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: W, AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: comp,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        writer.add(vIn)

        // Audio: song placed at `audioOffset` on a composition timeline, 1.5 s fade-out, re-encoded to AAC 256 kbps.
        let audioAsset = AVURLAsset(url: Pipeline.audioURL(plan, work: work))
        guard let srcTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else { throw MVError("No audio track in file") }
        let srcDur = try await audioAsset.load(.duration)
        let composition = AVMutableComposition()
        let cTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let ts: CMTimeScale = 48000
        let audioLen: Double
        if let c = short {
            let s = max(0, c.start), e = min(CMTimeGetSeconds(srcDur), c.end)
            try cTrack.insertTimeRange(CMTimeRange(start: CMTime(seconds: s, preferredTimescale: ts), duration: CMTime(seconds: e - s, preferredTimescale: ts)), of: srcTrack, at: .zero)
            audioLen = e - s
        } else {
            try cTrack.insertTimeRange(CMTimeRange(start: .zero, duration: srcDur), of: srcTrack, at: CMTime(seconds: plan.audioOffset, preferredTimescale: ts))
            audioLen = plan.audioOffset + CMTimeGetSeconds(srcDur)
        }
        let params = AVMutableAudioMixInputParameters(track: cTrack)
        // Shorts with the dynamic kit fade the music up under the opening title; a looping Short only dips for a few ms at the seam.
        let fadeLen = short == nil ? 1.5 : ((short!.dynamic && short!.loop) ? 0.12 : (short!.fadeOut ?? ((short!.isWhole(of: plan.songDuration) && !short!.loop) ? 1.5 : 0.5)))
        if let s = short { params.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: s.dynamic ? 1.8 : 0.15, preferredTimescale: ts))) }
        params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: CMTime(seconds: max(0, audioLen - fadeLen), preferredTimescale: ts), duration: CMTime(seconds: min(fadeLen, audioLen), preferredTimescale: ts)))
        let mix = AVMutableAudioMix(); mix.inputParameters = [params]
        let reader = try AVAssetReader(asset: composition)
        let aOut = AVAssetReaderAudioMixOutput(audioTracks: [cTrack], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        aOut.audioMix = mix
        reader.add(aOut)
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000])
        aIn.expectsMediaDataInRealTime = false
        writer.add(aIn)

        guard reader.startReading() else { throw MVError("Audio reader failed: \(reader.error?.localizedDescription ?? "?")") }
        guard writer.startWriting() else { throw MVError("Writer failed: \(writer.error?.localizedDescription ?? "?")") }
        writer.startSession(atSourceTime: .zero)

        // Fanless Macs (Air) throttle when hot: back off the thread count when the system asks for it.
        func workers() -> Int {
            let pi = ProcessInfo.processInfo, cores = max(2, pi.activeProcessorCount)
            switch pi.thermalState { case .critical: return max(2, cores / 4); case .serious: return max(2, cores / 2); default: return pi.isLowPowerModeEnabled ? max(2, cores / 2) : cores }
        }
        let startTime = Date()
        let vq = DispatchQueue(label: "mv.video"), aq = DispatchQueue(label: "mv.audio")
        let group = DispatchGroup()
        group.enter(); group.enter()
        nonisolated(unsafe) var next = 0
        nonisolated(unsafe) var pendingQueue: [(Int, CVPixelBuffer)] = []
        nonisolated(unsafe) var vDone = false, aDone = false, cancelled = false

        func cleanupTempFiles() {
            if let siblings = try? FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path) {
                for f in siblings where f.hasPrefix(output.lastPathComponent + ".sb-") { try? FileManager.default.removeItem(at: output.deletingLastPathComponent().appendingPathComponent(f)) }
            }
        }

        vIn.requestMediaDataWhenReady(on: vq) {
            guard !vDone else { return }
            while vIn.isReadyForMoreMediaData {
                if cancelled {
                    pendingQueue.removeAll()
                    vDone = true; vIn.markAsFinished(); group.leave(); return
                }
                if !pendingQueue.isEmpty {
                    let (frameIdx, buf) = pendingQueue.removeFirst()
                    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(fps)))
                    let written = frameIdx + 1
                    if written % max(1, workers()) == 0 || written == total {
                        let done = Double(written) / Double(total)
                        let el = Date().timeIntervalSince(startTime)
                        progress?("Rendering video (\(String(format: "%.1f", Double(written) / max(el, 0.01))) fps)", done)
                    }
                    continue
                }
                if next >= total {
                    vDone = true; vIn.markAsFinished(); group.leave(); return
                }
                let n = min(workers() * 2, total - next)
                composer.releaseImages(before: Double(next) / Double(fps))
                var bufs = [CVPixelBuffer?](repeating: nil, count: n)
                let base = next
                bufs.withUnsafeMutableBufferPointer { bp in
                    let ptr = bp.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: n) { k in
                        if cancelled { return }
                        var pb: CVPixelBuffer?
                        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buf = pb else { return }
                        CVPixelBufferLockBaseAddress(buf, [])
                        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8,
                                            bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: sRGB, bitmapInfo: bitmapInfo)!
                        ctx.interpolationQuality = .high
                        composer.render(t: Double(base + k) / Double(fps), ctx: ctx)
                        CVPixelBufferUnlockBaseAddress(buf, [])
                        ptr[k] = buf
                    }
                }
                for k in 0..<n { if let b = bufs[k] { pendingQueue.append((base + k, b)) } }
                next += n
            }
        }
        aIn.requestMediaDataWhenReady(on: aq) {
            guard !aDone else { return }
            while aIn.isReadyForMoreMediaData {
                if cancelled { aDone = true; aIn.markAsFinished(); group.leave(); return }
                if let sb = aOut.copyNextSampleBuffer() { aIn.append(sb) } else { aDone = true; aIn.markAsFinished(); group.leave(); return }
            }
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in group.notify(queue: .global()) { c.resume() } }
        } onCancel: {
            cancelled = true
        }
        if cancelled || Task.isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            cleanupTempFiles()
            throw CancellationError()
        }
        await writer.finishWriting()
        cleanupTempFiles()
        if writer.status != .completed { throw MVError("Encoding failed: \(writer.error?.localizedDescription ?? "unknown")") }
        progress?("Done", 1)
    }
}
