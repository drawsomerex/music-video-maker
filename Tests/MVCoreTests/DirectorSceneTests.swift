import XCTest
@testable import MVCore

/// The scenes a looping video makes after you approve or change the director's plan.
final class DirectorSceneTests: XCTestCase {
    func testApprovedKeepsTheEditedWordsAndTheNumberChosen() {
        let edited = ["A calm lake at dawn", "The same lake in rain", "The lake under snow", "A fourth idea"]
        XCTAssertEqual(DirectorScenes.approved(edited, scenes: 3), Array(edited.prefix(3)))
        XCTAssertEqual(DirectorScenes.approved(edited, scenes: 9), edited)
        XCTAssertEqual(DirectorScenes.approved(edited, scenes: 0), ["A calm lake at dawn"])
        XCTAssertEqual(DirectorScenes.approved([], scenes: 3), [])
    }

    func testRemovingASceneToMakeAlsoLowersTheNumberToMake() {
        let texts = ["one", "two", "three", "four"]
        let r = DirectorScenes.remove(texts, scenes: 4, at: 1)
        XCTAssertEqual(r.texts, ["one", "three", "four"])
        XCTAssertEqual(r.scenes, 3)
    }

    func testRemovingASceneBeyondTheChosenCountKeepsTheCount() {
        let texts = ["one", "two", "three", "four"]
        let r = DirectorScenes.remove(texts, scenes: 2, at: 3)
        XCTAssertEqual(r.texts, ["one", "two", "three"])
        XCTAssertEqual(r.scenes, 2)
        XCTAssertEqual(DirectorScenes.approved(r.texts, scenes: r.scenes), ["one", "two"])
    }

    func testAtLeastOneSceneStays() {
        let one = DirectorScenes.remove(["only"], scenes: 1, at: 0)
        XCTAssertEqual(one.texts, ["only"])
        XCTAssertEqual(one.scenes, 1)
        let two = DirectorScenes.remove(["one", "two"], scenes: 1, at: 0)
        XCTAssertEqual(two.scenes, 1)
        XCTAssertEqual(two.texts, ["two"])
    }
}