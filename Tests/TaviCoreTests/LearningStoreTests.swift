import Foundation
import XCTest
@testable import TaviCore

final class LearningStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testConfirmedSpellingPersistsWithExactCase() throws {
        let url = directory.appendingPathComponent("words.json")
        let store = try LearningStore(url: url)
        let correction = LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 1)
        try store.confirm(correction)
        XCTAssertEqual(store.words.first?.confirmations, 1)
        try store.confirm(correction)
        try store.confirm(correction)
        try store.confirm(correction)
        let reopened = try LearningStore(url: url)
        XCTAssertEqual(reopened.words, [LearnedWord(raw: "3xhaust", text: "3Xhaust", confirmations: 4)])
    }

    func testEstablishedSpellingKeepsCountingAndHalvesOnContraryChoice() throws {
        let store = try LearningStore(url: directory.appendingPathComponent("words.json"))
        for _ in 0..<8 { try store.confirm(LearnedWord(raw: "gksdud", text: "한영", confirmations: 1)) }
        XCTAssertEqual(store.words.first?.confirmations, 8)
        try store.confirm(LearnedWord(raw: "gksdud", text: "gksdud", confirmations: 1))
        XCTAssertEqual(store.words.first, LearnedWord(raw: "gksdud", text: "한영", confirmations: 4))
        try store.confirm(LearnedWord(raw: "gksdud", text: "gksdud", confirmations: 1))
        XCTAssertEqual(store.words.first, LearnedWord(raw: "gksdud", text: "gksdud", confirmations: 1))
    }

    func testNewPreferenceNeedsFreshEvidence() throws {
        let store = try LearningStore(url: directory.appendingPathComponent("words.json"))
        try store.set(raw: "to", text: "to")
        try store.confirm(LearnedWord(raw: "to", text: "새", confirmations: 3))
        XCTAssertEqual(store.words.first?.confirmations, 1)
    }

    func testShiftedHangulKeysAreDifferentEntries() throws {
        let store = try LearningStore(url: directory.appendingPathComponent("words.json"))
        try store.set(raw: "ek", text: "다")
        try store.set(raw: "Ek", text: "따")
        XCTAssertEqual(store.words.count, 2)
    }

    func testRefreshBeforeWritePreservesOtherWindowChanges() throws {
        let url = directory.appendingPathComponent("words.json")
        let first = try LearningStore(url: url)
        let second = try LearningStore(url: url)
        try first.set(raw: "nickname", text: "NickName")
        try second.set(raw: "company", text: "Company")
        try first.reload()
        XCTAssertEqual(Set(first.words.map(\.raw)), ["nickname", "company"])
        try first.remove(raw: "company")
        XCTAssertEqual(first.words.count, 1)
    }

    func testMalformedDataIsNotOverwritten() throws {
        let url = directory.appendingPathComponent("words.json")
        let data = Data("not json".utf8)
        try data.write(to: url)
        XCTAssertThrowsError(try LearningStore(url: url))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testRejectsSentencesAndControlCharacters() throws {
        let store = try LearningStore(url: directory.appendingPathComponent("words.json"))
        XCTAssertThrowsError(try store.set(raw: "one two", text: "one"))
        XCTAssertThrowsError(try store.set(raw: "one", text: "one\u{0}"))
        XCTAssertTrue(store.words.isEmpty)
    }

    func testMultipleSelectedWordsAreRemovedTogether() throws {
        let url = directory.appendingPathComponent("words.json")
        let store = try LearningStore(url: url)
        try store.set(raw: "first", text: "First")
        try store.set(raw: "second", text: "Second")
        try store.set(raw: "third", text: "Third")
        try store.remove(rawKeys: ["first", "third"])
        XCTAssertEqual(try LearningStore(url: url).words.map(\.raw), ["second"])
    }
}
