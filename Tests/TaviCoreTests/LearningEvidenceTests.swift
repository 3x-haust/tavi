import Foundation
import XCTest
@testable import TaviCore

final class LearningEvidenceTests: XCTestCase {
    func testRepeatedTypedNicknameLearnsWithoutManualRegistration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LearningStore(url: directory.appendingPathComponent("words.json"))
        let observation = try XCTUnwrap(LearningEvidence.typedWord("3Xhaust", automaticallyChanged: false))
        XCTAssertEqual(observation.raw, "3xhaust")
        for _ in 0..<3 { try store.confirm(observation) }
        var engine = CompositionEngine()
        engine.words = store.words
        engine.append("3xhaust")
        XCTAssertEqual(engine.text, "3Xhaust")
        _ = engine.cancel()
        engine.append("3xhaustsms")
        XCTAssertEqual(engine.text, "3Xhaust는")
    }

    func testAutomaticOutputNeverBecomesEvidence() {
        XCTAssertNil(LearningEvidence.typedWord("3Xhaust", automaticallyChanged: true))
        XCTAssertNil(LearningEvidence.typedWord("hello", automaticallyChanged: false))
        XCTAssertNil(LearningEvidence.typedWord("123456", automaticallyChanged: false))
        XCTAssertNil(LearningEvidence.typedWord("안녕하세요", automaticallyChanged: false))
    }

    func testNewDeliberateCapitalizationIsNotOverridden() {
        var engine = CompositionEngine()
        engine.words = [LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 3)]
        engine.append("3XHaust")
        XCTAssertEqual(engine.text, "3XHaust")
    }

    func testEnglishAliasesCannotReplaceExactShiftedKoreanKeys() {
        var engine = CompositionEngine()
        engine.words = [
            LearnedWord(raw: "qk", text: "바", confirmations: 3),
            LearnedWord(raw: "Qk", text: "QK", confirmations: 3),
        ]
        engine.append("qk")
        XCTAssertEqual(engine.text, "바")
    }
}
