import Foundation

public enum Hangul {
    static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let finals = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    static let mapping: [Character: Character] = Dictionary(uniqueKeysWithValues:
        zip(Array("rRseEfaqQtTdwWczxvgkoiOjpuPhynbml"), Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎㅏㅐㅑㅒㅓㅔㅕㅖㅗㅛㅜㅠㅡㅣ")))
    static let vowelPairs = ["ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ",
                             "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"]
    static let finalPairs = ["ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ",
                             "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ",
                             "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"]

    public static func compose(_ raw: String) -> String {
        var output = ""
        var initial: Character?
        var vowel: Character?
        var final: Character?

        func rendered() -> String {
            guard let initial, let vowel,
                  let l = initials.firstIndex(of: initial),
                  let v = vowels.firstIndex(of: vowel) else {
                return [initial, vowel, final].compactMap { $0 }.map(String.init).joined()
            }
            let t = final.flatMap { finals.firstIndex(of: $0) } ?? 0
            return UnicodeScalar(0xAC00 + (l * 21 + v) * 28 + t).map(String.init) ?? ""
        }
        func flush() {
            output += rendered()
            initial = nil
            vowel = nil
            final = nil
        }
        for key in raw {
            let normalized = mapping[key] != nil ? key : Character(String(key).lowercased())
            guard let jamo = mapping[normalized] else {
                flush()
                output.append(key)
                continue
            }
            if vowels.contains(jamo) {
                if let last = final {
                    if let pair = finalPairs.first(where: { $0.value == String(last) }) {
                        let parts = Array(pair.key)
                        final = parts[0]
                        output += rendered()
                        initial = parts[1]
                    } else {
                        final = nil
                        output += rendered()
                        initial = last
                    }
                    vowel = jamo
                    final = nil
                } else if let current = vowel {
                    if let merged = vowelPairs[String(current) + String(jamo)]?.first {
                        vowel = merged
                    } else {
                        flush()
                        vowel = jamo
                    }
                } else {
                    vowel = jamo
                }
            } else if initial == nil || vowel == nil {
                flush()
                initial = jamo
            } else if let last = final {
                if let merged = finalPairs[String(last) + String(jamo)]?.first {
                    final = merged
                } else {
                    flush()
                    initial = jamo
                }
            } else if finals.contains(jamo) {
                final = jamo
            } else {
                flush()
                initial = jamo
            }
        }
        flush()
        return output
    }

    public static func keys(for text: String) -> String {
        let inverse = Dictionary(uniqueKeysWithValues: mapping.map { ($0.value, String($0.key)) })
        func keys(_ jamo: Character) -> String {
            if let direct = inverse[jamo] { return direct }
            if let pair = (vowelPairs.merging(finalPairs) { first, _ in first })
                .first(where: { $0.value == String(jamo) }) {
                return pair.key.map { inverse[$0] ?? String($0) }.joined()
            }
            return String(jamo)
        }
        return text.map { character in
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
                  (0xAC00...0xD7A3).contains(scalar.value) else { return keys(character) }
            let index = Int(scalar.value) - 0xAC00
            let finalIndex = index % 28
            return keys(initials[index / 588]) + keys(vowels[index / 28 % 21])
                + (finalIndex == 0 ? "" : keys(finals[finalIndex]))
        }.joined()
    }

    static func syllableCount(_ text: String) -> Int {
        text.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count
    }

    static func jamoCount(_ text: String) -> Int {
        text.unicodeScalars.filter { (0x3131...0x3163).contains($0.value) }.count
    }
}
