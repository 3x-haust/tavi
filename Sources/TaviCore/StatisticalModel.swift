import Foundation

struct StatisticalModel: Sendable {
    enum EnglishTier: Int, Sendable {
        case unknown
        case known
        case common
    }

    struct EnglishEvidence: Sendable {
        let score: Double
        let tier: EnglishTier
    }

    static let shared = StatisticalModel()
    static var bundledByteCount: Int {
        guard let url = Bundle.module.url(forResource: "model-v2", withExtension: "dat.base64"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return 0 }
        return size.intValue
    }

    private static let symbolCount = 27
    private static let trigramCount = symbolCount * symbolCount * symbolCount
    private static let hangulSyllableCount = 11_172
    private static let smoothing = 0.25

    private let trigrams: [UInt16]
    private let contexts: [UInt32]
    private let syllables: [UInt16]
    private let syllableTotal: Double
    private let commonEnglish: BloomFilter
    private let knownEnglish: BloomFilter
    private let knownKorean: BloomFilter

    private init() {
        guard let url = Bundle.module.url(forResource: "model-v2", withExtension: "dat.base64"),
              let encoded = try? String(contentsOf: url, encoding: .utf8),
              let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              let decoded = Self.decode(data)
        else {
            trigrams = [UInt16](repeating: 0, count: Self.trigramCount)
            contexts = [UInt32](repeating: 0, count: Self.symbolCount * Self.symbolCount)
            syllables = [UInt16](repeating: 0, count: Self.hangulSyllableCount)
            syllableTotal = 0
            commonEnglish = BloomFilter()
            knownEnglish = BloomFilter()
            knownKorean = BloomFilter()
            return
        }
        trigrams = decoded.trigrams
        syllables = decoded.syllables
        commonEnglish = decoded.commonEnglish
        knownEnglish = decoded.knownEnglish
        knownKorean = decoded.knownKorean
        syllableTotal = Double(syllables.reduce(0) { $0 + UInt64($1) })

        var totals = [UInt32](repeating: 0, count: Self.symbolCount * Self.symbolCount)
        for a in 0..<Self.symbolCount {
            for b in 0..<Self.symbolCount {
                let context = a * Self.symbolCount + b
                let start = context * Self.symbolCount
                totals[context] = trigrams[start..<(start + Self.symbolCount)]
                    .reduce(0) { $0 + UInt32($1) }
            }
        }
        contexts = totals
    }

    func englishEvidence(_ token: String, externalCheck: ((String) -> Bool)? = nil) -> EnglishEvidence {
        guard let normalized = Self.normalizedASCII(token) else {
            return EnglishEvidence(score: -.infinity, tier: .unknown)
        }

        let tier: EnglishTier
        if commonEnglish.contains(normalized) {
            tier = .common
        } else if knownEnglish.contains(normalized) || (normalized.count >= 2 && externalCheck?(token) == true) {
            tier = .known
        } else {
            tier = .unknown
        }

        let probability = averageEnglishLogProbability(normalized)
        let statistical = 7.0 + probability * 1.15
        switch tier {
        case .common:
            return EnglishEvidence(score: max(8.2, statistical), tier: tier)
        case .known:
            return EnglishEvidence(score: max(6.8, statistical), tier: tier)
        case .unknown:
            return EnglishEvidence(score: statistical, tier: tier)
        }
    }

    func koreanScore(_ text: String) -> Double {
        guard !text.isEmpty else { return -.infinity }
        var total = 0.0
        var units = 0
        var syllableUnits = 0
        let denominator = syllableTotal + Self.smoothing * Double(Self.hangulSyllableCount)

        for scalar in text.unicodeScalars {
            if (0xAC00...0xD7A3).contains(scalar.value) {
                let count = Double(syllables[Int(scalar.value - 0xAC00)])
                total += log((count + Self.smoothing) / denominator)
                units += 1
                syllableUnits += 1
            } else if (0x3131...0x3163).contains(scalar.value) {
                total -= 11.5
                units += 1
            }
        }
        guard units > 0 else { return -.infinity }
        var score = 11.2 + total / Double(units)
        if syllableUnits > 0, syllableUnits == units, knownKorean.contains(text) {
            score = max(score, 8.0)
        }
        if syllableUnits == 0 {
            let chat = text.count >= 2 && text.allSatisfy { "ㅋㅎㅠㅜㄷㅇㄱㅅㅂㄴ".contains($0) }
            score = chat ? 7.0 : score
        }
        return score
    }

    func isKnownEnglish(_ token: String) -> Bool {
        guard let normalized = Self.normalizedASCII(token) else { return false }
        return knownEnglish.contains(normalized)
    }

    func isCommonEnglish(_ token: String) -> Bool {
        guard let normalized = Self.normalizedASCII(token) else { return false }
        return commonEnglish.contains(normalized)
    }

    func isEnglishWord(_ token: String) -> Bool {
        guard let normalized = Self.normalizedASCII(token) else { return false }
        return commonEnglish.contains(normalized) || knownEnglish.contains(normalized)
    }

    private static func normalizedASCII(_ token: String) -> String? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(64, token.utf8.count))
        for byte in token.utf8 {
            if byte == 39 { continue }
            let lower = (65...90).contains(byte) ? byte + 32 : byte
            guard (97...122).contains(lower), bytes.count < 64 else { return nil }
            bytes.append(lower)
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    func isKnownKorean(_ text: String) -> Bool {
        knownKorean.contains(text)
    }

    private func averageEnglishLogProbability(_ word: String) -> Double {
        var codes = [0, 0]
        codes.reserveCapacity(word.count + 3)
        for scalar in word.unicodeScalars {
            codes.append(Int(scalar.value) - 96)
        }
        codes.append(0)

        var total = 0.0
        for index in 2..<codes.count {
            let context = codes[index - 2] * Self.symbolCount + codes[index - 1]
            let count = Double(trigrams[context * Self.symbolCount + codes[index]])
            let contextCount = Double(contexts[context])
            total += log(
                (count + Self.smoothing)
                    / (contextCount + Self.smoothing * Double(Self.symbolCount))
            )
        }
        return total / Double(codes.count - 2)
    }

    private struct Decoded {
        let trigrams: [UInt16]
        let syllables: [UInt16]
        let commonEnglish: BloomFilter
        let knownEnglish: BloomFilter
        let knownKorean: BloomFilter
    }

    private static func decode(_ data: Data) -> Decoded? {
        var reader = BinaryReader(data: data)
        guard reader.bytes(count: 4) == Data("TVM2".utf8),
              let trigramItems = reader.uint32(), trigramItems == trigramCount,
              let trigrams = reader.uint16Array(count: trigramItems),
              let syllableItems = reader.uint32(), syllableItems == hangulSyllableCount,
              let syllables = reader.uint16Array(count: syllableItems),
              let commonEnglish = reader.bloomFilter(),
              let knownEnglish = reader.bloomFilter(),
              let knownKorean = reader.bloomFilter(),
              reader.isAtEnd
        else { return nil }
        return Decoded(
            trigrams: trigrams,
            syllables: syllables,
            commonEnglish: commonEnglish,
            knownEnglish: knownEnglish,
            knownKorean: knownKorean
        )
    }
}

private struct BloomFilter: Sendable {
    private let bits: Data
    private let bitCount: UInt32

    init(bits: Data = Data(), bitCount: UInt32 = 0) {
        self.bits = bits
        self.bitCount = bitCount
    }

    func contains(_ value: String) -> Bool {
        guard bitCount > 0 else { return false }
        let bytes = value.utf8
        let first = Self.fnv1a(bytes, seed: 2_166_136_261)
        let step = Self.fnv1a(bytes, seed: 16_777_619) | 1
        for round in UInt32(0)..<4 {
            let position = (first &+ round &* step) % bitCount
            let byte = bits[Int(position >> 3)]
            if byte & (1 << UInt8(position & 7)) == 0 { return false }
        }
        return true
    }

    private static func fnv1a(_ bytes: String.UTF8View, seed: UInt32) -> UInt32 {
        bytes.reduce(seed) { ($0 ^ UInt32($1)) &* 16_777_619 }
    }
}

private struct BinaryReader {
    let data: Data
    var index = 0

    var isAtEnd: Bool { index == data.count }

    mutating func bytes(count: Int) -> Data? {
        guard count >= 0, index + count <= data.count else { return nil }
        defer { index += count }
        return Data(data[index..<(index + count)])
    }

    mutating func uint16() -> UInt16? {
        guard let bytes = bytes(count: 2) else { return nil }
        return UInt16(bytes[bytes.startIndex]) | UInt16(bytes[bytes.startIndex + 1]) << 8
    }

    mutating func uint32() -> Int? {
        guard let bytes = bytes(count: 4) else { return nil }
        return Int(bytes[bytes.startIndex])
            | Int(bytes[bytes.startIndex + 1]) << 8
            | Int(bytes[bytes.startIndex + 2]) << 16
            | Int(bytes[bytes.startIndex + 3]) << 24
    }

    mutating func uint16Array(count: Int) -> [UInt16]? {
        guard count >= 0, index + count * 2 <= data.count else { return nil }
        let start = index
        index += count * 2
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            (0..<count).map { item in
                let offset = start + item * 2
                return UInt16(buffer[offset]) | UInt16(buffer[offset + 1]) << 8
            }
        }
    }

    mutating func bloomFilter() -> BloomFilter? {
        guard let bitCount = uint32(), bitCount > 0, bitCount.isMultiple(of: 8),
              let bytes = bytes(count: bitCount / 8)
        else { return nil }
        return BloomFilter(bits: bytes, bitCount: UInt32(bitCount))
    }
}
