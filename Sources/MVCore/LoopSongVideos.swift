// A video of each song of a looping video, made automatically beside the long one: six songs that each repeat for 10 minutes give one 60-minute video
// and six 10-minute videos. Each song's video is the song with its own repeats (exactly as it plays in the long video), over the scene that song plays under.
import Foundation
import AVFoundation
import CoreGraphics

extension LoopVideo {
    /// The project for the video of one song: just that song, played with its repeats, over its own scene. The long video's other settings stay.
    public static func songVideoProject(_ p: LoopProject, track k: Int) -> LoopProject? {
        guard p.tracks.indices.contains(k) else { return nil }
        var q = p
        let song = songName(p.tracks[k].title, k)
        q.tracks = [p.tracks[k]]; q.tracks[0].clip = nil
        q.playOnce = true                                           // one pass: the song with its repeats, and nothing after it
        q.sceneChange = .never; q.sceneClips = []
        q.clip = songClips(p)[k].clip ?? p.clip                     // the scene this song plays under in the long video
        q.title = song; q.screenTitle = song                        // the title screen and the YouTube words are the song's
        if q.cards == .everySong { q.cards = .beginning }          // one song: its title once, at the start
        q.songVideos = false; q.output = nil; q.thumbnail = nil; q.listing = nil
        return q
    }

    /// "01 Rain on the Window – 10 Minutes"
    public static func songVideoName(_ p: LoopProject, track k: Int, seconds: Double) -> String {
        let name = songName(p.tracks[k].title, k).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return String(format: "%02d ", k + 1) + name + " – " + YouTubeKit.durationText(seconds)
    }

    /// Makes one video per song into `folder`, each with its YouTube thumbnail and description. Returns the videos made.
    @discardableResult
    public static func makeSongVideos(_ p0: LoopProject, dir: URL, folder: URL, config: Config = .load(), progress: ((String, Double) -> Void)? = nil) async throws -> [URL] {
        var p = p0
        try ensureAnalysis(&p, dir: dir)
        guard p.clip != nil, !p.tracks.isEmpty else { throw MVError("Make or add the loop clip and add a song first.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var made: [URL] = []
        let n = p.tracks.count
        for k in 0..<n {
            try Task.checkCancellation()
            guard let q = songVideoProject(p, track: k), let plan = plan(q) else { continue }
            let out = folder.appendingPathComponent(songVideoName(p, track: k, seconds: plan.total) + ".mp4")
            let base = Double(k) / Double(n), span = 1 / Double(n)
            let label = "Song video \(k + 1) of \(n): \(songName(p.tracks[k].title, k))"
            try await render(q, dir: dir, output: out) { ph, f in progress?("\(label) · \(ph)", base + span * 0.95 * f) }
            progress?("\(label) · writing its thumbnail and description", base + span * 0.96)
            // the thumbnail and description beside it (written without touching the project's own YouTube files)
            if let c = q.clip {
                let src = dir.appendingPathComponent("thumbnail-source-\(k + 1).jpg")
                let g = AVAssetImageGenerator(asset: AVURLAsset(url: dir.appendingPathComponent(c))); g.appliesPreferredTrackTransform = true
                if let img = try? g.copyCGImage(at: .zero, actualTime: nil), let d = PictureFit.jpegData(img, quality: 0.95) {
                    try? d.write(to: src)
                    let listing = await YouTubeKit.loopListing(q, plan: plan, config: config)
                    let t = thumbWords(q)
                    _ = try? YouTubeKit.writeFiles(beside: out, picture: src, thumbTitle: t.title, badge: t.badge, line: t.line, listing: listing)
                    try? FileManager.default.removeItem(at: src)
                }
            }
            made.append(out)
        }
        progress?("Done", 1)
        return made
    }
}
