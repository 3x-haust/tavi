# Implementation contract

`TaviCore` is Foundation-only, with no network and no UI dependencies.

```swift
public struct Candidate: Equatable, Sendable {
    public let text: String
    public let reason: String
    public let confidence: Double
}
public struct LearnedWord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { raw }
    public let raw: String
    public var text: String
    public var confirmations: Int
}
public struct CompositionEngine {
    public init()
    public private(set) var raw: String
    public private(set) var text: String
    public private(set) var candidates: [Candidate]
    public private(set) var isExplicit: Bool
    public var words: [LearnedWord]
    public var englishWord: ((String) -> Bool)?
    public mutating func append(_ key: String)
    public mutating func backspace()
    public mutating func correct()
    public mutating func sourceChanged(to language: InputLanguage)
    public mutating func choose(_ text: String)
    public mutating func commit(learn: Bool = true) -> Commit
    public mutating func cancel() -> String // raw keys, then clears composition
}
public struct Commit {
    public let text: String
    public let correction: LearnedWord? // explicit, changed choice only
}
public final class LearningStore {
    public init(url: URL? = nil) throws
    public private(set) var words: [LearnedWord]
    public func reload() throws
    public func confirm(_ word: LearnedWord) throws
    public func set(raw: String, text: String) throws
    public func remove(raw: String) throws
}
public enum Hangul {
    public static func compose(_ raw: String) -> String
    public static func keys(for text: String) -> String
}
```

The app owns one store on its main thread. Store methods throw, use atomic
writes, refresh before mutations and preserve exact casing. The default URL
is Application Support/Tavi/words.json. UI must surface persistence errors,
not silently pretend a correction was saved. No raw session logging.

Automatic preference needs 3 confirmations; manually adding a spelling makes
it immediately preferred. Repeated key presses before a single commit count
as ONE example, not several. Cancelling/focus loss/shortcuts do not train.
Explicit choice stays locked until edit or commit.

The classifier uses precomputed compact character/syllable statistics
and corpus-derived lookup tables. Do not load NSSpellChecker or train a model
on the user's typing path. No network, whole-corpus loading or per-key lexicon
construction is allowed. See DESIGN.md for measurable release targets.

The host is a native InputMethodKit input method. `InputSession` maps typed
keys, correction, deletion and boundaries into pass-through, marked-text,
or commit effects. A controller applies those effects to its own IMK client.
Only confirmed boundaries can produce learning evidence. No accessibility
replacement, synthetic-backspace or clipboard path remains.
See [HOST.md](HOST.md) for lifecycle and terminal Enter semantics.
