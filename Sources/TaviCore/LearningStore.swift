import Foundation

public struct LearnedWord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { raw }
    public let raw: String
    public var text: String
    public var confirmations: Int

    public init(raw: String, text: String, confirmations: Int) {
        self.raw = raw
        self.text = text
        self.confirmations = confirmations
    }
}

public final class LearningStore {
    public enum Failure: Error, LocalizedError {
        case invalidEntry
        case full

        public var errorDescription: String? {
            switch self {
            case .invalidEntry: return "단어는 공백 없이 64자 이내로 입력해 주세요."
            case .full: return "개인 사전이 2,000개에 도달했어요. 사용하지 않는 단어를 지워 주세요."
            }
        }
    }

    public let url: URL
    public private(set) var words: [LearnedWord] = []
    public static let limit = 2_000
    /// Three confirmations make a spelling the default; further ones keep counting
    /// so a long-used spelling outranks newer learned rules and survives a stray choice.
    public static let threshold = 3
    public static let maximumConfirmations = 999

    public init(url: URL? = nil) throws {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tavi/words.json")
        try reload()
    }

    public func reload() throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            words = []
            return
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([LearnedWord].self, from: data)
        guard decoded.count <= Self.limit, Set(decoded.map(\.raw)).count == decoded.count,
              decoded.allSatisfy({ Self.valid(raw: $0.raw, text: $0.text) && (1...Self.maximumConfirmations).contains($0.confirmations) })
        else { throw Failure.invalidEntry }
        words = decoded
    }

    public func confirm(_ word: LearnedWord) throws {
        guard Self.valid(raw: word.raw, text: word.text) else { throw Failure.invalidEntry }
        try reload()
        var updated = words
        if let index = updated.firstIndex(where: { $0.raw == word.raw }) {
            let previous = updated[index]
            if previous.text == word.text {
                updated[index].confirmations = min(Self.maximumConfirmations, previous.confirmations + 1)
            } else if previous.confirmations / 2 >= Self.threshold {
                // A contrary choice halves an established spelling instead of erasing it.
                updated[index].confirmations = previous.confirmations / 2
            } else {
                updated[index] = LearnedWord(raw: word.raw, text: word.text, confirmations: 1)
            }
        } else {
            guard updated.count < Self.limit else { throw Failure.full }
            updated.append(LearnedWord(raw: word.raw, text: word.text, confirmations: 1))
        }
        try save(updated)
    }

    public func set(raw: String, text: String) throws {
        guard Self.valid(raw: raw, text: text) else { throw Failure.invalidEntry }
        try reload()
        var updated = words.filter { $0.raw != raw }
        guard updated.count < Self.limit else { throw Failure.full }
        updated.append(LearnedWord(raw: raw, text: text, confirmations: Self.threshold))
        try save(updated)
    }

    public func remove(raw: String) throws {
        try remove(rawKeys: [raw])
    }

    public func remove(rawKeys: Set<String>) throws {
        try reload()
        try save(words.filter { !rawKeys.contains($0.raw) })
    }

    private func save(_ updated: [LearnedWord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(updated)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        words = updated
    }

    private static func valid(raw: String, text: String) -> Bool {
        !raw.isEmpty && !text.isEmpty && raw.count <= 64 && text.count <= 64
            && raw.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
            && !text.contains(where: { $0.isWhitespace || $0.isNewline })
            && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
