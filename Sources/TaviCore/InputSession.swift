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
    public var raw: String { engine.raw }
    public var text: String { engine.text }

    public init() {}

    public mutating func setWords(_ words: [LearnedWord]) {
        engine.words = words
    }

    public mutating func handle(_ key: Key) -> Update {
        switch key {
        case .backspace:
            guard !raw.isEmpty else { return .pass }
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
            if raw.count == 64 {
                let original = engine.cancel()
                literalUntilBoundary = true
                return .commit(original + key, consumesEvent: true, evidence: nil)
            }
            engine.append(key)
            return .mark(text)
        }
    }

    /// The user's input-source switch key during a composition toggles the word between
    /// its Korean reading and its literal keys without committing; Space confirms (and
    /// teaches) the choice. It is the only correction key.
    public mutating func toggleLanguage() -> Update {
        guard !raw.isEmpty else { return .pass }
        engine.lock(to: text == Hangul.compose(raw) ? .latin : .korean)
        return .mark(text)
    }

    public mutating func finish(learn: Bool) -> Update {
        literalUntilBoundary = false
        return commit(suffix: "", consumesEvent: false, learn: learn)
    }

    private mutating func commit(suffix: String, consumesEvent: Bool, learn: Bool) -> Update {
        guard !raw.isEmpty else { return .pass }
        let original = raw
        let result = engine.commit(learn: learn)
        let evidence = learn ? result.correction ?? LearningEvidence.typedWord(
            result.text, automaticallyChanged: original != result.text
        ) : nil
        return .commit(result.text + suffix, consumesEvent: consumesEvent, evidence: evidence)
    }
}
