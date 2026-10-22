// The music of a looping long video: one song or a playlist of up to 100, played whole (never cut off) until the chosen length is reached.
//
//   • each song is listened to once: where its sound really starts and ends (silence trimmed, ring-outs kept), how loud it is
//     (ITU-R BS.1770 loudness, the measure YouTube uses), whether it fades out at the end and whether it opens with a hit;
//   • the plays are scheduled: the list in order, then again from the top (optionally shuffled each round), until the end of a song
//     reaches the length you chose (the song that crosses it plays to its end);
//   • joins: Seamless (a tight 3-second blend), Automatic (overlap a song that fades out, a 2-second pause after a clean stop, never fade
//     in a song that opens with a hit), Crossfade (2–12 s) or Album gaps (0.5–5 s);
//   • the mix is made a little at a time, with at most a few songs in memory, so 100 songs and 12 hours need no more memory than one.
import Foundation
import AVFoundation

public struct LoopTrack: Codable, Equatable, Identifiable {
    public var id = UUID().uuidString
    public var file = ""                  // inside the project folder
    public var title = ""                 // shown on its title card, in the chapters and the tracklist (default: the file name)
    public var seconds = 0.0
    public var cardOn = true              // its own title card (when cards are on for every song)
    public init(file: String, title: String, seconds: Double) { self.file = file; self.title = title; self.seconds = seconds }
    enum CodingKeys: String, CodingKey { case id, file, title, seconds, cardOn }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""; title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0; cardOn = try c.decodeIfPresent(Bool.self, forKey: .cardOn) ?? true
    }
}

/// What listening to a song found (kept in the project, so each song is listened to once).
public struct TrackAnalysis: Codable, Equatable {
    public var start = 0.0, end = 0.0            // where the sound really starts and ends (seconds into the file)
    public var loudness = -14.0                  // integrated loudness, LUFS
    public var peak = 1.0                        // highest sample (0…1)
    public var fadesOut = false                  // gets gradually quieter over its last seconds
    public var fadeLength = 0.0                  // how long that fade is
    public var hardStart = false                 // opens at full strength (a hit)
    public var length: Double { max(0.1, end - start) }
    public init() {}
}

public enum LoopTransition: String, Codable, CaseIterable { case seamless, automatic, crossfade, albumGaps
    public var name: String { switch self { case .seamless: "Seamless"; case .automatic: "Automatic"; case .crossfade: "Crossfade"; case .albumGaps: "Album gaps" } }
}

public enum LoopAudio {
    public static let rate = 48000
    public static let targetLUFS = -14.0          // YouTube's reference loudness

    // MARK: reading a song
    /// The whole song as stereo 48 kHz samples (interleaved).
    static func decode(_ url: URL, from: Double = 0, to: Double? = nil) throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { throw MVError("“\(url.lastPathComponent)” has no sound to use.") }
        let r = try AVAssetReader(asset: asset)
        if from > 0 || to != nil { r.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 48000), end: to.map { CMTime(seconds: $0, preferredTimescale: 48000) } ?? asset.duration) }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
                                                                          AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false])
        r.add(out); r.startReading()
        var all: [Float] = []
        all.reserveCapacity(Int((to ?? CMTimeGetSeconds(asset.duration)) - from + 1) * rate * 2)
        while let sb = out.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
            let n = CMBlockBufferGetDataLength(bb), old = all.count
            all.append(contentsOf: repeatElement(0, count: n / 4))
            all.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: n, destination: $0.baseAddress! + old * 4) }
        }
        return all
    }

    /// Listens to a song once: trimmed start and end, loudness, peak, how it ends and how it begins.
    public static func analyze(_ url: URL) throws -> TrackAnalysis {
        let s = try decode(url)
        let frames = s.count / 2
        guard frames > rate else { throw MVError("“\(url.lastPathComponent)” is too short to use.") }
        var a = TrackAnalysis()
        // silence at both ends (quieter than about −50 dB), keeping 50 ms
        let threshold: Float = 0.003
        var first = 0, last = frames - 1
        while first < frames && max(abs(s[first * 2]), abs(s[first * 2 + 1])) < threshold { first += 1 }
        while last > first && max(abs(s[last * 2]), abs(s[last * 2 + 1])) < threshold { last -= 1 }
        first = max(0, first - rate / 20); last = min(frames - 1, last + rate / 20)
        a.start = Double(first) / Double(rate); a.end = Double(last + 1) / Double(rate)
        var peak: Float = 0
        for i in (first * 2)...(last * 2 + 1) { peak = max(peak, abs(s[i])) }
        a.peak = Double(peak)
        a.loudness = integratedLoudness(s, from: first, to: last)
        // level in half-second steps (dB), to read the ending and the opening
        let step = rate / 2
        func level(_ f0: Int) -> Double {
            var sum = 0.0; let f1 = min(last, f0 + step)
            guard f1 > f0 else { return -100 }
            for f in f0..<f1 { let l = Double(s[f * 2]), r = Double(s[f * 2 + 1]); sum += (l * l + r * r) / 2 }
            return 10 * log10(max(1e-12, sum / Double(f1 - f0)))
        }
        let steps = stride(from: first, to: last, by: step).map(level)
        let typical = steps.sorted()[steps.count * 6 / 10]                  // a loud-ish moment of the song
        // the ending: much quieter over the last seconds than 6–12 s before, and falling steadily (no new rise)
        if steps.count > 30 {
            let tail = Array(steps.suffix(24))                                // the last 12 s
            let ref = tail.prefix(12).max() ?? typical, endLevel = tail.suffix(3).reduce(0, +) / 3
            var rises = 0
            for k in 12..<(tail.count - 1) where tail[k + 1] > tail[k] + 2 { rises += 1 }
            if ref - endLevel >= 10, rises <= 1 {
                a.fadesOut = true
                let drop = tail.firstIndex(where: { $0 < ref - 3 }) ?? 12
                a.fadeLength = min(10, max(3, Double(tail.count - drop) * 0.5))
            }
        }
        a.hardStart = (steps.first ?? -100) >= typical - 6                   // the first half second is already near full strength
        return a
    }

    /// Integrated loudness (ITU-R BS.1770-4): K-weighting, 400 ms blocks every 100 ms, absolute gate −70 LUFS, relative gate −10 LU.
    static func integratedLoudness(_ s: [Float], from: Int, to: Int) -> Double {
        // K-weighting at 48 kHz: a high shelf, then a high pass
        let b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285], a1 = [1.0, -1.69065929318241, 0.73248077421585]
        let b2 = [1.0, -2.0, 1.0], a2 = [1.0, -1.99004745483398, 0.99007225036621]
        let n = to - from + 1
        var power = [Double](repeating: 0, count: n)
        for ch in 0..<2 {
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0, z1 = 0.0, z2 = 0.0, w1 = 0.0, w2 = 0.0
            for i in 0..<n {
                let x = Double(s[(from + i) * 2 + ch])
                let y = b1[0] * x + b1[1] * x1 + b1[2] * x2 - a1[1] * y1 - a1[2] * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                let w = b2[0] * y + b2[1] * z1 + b2[2] * z2 - a2[1] * w1 - a2[2] * w2
                z2 = z1; z1 = y; w2 = w1; w1 = w
                power[i] += w * w
            }
        }
        let block = rate * 4 / 10, hop = rate / 10
        var blocks: [Double] = []
        var start = 0
        var sum = power.prefix(block).reduce(0, +)
        while start + block <= n {
            blocks.append(sum / Double(block))
            let next = start + hop
            if next + block > n { break }
            for k in start..<next { sum -= power[k] }
            for k in (start + block)..<(next + block) { sum += power[k] }
            start = next
        }
        func lufs(_ p: Double) -> Double { -0.691 + 10 * log10(max(1e-12, p)) }
        let abs = blocks.filter { lufs($0) > -70 }
        guard !abs.isEmpty else { return -70 }
        let rel = lufs(abs.reduce(0, +) / Double(abs.count)) - 10
        let gated = abs.filter { lufs($0) > rel }
        return lufs((gated.isEmpty ? abs : gated).reduce(0, +) / Double((gated.isEmpty ? abs : gated).count))
    }

    // MARK: the plan
    /// One play of one song on the video's timeline.
    public struct Play: Equatable {
        public var track: Int                  // index into the playlist
        public var start: Double               // when it starts in the video (seconds)
        public var from: Double, to: Double    // the part of the file that plays (trimmed)
        public var fadeIn: Double, fadeOut: Double
        public var gain: Double
        public var round: Int                  // 0 = the first time through the playlist
        public var length: Double { to - from }
        public var end: Double { start + length }
    }
    public struct Plan { public var plays: [Play]; public var total: Double; public var songsEnd: Double
        /// The first time through the playlist (for the chapters).
        public var firstRound: [Play] { plays.filter { $0.round == 0 } }
    }

    /// Plays the songs whole until one ends at or after `minimum` seconds; the video lasts until that song ends, plus `tail` seconds.
    public static func plan(analyses: [TrackAnalysis], transition: LoopTransition, crossfade: Double, gap: Double, evenVolume: Bool, shuffle: Bool,
                            minimum: Double, seed: UInt64, tail: Double = 3, onePass: Bool = false) -> Plan {
        guard !analyses.isEmpty else { return Plan(plays: [], total: 0, songsEnd: 0) }
        func gain(_ a: TrackAnalysis) -> Double {
            guard evenVolume, analyses.count > 1, a.loudness > -60 else { return 1 }
            return min(4, max(0.1, pow(10, (targetLUFS - a.loudness) / 20)))
        }
        var rng = SeededRNG(seed)
        var plays: [Play] = []
        var round = 0
        var order = Array(analyses.indices)
        var t = 0.0
        while plays.isEmpty || (!onePass && plays.last!.end < minimum) {        // each song once: one time through, whatever the length
            if round > 0 && shuffle {
                order.shuffleSeeded(&rng)
                if order.count > 1, let lastPlayed = plays.last?.track, order.first == lastPlayed { order.swapAt(0, 1 + Int(rng.next() % UInt64(order.count - 1))) }
            }
            for i in order {
                let a = analyses[i]
                var p = Play(track: i, start: t, from: a.start, to: a.end, fadeIn: 0, fadeOut: 0, gain: gain(a), round: round)
                if var prev = plays.last {
                    let pa = analyses[prev.track]
                    switch transition {
                    case .seamless, .crossfade:
                        let want = transition == .seamless ? 3.0 : min(12, max(2, crossfade))
                        let o = min(want, prev.length / 3, p.length / 3)
                        p.start = prev.end - o; prev.fadeOut = o; p.fadeIn = o
                    case .albumGaps:
                        p.start = prev.end + min(5, max(0.5, gap))
                    case .automatic:
                        if pa.fadesOut {                                         // flows on: the next song starts during the fade
                            let o = min(6, max(3, pa.fadeLength * 0.6), prev.length / 3, p.length / 3)
                            p.start = prev.end - o; prev.fadeOut = o; p.fadeIn = a.hardStart ? 0 : min(o, 2)
                        } else { p.start = prev.end + 2 }                       // a clean stop: let it ring, then a short pause
                    }
                    plays[plays.count - 1] = prev
                }
                plays.append(p); t = p.end
                if !onePass && p.end >= minimum { break }
                if plays.count > 200_000 { break }
            }
            round += 1
            if plays.count > 200_000 { break }
        }
        let songsEnd = plays.last?.end ?? 0
        return Plan(plays: plays, total: songsEnd + tail, songsEnd: songsEnd)
    }

    // MARK: the mix
    /// Makes the sound a little at a time. Keeps at most three songs in memory.
    public final class Mixer {
        let urls: [URL]
        let plan: Plan
        private var cache: [(key: Int, samples: [Float])] = []     // trimmed songs, most recent last
        private var next = 0                                       // first play that may still sound
        public init(urls: [URL], plan: Plan) { self.urls = urls; self.plan = plan }

        private func samples(_ p: Play) throws -> [Float] {
            if let i = cache.firstIndex(where: { $0.key == p.track }) { let c = cache.remove(at: i); cache.append(c); return c.samples }
            let s = try LoopAudio.decode(urls[p.track], from: p.from, to: p.to)
            cache.append((p.track, s)); if cache.count > 3 { cache.removeFirst() }
            return s
        }

        /// `count` stereo frames starting at frame `start` (frames must be asked for in order).
        public func fill(_ out: inout [Float], start: Int, count: Int) throws {
            for i in 0..<(count * 2) { out[i] = 0 }
            let r = Double(LoopAudio.rate), t0 = Double(start) / r, t1 = Double(start + count) / r
            while next < plan.plays.count && plan.plays[next].end < t0 { next += 1 }
            var k = next
            while k < plan.plays.count && plan.plays[k].start < t1 {
                let p = plan.plays[k]; let isFirst = k == 0; k += 1
                guard p.end > t0 else { continue }
                let s = try samples(p)
                let pStart = Int((p.start * r).rounded()), n = s.count / 2
                let fi = Int(p.fadeIn * r), fo = Int(p.fadeOut * r), g = Float(p.gain)
                let lo = max(start, pStart), hi = min(start + count, pStart + n)
                guard hi > lo else { continue }
                for f in lo..<hi {
                    let j = f - pStart
                    var w: Float = g
                    if j < fi { w *= Float(sin(Double(j) / Double(fi) * .pi / 2)) }
                    if j >= n - fo { w *= Float(cos(Double(j - (n - fo)) / Double(max(1, fo)) * .pi / 2)) }
                    if j < 240 && p.fadeIn == 0 && !isFirst { w *= Float(j) / 240 }      // never a click where a song begins
                    out[(f - start) * 2] += s[j * 2] * w; out[(f - start) * 2 + 1] += s[j * 2 + 1] * w
                }
            }
            // safety limiter: a raised song or an overlap never clips
            for i in 0..<(count * 2) {
                let x = out[i], ax = abs(x)
                if ax > 0.95 { out[i] = (x < 0 ? -1 : 1) * (0.95 + 0.05 * Float(tanh(Double(ax - 0.95) / 0.05))) }
            }
        }
    }
}

extension Array {
    mutating func shuffleSeeded(_ rng: inout SeededRNG) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, to: 0, by: -1) { swapAt(i, Int(rng.next() % UInt64(i + 1))) }
    }
}
