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
