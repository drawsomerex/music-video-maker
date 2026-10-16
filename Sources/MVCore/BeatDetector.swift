// Finds beats in the song (used to time cuts and pulses in the punchy Shorts style).
import Foundation

/// Cheap onset detection (energy flux) so the picture can pulse on the music's hits. Times are relative to `start`.
public enum BeatDetector {
    struct BeatCache: Codable { var key: String; var beats: [Double] }

    public static func beats(audioPath: String, start: Double, end: Double, work: URL? = nil) async -> [Double] {
        let key = Transcriber.fileStamp(audioPath)
        let cacheURL = work?.appendingPathComponent("beats.json")
        if let u = cacheURL, let c = try? JSONDecoder().decode(BeatCache.self, from: Data(contentsOf: u)), c.key == key {
            return c.beats.filter { $0 >= start && $0 <= end }.map { $0 - start }
        }
        guard let pcm = try? await Transcriber.loadMono16k(path: audioPath), !pcm.isEmpty else { return [] }
        let hop = 160                                                         // 10 ms
        let n = pcm.count / hop
        guard n > 100 else { return [] }
        var e = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var s = 0.0
            for k in (i * hop)..<((i + 1) * hop) { let v = Double(pcm[k]) / 32768; s += v * v }
            e[i] = (s / Double(hop)).squareRoot()
        }
        let c = e.map { log(1 + 40 * $0) }                                    // compress dynamics
        var flux = [Double](repeating: 0, count: n)
        for i in 6..<n { flux[i] = max(0, c[i] - c[(i - 6)..<i].reduce(0, +) / 6) }
        var allBeats: [Double] = []; var last = -1.0
        let win = 200                                                         // adaptive threshold over ±1 s
        for i in 4..<(n - 4) {
            let lo = max(0, i - win), hi = min(n, i + win)
            let seg = flux[lo..<hi]; let mean = seg.reduce(0, +) / Double(seg.count)
            let sd = (seg.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(seg.count)).squareRoot()
            let isPeak = flux[i] >= flux[(i - 4)...(i + 4)].max()!
            if isPeak && flux[i] > mean + 0.9 * sd && flux[i] > 0.02 {
                let t = Double(i) * 0.01
                if t - last >= 0.30 { allBeats.append(t); last = t }
            }
        }
        if let u = cacheURL {
            try? JSONEncoder().encode(BeatCache(key: key, beats: allBeats)).write(to: u, options: .atomic)
        }
        return allBeats.filter { $0 >= start && $0 <= end }.map { $0 - start }
    }
}
