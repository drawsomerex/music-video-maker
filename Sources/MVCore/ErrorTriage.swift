// What went wrong, in one plain sentence. The app's own messages stay as they are; underneath them the "Something went wrong" box adds what kind of problem it
// looks like and the one thing to do. Jev picks the kind (a multiple-choice question about the message); simple word rules do it when Jev is not available.
import Foundation

public enum ErrorTriage {
    public enum Kind: String, CaseIterable { case key, credit, busy, network, file, other }
    public enum Action { case none, addKey, addCredit }
    public struct Advice: Equatable { public var kind: Kind; public var text: String; public var action: Action
        public static func == (a: Advice, b: Advice) -> Bool { a.kind == b.kind } }

    public static func advice(_ kind: Kind) -> Advice? {
        switch kind {
        case .key: return Advice(kind: kind, text: "This looks like a problem with your OpenRouter key. Check that it is pasted in Settings, then try again.", action: .addKey)
        case .credit: return Advice(kind: kind, text: "Your OpenRouter credit may have run out. Add credit at openrouter.ai, then try again.", action: .addCredit)
        case .busy: return Advice(kind: kind, text: "The online service is busy right now. Nothing is lost: wait a few minutes and try again.", action: .none)
        case .network: return Advice(kind: kind, text: "The internet connection seems to have dropped. Check it, then try again.", action: .none)
        case .file: return Advice(kind: kind, text: "The app could not read or save a file. Check that the disk has free space and that the folder is still there, then try again.", action: .none)
        case .other: return nil
        }
    }

    /// Word rules: used when Jev is off or cannot answer.
    public static func rule(_ message: String) -> Kind? {
        let m = message.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { m.contains($0) } }
        if has(["credit", "insufficient", "payment required", "402"]) { return .credit }
        if has(["api key", "openrouter key", "unauthorized", "401", "invalid key", "sk-or"]) { return .key }
        if has(["very busy", "try again in a few minutes", "overloaded", "rate limit", "429", "503", "502"]) { return .busy }
        if has(["internet", "offline", "network connection", "timed out", "could not connect", "connection was lost", "not connected to the internet"]) { return .network }
        if has(["no space", "disk", "permission", "couldn't be opened", "couldn’t be opened", "no such file", "not writable", "could not be saved", "couldn't save", "couldn't write"]) { return .file }
        return nil
    }

    static let question = JevQuestion(id: "kind", instructions: "What kind of problem does this error message describe?", kind: .choice([
        "key": "The OpenRouter key is missing, wrong or not accepted.",
        "credit": "The OpenRouter credit has run out or a payment is needed.",
        "busy": "An online service is busy, overloaded or temporarily failing, and trying again later should work.",
        "network": "The internet connection is missing, lost or too slow.",
        "file": "A file or folder could not be read, found or saved, or the disk is full.",
        "other": "Something else: a missing step, a mistake in what was asked, or a problem inside the app."]))

    /// The advice for an error message, or nil when there is nothing useful to add. Never takes long: after three seconds the word rules answer.
    public static func advice(for message: String, apiKey: String, useJev: Bool = true) async -> Advice? {
        if useJev, !apiKey.isEmpty {
            let jev: Kind?? = await withTaskGroup(of: Kind??.self) { g in
                g.addTask {
                    guard let a = await Jev.decide(state: ["message": String(message.prefix(1500))], [question], apiKey: apiKey, timeout: 3)?["kind"],
                          let c = a.choice, let k = Kind(rawValue: c), (a.confidence ?? 1) >= 0.5 else { return .some(nil) }
                    return .some(k)
                }
                g.addTask { try? await Task.sleep(nanoseconds: 3_000_000_000); return .none }
                let r = await g.next() ?? .none; g.cancelAll(); return r
            }
            if let jev { if let k = jev { return advice(k) } else { /* Jev was unsure: the word rules decide */ } }
        }
        return rule(message).flatMap(advice)
    }
}
