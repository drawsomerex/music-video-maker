import XCTest
@testable import MVCore

final class JevTests: XCTestCase {
    var saved: ((URLRequest) async throws -> (Data, URLResponse))!
    override func setUp() { saved = Jev.send }
    override func tearDown() { Jev.send = saved }

    func respond(_ status: Int, _ json: String) -> (URLRequest) async throws -> (Data, URLResponse) {
        { req in (Data(json.utf8), HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!) }
    }

    func testParsesYesNoAndChoiceAnswers() {
        let json = #"{"answers":{"a":{"type":"noul","noul":0.96},"b":{"type":"choice","choice":"payments","confidence":0.67,"probabilities":{"payments":0.78,"frontend":0.22}}}}"#
        let qs = [JevQuestion(id: "a", instructions: "?", kind: .yesNo(yes: "y", no: "n")), JevQuestion(id: "b", instructions: "?", kind: .choice(["payments": "p", "frontend": "f"]))]
        let a = Jev.parse(Data(json.utf8), expecting: qs)
        XCTAssertEqual(a?["a"]?.yes, 0.96); XCTAssertEqual(a?["b"]?.choice, "payments"); XCTAssertEqual(a?["b"]?.probabilities["frontend"], 0.22)
        XCTAssertNil(Jev.parse(Data(#"{"answers":{"a":{"type":"noul","noul":3}}}"#.utf8), expecting: [qs[0]]), "a probability outside 0…1 is not trusted")
        XCTAssertNil(Jev.parse(Data(#"{"answers":{"b":{"type":"choice","choice":"nonsense"}}}"#.utf8), expecting: [qs[1]]), "an option that was not offered is not trusted")
    }
    func testRequestShape() {
        let r = Jev.request(model: "m", state: ["x": "y"], [JevQuestion(id: "a", instructions: "Q", kind: .yesNo(yes: "Y", no: "N"))])
        let q = (r["questions"] as? [String: Any])?["a"] as? [String: Any]
        XCTAssertEqual(q?["type"] as? String, "noul"); XCTAssertEqual((q?["criteria"] as? [String: String])?["true"], "Y")
        XCTAssertEqual((r["state"] as? [String: String])?["x"], "y")
    }
    func testNoKeyOrBadStatusGivesNil() async {
        let q = [JevQuestion(id: "a", instructions: "?", kind: .yesNo(yes: "y", no: "n"))]
        Jev.send = respond(200, #"{"answers":{"a":{"type":"noul","noul":0.5}}}"#)
        let none = await Jev.decide(state: ["s": "t"], q, apiKey: ""); XCTAssertNil(none)
        Jev.send = respond(402, "{}")
        let credit = await Jev.decide(state: ["s": "t"], q, apiKey: "k"); XCTAssertNil(credit)
        Jev.send = respond(200, #"{"answers":{"a":{"type":"noul","noul":0.5}}}"#)
        let ok = await Jev.decide(state: ["s": "t"], q, apiKey: "k"); XCTAssertEqual(ok?["a"]?.yes, 0.5)
    }
    func testFallsBackToTheNamedModelWhenTheAliasIsUnknown() async {
        var tried: [String] = []
        Jev.send = { req in
            let model = (try? JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])?["model"] as? String ?? ""
            tried.append(model)
            return (Data(model.contains("latest") ? "{}".utf8 : #"{"answers":{"a":{"type":"noul","noul":0.9}}}"#.utf8), HTTPURLResponse(url: req.url!, statusCode: model.contains("latest") ? 400 : 200, httpVersion: nil, headerFields: nil)!)
        }
        let a = await Jev.decide(state: ["s": "t"], [JevQuestion(id: "a", instructions: "?", kind: .yesNo(yes: "y", no: "n"))], apiKey: "k")
        XCTAssertEqual(a?["a"]?.yes, 0.9); XCTAssertEqual(tried, Jev.models)
    }

    func testClipRiskMentionsOnlyConfidentYes() async {
        Jev.send = { req in
            let state = (try? JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])?["state"] as? [String: String]
            let people = state?["scene"]?.contains("crowd") == true
            let json = #"{"answers":{"people":{"type":"noul","noul":\#(people ? 0.92 : 0.1)},"petals":{"type":"noul","noul":0.6},"travel":{"type":"noul","noul":0.05},"text":{"type":"noul","noul":0.02}}}"#
            return (Data(json.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let flags = await ClipRisk.check([.init(label: "Scene 1", idea: "A crowd walks through the square"), .init(label: "Scene 2", idea: "Rain on a window")], kind: .loop, apiKey: "k")
        XCTAssertEqual(flags, [ClipRisk.Flag(label: "Scene 1", reasons: ["people or animals coming and going"])], "0.6 is unsure, so it stays quiet")
        XCTAssertNotNil(ClipRisk.advice(flags)); XCTAssertNil(ClipRisk.advice([])); XCTAssertNil(ClipRisk.advice(nil))
    }
    func testClipRiskSaysNothingWhenJevCannotAnswer() async {
        Jev.send = respond(500, "{}")
        let flags = await ClipRisk.check([.init(label: "Picture 1", idea: "x")], kind: .video, apiKey: "k")
        XCTAssertNil(flags)
    }

    func testErrorWordRules() {
        XCTAssertEqual(ErrorTriage.rule("Insufficient credits"), .credit)
        XCTAssertEqual(ErrorTriage.rule("OpenRouter is very busy right now. Please try again in a few minutes."), .busy)
        XCTAssertEqual(ErrorTriage.rule("The Internet connection appears to be offline."), .network)
        XCTAssertNil(ErrorTriage.rule("Add a song first."))
    }
    func testErrorAdviceUsesJevThenRules() async {
        Jev.send = respond(200, #"{"answers":{"kind":{"type":"choice","choice":"network","confidence":0.9,"probabilities":{"network":0.9}}}}"#)
        var a = await ErrorTriage.advice(for: "Something odd happened", apiKey: "k"); XCTAssertEqual(a?.kind, .network)
        Jev.send = respond(200, #"{"answers":{"kind":{"type":"choice","choice":"other","confidence":0.9,"probabilities":{"other":0.9}}}}"#)
        a = await ErrorTriage.advice(for: "Add a song first.", apiKey: "k"); XCTAssertNil(a)
        Jev.send = respond(500, "{}")
        a = await ErrorTriage.advice(for: "Insufficient credits", apiKey: "k"); XCTAssertEqual(a?.kind, .credit, "Jev not reachable: the word rules answer")
        a = await ErrorTriage.advice(for: "Insufficient credits", apiKey: ""); XCTAssertEqual(a?.kind, .credit)
    }

    func testShortCandidatesStartWithTheLoudestStretch() {
        // 4 minutes: quiet intro, a build, a loud chorus, a quiet middle, a second chorus
        var e = [Float](repeating: 0.05, count: 480)
        for i in 100..<190 { e[i] = 0.05 + 0.4 * Float(i - 100) / 90 }
        for i in 190..<290 { e[i] = 0.5 }
        for i in 330..<430 { e[i] = 0.45 }
        let c = LoopVideo.shortCandidates(energy: e, seconds: 45)
        XCTAssertGreaterThanOrEqual(c.count, 2)
        let old = LoopVideo.shortWindow(energy: e, seconds: 45)
        XCTAssertEqual(c.first?.start, old?.start, "the first candidate is what the Short used before")
        XCTAssertTrue(c.allSatisfy { $0.words.contains("Loudness") })
        XCTAssertEqual(Set(c.map(\.start)).count, c.count)
    }
}
