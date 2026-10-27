import XCTest
@testable import TaviCore

final class TutorialProgressTests: XCTestCase {
    func testOnlyRealMatchingActionsCompleteSteps() {
        var progress = TutorialProgress()
        progress.advance()
        XCTAssertEqual(progress.step, .typing)
        progress.composed(raw: "APIfmf", text: "APIfmf")
        XCTAssertFalse(progress.canAdvance)
        progress.composed(raw: "APIfmf", text: "API를")
        progress.advance()
        XCTAssertEqual(progress.step, .correction)
        progress.corrected(raw: "to", before: "to", after: "to")
        XCTAssertFalse(progress.canAdvance)
        progress.corrected(raw: "to", before: "to", after: "새")
        progress.advance()
        XCTAssertEqual(progress.step, .learning)
        progress.learned(LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 2))
        XCTAssertFalse(progress.canAdvance)
        progress.learned(LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 3))
        progress.advance()
        XCTAssertEqual(progress.step, .finished)
    }

    func testSkipAndReplayDoNotFakeLearning() {
        var progress = TutorialProgress()
        progress.skip()
        XCTAssertEqual(progress.step, .finished)
        XCTAssertNil(progress.learnedText)
        progress.restart()
        XCTAssertEqual(progress.step, .typing)
        XCTAssertEqual(progress.confirmations, 0)
    }

    func testReturningUserStartsFinished() {
        XCTAssertEqual(TutorialProgress(completed: true).step, .finished)
    }
}
