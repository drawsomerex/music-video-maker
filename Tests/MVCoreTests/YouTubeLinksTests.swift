import XCTest
@testable import MVCore

final class YouTubeLinksTests: XCTestCase {
    func testLinksAreOffUntilSetThenAddedNearTheTop() {
        let l = YouTubeKit.Listing(title: "T", description: "First paragraph.\n\nLyrics\nla la", tags: [], hashtags: [])
        XCTAssertEqual(YouTubeKit.withLinks(l, config: Config()).description, l.description)        // nothing set: nothing added
        var c = Config(); c.website = "mysongs.com"; c.tipJar = "https://ko-fi.com/me"
        let d = YouTubeKit.withLinks(l, config: c).description
        XCTAssertTrue(d.hasPrefix("First paragraph.\n\n🌐 Website: https://mysongs.com\n☕ Tip jar"))
        XCTAssertTrue(d.contains("https://ko-fi.com/me")); XCTAssertTrue(d.hasSuffix("la la"))
        XCTAssertEqual(YouTubeKit.withLinks(YouTubeKit.withLinks(l, config: c), config: c).description, d)   // never twice
        c.website = ""
        XCTAssertFalse(YouTubeKit.withLinks(l, config: c).description.contains("Website"))
    }

    func testThumbnailWithLogo() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pic = env["MV_THUMB_PIC"], let logo = env["MV_THUMB_LOGO"], let out = env["MV_THUMB_OUT"] else { throw XCTSkip("no sample picture") }
        try YouTubeKit.thumbnail(picture: URL(fileURLWithPath: pic), title: "Where the Bison Walk the Steam", badge: nil, line: "Lyric video", output: URL(fileURLWithPath: out), logo: URL(fileURLWithPath: logo))
        XCTAssertTrue(FileManager.default.fileExists(atPath: out))
    }
}
