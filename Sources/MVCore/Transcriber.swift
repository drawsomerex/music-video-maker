// Fallback transcription through windowed HTTP requests when exact word timing isn't available.
import Foundation
import AVFoundation

/// Speech recognition through oMLX (Parakeet). oMLX's Parakeet endpoint returns text without word times, so the song is
/// transcribed in short overlapping windows; `LyricAligner` then recovers each word's time from which windows contain it.
public struct TranscriptWindow: Codable { public var start: Double; public var text: String }

public enum Transcriber {
    public static let windowLength = 4.0
    public static let hop = 0.75

    private static let pcmLock = NSLock()
    nonisolated(unsafe) private static var cachedPCMKey = ""
    nonisolated(unsafe) private static var cachedPCM: [Int16] = []

    static func fileStamp(_ path: String) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        return "\(path)|\(a?[.size] ?? 0)|\(a?[.modificationDate] ?? Date.distantPast)"
    }

    /// Decodes any audio file to 16 kHz mono Int16 samples (cached in memory for the current song).
    public static func loadMono16k(path: String) async throws -> [Int16] {
        let key = fileStamp(path)
        if let hit: [Int16] = pcmLock.withLock({ (key == cachedPCMKey && !cachedPCM.isEmpty) ? cachedPCM : nil }) {
            return hit
        }

        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw MVError("No audio track found in that file.") }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        reader.add(out)
        guard reader.startReading() else { throw MVError("Couldn't decode audio: \(reader.error?.localizedDescription ?? "?")") }
        var samples: [Int16] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            let n = CMBlockBufferGetDataLength(bb) / 2
            var chunk = [Int16](repeating: 0, count: n)
            CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: n * 2, destination: &chunk)
            samples += chunk
        }
        pcmLock.withLock {
            cachedPCMKey = key; cachedPCM = samples
        }
        return samples
    }

    public static func wav(_ s: ArraySlice<Int16>, sampleRate: Int = 16000, channels: Int = 1) -> Data {
        var d = Data(); let bytes = s.count * 2
        let byteRate = sampleRate * channels * 2
        let blockAlign = channels * 2
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(channels); u32(sampleRate); u32(byteRate); u16(blockAlign); u16(16); d.append("data".data(using: .ascii)!); u32(bytes)
        s.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: $0.baseAddress, count: $0.count)) }
        return d
    }

    /// One request over the whole song → clean plain text (the windowed pass is only used for timing).
    public static func fullText(audioPath: String, omlx: OMLX) async throws -> String {
        let pcm = try await loadMono16k(path: audioPath)
        return try await omlx.transcribe(wav: wav(pcm[...]), timeout: 900).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func transcribe(audioPath: String, omlx: OMLX, progress: ProgressHandler? = nil) async throws -> [TranscriptWindow] {
        progress?("Reading audio", 0.02)
        let pcm = try await loadMono16k(path: audioPath)
        let total = Double(pcm.count) / 16000
        let L = windowLength
        var starts: [Double] = []; var t = 0.0
        while t < total - 1.0 { starts.append(t); t += hop }
        var results = [String](repeating: "", count: starts.count)
        var done = 0

        try await withThrowingTaskGroup(of: (Int, String).self) { g in
            var next = 0
            func add() {
                guard next < starts.count else { return }
                let i = next; next += 1
                let a = Int(starts[i] * 16000), b = min(pcm.count, a + Int(L * 16000))
                let data = wav(pcm[a..<b])
                g.addTask { (i, try await omlx.transcribe(wav: data).trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            for _ in 0..<8 { add() }
            while let (i, text) = try await g.next() {
                results[i] = text
                done += 1; let d = done
                if d % 8 == 0 { progress?("Transcribing with Parakeet (oMLX)", 0.05 + 0.9 * Double(d) / Double(starts.count)) }
                add()
            }
        }
        return zip(starts, results).map { TranscriptWindow(start: $0, text: $1) }
    }
}

extension Transcriber {
    struct WaveformCache: Codable { var key: String; var peaks: [Float] }

    /// Peak level (0…1) every 10 ms — for drawing the waveform in the Shorts editor. Cached in `work/waveform.json` when `work` is given.
    public static func waveform(audioPath: String, work: URL? = nil) async throws -> [Float] {
        let key = fileStamp(audioPath)
        let cacheURL = work?.appendingPathComponent("waveform.json")
        if let u = cacheURL, let c = try? JSONDecoder().decode(WaveformCache.self, from: Data(contentsOf: u)), c.key == key, !c.peaks.isEmpty {
            return c.peaks
        }
        let pcm = try await loadMono16k(path: audioPath)
        let step = 160
        var out = [Float](); out.reserveCapacity(pcm.count / step + 1)
        var i = 0
        while i < pcm.count {
            var m: Int32 = 0
            for k in i..<min(pcm.count, i + step) { m = max(m, abs(Int32(pcm[k]))) }
            out.append(Float(m) / 32768); i += step
        }
        let peak = max(out.max() ?? 1, 0.05)
        let norm = out.map { min(1, $0 / peak) }
        if let u = cacheURL {
            try? JSONEncoder().encode(WaveformCache(key: key, peaks: norm)).write(to: u, options: .atomic)
        }
        return norm
    }
}
