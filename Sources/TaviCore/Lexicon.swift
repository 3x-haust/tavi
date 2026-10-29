import Foundation

struct Lexicon {
    private struct Scored {
        let text: String
        let score: Double
        let reason: String
    }

    private static let model = StatisticalModel.shared
    private static let suffixes: Set<String> = [
        "은", "는", "이", "가", "을", "를", "에", "의", "와", "과", "도", "만", "로", "으로",
        "에서", "에게", "한테", "부터", "까지", "처럼", "보다", "하고", "이랑", "랑",
        "라고", "이라고", "라는", "이라는", "이나", "나", "요", "야", "입니다", "를요", "는요",
    ]
    private static let suffixKeys = Set(suffixes.map { Hangul.keys(for: $0) })
    /// Ordinals and units that follow a number in English (4th, 5km, 3px), which stay Latin.
    private static let numberSuffixes: Set<String> = [
        "st", "nd", "rd", "th", "am", "pm", "px", "pt", "em", "ms", "fps", "hz", "khz", "mhz", "ghz",
        "kb", "mb", "gb", "tb", "kbps", "mbps", "gbps", "km", "kg", "cm", "mm", "ml", "hr", "hrs",
        "min", "sec", "fa", "gen", "bit", "bits", "pc", "pcs", "rpm", "dpi", "ppi", "xl", "xs",
    ]

    func candidates(
        for raw: String,
        previousToken: String?,
        learnedByKey: [String: LearnedWord],
        learnedByFolded: [String: LearnedWord],
        check: ((String) -> Bool)?
    ) -> [Candidate] {
        guard !raw.isEmpty else { return [] }
        // A count or date before Korean (3ro → 3개, 10dlf → 10일): the number stays as typed and
        // the letters are read as a word of their own, unless a learned word starts the token
        // (3xhaustsms → 3Xhaust는). A doubtful Korean reading (3xhaust → 3토면ㅅ) leaves it literal.
        if let split = raw.firstIndex(where: { !($0.isASCII && $0.isNumber) }), split != raw.startIndex,
           !raw.indices[split...].contains(where: {
               Self.learned(in: learnedByKey, folded: learnedByFolded, matching: String(raw[...$0])) != nil
           }) {
            let letters = String(raw[split...])
            if letters.count >= 2, letters.allSatisfy({ $0.isASCII && $0.isLetter }),
               !Self.numberSuffixes.contains(letters.lowercased()) {
                let number = String(raw[..<split])
                let reading = candidates(
                    for: letters, previousToken: previousToken,
                    learnedByKey: learnedByKey, learnedByFolded: learnedByFolded, check: check
                )
                if let best = reading.first, !Self.isKoreanText(best.text) || best.confidence >= 0.80 {
                    return reading.map { Candidate(text: number + $0.text, reason: $0.reason, confidence: $0.confidence) }
                }
            }
        }
        let hangul = Hangul.compose(raw)
        var scored: [Scored] = []
        func add(_ text: String, _ score: Double, _ reason: String) {
            guard !text.isEmpty, score.isFinite else { return }
            scored.append(Scored(text: text, score: score, reason: reason))
        }

        let english = Self.model.englishEvidence(raw, externalCheck: check)
        let wholeKoreanWord = Hangul.jamoCount(hangul) == 0 && Self.model.isKnownKorean(hangul)
        var englishScore = english.score
        var koreanScore = Self.model.koreanScore(hangul)
        let koreanShift = raw.contains(where: \.isLowercase)
            && raw.first(where: \.isUppercase).map { "QWERTOP".contains($0) } == true
            && raw.allSatisfy { $0.isASCII && $0.isLetter }
            && Hangul.jamoCount(hangul) == 0
        if Self.isStructuredLatin(raw), !koreanShift {
            englishScore = max(englishScore, 14)
        } else if Self.isAcronym(raw) {
            englishScore = max(englishScore, 10)
        }
        if let previousToken {
            if Self.isKoreanText(previousToken) {
                koreanScore += 0.45
            } else if Self.isLatinText(previousToken) {
                englishScore += 0.35
            }
        }
        add(raw, englishScore, "Latin")
        if hangul != raw {
            add(hangul, koreanScore, "한국어")
        }

        if let word = Self.learned(in: learnedByKey, folded: learnedByFolded, matching: raw),
           word.confirmations >= LearningStore.threshold {
            // More confirmations rank higher, so a long-used spelling beats newer learned splits.
            add(word.text, 40 + min(log2(Double(word.confirmations)), 8), "내 단어")
        }

        // Real mixed tokens leave stray jamo when read whole (APIfmf → 몌ㅑ를). When
        // lowercase keys form only complete, plausible syllables (ahdmf → 모을,
        // gksdud → 한영), a short English fragment is likely coincidence, so the
        // split ranks below the whole Korean reading and stays reachable through correction.
        // A single trailing consonant is the next syllable being typed (dkss → 안ㄴ),
        // not evidence against Korean, so it must not let a fragment (아ss) win mid-word.
        let pending = hangul.last.map { Hangul.initials.contains($0) } == true && hangul.count > 1
        let stem = pending ? String(hangul.dropLast()) : hangul
        // Shift on Q/W/E/R/T/O/P types a doubled consonant or vowel (ehoTsk → 됐나), not a capital.
        let koreanShifted = raw.contains(where: \.isUppercase) && raw.allSatisfy { !$0.isUppercase || "QWERTOP".contains($0) }
        let completeKorean = Hangul.jamoCount(stem) == 0 && (koreanShifted || !raw.contains(where: \.isUppercase))
        let stemScore = pending ? Self.model.koreanScore(stem) : koreanScore
        let knownWholeKorean = Self.model.isKnownKorean(stem)
        // A Latin tail after Korean is the rarer order (particles follow English, not precede it), and the
        // English word lists hold Korean typed in the wrong mode (si = 냐, rjtl = 거시), so when the whole
        // reading is clean Korean (anjsi → 뭐냐, not 뭐si) the Korean wins unless the tail was learned.
        // A Korean word straight after English is rarer still: when the keys already read as clean Korean,
        // the English head is a coincidence too (gotejsl → 햇더니, not got더니). So is a guessed name before
        // a particle whose keys read better as Korean (skawkcjfja → 남자처럼, not skawk처럼; turksdl → turks이).
        func addSplit(_ text: String, _ score: Double, _ reason: String, latin: String, learned: Bool, koreanFirst: Bool = false, weakHead: Bool = false) {
            let coincidental = completeKorean && !learned
                && (koreanFirst || weakHead || knownWholeKorean || koreanShifted || (stemScore >= 5 && latin.count <= 3))
            add(text, coincidental ? min(score, koreanScore - 1) : score, reason)
        }

        let keys = Array(raw.utf8)
        if keys.count >= 3, english.tier == .unknown, keys.allSatisfy({ $0 < 128 }) {
            for split in 2..<keys.count {
                let head = String(decoding: keys[..<split], as: UTF8.self)
                let tail = String(decoding: keys[split...], as: UTF8.self)
                let preference = Self.learned(in: learnedByKey, folded: learnedByFolded, matching: head)
                let learnedHead = preference.flatMap { $0.confirmations >= LearningStore.threshold ? $0 : nil }
                let allowsSplit = !wholeKoreanWord || learnedHead != nil
                    || raw.first(where: \.isUppercase).map { !"QWERTOP".contains($0) } == true
                let trustedHead = Self.model.isEnglishWord(head)
                    || Self.isAcronym(head) || learnedHead != nil || check?(head) == true
                let headEnglishScore = Self.model.englishEvidence(head).score
                let plausibleNewName = !trustedHead
                    && Self.suffixKeys.contains(tail) && head.count >= 3
                    && !Self.model.isKnownKorean(hangul)
                    && headEnglishScore >= 2.8
                let englishHead = trustedHead || plausibleNewName
                if englishHead, allowsSplit {
                    let tailHangul = Hangul.compose(tail)
                    let spelling = learnedHead?.text ?? head
                    if Self.suffixes.contains(tailHangul) {
                        addSplit(spelling + tailHangul, (learnedHead == nil ? 12.5 : 30) + min(Double(head.count), 8) / 10,
                                 "Latin + 조사", latin: head, learned: learnedHead != nil,
                                 weakHead: !trustedHead && Self.model.koreanScore(Hangul.compose(head)) > headEnglishScore + 0.5)
                        break
                    }
                    if Hangul.syllableCount(tailHangul) >= 2,
                       Self.model.isKnownKorean(tailHangul) || Self.model.koreanScore(tailHangul) >= 4.7 {
                        addSplit(spelling + tailHangul, 11.8 + min(Double(head.count), 8) / 10,
                                 "Latin + 한국어", latin: head, learned: learnedHead != nil, weakHead: true)
                    }
                }

                let tailEntry = learnedByKey[tail] ?? learnedByFolded[tail.lowercased()]
                let rememberedLatinTail = (tailEntry?.confirmations ?? 0) >= LearningStore.threshold
                    && tailEntry.map { Self.isASCIIWord($0.text) } == true
                if tail.count >= 2, !wholeKoreanWord || rememberedLatinTail,
                   Self.model.isEnglishWord(tail)
                    || check?(tail) == true || rememberedLatinTail {
                    let headHangul = Hangul.compose(head)
                    if Hangul.syllableCount(headHangul) >= 1, Self.model.isKnownKorean(headHangul) {
                        let preferredTail = rememberedLatinTail
                            ? Self.learned(in: learnedByKey, folded: learnedByFolded, matching: tail)?.text ?? tail : tail
                        addSplit(headHangul + preferredTail, rememberedLatinTail ? 30 : 10.5,
                                 "한국어 + Latin", latin: tail, learned: rememberedLatinTail, koreanFirst: true)
                    }
                }
            }
        }

        var best: [String: Scored] = [:]
        for item in scored where item.score > (best[item.text]?.score ?? -.infinity) {
            best[item.text] = item
        }
        let ordered = best.values.sorted {
            $0.score == $1.score ? $0.text < $1.text : $0.score > $1.score
        }
        guard let maximum = ordered.first?.score else { return [] }
        let weights = ordered.map { exp(min(0, $0.score - maximum)) }
        let total = weights.reduce(0, +)
        return zip(ordered, weights).map { item, weight in
            Candidate(text: item.text, reason: item.reason, confidence: total > 0 ? weight / total : 0)
        }
    }

    private static func learned(
        in index: [String: LearnedWord], folded: [String: LearnedWord], matching raw: String
    ) -> LearnedWord? {
        if let exact = index[raw] { return exact }
        guard let word = folded[raw.lowercased()],
              isASCIIWord(word.raw), isASCIIWord(raw), isASCIIWord(word.text) else { return nil }
        if raw.contains(where: \.isUppercase),
           raw.caseInsensitiveCompare(word.text) == .orderedSame, raw != word.text { return nil }
        return word
    }

    private static func isASCIIWord(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func isAcronym(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy { $0.isASCII && $0.isUppercase }
    }

    private static func isStructuredLatin(_ text: String) -> Bool {
        guard text.unicodeScalars.allSatisfy({ $0.isASCII }) else { return false }
        if text.contains("://") || text.hasPrefix("www.") || text.contains("@")
            || text.contains("/") || text.contains("\\") || text.contains("_")
            || text.contains("`") || text.contains(".") || text.contains(":")
        {
            return true
        }
        if text.contains(where: \.isNumber) { return true }
        var sawLowercase = false
        for character in text {
            if character.isLowercase {
                sawLowercase = true
            } else if sawLowercase, character.isUppercase {
                return true
            }
        }
        return false
    }

    private static func isKoreanText(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    private static func isLatinText(_ text: String) -> Bool {
        text.contains { $0.isASCII && $0.isLetter } && !isKoreanText(text)
    }
}
