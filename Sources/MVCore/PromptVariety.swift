// Controlled randomness for picture prompts: every section gets its own time of day, weather and camera view, so no two prompts end up alike.
import Foundation

enum PromptVariety {
    static let times = ["at sunrise", "in soft early-morning light", "at midday under a high sun", "in warm late-afternoon light", "at golden hour", "in bright afternoon sun",
                        "in glowing morning light", "in dappled sunlight", "under a clear blue sky", "in warm, radiant light"]
    static let weather = ["clear and crisp", "with fluffy white clouds", "just after a sunny shower, with sparkling reflections", "with a gentle breeze moving everything", "warm and golden",
                          "with a rainbow in the distance", "bright and fresh", "with sunlight streaming through", "in glittering fresh snow under blue sky", "with sparkling light"]
    static let views = ["a wide establishing view", "a medium shot", "seen from a high vantage point", "seen low to the ground", "framed through an archway, doorway or window",
                        "a figure lit by the sun", "a detail of an everyday object that belongs to this place", "a long view down a street or path",
                        "seen from behind a small group of people (no faces)", "a reflection in water or glass"]

    /// One hint per section: lists are dealt out in shuffled rounds, so neighbours never repeat and the same combination does not come back soon.
    static func hints(count: Int) -> [String] {
        var a = Deal(times), b = Deal(weather), c = Deal(views)
        return (0..<max(0, count)).map { _ in "\(c.next()), \(a.next()), \(b.next())" }
    }
    static func hint() -> String { "\(views.randomElement()!), \(times.randomElement()!), \(weather.randomElement()!)" }

    struct Deal {
        let items: [String]; var deck: [String] = []; var last = ""
        init(_ items: [String]) { self.items = items }
        mutating func next() -> String {
            if deck.isEmpty { deck = items.shuffled(); if deck.last == last, deck.count > 1 { deck.swapAt(0, deck.count - 1) } }
            last = deck.removeLast(); return last
        }
    }
}
