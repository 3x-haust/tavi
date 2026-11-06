#if DEBUG
import AppKit
import Foundation
import TaviCore

enum EditorCheck {
    static func run() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tavi-editor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try LearningStore(url: directory.appendingPathComponent("words.json"))
        let view = InlineEditor(store: store) { _ in }
        view.learning = false
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.contentView = view
        window.makeFirstResponder(view)
        precondition(view.textStorage != nil && view.textContainer != nil, "Missing native text system")
        view.insertText("native input", replacementRange: NSRange(location: 0, length: 0))
        precondition(view.string == "native input", "Native insertion failed")
        view.selectAll(nil)
        precondition(view.selectedRange().length == (view.string as NSString).length, "Select all failed")
        view.insertText("", replacementRange: view.selectedRange())
        var typed = ""
        for (key, code) in [("s", UInt16(1)), ("m", UInt16(46)), ("s", UInt16(1))] {
            typed += key
            send(key: key, code: code, to: view, in: window)
            precondition(view.string == typed || view.string == Hangul.compose(typed), "Mixed partial composition")
            view.unmarkText()
        }
        // Any input-source switch toggles the composing word, whichever key the user switches with.
        let composed = view.string
        view.applySourceChange(from: "check.previous", to: "check.next")
        precondition(Set([composed, view.string]) == ["sms", "는"], "Switch key did not toggle the whole token: \(view.string)")
        view.applySourceChange(from: "check.next", to: "check.previous")
        precondition(view.string == composed, "Second switch did not toggle back: \(view.string)")
        view.finish(learn: false)
        view.applySourceChange(from: "check.previous", to: "check.next")
        precondition(view.string == composed, "A switch without a composition changed committed text")
        send(key: "a", code: 0, modifiers: [.control], to: view, in: window)
        precondition(view.selectedRange().length == (view.string as NSString).length, "Control+A failed")
        view.insertText("replace", replacementRange: view.selectedRange())
        precondition(view.string == "replace", "Selected text replacement failed")
        checkShiftedKorean(in: view, window: window)
        view.learning = true
        var learned = ""
        for _ in 0..<3 {
            view.selectAll(nil)
            view.insertText("", replacementRange: view.selectedRange())
            send(key: "a", code: 0, to: view, in: window)
            send(key: "h", code: 4, to: view, in: window)
            view.applySourceChange(from: "check.previous", to: "check.next")
            learned = view.string
            view.finish(learn: true)
        }
        precondition(store.words.first(where: { $0.raw == "ah" })?.text == learned
            && store.words.first(where: { $0.raw == "ah" })?.confirmations == 3, "Visible correction was not learned")
        let rows = CheckRows()
        let table = WordTableView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("test")))
        table.dataSource = rows
        window.contentView = table
        table.reloadData()
        table.selectAll(nil)
        precondition(table.selectedRowIndexes == IndexSet([0, 1, 2]), "Table select all failed")
        let row = table.rect(ofRow: 1)
        let point = table.convert(NSPoint(x: row.midX, y: row.midY), to: nil)
        guard let click = NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: .control, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ) else { preconditionFailure("Cannot create selection event") }
        table.mouseDown(with: click)
        precondition(table.selectedRowIndexes == IndexSet([0, 2]), "Control-click toggle failed")
        send(key: "a", code: 0, modifiers: [.control], to: table, in: window)
        precondition(table.selectedRowIndexes.count == 3, "Table Control+A failed")
        window.close()
        print("EDITOR_CHECK_PASSED")
    }

    private static func checkShiftedKorean(in view: InlineEditor, window: NSWindow) {
        view.selectAll(nil)
        view.insertText("", replacementRange: view.selectedRange())
        let codes: [Character: UInt16] = [
            "w": 13, "k": 40, "m": 46, "d": 2, "s": 1, "r": 15, "p": 35,
            "t": 17, "j": 38, "q": 12, "h": 4, "f": 3, "o": 31, "l": 37, "e": 14,
        ]
        var committed = ""
        for (raw, expected) in [
            ("WKwmdskrp", "짜증나게"), ("TJqhfrp", "써볼게"),
            ("toRL", "새끼"), ("hello", "hello"),
        ] {
            for key in raw {
                let code = codes[Character(String(key).lowercased())]!
                send(key: String(key), code: code, modifiers: key.isUppercase ? [.shift] : [], to: view, in: window)
                precondition(view.string.hasPrefix(committed), "Next key changed committed text")
            }
            precondition(view.string == committed + expected, "Shifted composition failed: \(view.string)")
            send(key: " ", code: 49, to: view, in: window)
            committed += expected + " "
            precondition(view.string == committed, "Space changed corrected text: \(view.string)")
        }
        precondition(view.string == "짜증나게 써볼게 새끼 hello ", "Corrected sentence was not preserved")
    }

    private static func send(
        key: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [],
        to view: NSResponder, in window: NSWindow
    ) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code
        ) else { preconditionFailure("Cannot create native test event") }
        view.keyDown(with: event)
    }
}

private final class CheckRows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 3 }
}
#endif
