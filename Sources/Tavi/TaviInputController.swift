import AppKit
import Carbon
import InputMethodKit
import OSLog
import TaviCore

@objc(TaviInputController)
final class TaviInputController: IMKInputController {
    private var session = InputSession()
    private let runtime = InputMethodRuntime.shared
    private let replacement = NSRange(location: NSNotFound, length: NSNotFound)

    private var active = false
    private var deciding = false
    private var resuming = false
    private var keystrokes = 0
    /// A Caps Lock that toggled here may also switch the source; that is the same press.
    private var capsToggle = Date.distantPast
    private static let log = Logger(subsystem: "dev.3xhaust.inputmethod.tavi", category: "language-key")

    override func activateServer(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        active = true
        client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.US")
        // Coming back from a language-key switch keeps the toggled composition alive.
        if resuming || deciding {
            resuming = false
            return
        }
        session = InputSession()
        runtime.reloadWords()
        // Choosing Tavi while its automatic input is off means the user wants it back on.
        if !runtime.enabled, InputSourceSetup.isSelected { runtime.enabled = true }
    }

    override func deactivateServer(_ sender: Any!) {
        active = false
        guard let client = sender as? IMKTextInput else { return }
        end(on: client)
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        end(on: client)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    /// The correction key is whatever the user switches input sources with (한/영 via
    /// Caps Lock, Globe, ⌃Space…). macOS handles that key itself and only tells Tavi by
    /// ending the composition. Whether the source really changed is known a moment
    /// later: if it did, the key toggles the word and Tavi returns; otherwise it was a
    /// focus change and the word is committed as usual. When Caps Lock is the switch key
    /// and reaches Tavi instead, it toggles directly in `handle`.
    private func end(on client: IMKTextInput) {
        guard !session.raw.isEmpty, runtime.enabled else {
            _ = apply(session.finish(learn: false), to: client)
            return
        }
        guard !deciding else { return }
        deciding = true
        let typed = keystrokes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.deciding = false
            Self.log.notice("end selected=\(InputSourceSetup.isSelected) keys=\(self.session.raw.count) typed=\(typed != self.keystrokes)")
            if !InputSourceSetup.isSelected, InputSourceSetup.reselect() == noErr {
                if Date().timeIntervalSince(self.capsToggle) > 0.4 {
                    _ = self.apply(self.session.toggleLanguage(), to: client)
                } else {
                    _ = self.apply(.mark(self.session.text), to: client)
                }
                self.resuming = true
            } else if typed == self.keystrokes || !InputSourceSetup.isSelected {
                _ = self.apply(self.session.finish(learn: false), to: client)
            }
        }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? IMKTextInput,
              client.bundleIdentifier() != InputSourceSetup.applicationID else { return false }
        if event.type == .flagsChanged {
            guard event.keyCode == 57 else { return false }
            Self.log.notice("caps lock keys=\(self.session.raw.count) switches=\(LanguageKey.capsLockSwitches)")
            guard LanguageKey.capsLockSwitches, !session.raw.isEmpty, runtime.enabled else { return false }
            // One press can arrive twice a few milliseconds apart; a second toggle would undo the first.
            guard Date().timeIntervalSince(capsToggle) > 0.05 else { return true }
            capsToggle = Date()
            return apply(session.toggleLanguage(), to: client)
        }
        guard event.type == .keyDown else { return false }
        keystrokes += 1
        guard runtime.enabled, !Self.isSecureInput(in: client) else {
            _ = apply(session.finish(learn: false), to: client)
            return false
        }
        if session.raw.isEmpty { session.setWords(runtime.store?.words ?? []) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key: InputSession.Key
        if !flags.intersection([.command, .control, .option]).isEmpty {
            key = .passThrough
        } else {
            switch event.keyCode {
            case 51: key = .backspace
            case 53: key = .escape
            case 49: key = .space
            case 36, 76: key = .enter
            case 48, 115...126: key = .passThrough
            default:
                guard var characters = event.characters, !characters.isEmpty else { return false }
                // Caps Lock is usually the language key, so its lock state never capitalizes; only Shift does.
                if flags.contains(.capsLock), characters.allSatisfy({ $0.isASCII && $0.isLetter }) {
                    characters = flags.contains(.shift) ? characters.uppercased() : characters.lowercased()
                }
                key = characters.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value)
                }) ? .passThrough : .text(characters)
            }
        }
        // Without a text field (Finder's file list, a table) keys keep their own meaning, such as type-select.
        if session.raw.isEmpty, case .text = key, client.selectedRange().location == NSNotFound {
            Self.log.notice("no text field in \(client.bundleIdentifier() ?? "?", privacy: .public)")
            return false
        }
        let update = session.handle(key)
        if case .commit(let text, _, let evidence) = update, Self.keyDropsCommittedText.contains(client.bundleIdentifier() ?? "") {
            switch key {
            case .text, .space:
                break
            case .enter, .escape:
                // These hosts send either the committed text or the key, never both; the key rides along as text.
                client.insertText(text, replacementRange: replacement)
                client.insertText(event.characters ?? "\r", replacementRange: replacement)
                runtime.confirm(evidence)
                return true
            default:
                // Tab, arrows and shortcuts would replace the text: commit after the key and let the next press act.
                DispatchQueue.main.async { client.insertText(text, replacementRange: self.replacement) }
                runtime.confirm(evidence)
                return true
            }
        }
        return apply(update, to: client)
    }

    /// A password prompt that turned on Secure Event Input, as Ghostty does for `sudo`: its keys
    /// pass through untouched, so a password is never read as Korean or shown as marked text.
    /// Secure input another app left on does not stop Tavi elsewhere; an unknown owner counts.
    private static func isSecureInput(in client: IMKTextInput) -> Bool {
        guard IsSecureEventInputEnabled() else { return false }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? pid_t,
              let owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return true }
        return owner == client.bundleIdentifier()
    }

    /// Terminals that encode a key event with the text an input method commits during it as one or the other.
    private static let keyDropsCommittedText: Set<String> = ["com.mitchellh.ghostty"]

    override func composedString(_ sender: Any!) -> Any! { session.text as NSString }

    override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: session.raw)
    }

    /// Tavi's only menu: the input-source menu in the menu bar.
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "자동 한영 입력", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.state = runtime.enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "설정과 내 단어…", action: #selector(openSettings(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "튜토리얼…", action: #selector(openTutorial(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "키보드 설정 열기…", action: #selector(openKeyboardSettings(_:)), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func toggleEnabled(_ sender: Any?) { runtime.enabled.toggle() }

    @objc private func openKeyboardSettings(_ sender: Any?) { InputSourceSetup.openSettings() }

    @objc private func openTutorial(_ sender: Any?) { openApplication(tutorial: true) }

    @objc private func openSettings(_ sender: Any?) { openApplication(tutorial: false) }

    private func openApplication(tutorial: Bool) {
        guard !InputSourceSetup.openApplication(tutorial: tutorial) else { return }
        let alert = NSAlert()
        alert.messageText = "응용 프로그램에서 Tavi를 열어 주세요"
        alert.informativeText = "설정 앱을 찾을 수 없어요. Tavi 앱을 응용 프로그램 폴더에 다시 복사해 주세요."
        alert.runModal()
    }

    @discardableResult
    private func apply(_ update: InputSession.Update, to client: IMKTextInput) -> Bool {
        switch update {
        case .pass:
            return false
        case .mark(let text):
            client.setMarkedText(
                text, selectionRange: NSRange(location: (text as NSString).length, length: 0),
                replacementRange: replacement
            )
            return true
        case .commit(let text, let consumesEvent, let evidence):
            client.insertText(text, replacementRange: replacement)
            runtime.confirm(evidence)
            return consumesEvent
        }
    }
}
