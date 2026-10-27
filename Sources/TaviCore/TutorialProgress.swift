public struct TutorialProgress {
    public enum Step: Int, Equatable {
        case typing, correction, learning, finished
    }

    public private(set) var step: Step
    public private(set) var canAdvance = false
    public private(set) var learnedText: String?
    public private(set) var confirmations = 0

    public init(completed: Bool = false) {
        step = completed ? .finished : .typing
    }

    public mutating func composed(raw: String, text: String) {
        if step == .typing, raw == "APIfmf", text == "API를" { canAdvance = true }
    }

    public mutating func corrected(raw: String, before: String, after: String) {
        guard step == .correction, raw == "to", before != after,
              Set([before, after]) == Set(["to", "새"]) else { return }
        canAdvance = true
    }

    public mutating func learned(_ word: LearnedWord) {
        guard step == .learning else { return }
        learnedText = word.text
        confirmations = word.confirmations
        canAdvance = confirmations >= 3
    }

    public mutating func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
        canAdvance = false
    }

    public mutating func skip() { step = .finished; canAdvance = false }
    public mutating func restart() { self = TutorialProgress() }
}
