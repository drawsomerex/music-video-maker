// Reads the song's duration.
import AVFoundation

public func audioDuration(path: String) async throws -> Double {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let d = try await asset.load(.duration)
    return CMTimeGetSeconds(d)
}
