// A video clip that plays inside a section instead of a still picture (the song's own sound stays; the clip's sound is not used).
import Foundation
import AVFoundation
import CoreGraphics

final class VideoClipSource: @unchecked Sendable {
    private let asset: AVURLAsset
    private let gen: AVAssetImageGenerator
    private let seconds: Double          // length of the part that plays (after trimming)
    private let from: Double             // where in the clip it starts
    private let lock = NSLock()
    private var lastKey = Int.min, lastImage: CGImage?
    // Reading the clip from start to finish: each picture is decoded once (asking for single pictures decodes again from the last keyframe every time).
    private let track: AVAssetTrack?
    private let outSize: CGSize?                 // decoded size (nil = as stored)
    private var reader: AVAssetReader?, output: AVAssetReaderTrackOutput?
    private var recent: [(t: Double, img: CGImage)] = []        // the last second or so of decoded pictures, oldest first
    private var readerAtEnd = false

    init(url: URL, maxPixel: Int, start: Double = 0, end: Double? = nil) {
        asset = AVURLAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        let whole = duration.isFinite && duration > 0 ? duration : 0.001
        from = min(max(0, start), max(0, whole - 0.001))
        seconds = max(0.001, min(end ?? whole, whole) - from)
        gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 60, preferredTimescale: 600)
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        // the reader is only used for clips stored upright (a phone video stored sideways goes through the generator, which turns it)
        let t = asset.tracks(withMediaType: .video).first
        if let t, t.preferredTransform.isIdentity {
            track = t
            let n = t.naturalSize, scale = min(1, Double(maxPixel) / Double(max(n.width, n.height, 1)))
            outSize = scale < 1 ? CGSize(width: (Double(n.width) * scale / 2).rounded() * 2, height: (Double(n.height) * scale / 2).rounded() * 2) : nil
        } else { track = nil; outSize = nil }
    }
    deinit { reader?.cancelReading() }

    private func startReader(at t: Double) {
        reader?.cancelReading(); reader = nil; output = nil; recent = []; readerAtEnd = false
        guard let track, let r = try? AVAssetReader(asset: asset) else { return }
        var settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if let o = outSize { settings[kCVPixelBufferWidthKey as String] = Int(o.width); settings[kCVPixelBufferHeightKey as String] = Int(o.height) }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        out.alwaysCopiesSampleData = false
        guard r.canAdd(out) else { return }
        r.add(out)
        r.timeRange = CMTimeRange(start: CMTime(seconds: max(0, t - 0.05), preferredTimescale: 600), end: asset.duration)
        guard r.startReading() else { return }
        reader = r; output = out
    }

    /// Decodes the next picture and keeps a copy (the decoder's own buffers are handed straight back).
    private func readOne() {
        guard let out = output, let sb = out.copyNextSampleBuffer() else { readerAtEnd = true; return }
        guard let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        // the video's own colour space (Rec. 709 and its tone curve), so the picture looks exactly as when it is picked out on its own
        let attachments = CVBufferCopyAttachments(pb, .shouldPropagate)
        let space = attachments.flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() } ?? CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
        guard let base = CVPixelBufferGetBaseAddress(pb), let provider = CGDataProvider(data: Data(bytes: base, count: bpr * h) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bpr, space: space,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        recent.append((t, img))
    }

    /// The picture showing at `want` seconds into the file, read in order. Requests close together (as when a video is made, a batch of frames at a time)
    /// decode each picture once; a jump backwards or far ahead starts reading again from there.
    private func sequentialFrame(_ want: Double) -> CGImage? {
        guard track != nil else { return nil }
        let tol = 0.5 / 60
        let behind = recent.first.map { want < $0.t - tol } ?? true
        let farAhead = recent.last.map { want > $0.t + 2.0 } ?? true
        if reader == nil || behind || (farAhead && !(readerAtEnd && !recent.isEmpty)) { startReader(at: want) }
        guard reader != nil else { return nil }
        while !readerAtEnd, (recent.last?.t ?? -1) < want - tol { readOne() }
        let pick = recent.last(where: { $0.t <= want + tol }) ?? recent.first
        if let p = pick { recent.removeAll { $0.t < min(p.t, want) - 1.0 } }      // keep about a second behind, for frames drawn slightly out of order
        return pick?.img
    }

    /// How long the chosen part of the clip plays.
    var playSeconds: Double { seconds }
    /// The last picture of the chosen part of the clip (the frame that is held after the clip, where the camera starts moving).
    func lastFrameImage() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        return try? gen.copyCGImage(at: CMTime(seconds: from + max(0, seconds - 0.06), preferredTimescale: 600), actualTime: nil)
    }

    /// What to show `t` seconds into a scene that lasts `sceneLength`. A clip that has to repeat loops like a professional video loop:
    /// the last stretch of the clip dissolves into its beginning (an overlap of up to 0.8 s) and playback carries on from there, so there is never a hard cut.
    func looped(at t: Double, sceneLength: Double) -> (main: CGImage?, over: CGImage?, overAlpha: Double) {
        guard sceneLength > seconds + 0.05 else { return (frame(at: t), nil, 0) }
        let f = min(0.8, seconds / 3), period = seconds - f
        let local = max(0, t.isFinite ? t : 0).truncatingRemainder(dividingBy: period)
        if t >= period, local < f {                                 // the seam: the end of the clip dissolves into its beginning
            return (frame(at: period + local), frame(at: local), local / f)
        }
        return (frame(at: local), nil, 0)
    }

    /// For tests: the picture picked on its own (the old way), to compare with the pictures read in order.
    func generatorFrame(at t: Double) -> CGImage? {
        try? gen.copyCGImage(at: CMTime(seconds: from + min(max(0, t), max(0, seconds - min(0.04, seconds / 2))), preferredTimescale: 600), actualTime: nil)
    }

    /// The picture of the clip `t` seconds after the scene began (the clip repeats if it is shorter than the scene).
    func frame(at t: Double) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let local = max(0, t.isFinite ? t : 0).truncatingRemainder(dividingBy: seconds)
        let key = Int((local * 30).rounded())                    // 30 pictures per second is plenty
        if key == lastKey, let img = lastImage { return img }
        let wanted = from + min(local, max(0, seconds - min(0.04, seconds / 2)))
        if let img = sequentialFrame(wanted) { lastKey = key; lastImage = img; return img }
        let img = try? gen.copyCGImage(at: CMTime(seconds: from + min(local, max(0, seconds - min(0.04, seconds / 2))), preferredTimescale: 600), actualTime: nil)
        if let img { lastKey = key; lastImage = img }
        return img ?? lastImage
    }
}
