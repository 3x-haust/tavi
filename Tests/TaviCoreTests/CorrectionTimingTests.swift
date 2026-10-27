import XCTest
@testable import TaviCore

final class CorrectionTimingTests: XCTestCase {
    func testExternalTypingNeverMutatesAnUnfinishedWord() {
        XCTAssertFalse(CorrectionTiming.allowsAutomaticReplacement(atBoundary: false, insertedBoundary: "", markedLength: 0))
        XCTAssertFalse(CorrectionTiming.allowsAutomaticReplacement(atBoundary: false, insertedBoundary: "", markedLength: 1))
    }

    func testOnlyVerifiedCommittedBoundariesCanConvert() {
        XCTAssertTrue(CorrectionTiming.allowsAutomaticReplacement(atBoundary: true, insertedBoundary: " ", markedLength: 0))
        XCTAssertFalse(CorrectionTiming.allowsAutomaticReplacement(atBoundary: true, insertedBoundary: " ", markedLength: 1))
        XCTAssertFalse(CorrectionTiming.allowsAutomaticReplacement(atBoundary: true, insertedBoundary: " ", markedLength: nil))
        XCTAssertFalse(CorrectionTiming.allowsAutomaticReplacement(atBoundary: true, insertedBoundary: "", markedLength: 0))
    }
}
