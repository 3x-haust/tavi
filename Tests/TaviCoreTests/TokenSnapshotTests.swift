import Foundation
import XCTest
@testable import TaviCore

final class TokenSnapshotTests: XCTestCase {
    private func snapshot(_ text: String, marked: Int? = 0) -> TokenSnapshot {
        let length = (text as NSString).length
        return TokenSnapshot(context: text, origin: 0, caret: length, documentLength: length, markedLength: marked)
    }

    func testTokenOffsetsUseUTF16() {
        let token = snapshot("👩‍💻 APIfmf ").token(allowBoundary: true)
        XCTAssertEqual(token?.text, "APIfmf")
        XCTAssertEqual(token?.range.location, ("👩‍💻 " as NSString).length)
        XCTAssertEqual(token?.boundary, " ")
    }

    func testActiveAndUnknownCompositionAbstain() {
        XCTAssertNil(snapshot("안녕", marked: 1).token(allowBoundary: true))
        XCTAssertNil(snapshot("안녕", marked: nil).token(allowBoundary: true))
    }

    func testURLsIdentifiersAndOversizeTokensAreUntouched() {
        for value in ["https://test.dev/APIfmf", "user@APIfmf", "some_variable", "--option", String(repeating: "a", count: 65)] {
            XCTAssertNil(snapshot(value).token(allowBoundary: false), value)
        }
    }

    func testOnlyCurrentTokenIsReturned() {
        XCTAssertEqual(snapshot("앞 문장 3토면ㅅ").token(allowBoundary: false)?.text, "3토면ㅅ")
        XCTAssertNil(snapshot("hello ").token(allowBoundary: false))
    }

    func testSourceCorrectionUsesWholeUnspacedNickname() throws {
        let token = try XCTUnwrap(snapshot("앞 문장 3토면ㅅ").token(allowBoundary: false))
        XCTAssertEqual(Hangul.keys(for: token.text), "3xhaust")
        XCTAssertEqual(token.range.length, ("3토면ㅅ" as NSString).length)
    }

    func testTruncatedTokenIsRejected() {
        let value = TokenSnapshot(context: "partialword", origin: 150, caret: 161, documentLength: 161, markedLength: 0)
        XCTAssertNil(value.token(allowBoundary: false))
    }
}
