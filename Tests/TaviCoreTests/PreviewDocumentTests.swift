import XCTest
@testable import TaviCore

final class PreviewDocumentTests: XCTestCase {
    func testSentencePreservesSeparatorsAndConvertsIndividualTokens() {
        XCTAssertEqual(PreviewDocument.convert("hello  APIfmf\n"), "hello  API를\n")
    }

    func testExistingKoreanIsNotTurnedIntoRawKeysWhenAmbiguous() {
        XCTAssertEqual(PreviewDocument.convert("안녕하세요!"), "안녕하세요!")
    }

    func testNicknameIsNotHardcoded() {
        let words = [LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 3)]
        XCTAssertEqual(PreviewDocument.convert("hello 3xhaust", words: words), "hello 3Xhaust")
    }

    func testLargePasteIsNotProcessed() {
        let text = String(repeating: "APIfmf ", count: 1_000)
        XCTAssertEqual(PreviewDocument.convert(text), text)
    }

    func testOneOversizeWordIsNeverTruncated() {
        let text = String(repeating: "A", count: 65)
        XCTAssertEqual(PreviewDocument.convert(text), text)
    }
}
