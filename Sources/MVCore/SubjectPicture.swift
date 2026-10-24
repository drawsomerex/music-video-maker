// A subject picture: a photo of the person, animal, object or place that should appear in the pictures that are drawn. It is sent to the picture
// maker as a reference ("draw this subject"), so the subject is redrawn in the chosen style; the photo itself never appears in the video.
// Subject photos can be your own or found with the search here (Openverse and Wikimedia Commons; no account needed).
import Foundation
import CoreGraphics
import ImageIO
import Vision

/// What a subject is: decided from the photo (auto), or chosen. A place is kept accurate with a slightly different angle; a creature (or an object)
/// is shown from a clearly different angle and pose.
public enum SubjectKind: String, Codable, CaseIterable, Sendable {
    case auto, place, creature
    public var name: String { switch self { case .auto: "Decide from the photo"; case .place: "A building or landscape"; case .creature: "A creature, person or object" } }
}

public struct SubjectHit: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var thumb: URL
    public var full: URL
    public var source: String
}

public enum SubjectPicture {
    static let agent = "MusicVideoMaker/1.0 (https://github.com/drawsomerex/music-video-maker)"

    /// Searches Openverse and Wikimedia Commons at the same time; results interleaved, best first.
    public static func search(_ query: String) async -> [SubjectHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        async let a = openverse(enc)
        async let b = wikimedia(enc)
        let (x, y) = await (a, b)
        var out: [SubjectHit] = [], seen = Set<URL>()
        for i in 0..<max(x.count, y.count) {
            for h in [i < x.count ? x[i] : nil, i < y.count ? y[i] : nil].compactMap({ $0 }) where !seen.contains(h.full) { seen.insert(h.full); out.append(h) }
        }
        return out
    }

    static func get(_ url: URL) async -> Data? {
        var r = URLRequest(url: url); r.timeoutInterval = 30; r.setValue(agent, forHTTPHeaderField: "User-Agent")
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return d
    }

    static func openverse(_ q: String) async -> [SubjectHit] {
        guard let u = URL(string: "https://api.openverse.org/v1/images/?q=\(q)&page_size=30"), let d = await get(u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let rs = j["results"] as? [[String: Any]] else { return [] }
        return rs.compactMap { r in
            guard let id = r["id"] as? String, let t = (r["thumbnail"] as? String).flatMap(URL.init), let f = (r["url"] as? String).flatMap(URL.init) else { return nil }
            return SubjectHit(id: "ov:" + id, title: r["title"] as? String ?? "", thumb: t, full: f, source: "Openverse")
        }
    }

    static func wikimedia(_ q: String) async -> [SubjectHit] {
        guard let u = URL(string: "https://commons.wikimedia.org/w/api.php?action=query&generator=search&gsrsearch=\(q)%20filetype:bitmap&gsrnamespace=6&gsrlimit=30&prop=imageinfo&iiprop=url%7Csize&iiurlwidth=400&format=json"),
              let d = await get(u), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let pages = (j["query"] as? [String: Any])?["pages"] as? [String: Any] else { return [] }
        let list = pages.values.compactMap { $0 as? [String: Any] }.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        return list.compactMap { p in
            guard let info = (p["imageinfo"] as? [[String: Any]])?.first, let ts = info["thumburl"] as? String, let t = URL(string: ts),
                  let orig = (info["url"] as? String).flatMap(URL.init) else { return nil }
            let w = info["width"] as? Int ?? 0
            let full = w > 1600 ? (URL(string: ts.replacingOccurrences(of: "/400px-", with: "/1600px-")) ?? orig) : orig     // a 1600-pixel copy, not a huge original
            return SubjectHit(id: "wm:" + ((p["title"] as? String) ?? ts), title: ((p["title"] as? String) ?? "").replacingOccurrences(of: "File:", with: ""), thumb: t, full: full, source: "Wikimedia Commons")
        }
    }

    /// Downloads a search result into `dir` and returns the file.
    public static func download(_ hit: SubjectHit, to dir: URL) async throws -> URL {
        var data = await get(hit.full)
        if data == nil { data = await get(hit.thumb) }
        guard let d = data else { throw MVError("That picture couldn't be downloaded. Try another one.") }
        let ext = ["jpg", "jpeg", "png", "webp", "gif", "tif", "tiff"].contains(hit.full.pathExtension.lowercased()) ? hit.full.pathExtension.lowercased() : "jpg"
        let out = dir.appendingPathComponent("subject-\(Int(Date().timeIntervalSince1970)).\(ext)")
        try d.write(to: out)
        guard loadImage(out, maxPixel: 64) != nil else { try? FileManager.default.removeItem(at: out); throw MVError("That result isn't a picture that can be read. Try another one.") }
        return out
    }

    /// The subject picture as a reference JPEG for the picture maker.
    public static func referenceJPEG(_ file: URL) -> Data? {
        guard let img = loadImage(file, maxPixel: 1024) else { return nil }
        return PictureFit.jpegData(img, quality: 0.88)
    }

    /// How different two pictures look to Apple Vision (0 = the same; an unrelated picture is about 1.1). Below `tooClose` a drawn picture is too much
    /// like the subject photo (the same pose and angle): only a warning is shown, nothing is redrawn.
    public static let tooClose: Float = 0.82
    public static func distance(_ a: URL, _ b: URL) -> Float? {
        func print(_ u: URL) -> VNFeaturePrintObservation? {
            let r = VNGenerateImageFeaturePrintRequest()
            guard (try? VNImageRequestHandler(url: u).perform([r])) != nil else { return nil }
            return r.results?.first as? VNFeaturePrintObservation
        }
        guard let x = print(a), let y = print(b) else { return nil }
        var d: Float = 0
        return (try? x.computeDistance(&d, to: y)) != nil ? d : nil
    }

    /// What the picture maker is told about a creature (or an object): a clearly different angle and pose, never a copy.
    public static let instruction = "only a guide to WHO or WHAT the subject is (the main person, animal, object or place it shows, with its kind, colours, markings and distinctive features). " +
        "Make a completely NEW, original picture of that subject: show it from a clearly DIFFERENT camera angle and distance than the reference, in a DIFFERENT pose or position, " +
        "in the new setting described, redrawn entirely in the art style described. Never copy, trace or reproduce the reference picture, its composition, framing, pose, background, " +
        "lighting or photographic look; a viewer must not be able to recognise the reference photo in the result"
    /// What the picture maker is told about a building or a landscape: true to the real place, seen from a slightly different angle.
    public static let placeInstruction = "a real building or landscape that must stay ACCURATE: keep its true architecture or landforms (shape, proportions, layout, windows, towers, " +
        "rooflines, materials, the lie of the hills, water and rocks) so it is clearly recognisable as the same place. Show it from a SLIGHTLY different camera angle " +
        "(a small step to one side, a little higher or lower, a slightly different distance), redrawn entirely in the art style described, with the light, weather and season of the scene described. " +
        "Do not copy the photo's exact framing, crop, light or photographic look, and do not invent or remove parts of the building or landscape"

    /// The instruction for a subject of this kind.
    public static func instruction(_ kind: SubjectKind) -> String { kind == .place ? placeInstruction : instruction }
    /// Below this a drawn picture is too much like the photo. A place is meant to stay close (only the angle moves a little), so only a near copy counts.
    public static func tooClose(_ kind: SubjectKind) -> Float { kind == .place ? 0.45 : tooClose }

    /// What the subject photo shows, from Apple Vision's on-device labels: a creature (a person or an animal) or a place (a building or a landscape).
    public static func detect(_ url: URL) -> SubjectKind {
        let r = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(url: url).perform([r])) != nil, let res = r.results else { return .creature }
        func conf(_ ids: [String]) -> Float { res.filter { ids.contains($0.identifier) }.map(\.confidence).max() ?? 0 }
        if conf(["animal", "people", "adult", "child", "baby", "bird", "insect", "fish", "reptile", "mammal", "canine", "feline"]) >= 0.3 { return .creature }
        if conf(["structure", "building", "architecture", "castle", "church", "tower", "bridge", "house", "land", "hill", "mountain", "cliff", "lake", "water_body", "forest", "valley", "shore", "beach", "waterfall"]) >= 0.3 { return .place }
        return .creature
    }
    /// The kind to use: your choice, or what the photo shows.
    public static func kind(_ chosen: SubjectKind, file: URL) -> SubjectKind { chosen == .auto ? detect(file) : chosen }

}
