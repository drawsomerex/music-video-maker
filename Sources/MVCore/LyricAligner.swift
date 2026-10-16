// Aligns your pasted lyrics to the recognised words (Needleman–Wunsch) so on-screen text is always yours, timed by the audio.
import Foundation

/// Forced alignment of the user's exact lyrics onto the transcript's word timings.
/// Needleman–Wunsch over normalised tokens; unmatched lyric words are interpolated between anchors.
struct LW { var line: Int; var text: String }

public enum LyricAligner {
    public struct Parsed { public var lines: [String]; public var stanzaBreaks: Set<Int> }  // break *before* line index

    /// Parses pasted lyrics. Blank lines = stanza breaks. `[Chorus]` / `(Verse 2)` markers are dropped but count as breaks.
    public static func parse(_ raw: String) -> Parsed {
        var lines: [String] = []; var breaks = Set<Int>(); var pendingBreak = false
        for l in raw.components(separatedBy: .newlines) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { pendingBreak = true; continue }
            if (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("(") && t.hasSuffix(")") && t.split(separator: " ").count <= 3) {
                pendingBreak = true; continue
            }
            if pendingBreak && !lines.isEmpty { breaks.insert(lines.count) }
            pendingBreak = false
            lines.append(t)
        }
        return Parsed(lines: lines, stanzaBreaks: breaks)
    }

    static func norm(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static let ones = ["zero","one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen","eighteen","nineteen"]
    static let tens = ["","","twenty","thirty","forty","fifty","sixty","seventy","eighty","ninety"]
    static func below100(_ n: Int) -> [String] { n < 20 ? [ones[n]] : (n % 10 == 0 ? [tens[n / 10]] : [tens[n / 10], ones[n % 10]]) }
    static func numberWords(_ s: String) -> [String] {
        guard let n = Int(s) else { return [s] }
        if n < 100 { return below100(n) }
        if n < 1000 { return [ones[n / 100], "hundred"] + (n % 100 == 0 ? [] : below100(n % 100)) }
        if n >= 1100 && n < 2000 || n >= 2010 && n < 2100 {      // years: "eighteen ninety seven"
            let a = n / 100, b = n % 100
            return below100(a) + (b == 0 ? ["hundred"] : (b < 10 ? ["oh", ones[b]] : below100(b)))
        }
        return [s]
    }
    /// Normalised sub-tokens of a written word: splits hyphens/punctuation, spells digits ("97" → ninety seven).
    static func expand(_ w: String) -> [String] {
        var out: [String] = []
        for piece in w.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") }) {
            let s = String(piece)
            if s.allSatisfy({ $0.isNumber }) { out += numberWords(s).map(norm) } else { let n = norm(s); if !n.isEmpty { out.append(n) } }
        }
        return out
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let la = Array(a), lb = Array(b)
        var prev = Array(0...lb.count)
        for i in 1...la.count {
            var cur = [i] + Array(repeating: 0, count: lb.count)
            for j in 1...lb.count {
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + (la[i-1] == lb[j-1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[lb.count]) / Double(max(la.count, lb.count))
    }

    /// Aligns the user's lyrics using windowed transcripts. A cursor walks forward through the lyrics; each window's words are matched to
    /// the lyric span near the cursor. A word spoken at time T appears in windows starting in [T−L+d, T], so
    /// T ≈ (first window start + L + last window start) / 2.
    public static func align(lines: [String], windows: [TranscriptWindow], windowLength L: Double, songDuration: Double) -> (lines: [LyricLine], coverage: Double) {
        var lw: [LW] = []
        for (i, l) in lines.enumerated() { for w in l.split(whereSeparator: { $0.isWhitespace }) { lw.append(LW(line: i, text: String(w))) } }
        struct Tok { var word: Int; var n: String }
        var lt: [Tok] = []
        for (i, w) in lw.enumerated() { for t in expand(w.text) { lt.append(Tok(word: i, n: t)) } }
        var seen = [[Double]](repeating: [], count: lw.count)
        var cursor = 0, misses = 0
        let NEG = -1e9

        func match(_ toks: [String], lo: Int, hi: Int) -> [(Int, Int)] {
            let n = toks.count, m = hi - lo
            if n == 0 || m <= 0 { return [] }
            var dp = [[Double]](repeating: [Double](repeating: NEG, count: m + 1), count: n + 1)
            var bt = [[UInt8]](repeating: [UInt8](repeating: 0, count: m + 1), count: n + 1)
            for j in 0...m { dp[0][j] = -0.05 * Double(abs(lo + j - cursor)) }      // prefer matches near the cursor
            for i in 1...n { for j in 0...m {
                var best = NEG; var b: UInt8 = 0
                if dp[i-1][j] > NEG { best = dp[i-1][j] - 0.8; b = 2 }
                if j > 0 {
                    let sim = similarity(toks[i-1], lt[lo + j - 1].n)
                    let s = sim >= 0.7 ? 2 * sim - 0.6 : -1
                    if dp[i-1][j-1] > NEG && dp[i-1][j-1] + s > best { best = dp[i-1][j-1] + s; b = 1 }
                    if dp[i][j-1] > NEG && dp[i][j-1] - 0.3 > best { best = dp[i][j-1] - 0.3; b = 3 }
                }
                dp[i][j] = best; bt[i][j] = b
            } }
            var j = (0...m).max { dp[n][$0] < dp[n][$1] }!
            var i = n; var pairs: [(Int, Int)] = []
            while i > 0 {
                switch bt[i][j] {
                case 1: pairs.append((lo + j - 1, i - 1)); i -= 1; j -= 1
                case 2: i -= 1
                default: j -= 1
                }
            }
            return pairs.reversed().filter { similarity(toks[$0.1], lt[$0.0].n) >= 0.7 }
        }

        for w in windows {
            let toks = w.text.split(whereSeparator: { $0.isWhitespace }).flatMap { expand(String($0)) }
            if toks.count < 2 || lt.isEmpty { continue }
            var lo = max(0, cursor - 6), hi = min(lt.count, cursor + toks.count * 3 + 25)
            if misses >= 4 { lo = 0; hi = lt.count }                                   // lost track: search everywhere
            let good = match(toks, lo: lo, hi: hi)
            if good.count >= max(2, toks.count / 2) {
                for (li, _) in good { seen[lt[li].word].append(w.start) }
                cursor = max(cursor, good.last!.0 - 1); misses = 0
            } else { misses += 1 }
        }

        var times = [(Double, Double)?](repeating: nil, count: lw.count)
        var matched = 0
        for i in lw.indices where !seen[i].isEmpty {
            let t = (seen[i].min()! + L + seen[i].max()!) / 2 - 0.04
            times[i] = (t, t + 0.5); matched += 1
        }
        let spanStart = windows.first(where: { !$0.text.isEmpty })?.start ?? 0
        let spanEnd = windows.last(where: { !$0.text.isEmpty }).map { $0.start + L } ?? songDuration
        return finalize(lines: lines, lw: lw, times: &times, matched: matched, spanStart: spanStart, spanEnd: spanEnd, songDuration: songDuration)
    }

    /// Aligns the user's lyrics to exact word timestamps (Needleman–Wunsch over normalised tokens; hyphens split, digits spelled).
    public static func align(lines: [String], words asr: [TimedWord], songDuration: Double) -> (lines: [LyricLine], coverage: Double) {
        var lw: [LW] = []
        for (i, l) in lines.enumerated() { for w in l.split(whereSeparator: { $0.isWhitespace }) { lw.append(LW(line: i, text: String(w))) } }
        struct Tok { var word: Int; var n: String }
        var lt: [Tok] = []
        for (i, w) in lw.enumerated() { for t in expand(w.text) { lt.append(Tok(word: i, n: t)) } }
        struct ATok { var n: String; var s: Double; var e: Double }
        var at: [ATok] = []
        for w in asr {
            let parts = expand(w.text); guard !parts.isEmpty else { continue }
            let d = (w.end - w.start) / Double(parts.count)
            for (k, t) in parts.enumerated() { at.append(ATok(n: t, s: w.start + d * Double(k), e: w.start + d * Double(k + 1))) }
        }
        var times = [(Double, Double)?](repeating: nil, count: lw.count)
        var matched = 0
        let nt = lt.count, m = at.count
        if nt > 0 && m > 0 {
            let gap = -0.6
            var dp = [[Float]](repeating: [Float](repeating: 0, count: m + 1), count: nt + 1)
            var bt = [[UInt8]](repeating: [UInt8](repeating: 0, count: m + 1), count: nt + 1)
            for i in 1...nt { dp[i][0] = Float(gap) * Float(i); bt[i][0] = 2 }
            for j in 1...m { dp[0][j] = Float(gap) * Float(j) * 0.5; bt[0][j] = 3 }     // extra heard words are cheap to skip
            for i in 1...nt { for j in 1...m {
                let sim = similarity(lt[i-1].n, at[j-1].n)
                let s: Double = sim >= 0.999 ? 2 : (sim >= 0.6 ? 2 * sim - 0.4 : -1)
                let d = dp[i-1][j-1] + Float(s), u = dp[i-1][j] + Float(gap), l = dp[i][j-1] + Float(gap) * 0.5
                if d >= u && d >= l { dp[i][j] = d; bt[i][j] = 1 } else if u >= l { dp[i][j] = u; bt[i][j] = 2 } else { dp[i][j] = l; bt[i][j] = 3 }
            } }
            var i = nt, j = m
            while i > 0 || j > 0 {
                let b = bt[i][j]
                if b == 1 {
                    if similarity(lt[i-1].n, at[j-1].n) >= 0.6 {
                        let w = lt[i-1].word
                        if let t = times[w] { times[w] = (min(t.0, at[j-1].s), max(t.1, at[j-1].e)) } else { times[w] = (at[j-1].s, at[j-1].e) }
                    }
                    i -= 1; j -= 1
                } else if b == 2 { i -= 1 } else { j -= 1 }
            }
            matched = times.filter { $0 != nil }.count
        }
        return finalize(lines: lines, lw: lw, times: &times, matched: matched, spanStart: asr.first?.start ?? 0, spanEnd: asr.last?.end ?? songDuration, songDuration: songDuration)
    }

    /// Shared tail: fill unmatched words by interpolation, enforce monotonic times and sane durations, build the lines.
    static func finalize(lines: [String], lw: [LW], times: inout [(Double, Double)?], matched: Int, spanStart: Double, spanEnd: Double, songDuration: Double) -> (lines: [LyricLine], coverage: Double) {
        let n = lw.count
        let coverage = n == 0 ? 0 : Double(matched) / Double(n)

        // Fallback: almost nothing matched → spread across the vocal span.
        if coverage < 0.12 {
            let s = spanStart, e = max(spanEnd, s + 1)
            let total = Double(lw.reduce(0) { $0 + max($1.text.count, 2) })
            var acc = 0.0
            for i in 0..<n {
                let w = Double(max(lw[i].text.count, 2))
                times[i] = (s + (e - s) * acc / total, s + (e - s) * (acc + w) / total)
                acc += w
            }
        } else {
            // Interpolate unmatched spans while respecting line boundaries so leading/trailing unmatched words
            // never get pulled across inter-line pauses or instrumental breaks.
            var i = 0
            while i < n {
                if times[i] != nil { i += 1; continue }
                var j = i; while j < n && times[j] == nil { j += 1 }
                let prevEnd: Double? = i > 0 ? times[i - 1]!.1 : nil
                let nextStart: Double? = j < n ? times[j]!.0 : nil
                let prevLine: Int? = i > 0 ? lw[i - 1].line : nil
                let nextLine: Int? = j < n ? lw[j].line : nil

                var curStart = prevEnd ?? 0.0
                var curEnd = nextStart ?? songDuration
                if curEnd < curStart + 0.05 { curEnd = curStart + 0.05 }

                var subIdx = i
                // 1) Trailing unmatched words belonging to `prevLine` stay attached to `prevEnd`
                if let pl = prevLine, lw[subIdx].line == pl {
                    var subEnd = subIdx
                    while subEnd < j && lw[subEnd].line == pl { subEnd += 1 }
                    let cnt = subEnd - subIdx
                    let wts = (subIdx..<subEnd).map { Double(max(lw[$0].text.count, 2)) }
                    let tw = wts.reduce(0, +)
                    let maxSpan = nextLine == pl ? (curEnd - curStart) : min(Double(cnt) * 0.32, (curEnd - curStart) * (subEnd == j ? 0.65 : 0.35))
                    let a = curStart
                    let b = max(a + 0.04, a + maxSpan)
                    var acc = 0.0
                    for k in subIdx..<subEnd {
                        let w = wts[k - subIdx]
                        times[k] = (a + (b - a) * acc / tw, a + (b - a) * (acc + w) / tw)
                        acc += w
                    }
                    curStart = min(curEnd, b + 0.12)
                    subIdx = subEnd
                }

                // 2) Leading unmatched words belonging to `nextLine` stay attached right before `nextStart`
                var tailStart = j
                if let nl = nextLine, subIdx < j, lw[j - 1].line == nl {
                    while tailStart > subIdx && lw[tailStart - 1].line == nl { tailStart -= 1 }
                    let cnt = j - tailStart
                    let wts = (tailStart..<j).map { Double(max(lw[$0].text.count, 2)) }
                    let tw = wts.reduce(0, +)
                    let avail = max(0.04, curEnd - curStart)
                    let maxSpan = min(Double(cnt) * 0.28, avail * (tailStart == subIdx ? 0.72 : 0.45))
                    let b = curEnd
                    let a = max(curStart, b - maxSpan)
                    var acc = 0.0
                    for k in tailStart..<j {
                        let w = wts[k - tailStart]
                        times[k] = (a + (b - a) * acc / tw, a + (b - a) * (acc + w) / tw)
                        acc += w
                    }
                    curEnd = max(curStart, a - 0.12)
                }

                // 3) Any remaining unmatched words (e.g. an entire unmatched line in the middle)
                if subIdx < tailStart {
                    // Group by line so each unmatched line stays compact instead of stretching across silence
                    var lineGroups: [( start: Int, end: Int )] = []
                    var g = subIdx
                    while g < tailStart {
                        let lnum = lw[g].line
                        var ge = g
                        while ge < tailStart && lw[ge].line == lnum { ge += 1 }
                        lineGroups.append((g, ge))
                        g = ge
                    }
                    let totalGap = max(0.05, curEnd - curStart)
                    let sliceSpan = totalGap / Double(lineGroups.count)
                    for (gi, grp) in lineGroups.enumerated() {
                        let cnt = grp.end - grp.start
                        let wts = (grp.start..<grp.end).map { Double(max(lw[$0].text.count, 2)) }
                        let tw = wts.reduce(0, +)
                        let winA = curStart + Double(gi) * sliceSpan
                        let winB = winA + sliceSpan
                        let cap = Double(cnt) * 0.34
                        var a = winA, b = winB
                        if b - a > cap {
                            let lead = min(0.45, (b - a - cap) * 0.35)
                            a += lead
                            b = a + cap
                        }
                        var acc = 0.0
                        for k in grp.start..<grp.end {
                            let w = wts[k - grp.start]
                            times[k] = (a + (b - a) * acc / tw, a + (b - a) * (acc + w) / tw)
                            acc += w
                        }
                    }
                }
                i = j
            }
        }

        // Monotonic cleanup + natural sung syllable hold durations
        var out: [LyricLine] = []
        var tcur = 0.0
        var idx = 0
        for (li, text) in lines.enumerated() {
            var words: [TimedWord] = []
            while idx < n && lw[idx].line == li {
                var (s, e) = times[idx]!
                s = max(s, tcur)
                e = max(e, s + 0.12)
                e = min(e, s + 2.2)
                words.append(TimedWord(text: lw[idx].text, start: s, end: e))
                tcur = s + 0.02
                idx += 1
            }
            // Extend brief TDT token emissions across sustained sung vowels within the same phrase
            for k in 0..<words.count {
                let charLen = max(2, words[k].text.filter { $0.isLetter }.count)
                let naturalHold = min(0.52, max(0.22, Double(charLen) * 0.065))
                if k + 1 < words.count {
                    let nextStart = words[k + 1].start
                    let gapToNext = nextStart - words[k].start
                    if gapToNext <= 0.65 && (words[k].end - words[k].start) < naturalHold {
                        words[k].end = min(words[k].start + naturalHold, max(words[k].start + 0.09, nextStart - 0.02))
                    } else {
                        words[k].end = min(words[k].end, max(words[k].start + 0.08, nextStart))
                    }
                } else if (words[k].end - words[k].start) < naturalHold {
                    words[k].end = min(songDuration, words[k].start + naturalHold)
                }
            }
            out.append(LyricLine(id: li, text: text, words: words))
            if let last = words.last { tcur = max(tcur, last.end) }
        }
        return (out, coverage)
    }
}
