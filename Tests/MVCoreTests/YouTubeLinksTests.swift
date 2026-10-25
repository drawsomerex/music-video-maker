import XCTest
@testable import MVCore

final class YouTubeLinksTests: XCTestCase {
    func testLinksAreOffUntilSetThenAddedNearTheTop() {
        let l = YouTubeKit.Listing(title: "T", description: "First paragraph.\n\nLyrics\nla la", tags: [], hashtags: [])
        XCTAssertEqual(YouTubeKit.withLinks(l, config: Config()).description, l.description)        // nothing set: nothing added
        var c = Config(); c.website = "mysongs.com"; c.tipJar = "https://ko-fi.com/me"
        let d = YouTubeKit.withLinks(l, config: c).description
        XCTAssertTrue(d.hasPrefix("First paragraph.\n\nWebsite: https://mysongs.com\nTip jar"))
        // a long opening paragraph: the links still come straight after its first, short sentence (before YouTube's "…more")
        let long = YouTubeKit.Listing(title: "T", description: "Three hours of calm music. " + String(repeating: "A peaceful scene with soft light. ", count: 10), tags: [], hashtags: [])
        let d2 = YouTubeKit.withLinks(long, config: c).description
        XCTAssertTrue(d2.hasPrefix("Three hours of calm music.\n\nWebsite:"), d2)
        let noStop = YouTubeKit.Listing(title: "T", description: String(repeating: "word ", count: 60), tags: [], hashtags: [])
        XCTAssertTrue(YouTubeKit.withLinks(noStop, config: c).description.hasPrefix("Website:"))
        XCTAssertTrue(d.contains("https://ko-fi.com/me")); XCTAssertTrue(d.hasSuffix("la la"))
        XCTAssertEqual(YouTubeKit.withLinks(YouTubeKit.withLinks(l, config: c), config: c).description, d)   // never twice
        c.website = ""
        XCTAssertFalse(YouTubeKit.withLinks(l, config: c).description.contains("Website"))
    }

    func testNoEmojis() {
        XCTAssertEqual(YouTubeKit.withoutEmoji("Calm music 😌✨ for focus ☕ #Study 3 hours"), "Calm music for focus #Study 3 hours")
        XCTAssertEqual(YouTubeKit.withoutEmoji("Line one 🎵\nLine two"), "Line one\nLine two")
        XCTAssertEqual(YouTubeKit.withoutEmoji("Café – “Ode” (2026)"), "Café – “Ode” (2026)")
    }

    func testThumbnailWithLogo() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pic = env["MV_THUMB_PIC"], let logo = env["MV_THUMB_LOGO"], let out = env["MV_THUMB_OUT"] else { throw XCTSkip("no sample picture") }
        try YouTubeKit.thumbnail(picture: URL(fileURLWithPath: pic), title: "Where the Bison Walk the Steam", badge: nil, line: "Lyric video", output: URL(fileURLWithPath: out), logo: URL(fileURLWithPath: logo))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out))
    }
}
