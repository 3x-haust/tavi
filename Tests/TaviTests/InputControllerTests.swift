import AppKit
import InputMethodKit
import XCTest
import TaviCore
@testable import Tavi

final class InputControllerTests: XCTestCase {
    private var directory: URL!
    private var preferences: UserDefaults!
    private var suiteName: String!
    private var runtime: InputMethodRuntime!
    private var window: NSWindow!
    private var client: EditorClient!
    private var controller: TaviInputController!
    private var secure = false

    override func setUpWithError() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "dev.3xhaust.tavi.tests.\(UUID().uuidString)"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        preferences.set(true, forKey: "compositionEnabled")
        preferences.set(false, forKey: "learning")
        runtime = InputMethodRuntime(
            store: try LearningStore(url: directory.appendingPathComponent("words.json")),
            preferences: preferences
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        client = EditorClient()
        window.contentView = client.view
        window.makeFirstResponder(client.view)
        controller = try XCTUnwrap(TaviInputController(runtime: runtime) { [unowned self] _ in
            self.secure
        })
        controller.activateServer(client)
    }

    override func tearDownWithError() throws {
        controller = nil
        client = nil
        window.close()
        window = nil
        runtime = nil
        preferences.removePersistentDomain(forName: suiteName)
        try FileManager.default.removeItem(at: directory)
    }

    func testFocusReturnComposesWithoutDocumentSelection() throws {
        try type("hello")
        XCTAssertTrue(send(" ", code: 49))
        XCTAssertEqual(client.view.string, "hello ")

        window.makeFirstResponder(nil)
        window.makeFirstResponder(client.view)
        client.reportsSelection = false
        controller.activateServer(client)
        XCTAssertEqual(client.selectedRange().location, NSNotFound)
        var caret = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &caret)
        XCTAssertGreaterThan(caret.height, 0, "The native editor still has an insertion point")

        try type("dkssud")
        XCTAssertEqual(client.view.string, "hello 안녕")
        XCTAssertTrue(client.view.hasMarkedText(), "The word must remain marked after focus returns")
        XCTAssertEqual(client.view.markedRange(), NSRange(location: 6, length: 2))
        // NSTextView draws marking separately; it is not an attribute of the stored document.
        XCTAssertEqual(client.view.markedTextAttributes?[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
        try snapshotComposition()
        XCTAssertTrue(send(" ", code: 49))
        try type("gksrmf")
        XCTAssertEqual(client.view.string, "hello 안녕 한글", "The next word must not replace the committed word")
    }

    func testUnavailableSelectionDoesNotBlockEnglishMarkedText() throws {
        client.reportsSelection = false

        try type("hello")

        XCTAssertEqual(client.view.string, "hello")
        XCTAssertTrue(client.view.hasMarkedText())
    }

    func testNoTextFieldLeavesTypeSelectionAndShortcutsToHost() {
        client.reportsSelection = false
        client.hasInsertionPoint = false

        XCTAssertFalse(send("a", code: 0))
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
            XCTAssertFalse(send("a", code: 0, modifiers: modifier))
        }
        XCTAssertFalse(send("\t", code: 48))
        XCTAssertFalse(send("\u{f702}", code: 123))

        XCTAssertEqual(client.markCalls, 0)
        XCTAssertEqual(client.insertCalls, 0)
        XCTAssertEqual(client.view.string, "")
    }

    func testCaretEvidenceIsNotReusedOutsideTextField() throws {
        client.reportsSelection = false
        try type("dkssud")
        XCTAssertTrue(send(" ", code: 49))
        let marks = client.markCalls
        let inserts = client.insertCalls
        client.hasInsertionPoint = false

        XCTAssertFalse(send("a", code: 0))

        XCTAssertEqual(client.markCalls, marks)
        XCTAssertEqual(client.insertCalls, inserts)
        XCTAssertEqual(client.view.string, "안녕 ")
    }

    func testKnownSelectionDoesNotNeedCaretFallback() throws {
        client.hasInsertionPoint = false

        try type("dkssud")

        XCTAssertEqual(client.view.string, "안녕")
        XCTAssertTrue(client.view.hasMarkedText())
        XCTAssertEqual(client.caretQueries, 0)
    }

    func testZeroWidthAndVerticalCaretsCanStartComposition() throws {
        client.reportsSelection = false
        for size in [NSSize(width: 0, height: 20), NSSize(width: 20, height: 0)] {
            client.caretOverride = NSRect(origin: .zero, size: size)
            try type("dkssud")
            XCTAssertTrue(client.view.hasMarkedText())
            XCTAssertTrue(send(" ", code: 49))
        }
        XCTAssertEqual(client.view.string, "안녕 안녕 ")
    }

    func testShortcutCommitsWithoutConsumingTheShortcut() throws {
        client.reportsSelection = false
        try type("dkssud")

        XCTAssertFalse(send("a", code: 0, modifiers: .command))

        XCTAssertEqual(client.view.string, "안녕")
        XCTAssertFalse(client.view.hasMarkedText())
        XCTAssertEqual(client.insertCalls, 1)
    }

    func testSecureInputBypassesCompositionAndCaretQueries() {
        secure = true
        client.reportsSelection = false

        XCTAssertFalse(send("a", code: 0))

        XCTAssertEqual(client.markCalls, 0)
        XCTAssertEqual(client.insertCalls, 0)
        XCTAssertEqual(client.caretQueries, 0)
        XCTAssertEqual(client.view.string, "")
    }

    func testDisabledInputBypassesCompositionAndCaretQueries() {
        preferences.set(false, forKey: "compositionEnabled")
        client.reportsSelection = false

        XCTAssertFalse(send("a", code: 0))

        XCTAssertEqual(client.markCalls, 0)
        XCTAssertEqual(client.insertCalls, 0)
        XCTAssertEqual(client.caretQueries, 0)
    }

    private func snapshotComposition() throws {
        guard let path = ProcessInfo.processInfo.environment["APP_ARTIFACTS_DIR"] else { return }
        client.view.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(client.view.bitmapImageRepForCachingDisplay(in: client.view.bounds))
        client.view.cacheDisplay(in: client.view.bounds, to: image)
        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("focus-composition.png"))
    }

    private func type(_ text: String) throws {
        for character in text {
            let consumed = send(String(character), code: 0)
            guard consumed else {
                XCTFail("An editable client rejected '\(character)' before creating marked text")
                throw RejectedInput()
            }
        }
    }

    private func send(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code
        )!
        // Direct invocation only: no events are posted to the user's session.
        return controller.handle(event, client: client)
    }
}

private struct RejectedInput: Error {}

/// Models a client without document-access ranges; composition still uses a native text view.
private final class EditorClient: NSObject, IMKTextInput {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    var reportsSelection = true
    var hasInsertionPoint = true
    var caretOverride: NSRect?
    private(set) var markCalls = 0
    private(set) var insertCalls = 0
    private(set) var caretQueries = 0

    override init() {
        super.init()
        view.isRichText = false
        view.font = .systemFont(ofSize: 20)
        view.markedTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue]
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        insertCalls += 1
        view.insertText(string!, replacementRange: replacementRange)
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        markCalls += 1
        view.setMarkedText(string!, selectedRange: selectionRange, replacementRange: replacementRange)
    }

    func selectedRange() -> NSRange {
        reportsSelection ? view.selectedRange() : NSRange(location: NSNotFound, length: NSNotFound)
    }
    func markedRange() -> NSRange { view.markedRange() }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        view.attributedSubstring(forProposedRange: range, actualRange: nil)
    }
    func length() -> Int { (view.string as NSString).length }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        caretQueries += 1
        lineRect.pointee = caretOverride ?? (hasInsertionPoint
            ? view.firstRect(forCharacterRange: view.selectedRange(), actualRange: nil) : .zero)
        return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { view.validAttributesForMarkedText() }
    func overrideKeyboard(withKeyboardNamed name: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "dev.3xhaust.tavi.test-editor" }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "test-editor" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        view.attributedSubstring(forProposedRange: range, actualRange: actualRange)?.string
    }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect {
        view.firstRect(forCharacterRange: range, actualRange: actualRange)
    }
}
