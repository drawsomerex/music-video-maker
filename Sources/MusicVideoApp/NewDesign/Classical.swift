// The "Classical" look of the New Design: a quiet near-white page, Cormorant Garamond headings over Lora text, hairline rules,
// and the one gold accent used as an outline or underline, never as a filled block. Colours and sizes come from the design's styles.css.
import SwiftUI
import CoreText

enum Classical {
    // MARK: colours (styles.css :root)
    static let bg = Color(hex: 0xF3F2F2)
    static let surface = Color(hex: 0xEAE9E9)
    static let text = Color(hex: 0x201F1D)
    static let accent = Color(hex: 0xB68235)
    static let accent100 = Color(hex: 0xFFF3E4), accent200 = Color(hex: 0xFFE3BF), accent300 = Color(hex: 0xFACB8D)
    static let accent600 = Color(hex: 0xA06F24), accent700 = Color(hex: 0x7D5411), accent800 = Color(hex: 0x5A3B0A)
    static let neutral300 = Color(hex: 0xD7D3D3), neutral500 = Color(hex: 0x9B9797), neutral600 = Color(hex: 0x7D7979)
    static let neutral700 = Color(hex: 0x605D5D), neutral800 = Color(hex: 0x444141)
    static let divider = Color(hex: 0x201F1D).opacity(0.16)
    static let paper = Color.white
    static let ok = Color(hex: 0x3F7D4E), warn = Color(hex: 0xB0431F)

    // MARK: fonts
    static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(weight == .semibold ? "CormorantGaramond-SemiBold" : "CormorantGaramond-Regular", size: size)
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom("Lora", size: size).weight(weight) }
    static func italic(_ size: CGFloat) -> Font { .custom("Lora", size: size).italic() }

    /// Registers the bundled font files once. Without them the text falls back to the system serif, which still reads fine.
    static let registered: Bool = {
        let dirs = [Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
                    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fonts")].compactMap { $0 }
        for d in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "ttf" }), !files.isEmpty else { continue }
            for f in files { CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) }
            return true
        }
        return false
    }()
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

/// Outlined button: a 1 px outline on a transparent ground. `.primary` is a gold outline; `.secondary` a grey one; `.ghost` has none.
struct ClassicalButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .secondary
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        let stroke = kind == .primary ? Classical.accent : (kind == .secondary ? Classical.neutral300 : .clear)
        c.label
            .font(Classical.body(compact ? 12 : 13, weight: kind == .primary ? .semibold : .regular))
            .foregroundStyle(kind == .primary ? Classical.accent700 : Classical.text)
            .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 4 : 7)
            .background(RoundedRectangle(cornerRadius: 4).fill(c.isPressed ? Classical.accent200 : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(c.isPressed ? Classical.accent600 : stroke, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}
extension ButtonStyle where Self == ClassicalButtonStyle {
    static var classical: ClassicalButtonStyle { .init() }
    static var classicalPrimary: ClassicalButtonStyle { .init(kind: .primary) }
    static var classicalGhost: ClassicalButtonStyle { .init(kind: .ghost) }
    static var classicalSmall: ClassicalButtonStyle { .init(compact: true) }
}

struct Hairline: View { var body: some View { Rectangle().fill(Classical.divider).frame(height: 1) } }
struct VHairline: View { var body: some View { Rectangle().fill(Classical.divider).frame(width: 1) } }

/// A small label tinted from the accent ramp.
struct ClassicalTag: View {
    let text: String; var accent = true
    var body: some View {
        Text(text).font(Classical.body(11)).foregroundStyle(accent ? Classical.accent700 : Classical.neutral700)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(accent ? Classical.accent100 : Classical.surface))
    }
}

/// Section heading: Cormorant, with an optional small grey note beside it.
struct ClassicalHeading: View {
    let text: String; var note: String? = nil; var size: CGFloat = 22
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text).font(Classical.heading(size)).foregroundStyle(Classical.text)
            if let note { Text(note).font(Classical.body(12)).foregroundStyle(Classical.neutral600) }
        }
    }
}
