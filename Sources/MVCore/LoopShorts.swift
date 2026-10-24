// YouTube Shorts from a looping video: one Short per song, made from that song's liveliest stretch (up to 45 seconds) with its scene.
// Upright 1080 × 1920: the scene full width in the middle over a soft, darkened, blurred copy of itself, the song's title above and the video's
// title below. The sound fades in and out. A text file beside each Short has its YouTube title, description and tags.
import Foundation
import AVFoundation
import CoreGraphics
import CoreImage
import AppKit

extension LoopVideo {
    public static let shortSeconds = 45.0

    /// Where each song's Short starts in the song (seconds) and how long it is: the loudest stretch, after the first tenth of the song,
    /// moved to the quietest moment within two seconds so it starts on a breath, not mid-phrase.
    public static func shortWindow(_ url: URL, seconds want: Double = shortSeconds) -> (start: Double, length: Double)? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first, let r = try? AVAssetReader(asset: asset) else { return nil }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1,
                                                                          AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        r.add(out); r.startReading()
        var energy: [Float] = [], acc: Float = 0, n = 0
        while let sb = out.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
            var len = 0, ptr: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
            guard let p = ptr else { continue }
            p.withMemoryRebound(to: Float.self, capacity: len / 4) { f in
                for i in 0..<(len / 4) { acc += f[i] * f[i]; n += 1; if n == 4000 { energy.append(sqrt(acc / 4000)); acc = 0; n = 0 } }    // half a second each
            }
        }
        let total = Double(energy.count) / 2
        guard total > 5 else { return nil }
        let length = min(want, total - 1), w = Int(length * 2)
        guard energy.count > w else { return (0, length) }
        let first = Int(Double(energy.count) * 0.1)
        var best = 0, bestSum: Float = -1, sum = energy[first..<min(energy.count, first + w)].reduce(0, +)
        var i = first
        while i + w <= energy.count {
            if sum > bestSum { bestSum = sum; best = i }
            if i + w < energy.count { sum += energy[i + w] - energy[i] }
            i += 1
        }
        let lo = max(0, best - 4), hi = min(energy.count - w, best + 4)
        let start = (lo...max(lo, hi)).min { energy[$0] < energy[$1] } ?? best
        return (Double(start) / 2, length)
    }

    /// The clip each song is shown with: the scene playing in the middle of its first play.
    static func shortClip(_ p: LoopProject, plan: LoopAudio.Plan, track: Int) -> String? {
        let scenes = sceneStarts(p, plan: plan)
        guard let play = plan.plays.first(where: { $0.track == track }) else { return p.clip }
        let mid = (play.start + play.end) / 2
        return scenes.last(where: { $0.t <= mid })?.clip ?? p.clip
    }

    /// Makes one Short per song into `folder`. Returns the files made.
    @discardableResult
    public static func makeShorts(_ p0: LoopProject, dir: URL, folder: URL, progress: ((String, Double) -> Void)? = nil) async throws -> [URL] {
        var p = p0
        try ensureAnalysis(&p, dir: dir)
        guard let plan = plan(p), p.clip != nil else { throw MVError("Make or add the loop clip first.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var made: [URL] = []
        for (k, t) in p.tracks.enumerated() {
            try Task.checkCancellation()
            progress?("Making Short \(k + 1) of \(p.tracks.count): \(t.title)…", Double(k) / Double(p.tracks.count))
            let song = dir.appendingPathComponent(t.file)
            guard let win = shortWindow(song), let clip = shortClip(p, plan: plan, track: k) else { continue }
            let label = songName(t.title, k)
            let name = String(format: "%02d ", k + 1) + label.replacingOccurrences(of: "/", with: "-")
            let out = folder.appendingPathComponent(name + ".mp4")
            try await renderShort(song: song, window: win, clip: dir.appendingPathComponent(clip), trim: p.trims[clip] ?? ClipTrim(),
                                  title: label, subtitle: p.tracks.count > 1 ? p.shownTitle : "", output: out)
            try shortListing(p, track: k).write(to: folder.appendingPathComponent(name + " – YouTube.txt"), atomically: true, encoding: .utf8)
            made.append(out)
        }
        progress?("Done", 1)
        return made
    }

    /// A song's name without a track number in front ("03 Rain" → "Rain").
    static func songName(_ title: String, _ k: Int) -> String {
        let t = title.replacingOccurrences(of: #"^\s*\d{1,3}(\s*[-.)_]+\s*|\s+)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Song \(k + 1)" : t
    }

    /// The YouTube title, description and tags for a song's Short.
    public static func shortListing(_ p: LoopProject, track k: Int) -> String {
        let song = songName(p.tracks[k].title, k)
        let album = p.shownTitle
        let full = p.playOnce ? "the full album" : "the full \(p.hours == p.hours.rounded() ? "\(Int(p.hours))-hour" : String(format: "%.1f-hour", p.hours)) video"
        let about = p.about.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String((p.tracks.count > 1 ? "\(song) · \(album)" : song).prefix(90)) + " #shorts"
        var d = p.tracks.count > 1 ? "“\(song)” from \(album)." : "“\(song)”."
        if !about.isEmpty { d += "\n\n" + about }
        d += "\n\nListen to \(full) on this channel: calm music for studying, reading, focus and relaxing."
        let tags = ["shorts", "study music", "relaxing music", "calm music", "focus music", song, album].map { $0.lowercased() }
        let hashtags = "#shorts #studymusic #relaxingmusic"
        return "TITLE\n\(title)\n\nDESCRIPTION\n\(d)\n\n\(hashtags)\n\nTAGS\n\(Array(NSOrderedSet(array: tags)).compactMap { $0 as? String }.joined(separator: ", "))\n"
    }

    /// One upright Short: the scene's loop full width in the middle over a blurred copy, the titles, and the song stretch with fades.
    static func renderShort(song: URL, window: (start: Double, length: Double), clip: URL, trim: ClipTrim, title: String, subtitle: String, output: URL) async throws {
        let W = 1080, H = 1920, fgH = 608
        let painter = LoopPainter(clip: clip, W: W, H: fgH, title: nil, trim: trim)
        let period = max(fps, Int((painter.period * Double(fps)).rounded()))
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let titleImg = renderTextImage(NSAttributedString(string: title, attributes: [.font: serifFont(size: 84, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: para]),
                                       maxWidth: CGFloat(W) * 0.86, pad: 40, shadow: true, shadowBlur: 24)
        let subImg = subtitle.isEmpty ? nil : renderTextImage(NSAttributedString(string: subtitle.uppercased(), attributes: [.font: roundedFont(size: 36, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.9), .paragraphStyle: para, .kern: 4]),
                                                              maxWidth: CGFloat(W) * 0.8, pad: 30, shadow: true, shadowBlur: 16)
        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
                                                                         AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
        vIn.expectsMediaDataInRealTime = false; aIn.expectsMediaDataInRealTime = false
        writer.add(vIn); writer.add(aIn)
        guard writer.startWriting() else { throw MVError("The Short could not be started.") }
        writer.startSession(atSourceTime: .zero)
        // the sound: the stretch of the song, faded in (1 s) and out (2.5 s)
        let audio = try songStretch(song, start: window.start, length: window.length)
        let frames = Int(window.length * Double(fps))
        let fgCtx = CGContext(data: nil, width: W, height: fgH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        let ci = CIContext()
        var vi = 0, ai = 0
        let aN = audio.count / 2
        while vi < frames || ai < aN {
            try Task.checkCancellation()
            var did = false
            if ai < aN, aIn.isReadyForMoreMediaData, Double(ai) / 48000 <= Double(vi) / Double(fps) + 1 {
                let n = min(4800, aN - ai)
                if let sb = audioSample(audio, from: ai, count: n) { aIn.append(sb) }
                ai += n; did = true
                if ai >= aN { aIn.markAsFinished() }
            } else if vi < frames, vIn.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool {
                var pb: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                if let pb {
                    painter.draw(loopTime: Double(vi % period) / Double(fps), ctx: fgCtx)
                    if let fg = fgCtx.makeImage() {
                        let t = Double(vi) / Double(fps)
                        let fade = min(1, min(t / 0.6, (window.length - t) / 1.2))
                        // the blurred, darkened background made from the same picture
                        let small = CIImage(cgImage: fg).transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
                        let cover = Double(H) / Double(fgH) * 4
                        let bg = small.clampedToExtent().applyingGaussianBlur(sigma: 10).transformed(by: CGAffineTransform(scaleX: cover, y: cover))
                        let bx = (Double(W) * 1.0 - Double(fg.width) * 0.25 * cover) / 2
                        let bgImg = ci.createCGImage(bg.transformed(by: CGAffineTransform(translationX: bx, y: 0)), from: CGRect(x: 0, y: 0, width: W, height: H))
                        paint(pb) { ctx in
                            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
                            if let b = bgImg { ctx.draw(b, in: CGRect(x: 0, y: 0, width: W, height: H)) }
                            ctx.setFillColor(CGColor(gray: 0, alpha: 0.42)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
                            let fy = Double(H) / 2 - Double(fgH) / 2 + 60                  // a little above the middle (bottom-up coordinates)
                            ctx.draw(fg, in: CGRect(x: 0, y: fy, width: Double(W), height: Double(fgH)))
                            let tw = Double(titleImg.width), th = Double(titleImg.height)
                            ctx.draw(titleImg, in: CGRect(x: (Double(W) - tw) / 2, y: fy + Double(fgH) + 40, width: tw, height: th))
                            if let s = subImg { ctx.draw(s, in: CGRect(x: (Double(W) - Double(s.width)) / 2, y: fy - Double(s.height) - 30, width: Double(s.width), height: Double(s.height))) }
                            if fade < 1 { ctx.setFillColor(CGColor(gray: 0, alpha: 1 - max(0, fade))); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
                        }
                        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(vi), timescale: CMTimeScale(fps)))
                    }
                }
                vi += 1; did = true
                if vi >= frames { vIn.markAsFinished() }
            }
            if writer.status == .failed { throw MVError("The Short could not be made: \(writer.error?.localizedDescription ?? "unknown")") }
            if !did { try await Task.sleep(nanoseconds: 1_000_000) }
        }
        await writer.finishWriting()
        if writer.status != .completed { throw MVError("The Short could not be saved: \(writer.error?.localizedDescription ?? "unknown")") }
    }

    /// A stretch of a song as 48 kHz stereo samples (interleaved), faded in and out.
    static func songStretch(_ url: URL, start: Double, length: Double) throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { throw MVError("The song could not be read.") }
        let r = try AVAssetReader(asset: asset)
        r.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 48000), duration: CMTime(seconds: length, preferredTimescale: 48000))
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                                                                          AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        r.add(out); r.startReading()
        var s: [Float] = []
        while let sb = out.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
            var len = 0, ptr: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
            if let p = ptr { p.withMemoryRebound(to: Float.self, capacity: len / 4) { s.append(contentsOf: UnsafeBufferPointer(start: $0, count: len / 4)) } }
        }
        let n = s.count / 2, fin = 48000, fout = Int(2.5 * 48000)
        for i in 0..<n {
            var g: Float = 1
            if i < fin { g = Float(i) / Float(fin) }
            if n - i < fout { g = min(g, Float(n - i) / Float(fout)) }
            s[2 * i] *= g; s[2 * i + 1] *= g
        }
        return s
    }

    static func audioSample(_ s: [Float], from: Int, count: Int) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var fmt: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * 8, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: count * 8, flags: 0, blockBufferOut: &block) == noErr, let block, let fmt else { return nil }
        s.withUnsafeBufferPointer { b in _ = CMBlockBufferReplaceDataBytes(with: b.baseAddress! + from * 2, blockBuffer: block, offsetIntoDestination: 0, dataLength: count * 8) }
        var sb: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: fmt, sampleCount: count, presentationTimeStamp: CMTime(value: CMTimeValue(from), timescale: 48000), packetDescriptions: nil, sampleBufferOut: &sb)
        return sb
    }
}
