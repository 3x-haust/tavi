import AppKit

final class WordTableView: NSTableView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowsMultipleSelection = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func mouseDown(with event: NSEvent) {
        if toggleControlSelection(event) { return }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if toggleControlSelection(event) { return }
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAll(nil)
            return
        }
        super.keyDown(with: event)
    }

    private func toggleControlSelection(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control), !event.modifierFlags.contains(.shift) else { return false }
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return false }
        window?.makeFirstResponder(self)
        var selection = selectedRowIndexes
        if selection.contains(row) { selection.remove(row) }
        else { selection.insert(row) }
        selectRowIndexes(selection, byExtendingSelection: false)
        return true
    }
}
