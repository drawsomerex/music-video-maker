// On-device picture analysis (Apple Vision): aesthetics, Ken Burns focus point and similarity.
import Foundation
import Vision
import ImageIO

/// On-device image analysis: aesthetics score, attention saliency (Ken Burns focus point), feature print (diversity).
public struct ImageAnalysis {
    public var aesthetics: Double      // 0...1
    public var isUtility: Bool
    public var focus: CGPoint          // normalised, origin top-left
    public var print: VNFeaturePrintObservation?
}

public enum ImageScorer {
    private static let subjectLock = NSLock()
    nonisolated(unsafe) private static var subjectCache: [String: [CGPoint]] = [:]

    /// The main subjects of a picture (people first, then other salient objects), as normalised points, origin top-left, at most 3, well apart from each other.
    /// The automatic Ken Burns travels from one subject to the next. Results are cached per file.
    public static func subjects(fileURL: URL) -> [CGPoint] {
        let mod = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = fileURL.path + "|\(mod)"
        subjectLock.lock(); if let c = subjectCache[key] { subjectLock.unlock(); return c }; subjectLock.unlock()
        var out: [CGPoint] = []
        if let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
           let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary) { out = detect(img) }
        subjectLock.lock(); subjectCache[key] = out; subjectLock.unlock()
        return out
    }

    /// The main subjects of a picture that is already in memory (for example the last frame of a clip).
    public static func subjects(image: CGImage) -> [CGPoint] {
        let scale = 640.0 / Double(max(image.width, image.height))
        guard scale < 1, let ctx = CGContext(data: nil, width: Int(Double(image.width) * scale), height: Int(Double(image.height) * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return detect(image) }
        ctx.interpolationQuality = .medium; ctx.draw(image, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        return detect(ctx.makeImage() ?? image)
    }

    static func detect(_ img: CGImage) -> [CGPoint] {
        var out: [CGPoint] = []
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        let people = VNDetectHumanRectanglesRequest(); people.upperBodyOnly = false
        let objects = VNGenerateObjectnessBasedSaliencyImageRequest()
        try? handler.perform([people, objects])
        var cands: [(CGPoint, Double)] = []
        for p in (people.results ?? []).sorted(by: { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }).prefix(3) {
            let b = p.boundingBox; if b.width * b.height > 0.01 { cands.append((CGPoint(x: b.midX, y: 1 - (b.minY + 0.72 * b.height)), 2 + Double(b.width * b.height))) }   // aim at the head and chest
        }
        for o in objects.results?.first?.salientObjects ?? [] {
            let b = o.boundingBox; let area = Double(b.width * b.height)
            if area > 0.015 && area < 0.8 { cands.append((CGPoint(x: b.midX, y: 1 - b.midY), area)) }
        }
        for (p, _) in cands.sorted(by: { $0.1 > $1.1 }) where out.count < 3 {
            if !out.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 0.18 }) { out.append(p) }
        }
        return out
    }

    public static func analyze(fileURL: URL) -> ImageAnalysis? {
        guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                   kCGImageSourceCreateThumbnailWithTransform: true,
                                                                   kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary) else { return nil }
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        let sal = VNGenerateAttentionBasedSaliencyImageRequest()
        let fp = VNGenerateImageFeaturePrintRequest()
        var reqs: [VNRequest] = [sal, fp]
        var aes: VNRequest?
        if #available(macOS 15.0, *) { let r = VNCalculateImageAestheticsScoresRequest(); aes = r; reqs.append(r) }
        try? handler.perform(reqs)

        var aesthetics = 0.5, utility = false
        if #available(macOS 15.0, *), let r = aes as? VNCalculateImageAestheticsScoresRequest, let o = r.results?.first {
            aesthetics = (Double(o.overallScore) + 1) / 2; utility = o.isUtility
        }
        var focus = CGPoint(x: 0.5, y: 0.5)
        if let o = sal.results?.first, let box = o.salientObjects?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
            focus = CGPoint(x: box.boundingBox.midX, y: 1 - box.boundingBox.midY)
        }
        return ImageAnalysis(aesthetics: aesthetics, isUtility: utility, focus: focus, print: fp.results?.first)
    }

}
