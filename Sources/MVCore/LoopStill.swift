// A still picture as the whole video: the picture becomes a short, perfectly steady clip that loops without a seam, so everything else (an album of any length,
// title cards, scene changes, Shorts, the YouTube files) works as it does with a moving clip, and nothing has to be paid for or waited for.
import Foundation
import AVFoundation
import CoreGraphics

extension LoopVideo {
    public static let stillSeconds = 4.0

    /// Writes `picture` as a `stillSeconds`-long 1080p clip (filled to the frame, centred).
    public static func makeStillClip(picture: URL, output: URL, width: Int = 1920, height: Int = 1080) async throws {
        guard let img = loadImage(picture, maxPixel: 3840) else { throw MVError("That picture could not be read.") }
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoMaxKeyFrameIntervalKey: fps, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw MVError("The still clip could not be started: \(writer.error?.localizedDescription ?? "unknown")") }
        writer.startSession(atSourceTime: .zero)
        guard let pb = pixelBuffer(width, height) else { throw MVError("Not enough memory to make the still clip.") }
        paint(pb) { ctx in
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let iw = Double(img.width), ih = Double(img.height), target = Double(width) / Double(height)
            // a picture that is not widescreen (a square album cover) is shown whole with black bars, never cropped
            let scale = abs(iw / ih / target - 1) > PictureFit.tolerance ? min(Double(width) / iw, Double(height) / ih) : max(Double(width) / iw, Double(height) / ih)
            let w = iw * scale, h = ih * scale
            ctx.draw(img, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
        }
        for f in 0..<Int(stillSeconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw MVError("The still clip could not be saved: \(writer.error?.localizedDescription ?? "unknown")") }
    }

    /// Makes the project's picture its clip: no motion, no cost.
    public static func useStill(_ p: inout LoopProject, dir: URL, config: Config = .load()) async throws {
        guard let pic = p.picture else { throw MVError("Add or draw the picture first.") }
        let tmp = dir.appendingPathComponent("still-\(UUID().uuidString.prefix(8)).mp4")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await makeStillClip(picture: dir.appendingPathComponent(pic), output: tmp)
        try addClip(&p, dir: dir, file: tmp, config: config)
        if let c = p.clip { p.versionQualities[c] = "Still picture (no motion)"; p.versionCosts[c] = 0; p.clipWarning = nil }
    }

    /// The length of one full pan-and-zoom cycle, in seconds, unless the path says otherwise.
    public static let kenBurnsSeconds = 20.0

    /// One stop of the camera: where it looks (0–1 across and down the frame, 0.5 / 0.5 the middle) and how close it is (1 = the whole frame).
    public struct KenBurnsPoint: Codable, Equatable {
        public var x = 0.5, y = 0.5, zoom = 1.0
        public init(x: Double = 0.5, y: Double = 0.5, zoom: Double = 1.0) { self.x = x; self.y = y; self.zoom = zoom }
    }
    /// The camera's round trip: it passes through the points in order and then returns smoothly to the first, so the clip repeats without a seam.
    /// At least two points, as many as you like.
    public struct KenBurnsPath: Codable, Equatable {
        public var points: [KenBurnsPoint]
        public var seconds: Double
        public init(points: [KenBurnsPoint], seconds: Double = LoopVideo.kenBurnsSeconds) { self.points = points; self.seconds = seconds }
        /// The gentle default: a slow drift to the right with a little push in, and back.
        public static let standard = KenBurnsPath(points: [KenBurnsPoint(x: 0.4, y: 0.5, zoom: 1.1), KenBurnsPoint(x: 0.62, y: 0.52, zoom: 1.22)])
        /// Always two points or more, every number in range, a sensible length.
        public var cleaned: KenBurnsPath {
            var pts = points.map { KenBurnsPoint(x: $0.x.isFinite ? min(1, max(0, $0.x)) : 0.5, y: $0.y.isFinite ? min(1, max(0, $0.y)) : 0.5, zoom: $0.zoom.isFinite ? min(3, max(1, $0.zoom)) : 1) }
            while pts.count < 2 { pts.append(Self.standard.points[pts.count]) }
            return KenBurnsPath(points: pts, seconds: seconds.isFinite ? min(120, max(6, seconds)) : LoopVideo.kenBurnsSeconds)
        }
        /// Where the camera is `t` of the way round (0 up to 1, wrapping): a smooth closed curve through the points (Catmull-Rom; the zoom is smoothed as a ratio).
        public func camera(at t: Double) -> KenBurnsPoint {
            let c = cleaned.points, n = c.count
            let u = (t - t.rounded(.down)) * Double(n), i = Int(u) % n, f = u - Double(Int(u))
            func at(_ k: Int) -> (Double, Double, Double) { let q = c[((k % n) + n) % n]; return (q.x, q.y, log(q.zoom)) }
            func cr(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                0.5 * (2 * b + (-a + c) * f + (2 * a - 5 * b + 4 * c - d) * f * f + (-a + 3 * b - 3 * c + d) * f * f * f)
            }
            let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
            return KenBurnsPoint(x: min(1, max(0, cr(p0.0, p1.0, p2.0, p3.0))), y: min(1, max(0, cr(p0.1, p1.1, p2.1, p3.1))),
                                 zoom: min(3, max(1, exp(cr(p0.2, p1.2, p2.2, p3.2)))))
        }
    }

    /// Writes `picture` as a clip of one full cycle of `path` (1080p) with a slow camera move through the points and back to the first. The camera
    /// path is closed — the frame after the last is the first — so the clip repeats without a seam. A picture that is not widescreen keeps its black
    /// bars. The camera never looks past the edge of the frame.
    public static func makeKenBurnsClip(picture: URL, output: URL, path: KenBurnsPath = .standard, width: Int = 1920, height: Int = 1080) async throws {
        guard let img = loadImage(picture, maxPixel: 3840) else { throw MVError("That picture could not be read.") }
        let path = path.cleaned
        let frames = max(1, Int((path.seconds * Double(fps)).rounded()))
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoMaxKeyFrameIntervalKey: fps, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw MVError("The Ken Burns clip could not be started: \(writer.error?.localizedDescription ?? "unknown")") }
        writer.startSession(atSourceTime: .zero)
        let W = Double(width), H = Double(height)
        let iw = Double(img.width), ih = Double(img.height), target = W / H
        // the same fitted picture as the still clip: a square cover is shown whole with black bars, never cropped
        let fit = abs(iw / ih / target - 1) > PictureFit.tolerance ? min(W / iw, H / ih) : max(W / iw, H / ih)
        let w = iw * fit, h = ih * fit
        for f in 0..<frames {
            guard let pb = pixelBuffer(width, height) else { throw MVError("Not enough memory to make the Ken Burns clip.") }
            let cam = path.camera(at: Double(f) / Double(frames))           // 0 up to (just under) 1: frame `frames` would be frame 0 again
            let z = cam.zoom
            // the middle of what the camera sees, kept so that what it sees stays inside the frame
            let cx = min(max(cam.x * W, W / (2 * z)), W - W / (2 * z)), cy = min(max(cam.y * H, H / (2 * z)), H - H / (2 * z))
            paint(pb) { ctx in
                ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.interpolationQuality = .high
                ctx.saveGState()
                ctx.translateBy(x: W / 2, y: H / 2)
                ctx.scaleBy(x: z, y: z)
                ctx.translateBy(x: -cx, y: -(H - cy))                         // the picture's y runs up in the context, the point's y runs down
                ctx.draw(img, in: CGRect(x: (W - w) / 2, y: (H - h) / 2, width: w, height: h))
                ctx.restoreGState()
            }
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw MVError("The Ken Burns clip could not be saved: \(writer.error?.localizedDescription ?? "unknown")") }
    }

    /// Makes the project's picture its clip with a slow pan and zoom that loops perfectly: no generated motion, no cost.
    public static func useKenBurns(_ p: inout LoopProject, dir: URL, config: Config = .load()) async throws {
        guard let pic = p.picture else { throw MVError("Add or draw the picture first.") }
        let tmp = dir.appendingPathComponent("kenburns-\(UUID().uuidString.prefix(8)).mp4")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let path = (p.kenBurnsPaths[pic] ?? .standard).cleaned
        try await makeKenBurnsClip(picture: dir.appendingPathComponent(pic), output: tmp, path: path)
        try addClip(&p, dir: dir, file: tmp, config: config)
        guard let c = p.clip else { return }
        p.versionQualities[c] = "Ken Burns (slow pan and zoom on the picture)"; p.versionCosts[c] = 0; p.clipWarning = nil
        // the clip is one closed cycle: play all of it and dissolve nothing at the join, so the camera never runs back over itself
        p.trims[c] = ClipTrim(start: 0, end: path.seconds, blend: 0)
        p.loopScores[c] = 0; p.loopDrift[c] = 0                  // a closed path is a perfect loop (nothing to measure)
    }
}

extension LoopVideo {
    /// A chosen length in words: "10 minutes", "1 hour", "3 hours", "1.5 hours". `dash` gives the form that goes before a noun ("10-minute", "3-hour").
    public static func lengthWords(_ hours: Double, dash: Bool = false) -> String {
        let minutes = Int((hours * 60).rounded())
        let (n, unit): (String, String) = hours < 1 ? ("\(minutes)", "minute") : (hours == hours.rounded() ? "\(Int(hours))" : String(format: "%.1f", hours), "hour")
        return dash ? "\(n)-\(unit)" : "\(n) \(unit)" + (n == "1" ? "" : "s")
    }
    public static let tenMinutes = 10.0 / 60
}
