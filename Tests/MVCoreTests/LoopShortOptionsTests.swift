import XCTest
import CoreGraphics
import AVFoundation
@testable import MVCore

final class LoopShortOptionsTests: XCTestCase {
    func testTextIsIndependentOfSongAndCanBeHidden() throws {
        var options = LoopShortOptions()
        XCTAssertEqual(options.title(song: "Song title"), "Song title")
        options.heading = .custom; options.text = "Rest and be still"
        XCTAssertEqual(options.title(song: "Song title"), "Rest and be still")
        options.heading = .none; XCTAssertEqual(options.title(song: "Song title"), "")
        options.subtitle = ""; XCTAssertEqual(options.subtitle(project: "Album", playlist: true), "")
        XCTAssertTrue(try JSONDecoder().decode(LoopProject.self, from: Data(#"{"id":"old","title":"Old"}"#.utf8)).shortOptions.fillScreen)
        options.framing["scene"] = ShortFraming(x: 0.8, y: 0.3)
        XCTAssertEqual(try JSONDecoder().decode(LoopShortOptions.self, from: JSONEncoder().encode(options)), options)
    }
    func testCropAlwaysFillsPortraitAndUsesBothAxes() {
        let canvas = CGSize(width: 1080, height: 1920)
        for source in [CGSize(width: 1920, height: 1080), CGSize(width: 720, height: 2400), canvas] {
            for x in [0.0, 0.5, 1] { for y in [0.0, 0.5, 1] {
                let rect = LoopShortOptions.crop(source: source, canvas: canvas, framing: .init(x: x, y: y))
                XCTAssertLessThanOrEqual(rect.minX, 0.001); XCTAssertLessThanOrEqual(rect.minY, 0.001)
                XCTAssertGreaterThanOrEqual(rect.maxX, canvas.width - 0.001); XCTAssertGreaterThanOrEqual(rect.maxY, canvas.height - 0.001)
            } }
        }
        let wide = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(LoopShortOptions.crop(source: wide, canvas: canvas, framing: .init(x: 0)).minX, 0)
        XCTAssertEqual(LoopShortOptions.crop(source: wide, canvas: canvas, framing: .init(x: 1)).maxX, 1080, accuracy: 0.001)
        let tall = CGSize(width: 720, height: 2400)
        XCTAssertEqual(LoopShortOptions.crop(source: tall, canvas: canvas, framing: .init(y: 0)).maxY, 1920, accuracy: 0.001)
    }
}

extension ClipSafetyTests {
    func testLoopingShortActuallyFillsScreenAndFollowsSceneFraming() async throws {
        let dir = try scratch()
        let clip = try fixture(dir, name: "bands.mp4", args: ["-f", "lavfi", "-i", "color=green:size=640x360:rate=30,drawbox=x=0:y=0:w=213:h=360:color=red:t=fill,drawbox=x=427:y=0:w=213:h=360:color=blue:t=fill", "-t", "5", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
        let audio = try fixture(dir, name: "song.wav", args: ["-f", "lavfi", "-i", "sine=frequency=220:sample_rate=48000", "-t", "5"])
        for (x, channel) in [(0.0, 0), (0.5, 1), (1.0, 2)] {
            let output = dir.appendingPathComponent("short-\(channel).mp4")
            try await LoopVideo.renderShort(song: audio, window: (0, 3), clip: clip, trim: ClipTrim(start: 0, end: 3), title: "", subtitle: "", output: output, framing: .init(x: x), W: 180, H: 320)
            let asset = AVURLAsset(url: output)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, 3, accuracy: 0.05)
            let generator = AVAssetImageGenerator(asset: asset)
            let image = try await generator.image(at: CMTime(seconds: 1.4, preferredTimescale: 600)).image
            var bytes = [UInt8](repeating: 0, count: 4 * 4 * 4)
            let ctx = CGContext(data: &bytes, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 4, height: 4))
            for pixel in [0, 3, 12, 15] {
                XCTAssertGreaterThan(bytes[pixel * 4 + channel], 70, "all four corners show the selected scene, with no letterbox or blurred band")
                for other in 0..<3 where other != channel { XCTAssertLessThan(bytes[pixel * 4 + other], 55) }
            }
        }
    }
}
