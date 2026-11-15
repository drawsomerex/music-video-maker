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

    /// The length of one full pan-and-zoom cycle, in seconds: the clip is exactly this long, so the last picture leads straight back to the first.
    public static let kenBurnsSeconds = 20.0
    /// How far the picture grows halfway through the cycle (6 %), and so how much room the pan has before it would reach an edge.
    static let kenBurnsZoom = 0.06

    /// Writes `picture` as a `kenBurnsSeconds`-long 1080p clip with a slow, subtle camera move: the picture drifts sideways and grows a little,
    /// then comes back. The camera path is closed — frame N (at `fps`) is frame 0 — so the clip repeats without a seam, unlike a generated clip
    /// whose end can only be dissolved into its start. A picture that is not widescreen keeps its black bars: the camera moves around the picture
    /// in the middle of the frame, never filling the bars.
    public static func makeKenBurnsClip(picture: URL, output: URL, seconds: Double = kenBurnsSeconds, width: Int = 1920, height: Int = 1080) async throws {
        guard let img = loadImage(picture, maxPixel: 3840) else { throw MVError("That picture could not be read.") }
        let T = max(1, seconds), frames = max(1, Int((T * Double(fps)).rounded()))
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoMaxKeyFrameIntervalKey: fps, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input)
        guard writer.startWriting() else { throw MVError("The Ken Burns clip could not be started: \(writer.error?.localizedDescription ?? "unknown")") }
        writer.startSession(atSourceTime: .zero)
        let iw = Double(img.width), ih = Double(img.height), target = Double(width) / Double(height)
        // the same fitted picture as the still clip: a square cover is shown whole with black bars, never cropped
        let fit = abs(iw / ih / target - 1) > PictureFit.tolerance ? min(Double(width) / iw, Double(height) / ih) : max(Double(width) / iw, Double(height) / ih)
        let w = iw * fit, h = ih * fit
        for f in 0..<frames {
            guard let pb = pixelBuffer(width, height) else { throw MVError("Not enough memory to make the Ken Burns clip.") }
            let t = Double(f) / Double(frames)                          // 0 up to (just under) 1: frame `frames` would be frame 0 again
            let phase = 2 * Double.pi * t
            let grow = (1 - cos(phase)) / 2                             // 0 at the start, 1 halfway through, 0 at the end
            let scale = 1 + kenBurnsZoom * grow
            // the pan is only let out as far as the zoom has opened the frame, so a moving edge never comes in
            let panX = 0.012 * Double(width) * grow * sin(phase)
            let panY = 0.008 * Double(height) * grow * sin(phase + .pi / 3)
            paint(pb) { ctx in
                ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.interpolationQuality = .high                        // Lanczos-quality resampling from the high-resolution picture
                ctx.saveGState()
                ctx.translateBy(x: Double(width) / 2 + panX, y: Double(height) / 2 + panY)
                ctx.scaleBy(x: scale, y: scale)
                ctx.draw(img, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
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
        try await makeKenBurnsClip(picture: dir.appendingPathComponent(pic), output: tmp)
        try addClip(&p, dir: dir, file: tmp, config: config)
        guard let c = p.clip else { return }
        p.versionQualities[c] = "Ken Burns (slow pan and zoom on the picture)"; p.versionCosts[c] = 0; p.clipWarning = nil
        // the clip is one closed cycle: play all of it and dissolve nothing at the join, so the camera never runs back over itself
        p.trims[c] = ClipTrim(start: 0, end: kenBurnsSeconds, blend: 0)
        rateLoop(&p, clip: c, dir: dir)
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
