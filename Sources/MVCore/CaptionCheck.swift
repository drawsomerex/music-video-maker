// A second, independent look at the captions' timing, made from the sound itself (not from the speech recogniser that timed them).
// Every caption line should start where there is music; a line that starts in silence, or after the music has ended, was timed wrongly
// (typically lines the recogniser could not hear, which are spread between two known words, often at the very end of a song).
// Such lines are moved onto the nearest real start of sound that keeps the lines in order, and anything that still hangs past the last sound is trimmed.
import Foundation

public enum CaptionCheck {
    public struct Result {
        public var lines: [LyricLine]
        public var checked: Int
        public var moved: [Int] = []            // line numbers moved onto the music
        public var unresolved: [Int] = []       // line numbers that start where nothing sounds and could not be placed
        public var soundEnd: Double             // the last moment with any sound
        public var summary: String
        public var changed: Bool { !moved.isEmpty }
    }

    /// Loudness in decibels every 10 ms from 16 kHz samples.
    public static func envelope(_ pcm: [Int16]) -> [Float] {
        let hop = 160, n = pcm.count / hop
        guard n > 0 else { return [] }
        var out = [Float](repeating: -120, count: n)
        for i in 0..<n {
            var s: Float = 0
            for k in (i * hop)..<((i + 1) * hop) { let v = Float(pcm[k]) / 32768; s += v * v }
            out[i] = 10 * log10(s / Float(hop) + 1e-12)
        }
        return out
    }

    struct Sound { var threshold: Float; var env: [Float]
        func hasSound(_ a: Double, _ b: Double) -> Bool {
            let lo = max(0, Int(a * 100)), hi = min(env.count - 1, Int(b * 100))
            guard lo <= hi else { return false }
            for i in lo...hi where env[i] > threshold { return true }
            return false
        }
        /// The last moment with sound (at least a tenth of a second of it).
        var end: Double {
            var i = env.count - 1
            while i > 10 { if env[(i - 9)...i].min()! > threshold { return Double(i + 1) / 100 }; i -= 1 }
            return 0
        }
        /// Starts of sound: after at least a quarter second below the threshold, or a sudden rise of 9 dB within 60 ms.
        var onsets: [Double] {
            var out: [Double] = []
            var quiet = 0
            for i in 6..<env.count {
                if env[i] <= threshold { quiet += 1; continue }
                let after = quiet
                quiet = 0
                let rise = env[i] - env[i - 6] >= 9
                if (after >= 25 || rise) && (out.last.map { Double(i) / 100 - $0 >= 0.12 } ?? true) { out.append(Double(i) / 100) }
            }
            return out
        }
    }

    static func sound(_ env: [Float]) -> Sound? {
        guard env.count > 300 else { return nil }
        let sorted = env.sorted()
        let loud = sorted[Int(Double(sorted.count - 1) * 0.95)]
        guard loud > -50 else { return nil }                                    // practically silent: nothing to check against
        return Sound(threshold: max(loud - 32, -70), env: env)
    }

    /// Checks every line against the sound and repairs the ones that start in silence. `tail` lines (the last fifth) are reported separately.
    public static func run(lines inLines: [LyricLine], env: [Float], songDuration: Double) -> Result {
        var lines = inLines
        let n = lines.count
        guard n > 0, let snd = sound(env) else { return Result(lines: lines, checked: 0, soundEnd: songDuration, summary: "The captions could not be checked against the sound (the song is too quiet or too short).") }
        let soundEnd = min(snd.end, songDuration)
        let onsets = snd.onsets
        var moved: [Int] = [], unresolved: [Int] = []
        func shift(_ i: Int, by d: Double) {
            for k in lines[i].words.indices {
                lines[i].words[k].start = max(0, lines[i].words[k].start + d)
                lines[i].words[k].end = max(lines[i].words[k].start + 0.08, lines[i].words[k].end + d)
            }
        }
        for i in 0..<n where !lines[i].words.isEmpty {
            let s = lines[i].start
            if snd.hasSound(s - 0.08, s + 0.4) { continue }                      // it starts where there is music
            let lower = i > 0 ? lines[i - 1].start + 0.15 : 0
            let upper = i + 1 < n ? lines[i + 1].start - 0.15 : soundEnd
            let near = onsets.filter { $0 >= lower && $0 <= upper && abs($0 - s) <= 3.0 }.min { abs($0 - s) < abs($1 - s) }
            if let o = near { shift(i, by: o - s); moved.append(i) } else { unresolved.append(i) }
        }
        // a line must end before the next one starts, and nothing hangs on after the last sound
        for i in 0..<n where !lines[i].words.isEmpty {
            let cap = i + 1 < n && !lines[i + 1].words.isEmpty ? lines[i + 1].start - 0.02 : soundEnd + 0.5
            for k in lines[i].words.indices { lines[i].words[k].end = max(lines[i].words[k].start + 0.08, min(lines[i].words[k].end, cap)) }
        }
        let tailFrom = Int(Double(n) * 0.8)
        let movedTail = moved.filter { $0 >= tailFrom }.count
        var text: String
        if moved.isEmpty && unresolved.isEmpty { text = "Checked all \(n) captions against the sound: every one starts on the music." }
        else {
            text = "Checked \(n) captions against the sound."
            if !moved.isEmpty { text += " \(moved.count) started in silence" + (movedTail > 0 ? " (\(movedTail) near the end)" : "") + " and \(moved.count == 1 ? "was" : "were") moved onto the music." }
            if !unresolved.isEmpty { text += " \(unresolved.count) could not be placed (line\(unresolved.count == 1 ? "" : "s") \(unresolved.prefix(6).map { String($0 + 1) }.joined(separator: ", "))): use Sooner or Later, or move that line on the timeline." }
        }
        return Result(lines: lines, checked: n, moved: moved, unresolved: unresolved, soundEnd: soundEnd, summary: text)
    }
}

extension Pipeline {
    /// Double-checks a project's captions against its song and repairs what starts in silence. Returns nil if the song could not be read.
    @discardableResult
    public static func checkCaptions(plan: inout Plan, work: URL) async -> CaptionCheck.Result? {
        guard let pcm = try? await Transcriber.loadMono16k(path: audioURL(plan, work: work).path), !pcm.isEmpty else { return nil }
        let r = CaptionCheck.run(lines: plan.lines, env: CaptionCheck.envelope(pcm), songDuration: plan.songDuration)
        guard r.checked > 0 else { plan.captionCheck = r.summary; return r }
        if r.changed {
            plan.lines = r.lines
            plan.sections = plan.pictureBoundaries == nil ? Planner.rebound(plan.sections, lines: plan.lines, duration: plan.songDuration) : TimelineEditor.assignLines(plan.sections, lines: plan.lines)
        }
        plan.captionCheck = r.summary + (plan.timing == "exact" ? "" : " Timing is approximate (exact word timing was not available).")
        return r
    }
}
