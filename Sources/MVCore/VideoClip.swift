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

    init(url: URL, maxPixel: Int, start: Double = 0, end: Double? = nil) {
        asset = AVURLAsset(url: url)
        let whole = max(0.1, CMTimeGetSeconds(asset.duration))
        from = min(max(0, start), whole - 0.1)
        seconds = max(0.1, min(end ?? whole, whole) - from)
        gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 60, preferredTimescale: 600)
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
    }

    /// What to show `t` seconds into a scene that lasts `sceneLength`. A clip that has to repeat loops like a professional video loop:
    /// the last stretch of the clip dissolves into its beginning (an overlap of up to 0.8 s) and playback carries on from there, so there is never a hard cut.
    func looped(at t: Double, sceneLength: Double) -> (main: CGImage?, over: CGImage?, overAlpha: Double) {
        guard sceneLength > seconds + 0.05 else { return (frame(at: t), nil, 0) }
        let f = min(0.8, seconds / 3), period = seconds - f
        let local = t.truncatingRemainder(dividingBy: period)
        if t >= period, local < f {                                 // the seam: the end of the clip dissolves into its beginning
            return (frame(at: period + local), frame(at: local), local / f)
        }
        return (frame(at: local), nil, 0)
    }

    /// The picture of the clip `t` seconds after the scene began (the clip repeats if it is shorter than the scene).
    func frame(at t: Double) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let local = t.truncatingRemainder(dividingBy: seconds)
        let key = Int((local * 30).rounded())                    // 30 pictures per second is plenty
        if key == lastKey, let img = lastImage { return img }
        let img = try? gen.copyCGImage(at: CMTime(seconds: from + min(local, seconds - 0.04), preferredTimescale: 600), actualTime: nil)
        if let img { lastKey = key; lastImage = img }
        return img ?? lastImage
    }
}
