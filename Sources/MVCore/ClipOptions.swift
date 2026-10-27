// One duration/quality contract for both music-picture clips and looping scenes.
import Foundation

public struct ClipOptions: Codable, Equatable, Sendable {
    /// nil matches the picture's section (music) or uses 15 seconds (loop projects).
    public var seconds: Int?
    public var sharp = false
    public init(seconds: Int? = nil, sharp: Bool = false) { self.seconds = seconds; self.sharp = sharp }
    public var resolution: String { sharp ? "2K" : "768p" }
    public func usedSeconds(section: Double = 15) -> Int { [3, 5, 8, 15].contains(seconds ?? 0) ? seconds! : OpenRouterVideo.clipSeconds(forSectionSeconds: section) }
    /// HeyGen's minimum order is five seconds. The original stays on disk when three seconds are used.
    public func generatedSeconds(section: Double = 15) -> Int { max(5, usedSeconds(section: section)) }
    public func price(perSecond768: Double, section: Double = 15) -> Double { Double(generatedSeconds(section: section)) * (sharp ? 0.10 : perSecond768) }
    public var durationExplanation: String { seconds == 3 ? "Use 3 seconds from a 5-second order; the price covers all 5 seconds." : "The price covers the generated clip. End-to-start blending overlaps part of the clip, shortening the repeat interval." }
}
