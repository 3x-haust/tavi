import Foundation

public struct TokenSnapshot: Equatable {
    public let context: String
    public let origin: Int
    public let caret: Int
    public let documentLength: Int
    public let markedLength: Int?

    public init(context: String, origin: Int, caret: Int, documentLength: Int, markedLength: Int?) {
        self.context = context
        self.origin = origin
        self.caret = caret
        self.documentLength = documentLength
        self.markedLength = markedLength
    }

    public struct Token: Equatable {
        public let text: String
        public let range: NSRange
        public let boundary: String
    }

    public func token(allowBoundary: Bool) -> Token? {
        guard markedLength == 0, caret >= origin, caret <= documentLength else { return nil }
        let content = context as NSString
        let localCaret = caret - origin
        guard localCaret <= content.length else { return nil }
        let prefix = content.substring(to: localCaret)
        let boundary = allowBoundary ? String(prefix.reversed().prefix(while: {
            $0.isWhitespace || ".,!?;".contains($0)
        }).reversed()) : ""
        let remaining = String(prefix.dropLast(boundary.count))
        let token = String(remaining.reversed().prefix(while: { !$0.isWhitespace }).reversed())
        guard !token.isEmpty, token.count <= 64,
              token.unicodeScalars.allSatisfy({
                  (65...90).contains($0.value) || (97...122).contains($0.value)
                      || (48...57).contains($0.value) || (0xAC00...0xD7A3).contains($0.value)
                      || (0x3131...0x3163).contains($0.value)
              }) else { return nil }
        let start = caret - (boundary as NSString).length - (token as NSString).length
        guard start > origin || origin == 0 else { return nil }
        return Token(text: token, range: NSRange(location: start, length: (token as NSString).length), boundary: boundary)
    }
}
