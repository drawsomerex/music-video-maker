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
            let iw = Double(img.width), ih = Double(img.height), scale = max(Double(width) / iw, Double(height) / ih)
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
