// The automatic picture check: after every picture is drawn, a vision model (about a tenth of a cent) looks for the faults picture makers
// still make — scribbled text or signatures, watermarks, extra or missing fingers, warped faces, the wrong number of people or animals,
// a picture that doesn't match its idea, a focal point missing. A fault gets an orange note and one targeted fix ("change only this").
import Foundation

public enum PictureCheck {
    public static let model = "google/gemini-2.5-flash-lite"

    public struct Result: Sendable { public var problem: String?; public var fix: String?; public var cost: Double }

    /// Looks at the picture against what it was meant to show. `focal` = the two things that must be visible.
    public static func check(_ file: URL, idea: String, focal: [String], cast: String = "", config: Config = .load()) async -> Result? {
        guard let img = loadImage(file, maxPixel: 1024), let jpeg = PictureFit.jpegData(img, quality: 0.8) else { return nil }
        var text = """
        You check a picture that was drawn for a music video. It was meant to show: \(idea)
        """
        if focal.count >= 2 { text += "\nThese must both be clearly visible: \(focal[0]) and \(focal[1])." }
        if !cast.isEmpty { text += "\nIf any of these recurring people or things appear, they should look like this (they do NOT have to appear; never report one as missing): \(cast)" }
        text += """

        Look carefully for REAL faults only: any text, letters, numbers, signatures or watermarks; extra, missing or fused fingers or limbs; warped,
        melted or doubled faces or eyes; the wrong number of people or animals; objects merging into each other; something the idea above asks for that is
        missing or clearly wrong. Only the idea decides what must be in the picture. Small artistic liberties and style choices are NOT faults.
        Reply with ONLY this JSON: {"ok":true} or {"ok":false,"problem":"short plain description for the user (under 20 words)","fix":"one instruction for an editor that changes only that, e.g. 'Remove the scribbled letters on the wall'"}
        """
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!); req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue("Bearer \(config.openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let content: [[String: Any]] = [["type": "text", "text": text], ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]]]
        guard let body = try? JSONSerialization.data(withJSONObject: ["model": model, "temperature": 0.1, "response_format": ["type": "json_object"], "usage": ["include": true],
                                                                      "messages": [["role": "user", "content": content]]] as [String: Any]) else { return nil }
        req.httpBody = body
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ch = (j["choices"] as? [[String: Any]])?.first,
              let msg = (ch["message"] as? [String: Any])?["content"] as? String else { return nil }
        let cost = ((j["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue ?? 0
        return parse(msg, cost: cost)
    }

    /// Reads the check's answer (code fences and stray text around the JSON are allowed).
    static func parse(_ msg: String, cost: Double) -> Result? {
        guard let a = msg.firstIndex(of: "{"), let b = msg.lastIndex(of: "}"), let data = String(msg[a...b]).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let ok = (o["ok"] as? Bool) ?? ((o["ok"] as? String)?.lowercased() == "true")
        let problem = (o["problem"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), fix = (o["fix"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if ok || (problem ?? "").isEmpty { return Result(problem: nil, fix: nil, cost: cost) }
        return Result(problem: problem, fix: (fix ?? "").isEmpty ? "Fix this: \(problem!)" : fix, cost: cost)
    }

    /// The prompt for a targeted fix: the picture is attached and only the one thing changes.
    public static func fixPrompt(_ fix: String) -> String {
        "Edit the attached picture. \(fix). Change ONLY that. Keep everything else exactly the same: the composition and framing, every person, animal and object, their faces and clothing, the art style, the colours and the light. Widescreen 16:9, no text, no lettering, no watermark."
    }
}
