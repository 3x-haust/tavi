import XCTest
@testable import TaviCore

final class InputSessionTests: XCTestCase {
    func testNativeCompositionAndSpaceAreOneCommit() {
        var session = InputSession()
        for key in "APIfmf" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.text, "API를")
        XCTAssertEqual(session.handle(.space), .commit("API를 ", consumesEvent: true, evidence: nil))
        XCTAssertTrue(session.raw.isEmpty)
        XCTAssertEqual(session.handle(.space), .pass)
    }

    func testLanguageKeyTogglesTheComposingWordWithoutCommitting() {
        var session = InputSession()
        for key in "gksdud" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.text, "한영")
        XCTAssertEqual(session.toggleLanguage(), .mark("gksdud"))
        XCTAssertEqual(session.toggleLanguage(), .mark("한영"))
        XCTAssertEqual(session.toggleLanguage(), .mark("gksdud"))
        guard case .commit("gksdud ", consumesEvent: true, evidence: let evidence?) = session.handle(.space) else {
            return XCTFail("Space should confirm the toggled word")
        }
        XCTAssertEqual(evidence.text, "gksdud")
        var empty = InputSession()
        XCTAssertEqual(empty.toggleLanguage(), .pass)

        var continued = InputSession()
        for key in "hhh" { _ = continued.handle(.text(String(key))) }
        XCTAssertEqual(continued.text, "hhh")
        XCTAssertEqual(continued.toggleLanguage(), .mark("ㅗㅗㅗ"))
        for key in "hhh" { _ = continued.handle(.text(String(key))) }
        XCTAssertEqual(continued.text, "ㅗㅗㅗㅗㅗㅗ")
        XCTAssertEqual(continued.handle(.backspace), .mark("ㅗㅗㅗㅗㅗ"))
        XCTAssertEqual(continued.toggleLanguage(), .mark("hhhhh"))
        _ = continued.handle(.text("e"))
        XCTAssertEqual(continued.text, "hhhhhe")
    }

    func testReturnConfirmsAndReachesTheHost() {
        var session = InputSession()
        for key in "dkssud" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.handle(.enter), .commit("안녕", consumesEvent: false, evidence: nil))
        XCTAssertEqual(session.handle(.enter), .pass)
    }

    func testBackspaceRecomposesAndEmptyDeletePassesThrough() {
        var session = InputSession()
        for key in "gks" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.text, "한")
        XCTAssertEqual(session.handle(.backspace), .mark("하"))
        _ = session.handle(.backspace)
        XCTAssertEqual(session.handle(.backspace), .mark(""))
        XCTAssertEqual(session.handle(.backspace), .pass)
    }

    func testEscapeCommitsAndReachesTheHostWithoutLearning() {
        var session = InputSession()
        for key in "dkssud" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.handle(.escape), .commit("안녕", consumesEvent: false, evidence: nil))
        XCTAssertEqual(session.handle(.escape), .pass)
    }

    func testShortcutCommitsButDoesNotConsumeOrLearn() {
        var session = InputSession()
        for key in "APIfmf" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.handle(.passThrough), .commit("API를", consumesEvent: false, evidence: nil))
        XCTAssertEqual(session.handle(.passThrough), .pass)
    }

    func testExplicitCorrectionLearnsOnlyOnConfirmedBoundary() {
        var session = InputSession()
        for key in "to" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.toggleLanguage(), .mark("새"))
        XCTAssertEqual(session.handle(.space),
                       .commit("새 ", consumesEvent: true,
                               evidence: LearnedWord(raw: "to", text: "새", confirmations: 1)))
        session = InputSession()
        for key in "to" { _ = session.handle(.text(String(key))) }
        _ = session.toggleLanguage()
        XCTAssertEqual(session.finish(learn: false),
                       .commit("새", consumesEvent: false, evidence: nil))
    }

    func testDirectCasingLearnsButAutomaticOutputDoesNot() {
        var session = InputSession()
        for key in "3Xhaust" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.handle(.space),
                       .commit("3Xhaust ", consumesEvent: true,
                               evidence: LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 1)))
        for key in "dkssud" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.handle(.space), .commit("안녕 ", consumesEvent: true, evidence: nil))
    }

    func testCodeAndURLsRemainLiteralAfterSyntax() {
        var session = InputSession()
        var result = ""
        for key in "https://example.com/path" {
            switch session.handle(.text(String(key))) {
            case .commit(let value, _, _): result += value
            case .pass: result += String(key)
            case .mark: break
            }
        }
        XCTAssertEqual(result, "https://example.com/path")
        XCTAssertEqual(session.handle(.space), .pass)
        for key in "dkssud" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.text, "안녕")
    }

    func testSixtyFiveKeysAreNotDropped() {
        var session = InputSession()
        let token = String(repeating: "a", count: 65)
        var commits = ""
        for key in token {
            if case .commit(let value, _, _) = session.handle(.text(String(key))) { commits += value }
        }
        XCTAssertEqual(commits, token)
        XCTAssertEqual(session.handle(.space), .pass)
    }

    func testLeadingPathSyntaxKeepsRestOfTokenLiteral() {
        var session = InputSession()
        XCTAssertEqual(session.handle(.text("/")), .pass)
        for key in "dkssud" {
            XCTAssertEqual(session.handle(.text(String(key))), .pass)
        }
        XCTAssertEqual(session.handle(.space), .pass)
        for key in "dkssud" { _ = session.handle(.text(String(key))) }
        XCTAssertEqual(session.text, "안녕")
    }

    func testSessionsHaveIndependentComposition() {
        var first = InputSession()
        var second = InputSession()
        for key in "dkssud" { _ = first.handle(.text(String(key))) }
        for key in "hello" { _ = second.handle(.text(String(key))) }
        XCTAssertEqual(first.text, "안녕")
        XCTAssertEqual(second.text, "hello")
        _ = first.finish(learn: false)
        XCTAssertEqual(second.text, "hello")
    }
}
