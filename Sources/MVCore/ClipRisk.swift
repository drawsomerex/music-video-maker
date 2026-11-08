// A quick yes/no look at a scene's words before a paid video clip is ordered: will it animate well? Jev answers a few fixed questions about each idea.
// It only advises: the clip dialogs show what it found, and the clip is still made if you go ahead.
import Foundation

public enum ClipRisk {
    public enum Kind { case loop, video }
    public struct Item { public var label: String; public var idea: String; public var motion: String
        public init(label: String, idea: String, motion: String = "") { self.label = label; self.idea = idea; self.motion = motion } }
    public struct Flag: Equatable { public var label: String; public var reasons: [String] }
    public static let threshold = 0.7                // a "yes" must be this sure to be mentioned; anything unsure stays quiet
    static let overall: TimeInterval = 5            // never keeps the clip dialog waiting longer than this

    struct Risk { var id: String; var asks: String; var reason: String }
    static func risks(_ kind: Kind) -> [Risk] {
        switch kind {
        case .loop: return [
            Risk(id: "people", asks: "Does the scene need people or animals to walk in, walk out or cross the picture, or show a crowd?", reason: "people or animals coming and going"),
            Risk(id: "petals", asks: "Does the scene rely on loose petals, leaves, paper, hair or cloth blowing about?", reason: "loose petals, leaves, paper or hair blowing about"),
            Risk(id: "travel", asks: "Does something travel across the picture and not come back (a vehicle driving away, a bird flying out of sight), instead of moving in a repeating way in place?", reason: "motion that travels away and cannot repeat"),
            Risk(id: "text", asks: "Does the scene include readable words, signs or writing?", reason: "readable words or signs")]
        case .video: return [
            Risk(id: "crowd", asks: "Does the scene show a crowd or many people close together?", reason: "a crowd"),
            Risk(id: "hands", asks: "Is the main subject a close-up of hands or of a face?", reason: "a close-up of hands or a face"),
            Risk(id: "action", asks: "Does the scene need fast or violent action, such as an explosion, a fight or a crash?", reason: "fast or violent action"),
            Risk(id: "text", asks: "Does the scene include readable words, signs or writing?", reason: "readable words or signs")]
        }
    }
    static func questions(_ kind: Kind) -> [JevQuestion] {
        risks(kind).map { JevQuestion(id: $0.id, instructions: $0.asks, kind: .yesNo(yes: "Yes, the scene description clearly says so.", no: "No, or the scene description does not say so.")) }
    }

    /// The scenes that may not animate well. Nil when it could not check (then nothing is said).
    public static func check(_ items: [Item], kind: Kind, apiKey: String, limit: Int = 40) async -> [Flag]? {
        guard !items.isEmpty, !apiKey.isEmpty else { return nil }
        let rs = risks(kind), qs = questions(kind)
        return await withTaskGroup(of: [Flag]?.self) { group in
            group.addTask {
                var flags: [Flag] = [], answered = 0
                let list = Array(items.prefix(limit))
                var i = 0
                while i < list.count {
                    let chunk = list[i..<min(list.count, i + 6)]; i += 6
                    await withTaskGroup(of: (Item, [String: JevAnswer]?).self) { g in
                        for it in chunk { g.addTask {
                            var state = ["scene": it.idea]; if !it.motion.isEmpty { state["motion"] = it.motion }
                            return (it, await Jev.decide(state: state, qs, apiKey: apiKey, timeout: 4))
                        } }
                        for await (it, a) in g {
                            guard let a else { continue }
                            answered += 1
                            let why = rs.filter { (a[$0.id]?.yes ?? 0) >= threshold }.map(\.reason)
                            if !why.isEmpty { flags.append(Flag(label: it.label, reasons: why)) }
                        }
                    }
                }
                return answered > 0 ? flags.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending } : nil
            }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(overall * 1e9)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// What the dialog adds under its own text. Silent when nothing was found or the check could not run.
    public static func advice(_ flags: [Flag]?) -> String? {
        guard let flags, !flags.isEmpty else { return nil }
        let shown = flags.prefix(6).map { "• \($0.label): " + $0.reasons.joined(separator: "; ") }.joined(separator: "\n")
        let more = flags.count > 6 ? "\n…and \(flags.count - 6) more." : ""
        return "A quick free check (the Jev decision model) thinks \(flags.count == 1 ? "this scene" : "these scenes") may not animate well:\n\(shown)\(more)\nYou can still make \(flags.count == 1 ? "it" : "them"); changing the idea first usually works better."
    }
}
