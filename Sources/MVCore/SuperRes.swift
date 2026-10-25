// Sharper pictures for free: Apple's on-device super resolution (VideoToolbox, macOS 26 and later) enlarges every drawn picture 4×,
// then it is saved at 3840 wide, so the slow camera zooms stay crisp. Where it isn't available the picture is used as it came.
import Foundation
import VideoToolbox
import CoreImage
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

public enum SuperRes {
    public static let width = 3840

    /// True when this Mac can enlarge pictures.
    public static var available: Bool {
        if #available(macOS 26.0, *) { return VTSuperResolutionScalerConfiguration.isSupported && VTSuperResolutionScalerConfiguration.supportedScaleFactors.contains(4) }
        return false
    }

    /// Enlarges the picture at `input` and writes it to `output` as a JPEG (3840 wide). Returns false (and writes nothing) when it can't.
    public static func enlarge(_ input: URL, to output: URL) async -> Bool {
        guard #available(macOS 26.0, *), available,
              let src = CGImageSourceCreateWithURL(input as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              img.width <= 1920, img.width < width else { return false }
        guard let up = await enlarge4x(img) else { return false }
        let ctx = CIContext()
        let scale = Double(width) / Double(up.extent.width)
        let small = up.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ctx.createCGImage(small, from: small.extent.integral),
              let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    @available(macOS 26.0, *)
    static func enlarge4x(_ img: CGImage) async -> CIImage? {
        let w = img.width, h = img.height
        guard let cfg = VTSuperResolutionScalerConfiguration(frameWidth: w, frameHeight: h, scaleFactor: 4, inputType: .image, usePrecomputedFlow: false,
                                                             qualityPrioritization: .normal, revision: VTSuperResolutionScalerConfiguration.defaultRevision) else { return nil }
        if cfg.configurationModelStatus != .ready {           // the first time: Apple's model is downloaded once
            let ok: Bool = await withCheckedContinuation { k in cfg.downloadConfigurationModel { e in k.resume(returning: e == nil) } }
            guard ok, cfg.configurationModelStatus == .ready else { return nil }
        }
        let proc = VTFrameProcessor()
        do { try proc.startSession(configuration: cfg) } catch { return nil }
        defer { proc.endSession() }
        func buffer(_ attrs: [String: Any], _ w: Int, _ h: Int) -> CVPixelBuffer? {
            var a = attrs; a[kCVPixelBufferWidthKey as String] = w; a[kCVPixelBufferHeightKey as String] = h
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, (a[kCVPixelBufferPixelFormatTypeKey as String] as? NSNumber)?.uint32Value ?? kCVPixelFormatType_32BGRA, a as CFDictionary, &pb)
            return pb
        }
        let ctx = CIContext()
        guard let inPB = buffer(cfg.sourcePixelBufferAttributes, w, h), let outPB = buffer(cfg.destinationPixelBufferAttributes, w * 4, h * 4) else { return nil }
        ctx.render(CIImage(cgImage: img), to: inPB)
        let t = CMTime(value: 0, timescale: 30)
        guard let sf = VTFrameProcessorFrame(buffer: inPB, presentationTimeStamp: t), let df = VTFrameProcessorFrame(buffer: outPB, presentationTimeStamp: t),
              let params = VTSuperResolutionScalerParameters(sourceFrame: sf, previousFrame: nil, previousOutputFrame: nil, opticalFlow: nil, submissionMode: .random, destinationFrame: df) else { return nil }
        do { try await proc.process(parameters: params) } catch { return nil }
        return CIImage(cvPixelBuffer: outPB)
    }
}
