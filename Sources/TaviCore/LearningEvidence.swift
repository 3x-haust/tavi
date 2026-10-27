import Foundation

public enum LearningEvidence {
    public static func typedWord(_ text: String, automaticallyChanged: Bool) -> LearnedWord? {
        guard !automaticallyChanged, (3...64).contains(text.count),
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              text.filter(\.isLetter).count >= 2 else { return nil }
        let mixedCase = text.dropFirst().contains(where: \.isUppercase) && text.contains(where: \.isLowercase)
        guard mixedCase || text.contains(where: \.isNumber) || !StatisticalModel.shared.isKnownEnglish(text)
        else { return nil }
        return LearnedWord(raw: text.lowercased(), text: text, confirmations: 1)
    }
}
