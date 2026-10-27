import XCTest
@testable import TaviCore

final class HangulTests: XCTestCase {
    func testDubeolsikCompositionAndRoundTrip() {
        for (keys, text) in [
            ("gksrmf", "한글"),
            ("dkssudgktpdy", "안녕하세요"),
            ("rhk", "과"),
            ("rkqt", "값"),
            ("Qk", "빠"),
            ("qk", "바"),
        ] {
            XCTAssertEqual(Hangul.compose(keys), text)
            XCTAssertEqual(Hangul.compose(Hangul.keys(for: text)), text)
        }
    }

    func testShiftedKeysAreNotLowercased() {
        XCTAssertNotEqual(Hangul.compose("Qk"), Hangul.compose("qk"))
        XCTAssertNotEqual(Hangul.compose("Ek"), Hangul.compose("ek"))
        XCTAssertNotEqual(Hangul.compose("Wk"), Hangul.compose("wk"))
    }

    func testBackspaceRecomposesCompoundStateFromRawKeys() {
        var engine = CompositionEngine()
        for key in "gksrmf" {
            engine.append(String(key))
        }
        XCTAssertEqual(engine.candidates.first(where: { $0.text == "한글" })?.text, "한글")

        engine.backspace()
        XCTAssertEqual(Hangul.compose(engine.raw), "한그")
        engine.backspace()
        XCTAssertEqual(Hangul.compose(engine.raw), "한ㄱ")
        engine.backspace()
        XCTAssertEqual(Hangul.compose(engine.raw), "한")
    }

    func testNonKeyboardCharactersPassThroughWithoutLosingState() {
        let composed = Hangul.compose("gks-test")
        XCTAssertEqual(composed, "한-ㅅㄷㄴㅅ")
        XCTAssertEqual(Hangul.keys(for: composed), "gks-test")
    }
}
