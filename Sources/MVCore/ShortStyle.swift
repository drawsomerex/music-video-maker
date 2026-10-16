import Foundation
import CoreGraphics

/// Everything random about a Short's look, derived from one seed (plus the user's explicit choices) — so a look is reproducible.
public struct ShortStyle {
    public enum TextMode: String, CaseIterable { case sweep, pop, pill, stack }
    public enum TitleMode: String, CaseIterable { case slam, drop, bar }
    public enum Cut: Int, CaseIterable { case zoom, flash, whip, push, wipe }

    public var calm: Bool
    public var textMode: TextMode
    public var titleMode: TitleMode
    public var accentName: String
    public var accent: CGColor
    public var shotInterval: Double       // calm: seconds between camera waypoints; punchy: seconds between cuts inside a picture
    public var cuts: [Cut]                // transitions used between pictures
    public var pulse: Double              // beat-pulse strength (zoom fraction), 0 = off
    public var shake: Bool

    public static let paletteNames = ["Hot pink", "Sun yellow", "Electric cyan", "Lime", "Tangerine", "Violet"]
    static let palette: [(String, CGFloat, CGFloat, CGFloat)] = [
        ("Sun yellow", 1.00, 0.84, 0.04), ("Hot pink", 1.00, 0.23, 0.55), ("Electric cyan", 0.24, 0.86, 1.0),
        ("Lime", 0.71, 1.00, 0.23), ("Tangerine", 1.00, 0.54, 0.12), ("Violet", 0.70, 0.53, 1.00)]

    public static func make(seed: UInt64, clip: ShortClip? = nil) -> ShortStyle {
        var r = SeededRNG(seed &* 0x9E3779B97F4A7C15 &+ 12345)
        func pick<T>(_ a: [T]) -> T { a[Int(r.next() % UInt64(a.count))] }
        let calm = (clip?.motion ?? "calm") != "punchy"
        let seededCol = pick(palette)
        let col = palette.first(where: { $0.0 == clip?.accent }) ?? seededCol
        let seededText = pick(TextMode.allCases), seededTitle = pick(TitleMode.allCases)
        let text: TextMode
        switch clip?.textStyle ?? "pill" { case "pop": text = .pop; case "stack": text = .stack; case "sweep": text = .sweep; case "auto": text = seededText; default: text = .pill }
        var cuts = (calm ? [Cut.zoom, .wipe, .push] : Cut.allCases).shuffledSeeded(&r); cuts = Array(cuts.prefix(3))
        let pulseAmt = calm ? ((clip?.pulse ?? false) ? 0.014 : 0) : 0.025 + Double(r.next() % 1000) / 1000 * 0.025
        return ShortStyle(calm: calm, textMode: text, titleMode: seededTitle, accentName: col.0,
                          accent: CGColor(red: col.1, green: col.2, blue: col.3, alpha: 1),
                          shotInterval: calm ? 7.0 : 2.3 + Double(r.next() % 1000) / 1000 * 1.1, cuts: cuts,
                          pulse: pulseAmt, shake: !calm && r.next() % 2 == 0)
    }

    public var summary: String { "\(calm ? "calm" : "punchy") · \(textMode.rawValue) text · \(titleMode.rawValue) title · \(accentName) · \(cuts.map { "\($0)" }.joined(separator: "/")) cuts" }
}

extension Array {
    func shuffledSeeded(_ r: inout SeededRNG) -> [Element] {
        var a = self; var i = a.count - 1
        while i > 0 { let j = Int(r.next() % UInt64(i + 1)); a.swapAt(i, j); i -= 1 }
        return a
    }
}
