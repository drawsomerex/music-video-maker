// A video clip that plays inside a section instead of a still picture (the song's own sound stays; the clip's sound is not used).
import Foundation
import AVFoundation
import CoreGraphics

final class VideoClipSource: @unchecked Sendable {
    private let asset: AVURLAsset
    private let gen: AVAssetImageGenerator
    private let seconds: Double
    private let lock = NSLock()
    private var lastKey = Int.min, lastImage: CGImage?

    init(url: URL, maxPixel: Int) {
        asset = AVURLAsset(url: url)
        seconds = max(0.1, CMTimeGetSeconds(asset.duration))
        gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 1.0 / 60, preferredTimescale: 600)
        gen.maximumSize = CGSize(width: maxPixel, height: maxPixel)
    }

    /// The picture of the clip `t` seconds after the scene began (the clip repeats if it is shorter than the scene).
    func frame(at t: Double) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let local = t.truncatingRemainder(dividingBy: seconds)
        let key = Int((local * 30).rounded())                    // 30 pictures per second is plenty
        if key == lastKey, let img = lastImage { return img }
        let img = try? gen.copyCGImage(at: CMTime(seconds: min(local, seconds - 0.04), preferredTimescale: 600), actualTime: nil)
        if let img { lastKey = key; lastImage = img }
        return img ?? lastImage
    }
}
