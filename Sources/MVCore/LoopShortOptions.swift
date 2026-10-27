// Portrait framing and on-screen text are independent of song names, filenames and the long video.
import Foundation
import CoreGraphics

public enum ShortHeading: String, Codable, CaseIterable { case song, custom, none }
public struct ShortFraming: Codable, Equatable {
    public var x = 0.5, y = 0.5
    public init(x: Double = 0.5, y: Double = 0.5) { self.x = x; self.y = y }
}
public struct LoopShortOptions: Codable, Equatable {
    public var heading: ShortHeading = .song
    public var text = ""
    /// nil keeps the project title for playlists; empty hides it; other text replaces it.
    public var subtitle: String? = nil
    public var fillScreen = true
    public var framing: [String: ShortFraming] = [:]
    public init() {}
    public func title(song: String) -> String { switch heading { case .song: return song; case .custom: return String(text.prefix(180)); case .none: return "" } }
    public func subtitle(project: String, playlist: Bool) -> String { subtitle.map { String($0.prefix(180)) } ?? (playlist ? project : "") }
    /// Aspect-fill geometry with positions measured from the left/top, shared by the UI crop and the actual export.
    public static func crop(source: CGSize, canvas: CGSize, framing: ShortFraming) -> CGRect {
        let scale = max(canvas.width / max(1, source.width), canvas.height / max(1, source.height))
        let width = source.width * scale, height = source.height * scale
        let x = min(1, max(0, framing.x.isFinite ? framing.x : 0.5)), y = min(1, max(0, framing.y.isFinite ? framing.y : 0.5))
        return CGRect(x: -(width - canvas.width) * x, y: -(height - canvas.height) * (1 - y), width: width, height: height)
    }
}
