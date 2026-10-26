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
    public var lyrics: String? = nil      // its words, heard with Parakeet for the director (nil = not listened to yet; empty = no words)
    public var repeatMode: TrackRepeat = .once   // play it once, a number of times, for a number of minutes, or as long as its scene
    public init(file: String, title: String, seconds: Double) { self.file = file; self.title = title; self.seconds = seconds }
    enum CodingKeys: String, CodingKey { case id, file, title, seconds, cardOn, lyrics, repeatMode }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""; title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0; cardOn = try c.decodeIfPresent(Bool.self, forKey: .cardOn) ?? true
        lyrics = try c.decodeIfPresent(String.self, forKey: .lyrics)
        repeatMode = (try? c.decodeIfPresent(TrackRepeat.self, forKey: .repeatMode)) ?? .once
    }
}

/// How a song repeats before the next one: once (the usual), a number of times, for a number of minutes, or as long as its scene.
/// Repeats join the song's end to its start with a smooth blend; a timed repeat that ends mid-song blends into what comes next at a quiet moment.
public enum TrackRepeat: Codable, Equatable, Hashable, Sendable {
    case once, times(Int), minutes(Double), scene
    public var label: String {
        switch self {
        case .once: "Once"
        case .times(let n): "\(n) times"
        case .minutes(let m): m >= 60 && m.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(m / 60)) hour\(m == 60 ? "" : "s")" : "\(Int(m)) min"
        case .scene: "Its scene"
        }
    }
    /// The scene choice, in minutes (the scene's length).
    public func resolved(sceneMinutes: Double) -> TrackRepeat { self == .scene ? .minutes(max(1, sceneMinutes)) : self }
}

/// What listening to a song found (kept in the project, so each song is listened to once).
public struct TrackAnalysis: Codable, Equatable {
    public var start = 0.0, end = 0.0            // where the sound really starts and ends (seconds into the file)
    public var loudness = -14.0                  // integrated loudness, LUFS
    public var peak = 1.0                        // highest sample (0…1)
    public var fadesOut = false                  // gets gradually quieter over its last seconds
    public var fadeLength = 0.0                  // how long that fade is
    public var hardStart = false                 // opens at full strength (a hit)
    public var quietTail = 0.0                   // how long its ending is quiet (12 dB or more below the song) before the sound stops
    public var quietIntro = 0.0                  // how long its opening is quiet before the music is at strength
    public var version = 1                       // 2 = measured with the quiet tail and intro; 3 = with its level over time (older measurements are redone once)
    public var energy: [Float] = []              // the level (dB) every quarter second from `start`: a timed repeat ends at a quiet moment
    public var length: Double { max(0.1, end - start) }
    public static let currentVersion = 3
    public init() {}
    enum CodingKeys: String, CodingKey { case start, end, loudness, peak, fadesOut, fadeLength, hardStart, quietTail, quietIntro, version, energy }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0; end = try c.decodeIfPresent(Double.self, forKey: .end) ?? 0
        loudness = try c.decodeIfPresent(Double.self, forKey: .loudness) ?? -14; peak = try c.decodeIfPresent(Double.self, forKey: .peak) ?? 1
        fadesOut = try c.decodeIfPresent(Bool.self, forKey: .fadesOut) ?? false; fadeLength = try c.decodeIfPresent(Double.self, forKey: .fadeLength) ?? 0
        hardStart = try c.decodeIfPresent(Bool.self, forKey: .hardStart) ?? false
        quietTail = try c.decodeIfPresent(Double.self, forKey: .quietTail) ?? 0; quietIntro = try c.decodeIfPresent(Double.self, forKey: .quietIntro) ?? 0
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        energy = try c.decodeIfPresent([Float].self, forKey: .energy) ?? []
    }
}

public enum LoopTransition: String, Codable, CaseIterable { case seamless, automatic, crossfade, albumGaps
    public var name: String { switch self { case .seamless: "Seamless"; case .automatic: "Back to back"; case .crossfade: "Crossfade"; case .albumGaps: "Album gaps" } }
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
        // silence at both ends: quieter than 46 dB below the song's loudest moment (so a quiet song keeps its quiet intro), keeping 50 ms
        var loudest: Float = 0
        for v in s { loudest = max(loudest, abs(v)) }
        let threshold: Float = max(0.0003, loudest * 0.005)
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
        // level every quarter second (dB); "typical" is the level of the song's body
        let q = rate / 4
        let steps = stride(from: first, to: last, by: q).map { f0 -> Double in
            var sum = 0.0; let f1 = min(last, f0 + q)
            guard f1 > f0 else { return -100 }
            for f in f0..<f1 { let l = Double(s[f * 2]), r = Double(s[f * 2 + 1]); sum += (l * l + r * r) / 2 }
            return 10 * log10(max(1e-12, sum / Double(f1 - f0)))
        }
        _ = step; _ = level
        let typical = steps.sorted()[steps.count / 2]
        // the quiet tail: from the last moment the song is still near its body (within 12 dB) to the end; the quiet intro likewise from the start
        let quiet = typical - 12
        let lastLoud = steps.lastIndex(where: { $0 > quiet }) ?? (steps.count - 1)
        let firstLoud = steps.firstIndex(where: { $0 > quiet }) ?? 0
        a.quietTail = min(15, Double(steps.count - 1 - lastLoud) * 0.25)
        a.quietIntro = min(10, Double(firstLoud) * 0.25)
        // a real fade-out: falling for several seconds from the song's usual level (within 3 dB) to silence
        let lastFull = steps.lastIndex(where: { $0 > typical - 3 }) ?? (steps.count - 1)
        a.fadeLength = min(20, Double(steps.count - 1 - lastFull) * 0.25)
        a.fadesOut = a.fadeLength >= 4 && a.quietTail >= 1
        a.hardStart = a.quietIntro < 0.3                                     // at strength from the very start (a hit)
        a.energy = steps.map { Float(($0 * 10).rounded() / 10) }
        a.version = TrackAnalysis.currentVersion
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
        public var rep = 0                     // 0 = the song's first play in its turn; 1, 2… = its repeats (same turn)
        public var cut = false                 // a timed repeat ended it before the song's end (it blends into what comes next)
        public var length: Double { to - from }
        public var end: Double { start + length }
    }
    public struct Plan { public var plays: [Play]; public var total: Double; public var songsEnd: Double
        /// The first time through the playlist (for the chapters): each song's turn once, not its repeats.
        public var firstRound: [Play] { plays.filter { $0.round == 0 && $0.rep == 0 } }
        /// Where each song's turn starts (its repeats are part of the turn).
        public var turns: [Play] { plays.filter { $0.rep == 0 } }
    }

    /// Plays the songs until one's turn ends at or after `minimum` seconds; the video lasts until that turn ends, plus `tail` seconds.
    /// A song plays whole unless its repeat is timed (`repeats`, one per song; missing = once).
    public static func plan(analyses: [TrackAnalysis], transition: LoopTransition, crossfade: Double, gap: Double, evenVolume: Bool, shuffle: Bool,
                            minimum: Double, seed: UInt64, tail: Double = 3, onePass: Bool = false, repeats: [TrackRepeat] = []) -> Plan {
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
                    if prev.cut {
                        // the song before was cut by its timed repeat: it always blends into this one
                        p.start = prev.end - prev.fadeOut; p.fadeIn = prev.fadeOut
                    } else {
                        switch transition {
                        case .seamless, .crossfade:
                            let want = transition == .seamless ? 3.0 : min(12, max(2, crossfade))
                            let o = min(want, prev.length / 3, p.length / 3)
                            p.start = prev.end - o; prev.fadeOut = o; p.fadeIn = o
                        case .albumGaps:
                            p.start = prev.end + min(5, max(0.5, gap))
                        case .automatic:
                            // back to back: every song plays in full, untouched (no fades, no overlap); the next starts the moment the previous one's sound ends
                            p.start = prev.end
                        }
                        plays[plays.count - 1] = prev
                    }
                }
                plays.append(p)
                repeatTurn(&plays, a, i < repeats.count ? repeats[i] : .once)
                t = plays.last!.end
                if !onePass && plays.last!.end >= minimum { break }
                if plays.count > 200_000 { break }
            }
            round += 1
            if plays.count > 200_000 { break }
        }
        let songsEnd = plays.last?.end ?? 0
        return Plan(plays: plays, total: songsEnd + tail, songsEnd: songsEnd)
    }

    /// How a song's end blends into its own start when it repeats: through its fade-out if it has one, otherwise a 4-second blend, and always
    /// long enough to cover its quiet ending and quiet opening (plus 1.5 s of the music overlapping), so there is never a dip in the sound.
    static func selfJoin(_ a: TrackAnalysis) -> Double {
        let base = a.fadesOut ? min(8, max(3, a.fadeLength * 0.7)) : 4
        return min(a.length / 3, min(12, max(base, a.quietTail + a.quietIntro + 1.5)))
    }
    /// The blend when a timed repeat ends a song mid-way.
    static let cutBlend = 6.0

    /// Adds a song's repeats after its first play (the last play in `plays`).
    static func repeatTurn(_ plays: inout [Play], _ a: TrackAnalysis, _ mode: TrackRepeat) {
        guard let first = plays.last else { return }
        func again() {
            var prev = plays[plays.count - 1]
            let o = selfJoin(a)
            var r = Play(track: prev.track, start: prev.end - o, from: a.start, to: a.end, fadeIn: o, fadeOut: 0, gain: prev.gain, round: prev.round)
            r.rep = prev.rep + 1
            prev.fadeOut = o; plays[plays.count - 1] = prev
            plays.append(r)
        }
        switch mode {
        case .once, .scene: return
        case .times(let n):
            for _ in 1..<max(1, min(n, 1000)) { again() }
        case .minutes(let m):
            let target = first.start + max(0.5, m) * 60
            while plays.last!.end < target - 0.5 {
                // a last repeat that would only play a few seconds is left out: the turn ends a little early instead
                if target - (plays.last!.end - selfJoin(a)) < 20 { break }
                again()
                if plays.count > 200_000 { break }
            }
            var last = plays[plays.count - 1]
            if last.end > target + 0.5 {
                // ends mid-song: at a quiet moment just before the time, blending into what comes next
                let want = last.from + (target - last.start)
                let cut = quietMoment(a, before: want, notBefore: last.from + max(8, last.fadeIn + 2))
                last.to = max(last.from + 2, cut)
                last.fadeOut = min(cutBlend, last.length / 3)
                last.cut = true
                plays[plays.count - 1] = last
            }
        }
    }

    /// The quietest moment in the 15 seconds before `want` (file time), so a cut song fades out where the music breathes.
    static func quietMoment(_ a: TrackAnalysis, before want: Double, notBefore: Double) -> Double {
        guard !a.energy.isEmpty else { return want }
        let lo = max(notBefore, want - 15), hi = want
        guard hi - lo > 1 else { return want }
        var best = hi, bestLevel = Float.greatestFiniteMagnitude
        var x = hi
        while x >= lo {
            let k = Int(((x - a.start) / 0.25).rounded())
            if a.energy.indices.contains(k) {
                // the level over the next 2 seconds (the blend starts here), slightly favouring later moments
                let span = a.energy[k..<min(a.energy.count, k + 8)]
                let level = span.reduce(0, +) / Float(max(1, span.count)) + Float(hi - x) * 0.15
                if level < bestLevel { bestLevel = level; best = x }
            }
            x -= 0.25
        }
        return best
    }

    // MARK: the mix
    /// Makes the sound a little at a time. Keeps at most three songs in memory.
    public final class Mixer {
        let urls: [URL]
        let plan: Plan
        private var cache: [(key: String, samples: [Float])] = []  // trimmed songs (by song and part), most recent last
        private var next = 0                                       // first play that may still sound
        public init(urls: [URL], plan: Plan) { self.urls = urls; self.plan = plan }

        private func samples(_ p: Play) throws -> [Float] {
            let key = "\(p.track)|\(p.from)|\(p.to)"           // a song cut short by its timed repeat is a different part of the file
            if let i = cache.firstIndex(where: { $0.key == key }) { let c = cache.remove(at: i); cache.append(c); return c.samples }
            let s = try LoopAudio.decode(urls[p.track], from: p.from, to: p.to)
            cache.append((key, s)); if cache.count > 3 { cache.removeFirst() }
            return s
        }

        /// `count` stereo frames starting at frame `start` (frames must be asked for in order).
        public func fill(_ out: inout [Float], start: Int, count: Int) throws {
            for i in 0..<(count * 2) { out[i] = 0 }
            let r = Double(LoopAudio.rate), t0 = Double(start) / r, t1 = Double(start + count) / r
            while next < plan.plays.count && plan.plays[next].end < t0 { next += 1 }
            var k = next
            while k < plan.plays.count && plan.plays[k].start < t1 {
                let p = plan.plays[k]; let index = k; let isFirst = k == 0; k += 1
                guard p.end > t0 else { continue }
                let s = try samples(p)
                let pStart = Int((p.start * r).rounded()), n = s.count / 2
                let fi = Int(p.fadeIn * r), fo = Int(p.fadeOut * r), g = Float(p.gain)
                let lo = max(start, pStart), hi = min(start + count, pStart + n)
                guard hi > lo else { continue }
                _ = index
                for f in lo..<hi {
                    let j = f - pStart
                    var w: Float = g
                    if j < fi { w *= Float(sin(Double(j) / Double(fi) * .pi / 2)) }                       // a plain equal-power crossfade (only when one is chosen)
                    if j >= n - fo { w *= Float(cos(Double(j - (n - fo)) / Double(max(1, fo)) * .pi / 2)) }
                    if j < 96 && p.fadeIn == 0 && !isFirst { w *= Float(j) / 96 }        // 2 ms, only so a song never starts with a click
                    if j >= n - 96 && p.fadeOut == 0 { w *= Float(n - j) / 96 }
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
