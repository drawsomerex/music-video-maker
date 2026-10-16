// Records a song playing on the Mac (System Audio via ScreenCaptureKit, or Microphone/Line-In via AVAudioEngine),
// transcribes lyrics in real time with Parakeet, and automatically trims leading/trailing silence.
import Foundation
import AVFoundation
import CoreMedia
import ScreenCaptureKit

public struct TrimResult: Sendable {
    public var url: URL
    public var duration: Double
    public var trimmedStart: Double
    public var trimmedEnd: Double
}

public final class LiveSongRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public enum Source: String, CaseIterable, Identifiable, Sendable {
        case systemAudio = "System Audio (playing on this Mac)"
        case microphone = "Microphone / Audio Input"
        public var id: String { rawValue }
    }

    private let lock = NSLock()
    /// 48 kHz stereo interleaved Int16 samples (L, R, L, R...) for the high-quality song file.
    private var stereo48k: [Int16] = []
    /// 16 kHz mono Int16 samples for fast real-time Parakeet transcription.
    private var mono16k: [Int16] = []
    private var currentPeak: Float = 0
    private var isRunning = false

    private var scStream: SCStream?
    private var audioEngine: AVAudioEngine?
    private let sampleQueue = DispatchQueue(label: "mv.recorder.samples", qos: .userInteractive)

    public override init() { super.init() }

    public var recordedDuration: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(stereo48k.count / 2) / 48000.0
    }

    public var level: Float {
        lock.lock(); defer { lock.unlock() }
        return currentPeak
    }

    /// Starts capturing audio from the chosen source.
    public func start(source: Source) async throws {
        lock.lock()
        stereo48k.removeAll(keepingCapacity: true)
        mono16k.removeAll(keepingCapacity: true)
        currentPeak = 0
        isRunning = true
        lock.unlock()

        switch source {
        case .systemAudio:
            try await startSystemAudio()
        case .microphone:
            try await startMicrophone()
        }
    }

    private func startSystemAudio() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw RecordingPermissionError()
        }
        guard let display = content.displays.first else {
            throw MVError("No display found for system audio capture.")
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48000
        cfg.channelCount = 2
        // Minimal video dimensions required by ScreenCaptureKit on macOS 14
        cfg.width = 2
        cfg.height = 2
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        scStream = stream
    }

    private func startMicrophone() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw MVError("Microphone permission was denied. Enable it in System Settings → Privacy & Security → Microphone.") }
        } else if status == .denied || status == .restricted {
            throw MVError("Microphone permission is disabled. Enable it in System Settings → Privacy & Security → Microphone.")
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hwFormat = input.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw MVError("No active audio input device was found.")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buf, _ in
            self?.ingestAVBuffer(buf)
        }
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return }
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }

        var ablSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &ablSize, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard ablSize > 0 else { return }
        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: ablSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        let ablPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuf: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: ablPtr, bufferListSize: ablSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuf
        )
        guard status == noErr else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(ablPtr)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let sr = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48000

        var left = [Float](repeating: 0, count: numSamples)
        var right = [Float](repeating: 0, count: numSamples)

        if isFloat {
            if isNonInterleaved || buffers.count >= 2 {
                if let p0 = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                    for i in 0..<numSamples { left[i] = p0[i] }
                }
                if buffers.count >= 2, let p1 = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                    for i in 0..<numSamples { right[i] = p1[i] }
                } else {
                    right = left
                }
            } else if let p = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<numSamples {
                    left[i] = p[i * channels]
                    right[i] = channels > 1 ? p[i * channels + 1] : p[i * channels]
                }
            }
        } else {
            // 16-bit integer fallback
            if let p = buffers[0].mData?.assumingMemoryBound(to: Int16.self) {
                for i in 0..<numSamples {
                    left[i] = Float(p[i * channels]) / 32768.0
                    right[i] = channels > 1 ? Float(p[i * channels + 1]) / 32768.0 : left[i]
                }
            }
        }
        appendFloatFrames(left: left, right: right, sampleRate: sr)
    }

    private func ingestAVBuffer(_ buffer: AVAudioPCMBuffer) {
        let n = Int(buffer.frameLength)
        guard n > 0, let chData = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let sr = buffer.format.sampleRate
        var left = [Float](repeating: 0, count: n)
        var right = [Float](repeating: 0, count: n)
        let p0 = chData[0]
        for i in 0..<n { left[i] = p0[i] }
        if channels > 1 {
            let p1 = chData[1]
            for i in 0..<n { right[i] = p1[i] }
        } else {
            right = left
        }
        appendFloatFrames(left: left, right: right, sampleRate: sr)
    }

    private func appendFloatFrames(left: [Float], right: [Float], sampleRate: Double) {
        let n = left.count
        guard n > 0 else { return }

        // Compute peak level for UI meter
        var peak: Float = 0
        for i in 0..<n {
            let m = max(abs(left[i]), abs(right[i]))
            if m > peak { peak = m }
        }

        // Resample to 48 kHz stereo Int16
        let out48Count = sampleRate == 48000 ? n : max(1, Int((Double(n) * 48000.0 / sampleRate).rounded()))
        var chunk48 = [Int16]()
        chunk48.reserveCapacity(out48Count * 2)
        for i in 0..<out48Count {
            let srcIdx = min(n - 1, Int(Double(i) * sampleRate / 48000.0))
            let l = Int16(clamping: Int((left[srcIdx] * 32767.0).rounded()))
            let r = Int16(clamping: Int((right[srcIdx] * 32767.0).rounded()))
            chunk48.append(l); chunk48.append(r)
        }

        // Resample to 16 kHz mono Int16 for Parakeet
        let out16Count = max(1, Int((Double(n) * 16000.0 / sampleRate).rounded()))
        var chunk16 = [Int16]()
        chunk16.reserveCapacity(out16Count)
        for i in 0..<out16Count {
            let srcIdx = min(n - 1, Int(Double(i) * sampleRate / 16000.0))
            let mono = 0.5 * (left[srcIdx] + right[srcIdx])
            chunk16.append(Int16(clamping: Int((mono * 32767.0).rounded())))
        }

        lock.lock()
        if isRunning {
            stereo48k.append(contentsOf: chunk48)
            mono16k.append(contentsOf: chunk16)
            currentPeak = min(1.0, peak * 1.8)
        }
        lock.unlock()
    }

    /// Snapshot of the 16 kHz mono buffer for live transcription while recording continues.
    public func snapshotMono16k() -> [Int16] {
        lock.lock(); defer { lock.unlock() }
        return mono16k
    }

    /// Stops recording, trims leading and trailing silence, and writes a clean 48 kHz stereo WAV file.
    public func stopAndTrim(outputURL: URL, progress: ProgressHandler? = nil) async throws -> TrimResult {
        lock.lock()
        isRunning = false
        currentPeak = 0
        lock.unlock()

        if let s = scStream {
            try? await s.stopCapture()
            scStream = nil
        }
        if let e = audioEngine {
            e.inputNode.removeTap(onBus: 0)
            e.stop()
            audioEngine = nil
        }

        progress?("Analyzing & trimming silence at start and end…", 0.25)
        let rawStereo: [Int16] = {
            lock.lock(); defer { lock.unlock() }
            return stereo48k
        }()

        let totalFrames = rawStereo.count / 2
        guard totalFrames > 48000 else {
            throw MVError("Recording is too short (under 1 second). Play a song and record at least a few seconds.")
        }

        let trimmed = Self.trimStereo48k(rawStereo)
        progress?("Saving trimmed audio file…", 0.75)
        let wavData = Transcriber.wav(trimmed.samples[...], sampleRate: 48000, channels: 2)
        try? FileManager.default.removeItem(at: outputURL)
        try wavData.write(to: outputURL, options: .atomic)
        progress?("Audio ready", 1.0)
        return TrimResult(url: outputURL, duration: trimmed.duration, trimmedStart: trimmed.trimmedStart, trimmedEnd: trimmed.trimmedEnd)
    }

    /// Detects and cuts off silence before the song begins and after the song ends (48 kHz stereo interleaved Int16).
    public static func trimStereo48k(_ samples: [Int16]) -> (samples: [Int16], duration: Double, trimmedStart: Double, trimmedEnd: Double) {
        let sr = 48000
        let totalFrames = samples.count / 2
        guard totalFrames > sr else {
            return (samples, Double(totalFrames) / Double(sr), 0, 0)
        }
        let winFrames = 960 // 20 ms per window
        let numWins = totalFrames / winFrames
        guard numWins > 10 else {
            return (samples, Double(totalFrames) / Double(sr), 0, 0)
        }

        var rms = [Float](repeating: 0, count: numWins)
        for w in 0..<numWins {
            var sum: Float = 0
            let base = w * winFrames * 2
            for f in 0..<winFrames {
                let l = Float(samples[base + f * 2]) / 32768.0
                let r = Float(samples[base + f * 2 + 1]) / 32768.0
                let m = 0.5 * (l + r)
                sum += m * m
            }
            rms[w] = (sum / Float(winFrames)).squareRoot()
        }

        let sorted = rms.sorted()
        let peak = sorted.last ?? 0
        let p10 = sorted[max(0, numWins / 10)]
        // Adaptive threshold: above quiet room/system floor, or 2.5% of song peak
        let threshold = max(0.0035, min(0.035, max(p10 * 3.0, peak * 0.025)))

        // Require 3 consecutive 20ms windows (60ms) above threshold to ignore isolated clicks
        var firstWin = 0
        for w in 0..<(numWins - 2) {
            if rms[w] >= threshold && rms[w + 1] >= threshold && rms[w + 2] >= threshold {
                firstWin = w; break
            }
        }
        var lastWin = numWins - 1
        for w in stride(from: numWins - 1, through: 2, by: -1) {
            if rms[w] >= threshold && rms[w - 1] >= threshold && rms[w - 2] >= threshold {
                lastWin = w; break
            }
        }
        if lastWin <= firstWin {
            return (samples, Double(totalFrames) / Double(sr), 0, 0)
        }

        // Keep a gentle 0.15s pre-roll and 0.25s tail so note attacks and decays sound natural
        let padStartFrames = Int(0.15 * Double(sr))
        let padEndFrames = Int(0.25 * Double(sr))
        let startFrame = max(0, firstWin * winFrames - padStartFrames)
        let endFrame = min(totalFrames, (lastWin + 1) * winFrames + padEndFrames)

        let trimmedStart = Double(startFrame) / Double(sr)
        let trimmedEnd = Double(max(0, totalFrames - endFrame)) / Double(sr)
        let slice = Array(samples[(startFrame * 2)..<(endFrame * 2)])
        let dur = Double(endFrame - startFrame) / Double(sr)
        return (slice, dur, trimmedStart, trimmedEnd)
    }

    /// Transcribes a 16 kHz mono PCM buffer into formatted lyric lines (grouped into lines at pauses ≥ 0.45 s or sentence endings).
    public static func transcribePCM16k(_ pcm: [Int16], config: Config = .load()) async throws -> String {
        guard pcm.count > 16000 else { return "" }
        // Trim leading silence on the 16kHz buffer so Parakeet only processes active audio
        let hop = 320 // 20 ms at 16 kHz
        let nWins = pcm.count / hop
        var firstActive = 0
        for w in 0..<nWins {
            var peak: Int32 = 0
            for k in (w * hop)..<((w + 1) * hop) { peak = max(peak, abs(Int32(pcm[k]))) }
            if Float(peak) / 32768.0 > 0.005 { firstActive = max(0, w - 5); break }
        }
        let activeSlice = pcm[(firstActive * hop)...]
        guard activeSlice.count > 12000 else { return "" }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mv-live-\(UUID().uuidString).wav")
        try Transcriber.wav(activeSlice, sampleRate: 16000, channels: 1).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let omlx = OMLX(config: config)
        if (try? await omlx.ensureReady()) != nil,
           let words = try? await OMLXRuntime.wordTimes(audioPath: tmp.path, modelID: omlx.stt), !words.isEmpty {
            return formatWordsAsLyrics(words)
        }
        // Fallback to HTTP full-text transcription if wordTimes isn't available
        if let text = try? await omlx.transcribe(wav: Transcriber.wav(activeSlice, sampleRate: 16000, channels: 1), timeout: 60), !text.isEmpty {
            return text.replacingOccurrences(of: #"([.!?,;])\s+"#, with: "$1\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Groups timed words into natural song lyric lines based on vocal pauses and punctuation.
    public static func formatWordsAsLyrics(_ words: [TimedWord]) -> String {
        guard !words.isEmpty else { return "" }
        var lines: [String] = []
        var current: [String] = []
        for (i, w) in words.enumerated() {
            let clean = w.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            current.append(clean)
            let endsSentence = clean.last.map { ".!?".contains($0) } ?? false
            let endsClause = clean.last.map { ",;:—".contains($0) } ?? false
            let gapAfter = i + 1 < words.count ? (words[i + 1].start - w.end) : 99.0
            if i == words.count - 1 || gapAfter >= 0.55 || (endsSentence && current.count >= 3) || (endsClause && current.count >= 6) || current.count >= 10 {
                lines.append(current.joined(separator: " "))
                current.removeAll()
                // Insert a blank line (stanza break) on longer instrumental pauses (≥ 2.4 s)
                if i < words.count - 1 && gapAfter >= 2.4 {
                    lines.append("")
                }
            }
        }
        if !current.isEmpty { lines.append(current.joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }

    /// Transcribes an existing audio file on disk into formatted lyric lines.
    public static func transcribeAudioFile(url: URL, config: Config = .load()) async throws -> String {
        let pcm = try await Transcriber.loadMono16k(path: url.path)
        return try await transcribePCM16k(pcm, config: config)
    }

    /// Trims leading and trailing silence from any audio file on disk and writes a 48 kHz stereo WAV to `outputURL`.
    public static func trimAudioFile(at inputURL: URL, outputURL: URL, progress: ProgressHandler? = nil) async throws -> TrimResult {
        progress?("Reading audio for silence trimming…", 0.1)
        let asset = AVURLAsset(url: inputURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw MVError("No audio track found in that file.") }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
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
        progress?("Cutting leading & trailing silence…", 0.5)
        let trimmed = trimStereo48k(samples)
        progress?("Writing trimmed WAV…", 0.85)
        let wavData = Transcriber.wav(trimmed.samples[...], sampleRate: 48000, channels: 2)
        try? FileManager.default.removeItem(at: outputURL)
        try wavData.write(to: outputURL, options: .atomic)
        progress?("Done", 1.0)
        return TrimResult(url: outputURL, duration: trimmed.duration, trimmedStart: trimmed.trimmedStart, trimmedEnd: trimmed.trimmedEnd)
    }
}


/// macOS refused system-audio capture. After an app update it can keep showing the switch as "on" for the old copy of the app, so the UI
/// offers a one-click repair (reset the entry, grant again, restart) instead of just telling the user to look in System Settings.
public struct RecordingPermissionError: LocalizedError {
    public init() {}
    public var errorDescription: String? { "macOS isn't letting Music Video Maker record the sound your Mac is playing. Open Settings ▸ Fix recording permission to repair it." }
}
