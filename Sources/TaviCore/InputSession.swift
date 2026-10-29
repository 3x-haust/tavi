import Foundation

public struct InputSession {
    public enum Key {
        case text(String), backspace, escape, space, enter, passThrough
    }

    public enum Update: Equatable {
        case pass
        case mark(String)
        case commit(String, consumesEvent: Bool, evidence: LearnedWord?)
    }

    private var engine = CompositionEngine()
    private var literalUntilBoundary = false
    /// Digits that start a word go straight into the document, as with the system's Korean
    /// input: a page that formats a field as it is typed (010-1234-5678) would otherwise
    /// rewrite marked text and double it. They still lead the word, so 3ro reads as 3개.
    private var typedAhead = 0
    public var raw: String { engine.raw }
    /// The marked part of the word: the reading without the digits already typed.
    public var text: String {
        let typed = raw.prefix(typedAhead)
        return engine.text.hasPrefix(typed)
            ? String(engine.text.dropFirst(typedAhead)) : String(raw.dropFirst(typedAhead))
    }
    /// The keys behind `text`.
    public var markedRaw: String { String(raw.dropFirst(typedAhead)) }
    public var isComposing: Bool { raw.count > typedAhead }
    /// Set by the language key while nothing is composed; the next word is typed in it.
    public private(set) var nextLanguage: InputLanguage?

    public init() {}

    public mutating func setWords(_ words: [LearnedWord]) {
        engine.words = words
    }

    public mutating func handle(_ key: Key) -> Update {
        switch key {
        case .backspace:
            guard !raw.isEmpty else { return .pass }
            guard isComposing else {
                // The digit is already in the document, where the host deletes it.
                engine.backspace()
                typedAhead -= 1
                return .pass
            }
            engine.backspace()
            return .mark(text)
        case .space:
            literalUntilBoundary = false
            return commit(suffix: " ", consumesEvent: true, learn: true)
        case .enter:
            literalUntilBoundary = false
            return commit(suffix: "", consumesEvent: false, learn: true)
        case .escape, .passThrough:
            return finish(learn: false)
        case .text(let key):
            guard !literalUntilBoundary else { return .pass }
            guard key.count == 1,
                  key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                if ":/@\\_`.".contains(key), !key.isEmpty, text.allSatisfy(\.isASCII) {
                    if !raw.isEmpty { engine.choose(raw) }
                    literalUntilBoundary = true
                    return commit(suffix: key, consumesEvent: true, learn: false)
                }
                return commit(suffix: key, consumesEvent: true, learn: true)
            }
            if !isComposing, key.allSatisfy(\.isNumber) {
                if raw.count == 64 {
                    _ = engine.cancel()
                    typedAhead = 0
                }
                engine.append(key)
                typedAhead += 1
                if let language = nextLanguage {
                    engine.lock(to: language)
                    nextLanguage = nil
                }
                return .commit(key, consumesEvent: true, evidence: nil)
            }
            if raw.count == 64 {
                let original = markedRaw
                _ = engine.cancel()
                typedAhead = 0
                literalUntilBoundary = true
                return .commit(original + key, consumesEvent: true, evidence: nil)
            }
            engine.append(key)
            if let language = nextLanguage {
                engine.lock(to: language)
                nextLanguage = nil
            }
            return .mark(text)
        }
    }

    /// The language key with nothing composed, as an ordinary input method user presses it
    /// before a word: the next word is typed in the other language from the last one
    /// (`fallback` before any word). Pressing it again returns to automatic input.
    public mutating func toggleNextLanguage(fallback: InputLanguage) {
        guard raw.isEmpty else { return }
        if nextLanguage != nil {
            nextLanguage = nil
            return
        }
        nextLanguage = engine.previousToken.map {
            $0.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } ? .latin : .korean
        } ?? fallback
    }

    /// The user's input-source switch key during a composition toggles the word between
    /// its Korean reading and its literal keys without committing; Space confirms (and
    /// teaches) the choice. It is the only correction key.
    public mutating func toggleLanguage() -> Update {
        guard isComposing else { return .pass }
        engine.lock(to: engine.text == Hangul.compose(raw) ? .latin : .korean)
        return .mark(text)
    }

    public mutating func finish(learn: Bool) -> Update {
        literalUntilBoundary = false
        return commit(suffix: "", consumesEvent: false, learn: learn)
    }

    private mutating func commit(suffix: String, consumesEvent: Bool, learn: Bool) -> Update {
        guard !raw.isEmpty else { return .pass }
        let original = raw
        let shown = text
        let composing = isComposing
        let result = engine.commit(learn: learn)
        typedAhead = 0
        // Digits alone are already typed; there is nothing to insert or learn.
        guard composing || !suffix.isEmpty else { return .pass }
        let evidence = learn && composing ? result.correction ?? LearningEvidence.typedWord(
            result.text, automaticallyChanged: original != result.text
        ) : nil
        return .commit(shown + suffix, consumesEvent: consumesEvent, evidence: evidence)
    }
}
