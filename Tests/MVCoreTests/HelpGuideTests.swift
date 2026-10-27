import XCTest
@testable import MVCore

final class HelpGuideTests: XCTestCase {
    func testCommonWorkflowQuestionsRetrieveTheActualTask() {
        let cases = [
            ("Are Shorts created automatically?", "shortsPolicy"),
            ("How do I hide the song name and crop a looping Short full screen?", "loopShorts"),
            ("Why did my one hour loop become 74 minutes?", "loopMusic"),
            ("Can I make a 3 second clip?", "clipLength"),
            ("How do I recover a paid clip after Stop?", "clipRecovery"),
            ("How do I split and join pictures?", "parts"),
            ("Can I revert an app version and stay there?", "updates")
        ]
        for (question, expected) in cases {
            XCTAssertTrue(HelpGuide.relevant(to: question).contains { $0.id == expected }, "\(question) must retrieve \(expected)")
        }
    }
    func testLoopHelpIsDividedIntoManageableTasksAndIDsAreUnique() {
        XCTAssertEqual(Set(HelpGuide.sections.map(\.id)).count, HelpGuide.sections.count)
        for id in ["loopingVideo", "loopMusic", "clipLength", "clipRecovery", "loopScenes"] {
            let section = HelpGuide.section(id)
            XCTAssertNotNil(section)
            XCTAssertLessThan(section?.body.split { $0.isWhitespace }.count ?? 9999, 500)
        }
        XCTAssertTrue(HelpGuide.relevant(to: "zxqvzeroquux").isEmpty)
    }
}
