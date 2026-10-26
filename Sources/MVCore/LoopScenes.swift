// A looping video with more than one scene: the picture changes (a slow cross-fade) after a set time, at each song change, or both.
// Each scene is its own loop clip; the long video is still made fast, by writing each scene's encoded loop again and again and drawing only the
// pieces where something changes (the opening, title cards, the cross-fades between scenes, the ending).
import Foundation
import CoreGraphics
import AVFoundation

/// When the scene of a looping video changes.
public enum LoopSceneChange: String, Codable, CaseIterable {
    case never, time, songs, both
    public var name: String {
        switch self { case .never: "Never (one scene)"; case .time: "Every few minutes"; case .songs: "At each song change"; case .both: "Both" }
    }
}

extension LoopVideo {
    public static let sceneFade = 3.0                       // seconds of cross-fade between two scenes
    static let sceneMinGap = 30.0                            // never two scene changes closer than this

    /// The clips the video changes between, in order (the clip in use first if it is not in the list).
    public static func sceneClips(_ p: LoopProject) -> [String] {
        var list = p.sceneClips.filter { p.clips.contains($0) }
        if let c = p.clip, list.isEmpty || !list.contains(c) { list.insert(c, at: 0) }
        return list
    }

    /// Where each scene starts (seconds into the long video) and which clip it shows. One scene unless changes are chosen and two or more clips are in the list.
    public static func sceneStarts(_ p: LoopProject, plan: LoopAudio.Plan) -> [(t: Double, clip: String)] {
        let clips = sceneClips(p)
        guard let first = clips.first else { return [] }
        guard p.sceneChange != .never, clips.count > 1 else { return [(0, first)] }
        let times = sceneChangeTimes(p, plan: plan)
        return [(0, first)] + times.enumerated().map { ($0.element, clips[($0.offset + 1) % clips.count]) }
    }

    /// When the scene changes (seconds), whatever the number of clips: song changes and/or every few minutes, never during the title or the ending,
    /// never closer than 30 seconds.
    public static func sceneChangeTimes(_ p: LoopProject, plan: LoopAudio.Plan) -> [Double] {
        guard p.sceneChange != .never else { return [] }
        let earliest = titleScreenEnd + 5, latest = plan.songsEnd - 20
        var songs: [Double] = []
        if p.sceneChange == .songs || p.sceneChange == .both {
            // between songs' turns (a song repeating itself is not a song change)
            for (a, b) in zip(plan.plays, plan.plays.dropFirst()) where b.rep == 0 { songs.append(b.start < a.end ? (a.end + b.start) / 2 : (a.end + b.start) / 2) }
        }
        var times: [Double] = []
        if p.sceneChange == .time || p.sceneChange == .both {
            let step = max(1, p.sceneMinutes) * 60
            var t = step
            while t < latest { times.append(t); t += step }
            if p.sceneChange == .both { times = times.filter { t in !songs.contains { abs($0 - t) < 60 } } }      // a song change is close: that change is enough
        }
        let all = (songs + times).filter { $0 >= earliest && $0 <= latest }.sorted()
        var kept: [Double] = []
        for t in all where kept.last.map({ t - $0 >= sceneMinGap }) ?? true { kept.append(t) }
        return kept
    }

    /// How many different scenes the video can use well: one for each change, up to four (after that the clips simply take turns).
    public static func scenesWanted(_ p: LoopProject, plan: LoopAudio.Plan) -> Int { min(4, sceneChangeTimes(p, plan: plan).count + 1) }

    /// A small picture of a clip (its first moment), made once and kept beside it.
    public static func clipThumbnail(_ clip: String, dir: URL) -> URL? {
        let out = dir.appendingPathComponent("thumb-" + (clip as NSString).deletingPathExtension + ".jpg")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: dir.appendingPathComponent(clip))); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 480, height: 480)
        guard let img = try? g.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil), let d = PictureFit.jpegData(img, quality: 0.8) else { return nil }
        try? d.write(to: out); return out
    }

    /// The scenes of one long video, ready to draw frame by frame.
    final class SceneTimeline {
        let painters: [LoopPainter]                  // one per clip used
        let starts: [(frame: Int, painter: Int)]     // scene k shows from starts[k].frame until the next one
        let periods: [Int]                           // each painter's loop, in frames
        let fade: Int                                // half the cross-fade, in frames
        init(_ p: LoopProject, plan: LoopAudio.Plan, dir: URL, W: Int, H: Int, title: String?) {
            let scenes = LoopVideo.sceneStarts(p, plan: plan)
            var names: [String] = [], ps: [LoopPainter] = []
            var st: [(Int, Int)] = []
            for s in scenes {
                if !names.contains(s.clip) {
                    names.append(s.clip)
                    ps.append(LoopPainter(clip: dir.appendingPathComponent(s.clip), W: W, H: H, title: ps.isEmpty ? title : nil, trim: p.trims[s.clip] ?? ClipTrim()))
                }
                st.append((Int((s.t * Double(LoopVideo.fps)).rounded()), names.firstIndex(of: s.clip)!))
            }
            painters = ps; starts = st
            periods = ps.map { max(LoopVideo.fps, Int(($0.period * Double(LoopVideo.fps)).rounded())) }
            fade = Int(LoopVideo.sceneFade * Double(LoopVideo.fps) / 2)
        }
        /// The scene showing at frame `f`.
        func scene(_ f: Int) -> Int { var k = 0; while k + 1 < starts.count && starts[k + 1].frame <= f { k += 1 }; return k }
        /// Where scene `k`'s loop is at frame `f` (it starts from the beginning of its loop when the scene starts).
        func phase(_ f: Int, _ k: Int) -> Int { let m = periods[starts[k].painter]; return ((f - starts[k].frame) % m + m) % m }
        /// The frames around each scene change that are drawn as a cross-fade.
        var changes: [(Int, Int)] { starts.dropFirst().map { ($0.frame - fade, $0.frame + fade) } }
        /// Draws frame `f` (the overlays come from the first painter).
        func draw(_ f: Int, ctx: CGContext, titleTime: Double?, fadeToBlack: Double, fadeFromBlack: Double, cards: [(text: String, t: Double)]) {
            let k = scene(f)
            func t(_ k: Int) -> Double { Double(phase(f, k)) / Double(LoopVideo.fps) }
            var from = k, into: Int? = nil, alpha = 0.0
            if k + 1 < starts.count, f >= starts[k + 1].frame - fade { into = k + 1 }
            else if k > 0, f < starts[k].frame + fade { from = k - 1; into = k }
            if let i = into { let x = Double(f - (starts[i].frame - fade)) / Double(2 * fade); alpha = x * x * (3 - 2 * x) }
            let base = painters[starts[from].painter]
            base.draw(loopTime: t(from), ctx: ctx, titleTime: nil, fadeToBlack: 0, fadeFromBlack: 0, cards: [],
                      also: into.map { (painters[starts[$0].painter], t($0), alpha) })
            painters[0].drawOverlays(ctx: ctx, titleTime: titleTime, fadeToBlack: fadeToBlack, fadeFromBlack: fadeFromBlack, cards: cards)
        }
    }
}
