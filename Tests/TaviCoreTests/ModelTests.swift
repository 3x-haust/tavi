import XCTest
@testable import TaviCore

final class ModelTests: XCTestCase {
    func testEnglishCorpusStatisticsSeparateWordsFromKeyboardMash() {
        let model = StatisticalModel.shared
        XCTAssertGreaterThan(
            model.englishEvidence("planet").score,
            model.englishEvidence("qzxjv").score
        )
        XCTAssertTrue(model.isKnownEnglish("compiler"))
        XCTAssertTrue(model.isCommonEnglish("garden"))
    }

    func testKoreanCorpusStatisticsSeparateOrdinaryTextFromAccidentalHangul() {
        let model = StatisticalModel.shared
        XCTAssertGreaterThan(model.koreanScore("공원"), model.koreanScore(Hangul.compose("the")))
        XCTAssertTrue(model.isKnownKorean("파일"))
    }

    func testBundledModelIsBelowReleaseBudget() {
        XCTAssertGreaterThan(StatisticalModel.bundledByteCount, 0)
        XCTAssertLessThanOrEqual(StatisticalModel.bundledByteCount, 2 * 1_024 * 1_024)
    }

}
