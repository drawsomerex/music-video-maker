// The picture-style library: ready-made styles you can edit or delete, plus styles you add yourself. Changes are saved permanently.
import Foundation
import Combine

public final class StyleLibrary: ObservableObject, @unchecked Sendable {
    public static let shared = StyleLibrary()

    /// "AI Auto" is not a real style: it means "let the AI choose a style that fits the song".
    public static let auto = StylePreset(id: StylePreset.autoID, name: "AI Auto (match the song)", prompt: "", builtIn: true)

    static let builtIns: [(String, String)] = [
        ("Oil Painting", "Museum-quality impasto oil painting on linen canvas, rich visible brushstrokes, warm chiaroscuro lighting, deep painterly textures and atmospheric depth."),
        ("Acrylic Painting", "Vibrant modern acrylic painting on canvas, bold expressive brushwork, saturated pigments, crisp layered edges and dynamic contrast."),
        ("Vector Image", "Clean flat vector illustration, bold geometric shapes, crisp bezier lines, mid-century modern screenprint color palette and stylized atmospheric shading."),
        ("Realistic", "Photorealistic 35mm cinematic still frame, natural golden-hour and practical lighting, shallow depth of field, Kodak Vision3 film grain and anamorphic lens bokeh."),
        ("Watercolor & Ink", "Delicate hand-painted watercolor and fountain-pen ink wash on cold-press cotton paper, soft bleeding pigments, luminous highlights and organic paper grain."),
        ("Studio Anime", "Lush hand-painted anime background art, gouache sky and foliage, warm nostalgia, soft sunlight beams and detailed cinematic staging."),
        ("Vintage Comic Book", "Classic inked graphic novel illustration, bold crosshatching, halftone Ben-Day dot shading, dramatic noir shadows and vintage print color registration."),
        ("Neon Cyberpunk", "Atmospheric cyberpunk concept art, rain-slicked neon reflections, cyan and magenta volumetric fog, moody night-time lighting and high-contrast cinematic framing."),
        ("Charcoal & Gold Leaf", "Expressive charcoal and graphite drawing on textured rag paper accented with warm kintsugi gold leaf highlights, dramatic smudges and poetic contrast."),
        ("3D Claymation Diorama", "Handcrafted stop-motion miniature diorama, sculpted polymer clay and felt textures, warm miniature studio spotlights and tilt-shift macro depth of field."),
        ("Ukiyo-e Woodblock Print", "Traditional Japanese Ukiyo-e woodblock print, carved sumi ink outlines, flat mineral pigments on handmade washi paper, stylized waves and clouds."),
        ("Stained Glass", "Luminous cathedral stained-glass mosaic, leaded black contours, jewel-toned translucent glass panels glowing with backlit sunbeams."),
        ("Retro 1970s Poster", "Warm 1970s airbrushed vinyl album cover art, sun-bleached Kodachrome palette, subtle distressed halftone grain and sweeping cinematic horizon."),
        ("Pencil Sketch", "Detailed graphite pencil sketch on cream drawing paper, fine hatching and soft smudged shading, visible construction lines and a hand-drawn, observational feel."),
        ("Soft Pastel Chalk", "Soft chalk-pastel drawing on toned paper, velvety blended colour, gentle powdery texture, warm dreamy light and delicate edges."),
        ("Impressionist Painting", "Impressionist oil painting in loose dabs of broken colour, shimmering natural light, visible brushwork, soft edges and a fleeting, atmospheric mood."),
        ("Art Nouveau Poster", "Elegant Art Nouveau poster illustration, flowing organic lines, ornamental floral borders, muted gold and sage palette and flat decorative shapes."),
        ("Pixel Art", "Detailed retro pixel-art scene, limited colour palette, crisp square pixels, atmospheric dithering and charming 16-bit video-game staging."),
        ("Low-Poly 3D", "Stylised low-poly 3D render, faceted geometric surfaces, clean gradients, soft studio lighting and a calm, minimalist composition."),
        ("Paper Cut-out Collage", "Layered paper cut-out collage, hand-cut shapes with soft drop shadows between layers, textured craft papers and a warm handmade storybook look."),
        ("Vintage Sepia Photograph", "Authentic 19th-century sepia photograph, soft focus, faded edges, gentle film scratches and the quiet grain of an old albumen print."),
        ("1950s Technicolor Film", "Saturated 1950s Technicolor film still, rich ruby reds and teal blues, theatrical lighting, painted-backdrop depth and glamorous widescreen framing."),
        ("Film Noir", "High-contrast black-and-white film noir, venetian-blind shadows, wet streets, hard side lighting and moody smoke-filled atmosphere."),
        ("Storybook Illustration", "Warm children's storybook illustration, soft gouache and coloured-pencil textures, gentle rounded shapes, cosy lighting and a friendly, timeless feel."),
        ("Pop Art", "Bold pop-art illustration, flat vivid colours, thick black outlines, Ben-Day dots and punchy graphic contrast in the style of 1960s screen prints."),
        ("Gothic Graphic Novel", "Dark gothic graphic-novel art, heavy ink shadows, sweeping silhouettes, desaturated palette with a single accent colour and dramatic mist."),
        ("Surrealist Painting", "Dreamlike surrealist oil painting, impossible but gently logical juxtapositions, long shadows, glowing skies and meticulous smooth brushwork."),
        ("Folk Art", "Charming naive folk-art painting, flat decorative shapes, bright traditional colours, patterned borders and a hand-painted wooden-panel feel."),
        ("Blueprint Drawing", "Technical blueprint-style drawing, crisp white linework on deep cyan paper, measured annotations, precise perspective and subtle grid texture."),
        ("Dreamy Soft-Focus Photo", "Dreamy soft-focus photograph, glowing backlight, creamy bokeh, pastel haze and a gentle, nostalgic, ethereal mood."),
        ("Black & White Documentary", "Honest black-and-white documentary photograph, natural light, fine film grain, strong tonal range and unposed, observational composition."),
        ("Synthwave 80s", "Retro 1980s synthwave artwork, neon magenta and cyan gradients, chrome lettering-free horizon grids, glowing sunset and warm VHS scanline glow."),
        ("Sumi-e Ink Wash", "Japanese sumi-e ink wash painting, expressive brush strokes on rice paper, generous empty space, subtle grey gradations and a single red accent."),
        ("Renaissance Fresco", "Renaissance fresco painting, soft plaster texture, earthy ochre and terracotta pigments, balanced classical composition and gentle aged cracks."),
        ("Golden Age Comic Illustration", "Golden-age American magazine illustration, confident painted realism, warm nostalgic palette, clean storytelling composition and soft period lighting."),
        ("Moody Cinematic Teal & Orange", "Moody cinematic still with teal-and-orange colour grading, anamorphic flares, shallow depth of field, atmospheric haze and epic widescreen scale."),
        ("Gouache Travel Poster", "Mid-century gouache travel poster, bold flat colour blocks, simplified shapes, sunlit palette and optimistic, clean graphic composition."),
        ("Linocut Print", "Hand-carved linocut print, strong black shapes, limited two-colour palette, rough chiselled texture and bold folk-print rhythm."),
        ("Embroidered Tapestry", "Richly embroidered textile tapestry, visible stitches and thread sheen, warm woven texture and traditional decorative detailing."),
        ("Miniature Diorama Photo", "Tilt-shift photograph of a tiny handmade world, bright saturated colours, shallow depth of field and a playful toy-scale charm."),
        ("Chalkboard Illustration", "Hand-drawn chalkboard illustration, white and coloured chalk lines on a dark slate surface, soft smudges and a friendly, instructional feel."),
    ]

    private struct Store: Codable { var presets: [StylePreset]; var deletedBuiltIns: [String] }
    private let lock = NSLock()
    @Published public private(set) var presets: [StylePreset] = []        // everything except Auto, in display order
    private var deleted: Set<String> = []

    static var fileURL: URL {
        if let f = ProcessInfo.processInfo.environment["MV_STYLES_FILE"] { return URL(fileURLWithPath: f) }      // tests
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MusicVideo")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("styles.json")
    }

    init() { load() }

    public var all: [StylePreset] { [StyleLibrary.auto] + presets }
    public func preset(id: String) -> StylePreset? { all.first { $0.id == id } }
    /// The original text of a built-in style (to compare with your edited copy or to reset it).
    public func original(id: String) -> StylePreset? { StyleLibrary.shippedList().first { $0.id == id } }
    public func isModified(_ p: StylePreset) -> Bool { p.builtIn && original(id: p.id).map { $0.name != p.name || $0.prompt != p.prompt } == true }
    public var hasDeletedBuiltIns: Bool { !deleted.isEmpty }

    static func shippedList() -> [StylePreset] { builtIns.map { StylePreset(name: $0.0, prompt: $0.1 + " " + StylePreset.detail, builtIn: true) } }

    private func load() {
        var list = StyleLibrary.shippedList()
        if let d = try? Data(contentsOf: StyleLibrary.fileURL), let st = try? JSONDecoder().decode(Store.self, from: d) {
            deleted = Set(st.deletedBuiltIns)
            // keep the saved order and edits; add built-ins that are new in this version of the app
            var saved = st.presets
            // built-ins saved before every style asked for super high detail: brought up to date unless you changed their text
            for i in saved.indices where saved[i].builtIn {
                if let b = StyleLibrary.builtIns.first(where: { StylePreset.slug($0.0) == saved[i].id }), saved[i].prompt == b.1 { saved[i].prompt = b.1 + " " + StylePreset.detail }
            }
            let have = Set(saved.map(\.id))
            for b in list where !have.contains(b.id) && !deleted.contains(b.id) { saved.append(b) }
            list = saved
        }
        presets = list.filter { !deleted.contains($0.id) || !$0.builtIn }
    }

    private func persist() {
        let st = Store(presets: presets, deletedBuiltIns: Array(deleted).sorted())
        if let d = try? JSONEncoder().encode(st) { try? d.write(to: StyleLibrary.fileURL, options: .atomic) }
    }

    private func mutate(_ f: () -> Void) {
        lock.lock(); f(); persist(); lock.unlock()
        if Thread.isMainThread { objectWillChange.send() } else { DispatchQueue.main.async { self.objectWillChange.send() } }
    }

    /// Saves changes to an existing style (name and/or text) permanently.
    public func update(id: String, name: String, prompt: String) {
        mutate {
            if let i = presets.firstIndex(where: { $0.id == id }) {
                let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                presets[i].name = n.isEmpty ? presets[i].name : n; presets[i].prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Adds a new style of your own and returns it.
    @discardableResult
    public func add(name: String, prompt: String) -> StylePreset {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines); if base.isEmpty { base = "My style" }
        var unique = base; var n = 2
        while presets.contains(where: { $0.name.lowercased() == unique.lowercased() }) { unique = "\(base) \(n)"; n += 1 }
        let p = StylePreset(id: "custom-" + UUID().uuidString.prefix(8).lowercased(), name: unique, prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), builtIn: false)
        mutate { presets.append(p) }
        return p
    }

    public func delete(id: String) {
        mutate {
            if let i = presets.firstIndex(where: { $0.id == id }) { if presets[i].builtIn { deleted.insert(id) }; presets.remove(at: i) }
        }
    }

    /// Puts a built-in style back to its original name and text.
    public func reset(id: String) {
        guard let o = original(id: id) else { return }
        mutate { if let i = presets.firstIndex(where: { $0.id == id }) { presets[i] = o } }
    }

    /// Brings back every built-in style you deleted.
    public func restoreBuiltIns() {
        mutate {
            for b in StyleLibrary.shippedList() where deleted.contains(b.id) { presets.append(b) }
            deleted = []
        }
    }
}
