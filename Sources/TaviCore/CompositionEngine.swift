import Foundation

public enum InputLanguage: String, Codable, Sendable {
    case korean, latin
}

public struct Candidate: Equatable, Sendable {
    public let text: String
    public let reason: String
    public let confidence: Double

    public init(text: String, reason: String, confidence: Double) {
        self.text = text
        self.reason = reason
        self.confidence = confidence
    }
}

public struct Commit: Sendable {
    public let text: String
    public let correction: LearnedWord?
}

public struct CompositionEngine {
    public private(set) var raw = ""
    public private(set) var text = ""
    public private(set) var candidates: [Candidate] = []
    public private(set) var isExplicit = false
    public private(set) var confidence = 0.0
    public private(set) var automaticEligible = false
    public private(set) var isRemembered = false
    public var words: [LearnedWord] = [] {
        didSet {
            guard words != oldValue else { return }
            learnedByKey = [:]
            learnedByFolded = [:]
            for word in words.prefix(2_000) {
                learnedByKey[word.raw] = word
                if !word.raw.contains(where: \.isUppercase),
                   word.text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                    learnedByFolded[word.raw] = word
                }
            }
        }
    }
    public var englishWord: ((String) -> Bool)?
    public var previousToken: String? {
        get { contextToken }
        set { contextToken = newValue.map { String($0.suffix(Self.maximumRawLength)) } }
    }
    private let lexicon = Lexicon()
    private var automaticText = ""
    /// Set by the language key; the rest of the word keeps that language as keys are added.
    private var lockedLanguage: InputLanguage?
    private var contextToken: String?
    private var learnedByKey: [String: LearnedWord] = [:]
    private var learnedByFolded: [String: LearnedWord] = [:]
    private static let maximumRawLength = 64
    private static let automaticThreshold = 0.80
    private static let leaveKoreanThreshold = 0.99

    public init() {}

    public mutating func append(_ key: String) {
        guard raw.count < Self.maximumRawLength else { return }
        raw += key.prefix(Self.maximumRawLength - raw.count)
        refresh()
    }

    public mutating func backspace() {
        guard !raw.isEmpty else { return }
        raw.removeLast()
        refresh()
    }

    public mutating func lock(to language: InputLanguage) {
        guard !raw.isEmpty else { return }
        lockedLanguage = language
        choose(language == .korean ? Hangul.compose(raw) : raw)
    }

    public mutating func sourceChanged(to language: InputLanguage) {
        guard !raw.isEmpty else { return }
        lock(to: language)
        confidence = 1
        automaticEligible = true
    }

    public mutating func choose(_ preferred: String) {
        guard !raw.isEmpty, !preferred.isEmpty else { return }
        text = preferred
        isExplicit = true
        confidence = candidates.first(where: { $0.text == preferred })?.confidence ?? 1
        automaticEligible = true
    }

    public mutating func commit(learn: Bool = true) -> Commit {
        let correction = learn && isExplicit && text != automaticText
            ? LearnedWord(raw: raw, text: text, confirmations: 1) : nil
        let result = Commit(text: text, correction: correction)
        if !text.isEmpty {
            previousToken = text
        }
        clear()
        return result
    }

    public mutating func cancel() -> String {
        let result = raw
        clear()
        return result
    }

    private mutating func refresh() {
        let shownKorean = Self.isPlausibleKorean(text)
        candidates = lexicon.candidates(
            for: raw,
            previousToken: previousToken,
            learnedByKey: learnedByKey,
            learnedByFolded: learnedByFolded,
            check: englishWord
        )
        var chosen = candidates.first
        // Once a word reads as Korean, a weak mid-word preference must not flip it
        // back and forth (안 → 아ss → 안녀); only overwhelming evidence leaves Korean.
        if shownKorean, let best = chosen, !Self.isKoreanOnly(best.text),
           best.confidence < Self.leaveKoreanThreshold,
           let korean = candidates.first(where: { Self.isKoreanOnly($0.text) }),
           Self.isPlausibleKorean(korean.text) {
            chosen = korean
        }
        text = chosen?.text ?? raw
        confidence = chosen?.confidence ?? 0
        automaticEligible = text != raw && confidence >= Self.automaticThreshold
        automaticText = text
        if let lockedLanguage {
            choose(lockedLanguage == .korean ? Hangul.compose(raw) : raw)
            return
        }
        let preference = learnedByKey[raw] ?? learnedByFolded[raw.lowercased()]
        isRemembered = (preference?.confirmations ?? 0) >= LearningStore.threshold && preference?.text == text
        isExplicit = false
    }

    /// Korean whose only stray jamo is a trailing consonant still being typed (안ㄴ, not 채ㅡ).
    private static func isPlausibleKorean(_ text: String) -> Bool {
        guard isKoreanOnly(text) else { return false }
        let stem = text.last.map { Hangul.initials.contains($0) } == true ? String(text.dropLast()) : text
        return !stem.isEmpty && Hangul.jamoCount(stem) == 0
    }

    private static func isKoreanOnly(_ text: String) -> Bool {
        !text.isEmpty && !text.contains { $0.isASCII && $0.isLetter }
            && text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x3163).contains($0.value) }
    }

    private mutating func clear() {
        lockedLanguage = nil
        raw = ""
        text = ""
        automaticText = ""
        candidates = []
        isExplicit = false
        confidence = 0
        automaticEligible = false
        isRemembered = false
    }
}
