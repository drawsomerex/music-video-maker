import XCTest
@testable import MVCore

/// The loop clip's instruction: a static camera, slow motion, locked colour and landscape, and the optional frozen clouds.
final class LoopClipPromptTests: XCTestCase {
    private func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    func testStillCloudsOffLetsCloudsBillowSoftly() {
        let p = LoopVideo.clipPrompt(scene: "a green valley under a wide sky", motion: "waves rolling onto the shore", seconds: 15)
        XCTAssertTrue(p.contains("Clouds keep their places and only billow softly; they never slide across the sky."))
        XCTAssertTrue(p.contains("water, waves, clouds, foliage and smoke"))
        XCTAssertFalse(p.contains("completely still and frozen"))
        XCTAssertFalse(p.contains("No moving clouds"))
    }

    func testStillCloudsOnFreezesTheCloudsAndTheSky() {
        let p = LoopVideo.clipPrompt(scene: "a green valley under a wide sky", motion: "waves rolling onto the shore, clouds drifting slowly", seconds: 15, stillClouds: true)
        XCTAssertTrue(p.contains("The clouds and the sky stay completely still and frozen for the whole clip: no billowing, no drifting, no sliding, no reshaping."))
        XCTAssertTrue(p.contains("No moving clouds, no drifting sky."))
        XCTAssertTrue(p.contains("water, waves, foliage and smoke"), "clouds must not be asked to move when they are kept still")
        XCTAssertFalse(p.contains("water, waves, clouds, foliage and smoke"))
        XCTAssertFalse(p.contains("Clouds keep their places and only billow softly"))
    }

    func testEverythingThatMovesDoesSoInSlowMotion() {
        for stillClouds in [false, true] {
            let p = LoopVideo.clipPrompt(scene: "a coast", motion: "", stillClouds: stillClouds)
            XCTAssertTrue(p.contains("roughly a quarter of its natural speed"))
            for moving in ["water", "waves", "foliage", "smoke"] {
                XCTAssertTrue(p.contains(moving), "\(moving) should be named in the slow-motion line")
            }
            XCTAssertTrue(p.contains("only slowly and gently, never fast or rushed"))
        }
    }

    func testTheCameraIsStatedStaticAndLockedMoreThanOnce() {
        let p = LoopVideo.clipPrompt(scene: "a road through a valley", motion: "leaves stirring")
        XCTAssertGreaterThanOrEqual(count("Static locked camera", in: p), 2)
        XCTAssertGreaterThanOrEqual(count("no travelling, no flying, no dolly, no drone, no moving forward", in: p), 2)
        XCTAssertTrue(p.contains("The camera stays static and locked from the first second to the last: it never travels, flies, dollies, drifts or moves forward."))
    }

    func testColourAndEveryLandscapeElementAreAnchoredToTheFirstFrame() {
        let p = LoopVideo.clipPrompt(scene: "a green valley", motion: "grass swaying")
        XCTAssertTrue(p.contains("same colour grading, saturation and contrast as the first frame; do not shift hue or desaturate"))
        XCTAssertTrue(p.contains("Every landscape element in the first frame, such as valleys, hills, trees and buildings, stays visible, in place and in its own colour for the whole clip"))
        XCTAssertTrue(p.contains("nothing fades, vanishes or turns into something else"))
    }

    func testStillCloudsDefaultsOffAndRoundTrips() throws {
        let old = try JSONDecoder().decode(LoopProject.self, from: Data(#"{"id":"old","title":"Old"}"#.utf8))
        XCTAssertFalse(old.stillClouds)
        var p = LoopProject(); p.stillClouds = true
        let back = try JSONDecoder().decode(LoopProject.self, from: JSONEncoder().encode(p))
        XCTAssertTrue(back.stillClouds)
    }

    func testTheMotionDescriptionNeverAsksCloudsToMoveWhenTheyAreKeptStill() {
        let off = LoopVideo.motionInstructions()
        XCTAssertTrue(off.contains("clouds and mist only billow softly"))
        XCTAssertTrue(off.contains("clouds billowing softly in place"))

        let on = LoopVideo.motionInstructions(stillClouds: true)
        XCTAssertTrue(on.contains("the clouds and the sky never move at all"))
        XCTAssertFalse(on.contains("billow"))
        XCTAssertTrue(on.contains("the cabin, the clouds and the pines stay still"))
    }
}