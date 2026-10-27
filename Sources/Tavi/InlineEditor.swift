import AppKit
import Carbon
import OSLog
import TaviCore

final class InlineEditor: NSTextView {
    private let store: LearningStore
    private let onError: (String?) -> Void
    private let source = SourceMonitor()
    private let backingStorage: NSTextStorage
    private var engine = CompositionEngine()
    private var literalUntilBoundary = false
    private var renderedText = ""
    private var composingRange: NSRange?
    private var pendingCorrection: LearnedWord?
    private var correctionOriginal: String?
    /// Set while Tavi is being reselected after a toggle, so that switch back is not a toggle.
    private var returningToTavi = false
    /// One press of the switch key can arrive both as Caps Lock and as a source change;
    /// the second report of the same press is not another toggle.
    private enum Trigger { case capsLock, sourceChange }
    private var lastToggle: (trigger: Trigger, at: Date)?
    private static let log = Logger(subsystem: "dev.3xhaust.tavi", category: "language-key")
    var onComposition: ((String, String) -> Void)?
    var onCorrection: ((String, String, String) -> Void)?
    var onLearned: ((LearnedWord) -> Void)?
    var learning = true
    var assistanceEnabled = true {
        didSet { if !assistanceEnabled { finish(learn: false) } }
    }

    init(store: LearningStore, onError: @escaping (String?) -> Void) {
        self.store = store
        self.onError = onError
        backingStorage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 460, height: CGFloat.greatestFiniteMagnitude))
        backingStorage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 230), textContainer: container)
        minSize = NSSize(width: 0, height: 230)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isRichText = false
        allowsUndo = true
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        font = .systemFont(ofSize: 20)
        textColor = .labelColor
        backgroundColor = .textBackgroundColor
        insertionPointColor = .controlAccentColor
        markedTextAttributes = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: NSColor.secondaryLabelColor,
            .foregroundColor: NSColor.labelColor,
        ]
        textContainerInset = NSSize(width: 16, height: 16)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        setAccessibilityLabel("Tavi 바로 입력")
        source.changed = { [weak self] previous, current in
            self?.applySourceChange(from: previous, to: current)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:onError:)") }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { source.start() }
        return result
    }

    override func resignFirstResponder() -> Bool {
        finish(learn: false)
        source.stop()
        return super.resignFirstResponder()
    }

    func refreshWords() { engine.words = store.words }

    override func keyDown(with event: NSEvent) {
        guard assistanceEnabled else {
            finish(learn: false)
            super.keyDown(with: event)
            return
        }
        if !engine.raw.isEmpty, !hasMarkedText(), !compositionStillMatches() {
            _ = engine.commit(learn: false)
            engine.previousToken = renderedText
            renderedText = ""
            composingRange = nil
        }
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAll(nil)
            return
        }
        if event.modifierFlags.contains([.control, .shift]), [123, 124].contains(event.keyCode) {
            finish(learn: false)
            if event.keyCode == 123 { moveWordLeftAndModifySelection(nil) }
            else { moveWordRightAndModifySelection(nil) }
            return
        }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            finish(learn: false)
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 51, !engine.raw.isEmpty {
            pendingCorrection = nil
            correctionOriginal = nil
            engine.backspace()
            renderComposition()
            if engine.raw.isEmpty { super.unmarkText() }
            return
        }
        if event.keyCode == 53, !engine.raw.isEmpty {
            let original = engine.cancel()
            renderedText = ""
            super.insertText(original, replacementRange: markedRange())
            composingRange = nil
            return
        }
        if [36, 48, 49, 76].contains(event.keyCode) {
            finish(learn: true)
            literalUntilBoundary = false
            super.keyDown(with: event)
            return
        }
        if literalUntilBoundary {
            super.keyDown(with: event)
            return
        }
        guard let key = Self.latinKey(event), key.count == 1,
              key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            if let text = event.characters, text.count == 1, ":/@\\_`.".contains(text),
               !engine.raw.isEmpty, engine.text.allSatisfy(\.isASCII) {
                engine.choose(engine.raw)
                renderComposition()
                literalUntilBoundary = true
                finish(learn: false)
            } else {
                finish(learn: event.characters?.first?.isPunctuation == true)
            }
            super.keyDown(with: event)
            return
        }
        if engine.raw.count >= 64 {
            finish(learn: false)
            literalUntilBoundary = true
            super.keyDown(with: event)
            return
        }
        refreshWords()
        pendingCorrection = nil
        correctionOriginal = nil
        if engine.raw.isEmpty {
            let location = min(selectedRange().location, (string as NSString).length)
            let start = max(0, location - 160)
            engine.previousToken = (string as NSString).substring(with: NSRange(location: start, length: location - start))
                .split(whereSeparator: \.isWhitespace).last.map(String.init)
        }
        engine.append(key)
        renderComposition()
    }

    override func selectAll(_ sender: Any?) {
        finish(learn: false)
        super.selectAll(sender)
    }

    override func copy(_ sender: Any?) {
        finish(learn: false)
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        finish(learn: false)
        super.cut(sender)
    }

    override func paste(_ sender: Any?) {
        finish(learn: false)
        literalUntilBoundary = false
        super.paste(sender)
    }

    override func mouseDown(with event: NSEvent) {
        finish(learn: false)
        literalUntilBoundary = false
        super.mouseDown(with: event)
    }

    func finish(learn: Bool) {
        guard !engine.raw.isEmpty else { return }
        let raw = engine.raw
        let output = renderedText
        let explicitEvidence = pendingCorrection
        pendingCorrection = nil
        correctionOriginal = nil
        let wasMarked = hasMarkedText()
        let range = markedRange()
        let result = engine.commit(learn: learn && learning)
        renderedText = ""
        composingRange = nil
        engine.previousToken = output
        if wasMarked { super.insertText(output, replacementRange: range) }
        guard wasMarked, learn, learning else { return }
        let evidence = explicitEvidence ?? (result.text == output ? result.correction : nil)
            ?? LearningEvidence.typedWord(output, automaticallyChanged: output != raw)
        guard let evidence else { return }
        do {
            try store.confirm(evidence)
            if let saved = store.words.first(where: { $0.raw == evidence.raw }) { onLearned?(saved) }
            onError(nil)
        } catch { onError(error.localizedDescription) }
    }

    private func renderComposition(replacing explicitRange: NSRange? = nil) {
        // Same text the input method shows in other apps, so practice matches real typing.
        let output = engine.text
        renderedText = output
        let replacement = explicitRange ?? (hasMarkedText() ? NSRange(location: NSNotFound, length: 0)
            : composingRange ?? NSRange(location: NSNotFound, length: 0))
        super.setMarkedText(
            output, selectedRange: NSRange(location: (output as NSString).length, length: 0),
            replacementRange: replacement
        )
        composingRange = engine.raw.isEmpty ? nil : markedRange()
        onComposition?(engine.raw, output)
    }

    private func compositionStillMatches() -> Bool {
        guard let range = composingRange, NSMaxRange(range) <= (string as NSString).length,
              selectedRange() == NSRange(location: NSMaxRange(range), length: 0) else { return false }
        return (string as NSString).substring(with: range) == renderedText
    }

    /// The user's input-source switch key toggles the composing word between Korean and
    /// its keys, as it does in other apps. When that switch left Tavi, Tavi is selected again.
    func applySourceChange(from previous: String?, to current: String?) {
        Self.log.notice("source \(previous ?? "-", privacy: .public) → \(current ?? "-", privacy: .public) returning=\(self.returningToTavi) keys=\(self.engine.raw.count) marked=\(self.hasMarkedText())")
        if returningToTavi, current == InputSourceSetup.bundleID {
            returningToTavi = false
            return
        }
        toggleComposition(by: .sourceChange)
        if previous == InputSourceSetup.bundleID, !engine.raw.isEmpty,
           InputSourceSetup.reselect() == noErr { returningToTavi = true }
    }

    /// With "Caps Lock switches to ABC" on, Caps Lock is the switch key; it can reach this
    /// view directly when macOS does not switch away from Tavi.
    override func flagsChanged(with event: NSEvent) {
        if event.keyCode == 57 {
            Self.log.notice("caps lock keys=\(self.engine.raw.count) switches=\(LanguageKey.capsLockSwitches)")
            if LanguageKey.capsLockSwitches { toggleComposition(by: .capsLock) }
        }
        super.flagsChanged(with: event)
    }

    private func toggleComposition(by trigger: Trigger) {
        guard assistanceEnabled, !engine.raw.isEmpty, window?.firstResponder === self,
              selectedRange().length == 0 else { return }
        if let last = lastToggle, last.trigger != trigger, Date().timeIntervalSince(last.at) < 0.4 { return }
        // Switching sources can commit the marked text; the word is then still in place.
        let replacing: NSRange?
        if hasMarkedText() {
            replacing = nil
        } else if compositionStillMatches(), let range = composingRange {
            replacing = range
        } else {
            Self.log.notice("toggle skipped: composition no longer in place")
            return
        }
        lastToggle = (trigger, Date())
        let raw = engine.raw
        let before = renderedText
        engine.lock(to: engine.text == Hangul.compose(raw) ? .latin : .korean)
        renderComposition(replacing: replacing)
        Self.log.notice("toggled changed=\(self.renderedText != before)")
        guard renderedText != before else { return }
        if correctionOriginal == nil { correctionOriginal = before }
        pendingCorrection = renderedText == correctionOriginal ? nil
            : LearnedWord(raw: raw, text: renderedText, confirmations: 1)
        onCorrection?(raw, before, renderedText)
    }

    private static func latinKey(_ event: NSEvent) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey >> 8) }
        // Caps Lock is usually the language key, so its lock state never capitalizes; only Shift does.
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        guard UCKeyTranslate(
            layout, event.keyCode, UInt16(kUCKeyActionDown), modifiers,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKey, characters.count, &length, &characters
        ) == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}

final class InlineEditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let editor = documentView as? NSTextView else { return }
        let size = contentSize
        if editor.minSize.height != size.height {
            editor.minSize = NSSize(width: 0, height: size.height)
        }
        if editor.frame.width != size.width || editor.frame.height < size.height {
            editor.setFrameSize(NSSize(width: size.width, height: max(editor.frame.height, size.height)))
        }
    }
}
