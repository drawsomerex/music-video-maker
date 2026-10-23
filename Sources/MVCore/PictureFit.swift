// Outside photos that aren't widescreen (16:9): either extended to 16:9 by the picture maker with every original pixel kept, or cropped where you choose.
//
// Extending: the photo is placed in the middle of a 16:9 canvas (the empty sides filled with a soft blur of it, as a hint of colour), the picture maker
// paints a version where those sides continue the scene, and then the ORIGINAL photo is laid back over the middle with a soft edge. The picture maker
// always redraws the whole picture a little; its middle is thrown away, so the photo stays exactly as it was and only the new edges are generated.
import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Vision
import UniformTypeIdentifiers

public enum PictureFit {
    public static let target = 16.0 / 9.0
    /// How far from 16:9 a picture may be and still be just trimmed (3 %).
    public static let tolerance = 0.03

    /// Width ÷ height of a picture (upright), or nil if it can't be read.
    public static func aspect(_ url: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double, let h = props[kCGImagePropertyPixelHeight] as? Double, w > 0, h > 0 else { return nil }
        let o = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        return o >= 5 ? h / w : w / h
    }
    /// True for a picture (not a video) that isn't close enough to 16:9 to be trimmed without asking.
    public static func needsFitting(_ url: URL) -> Bool {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true, let a = aspect(url) else { return false }
        return abs(a / target - 1) > tolerance
    }
    /// Words for what is wrong with the shape.
    public static func describe(_ url: URL) -> String {
        guard let a = aspect(url) else { return "This picture isn't widescreen." }
        let kind = a < 0.95 ? "an upright (portrait) photo" : (a < 1.05 ? "a square photo" : (a < target ? "narrower than widescreen" : "wider than widescreen"))
        return "This picture is \(kind) (\(String(format: "%.2f", a)) : 1; widescreen is 1.78 : 1)."
    }

    /// The largest 16:9 crop of the picture, as fractions of its width and height, centred on `centre` (fractions, 0…1).
    public static func cropRect(aspect a: Double, centre: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        if a > target { let w = target / a; return CGRect(x: min(1 - w, max(0, centre.x - w / 2)), y: 0, width: w, height: 1) }
        let h = a / target; return CGRect(x: 0, y: min(1 - h, max(0, centre.y - h / 2)), width: 1, height: h)
    }

    /// The picture at its own size (never enlarged; very large photos are brought down to 4096 pixels).
    static func native(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return loadImage(url, maxPixel: min(4096, max(w, h)))
    }

    /// Saves the part `rect` (fractions, top-left origin) of the picture as a JPEG.
    public static func crop(_ url: URL, rect: CGRect, output: URL) throws {
        guard let img = native(url) else { throw MVError("The picture couldn't be read.") }
        let W = Double(img.width), H = Double(img.height)
        let r = CGRect(x: rect.minX * W, y: rect.minY * H, width: rect.width * W, height: rect.height * H).integral
        guard let c = img.cropping(to: r) else { throw MVError("The picture couldn't be cropped.") }
        try writeJPEG(c, to: output)
    }

    /// Extends the picture to 16:9: the picture maker paints the missing sides, then the original is laid back over the middle. Returns the cost.
    public static func extend(_ url: URL, output: URL, scene: String = "", config: Config = .load()) async throws -> Double {
        guard let img = native(url) else { throw MVError("The picture couldn't be read.") }
        let iw = Double(img.width), ih = Double(img.height), a = iw / ih
        // the canvas: the photo at full size, the missing sides added
        let CW = a < target ? (ih * target).rounded() : iw, CH = a < target ? ih : (iw / target).rounded()
        let place = CGRect(x: ((CW - iw) / 2).rounded(), y: ((CH - ih) / 2).rounded(), width: iw, height: ih)      // top-left origin
        // the hint for the picture maker: the photo in the middle, a soft blur of it filling the sides
        guard let hint = canvas(CW, CH, { ctx in
            let ci = CIImage(cgImage: img), s = max(CW / iw, CH / ih)
            let bg = ci.transformed(by: CGAffineTransform(scaleX: s, y: s)).clampedToExtent().applyingGaussianBlur(sigma: 40)
                .cropped(to: CGRect(x: (iw * s - CW) / 2, y: (ih * s - CH) / 2, width: CW, height: CH))
            if let b = ciContext.createCGImage(bg, from: bg.extent) { ctx.draw(b, in: CGRect(x: 0, y: 0, width: CW, height: CH)) }
            ctx.draw(img, in: flip(place, CH))
        }) else { throw MVError("The picture couldn't be prepared.") }
        let sides = a < target ? "left and right" : "top and bottom"
        let prompt = "Extend this exact picture to a 16:9 widescreen frame. The middle part is a finished \(a < target ? "photo" : "picture") and must stay exactly as it is: " +
            "the same content, framing, scale, position, colours, light and style. The soft blurred bands on the \(sides) are only placeholders: replace them with a sharp, " +
            "natural continuation of the same scene, as if the original had been taken wider with the same camera" + (scene.isEmpty ? "" : " (the scene: \(scene))") + ". " +
            "Continue the horizon, ground, sky, water and every edge seamlessly across the join, with the same lighting, perspective, grain and texture. " +
            "Do not add any new subject, person, animal, text, logo or frame. No borders, no visible seams, no blur."
        guard let hintJPEG = jpegData(hint, quality: 0.9) else { throw MVError("The picture couldn't be prepared.") }
        let gen = try await OpenRouter.generateImage(prompt: prompt, apiKey: config.openRouterKey, referenceJPEGs: [hintJPEG])
        guard let src = CGImageSourceCreateWithData(gen.data as CFData, nil), let painted = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw MVError("The extended picture couldn't be read.") }
        guard let out = composite(img, painted: painted) else { throw MVError("The extended picture couldn't be made.") }
        try writeJPEG(out, to: output)
        return gen.costUSD
    }

    /// The painted 16:9 picture scaled to the canvas and lined up with the photo, with the original photo laid over its middle (soft only where new sides meet it).
    static func composite(_ img: CGImage, painted: CGImage) -> CGImage? {
        let iw = Double(img.width), ih = Double(img.height), a = iw / ih
        let CW = a < target ? (ih * target).rounded() : iw, CH = a < target ? ih : (iw / target).rounded()
        let place = CGRect(x: ((CW - iw) / 2).rounded(), y: ((CH - ih) / 2).rounded(), width: iw, height: ih)
        // the painted version, scaled to the canvas and nudged so its middle lines up with the photo
        var shift = CGSize.zero
        if let pc = canvas(CW, CH, { $0.draw(painted, in: CGRect(x: 0, y: 0, width: CW, height: CH)) }), let mid = pc.cropping(to: place.integral) {
            let req = VNTranslationalImageRegistrationRequest(targetedCGImage: mid, options: [:])
            if (try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])) != nil, let t = (req.results?.first as? VNImageTranslationAlignmentObservation)?.alignmentTransform,
               abs(t.tx) < iw * 0.05, abs(t.ty) < ih * 0.05 { shift = CGSize(width: t.tx, height: t.ty) }
        }
        // the result: the painted canvas, then the original over the middle with a soft edge (only where new sides meet it)
        let feather = min(place.width, place.height) * 0.04
        return canvas(CW, CH, { ctx in
            ctx.draw(painted, in: CGRect(x: shift.width, y: shift.height, width: CW, height: CH))      // Vision's offset, in the same bottom-up coordinates as drawing
            guard let mask = edgeMask(Int(iw), Int(ih), feather: feather, horizontal: a < target) else { ctx.draw(img, in: flip(place, CH)); return }
            ctx.saveGState(); ctx.clip(to: flip(place, CH), mask: mask); ctx.draw(img, in: flip(place, CH)); ctx.restoreGState()
        })
    }

    // MARK: helpers
    static func flip(_ r: CGRect, _ H: Double) -> CGRect { CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height) }
    static func canvas(_ W: Double, _ H: Double, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        draw(ctx); return ctx.makeImage()
    }
    /// White inside, fading to black over `feather` pixels at the two edges that meet the new sides.
    static func edgeMask(_ w: Int, _ h: Int, feather: Double, horizontal: Bool) -> CGImage? {
        var px = [UInt8](repeating: 255, count: w * h)
        let n = max(1.0, feather)
        for y in 0..<h { for x in 0..<w {
            let d = horizontal ? Double(min(x, w - 1 - x)) : Double(min(y, h - 1 - y))
            if d < n { let v = d / n; px[y * w + x] = UInt8((v * v * (3 - 2 * v) * 255).rounded()) }
        } }
        guard let data = CFDataCreate(nil, px, px.count), let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: 0), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
    static func jpegData(_ img: CGImage, quality: Double) -> Data? {
        let d = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(d, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? d as Data : nil
    }
    static func writeJPEG(_ img: CGImage, to url: URL) throws {
        guard let d = jpegData(img, quality: 0.93) else { throw MVError("The picture couldn't be saved.") }
        try d.write(to: url)
    }
}
