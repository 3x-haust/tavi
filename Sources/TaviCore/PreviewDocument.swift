import Foundation

public enum PreviewDocument {
    public static func convert(_ input: String, words: [LearnedWord] = []) -> String {
        guard input.utf16.count <= 4_096 else { return input }
        var engine = CompositionEngine()
        engine.words = words
        var output = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let punctuation = String(token.reversed().prefix(while: { ".,!?;".contains($0) }).reversed())
            let body = String(token.dropLast(punctuation.count))
            guard body.count <= 64 else {
                output += token
                token = ""
                return
            }
            engine.append(Hangul.keys(for: body))
            let converted = engine.confidence >= 0.96 ? engine.text : body
            _ = engine.commit(learn: false)
            output += converted + punctuation
            token = ""
        }
        for character in input {
            if character.isWhitespace {
                flush()
                output.append(character)
            } else {
                token.append(character)
            }
        }
        flush()
        return output
    }
}
