import XCTest
@testable import TaviCore

final class CompositionTests: XCTestCase {
    func testOrdinaryEnglishAndKoreanUseStatisticalEvidence() {
        XCTAssertEqual(engine("garden").text, "garden")
        XCTAssertEqual(engine("window").text, "window")
        XCTAssertEqual(engine("dkssudgktpdy").text, "안녕하세요")
        XCTAssertEqual(engine("rhddnjs").text, "공원")
        XCTAssertEqual(engine("wkRN").text, "자꾸")
        XCTAssertEqual(engine("sork").text, "내가")
        XCTAssertEqual(engine("gody").text, "해요")
    }

    func testNarrowEnglishKoreanSplits() {
        let particle = engine("APIfmf")
        XCTAssertEqual(particle.text, "API를")
        XCTAssertTrue(particle.automaticEligible)
        XCTAssertGreaterThanOrEqual(particle.confidence, 0.80)

        let word = engine("PDFvkdlf")
        XCTAssertEqual(word.text, "PDF파일")
        XCTAssertTrue(word.automaticEligible)
        XCTAssertEqual(engine("catchtypedlfkrh").text, "catchtype이라고")
    }

    func testCoincidentalEnglishFragmentDoesNotSplitCompleteKorean() {
        XCTAssertEqual(engine("ahdmf").text, "모을")
        XCTAssertEqual(engine("gksdud").text, "한영")
        // Korean then a stray "English" tail: the clean Korean reading wins, a real mixed word still splits.
        XCTAssertEqual(engine("anjsi").text, "뭐냐")
        XCTAssertEqual(engine("dlrjtl").text, "이거시")
        XCTAssertEqual(engine("tofeature").text, "새feature")
        XCTAssertTrue(engine("gksdud").candidates.contains { $0.text == "한dud" })
        XCTAssertEqual(engine("gitdmf").text, "git을")
        XCTAssertEqual(engine("slackdp").text, "slack에")
        XCTAssertEqual(engine("ehoTsk").text, "됐나")
        XCTAssertEqual(engine("OKfmf").text, "OK를")
    }

    func testKoreanWordDoesNotFlickerThroughLatinWhileTyping() {
        for word in ["dkssudgktpdy", "dlfmadmf", "wkdtkfmf"] {
            var value = CompositionEngine()
            var shown: [String] = []
            for key in word {
                value.append(String(key))
                shown.append(value.text)
            }
            let firstKorean = shown.firstIndex { $0.contains { !$0.isASCII } } ?? 0
            XCTAssertFalse(shown[firstKorean...].contains { $0.contains { $0.isASCII && $0.isLetter } }, "\(word): \(shown)")
        }
        XCTAssertEqual(engine("commit").text, "commit")
    }

    func testLowercaseAbbreviationAndParticle() {
        XCTAssertEqual(engine("apifh").text, "api로",
                       "front=\(StatisticalModel.shared.englishEvidence("api")) whole=\(StatisticalModel.shared.englishEvidence("apifh"))")
    }

    func testKoreanPrefixWithRememberedNickname() {
        var value = CompositionEngine()
        value.words = [LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 3)]
        type("dkssud3xhaust", into: &value)
        XCTAssertEqual(value.text, "안녕3Xhaust")
    }

    func testObservationsDoNotChangeAutomaticPrediction() {
        let raw = "blorpx"
        let baseline = engine(raw)
        for count in [1, 2] {
            var observed = CompositionEngine()
            observed.words = [LearnedWord(raw: raw, text: "새로운값", confirmations: count)]
            type(raw, into: &observed)
            XCTAssertEqual(observed.text, baseline.text)
            XCTAssertEqual(observed.confidence, baseline.confidence)
        }
    }

    func testURLsCodeAndValidEnglishStayLiteral() {
        for literal in [
            "https://example.com/path",
            "name@example.com",
            "Sources/TaviCore",
            "parseJSON2",
            "can't",
            "the",
        ] {
            XCTAssertEqual(engine(literal).text, literal, literal)
        }
    }

    func testPreviousTokenProvidesSmallDeterministicContext() {
        var english = CompositionEngine()
        english.previousToken = "English"
        type("go", into: &english)
        XCTAssertEqual(english.text, "go")

        var korean = CompositionEngine()
        korean.previousToken = "한국어"
        type("go", into: &korean)
        XCTAssertEqual(korean.text, "해")
    }

    func testLearnedKoreanKeysMatchExactRawAndASCIISpellingMayIgnoreCase() {
        var shifted = CompositionEngine()
        shifted.words = [LearnedWord(raw: "Qk", text: "별명", confirmations: 3)]
        type("qk", into: &shifted)
        XCTAssertNotEqual(shifted.text, "별명")
        shifted = CompositionEngine()
        shifted.words = [LearnedWord(raw: "Qk", text: "별명", confirmations: 3)]
        type("Qk", into: &shifted)
        XCTAssertEqual(shifted.text, "별명")

        var canonical = CompositionEngine()
        canonical.words = [LearnedWord(raw: "nickname", text: "Nyx", confirmations: 3)]
        type("NICKNAME", into: &canonical)
        XCTAssertEqual(canonical.text, "Nyx")
    }

    func testPreferenceNeedsThreeConfirmations() {
        var pending = CompositionEngine()
        pending.words = [LearnedWord(raw: "garden", text: "Garden", confirmations: 2)]
        type("garden", into: &pending)
        XCTAssertEqual(pending.text, "garden")

        var confirmed = CompositionEngine()
        confirmed.words = [LearnedWord(raw: "garden", text: "Garden", confirmations: 3)]
        type("garden", into: &confirmed)
        XCTAssertEqual(confirmed.text, "Garden")
        XCTAssertTrue(confirmed.automaticEligible)
    }

    func testExplicitSourceChoiceBypassesInferenceEligibility() {
        var engine = CompositionEngine()
        type("go", into: &engine)
        engine.sourceChanged(to: .korean)
        XCTAssertEqual(engine.text, "해")
        XCTAssertTrue(engine.isExplicit)
        XCTAssertEqual(engine.confidence, 1)
        XCTAssertTrue(engine.automaticEligible)

        engine.sourceChanged(to: .latin)
        XCTAssertEqual(engine.text, "go")
        XCTAssertTrue(engine.isExplicit)
    }

    func testExplicitChangedChoiceLearnsOnce() {
        var engine = CompositionEngine()
        type("garden", into: &engine)
        engine.choose("Garden")
        let commit = engine.commit()
        XCTAssertEqual(commit.text, "Garden")
        XCTAssertEqual(commit.correction, LearnedWord(raw: "garden", text: "Garden", confirmations: 1))
        XCTAssertEqual(engine.previousToken, "Garden")
        XCTAssertTrue(engine.raw.isEmpty)
    }

    func testRawLengthIsBounded() {
        var engine = CompositionEngine()
        type(String(repeating: "a", count: 100), into: &engine)
        XCTAssertEqual(engine.raw.count, 64)
    }

    private func engine(_ raw: String) -> CompositionEngine {
        var result = CompositionEngine()
        type(raw, into: &result)
        return result
    }

    private func type(_ raw: String, into engine: inout CompositionEngine) {
        for character in raw {
            engine.append(String(character))
        }
    }
}
