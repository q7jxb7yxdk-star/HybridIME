import Foundation

struct BilingualDictionary: @unchecked Sendable {
    private let lexicon: StaticLexicon

    init(bundle: Bundle = .main) {
        lexicon = StaticLexicon(bundle: bundle)
    }

    init(lexicon: StaticLexicon) {
        self.lexicon = lexicon
    }

    func chineseCandidates(for english: String, limit: Int = 10) -> [String] {
        lexicon.bilingualCandidates(
            direction: .englishToChinese,
            key: english.lowercased(),
            limit: limit
        )
    }

    func englishCandidates(for chinese: String, limit: Int = 10) -> [String] {
        lexicon.bilingualCandidates(
            direction: .chineseToEnglish,
            key: chinese,
            limit: limit
        )
    }

    func longestEnglishMatch(
        forChineseKeys keys: [String],
        limit: Int = 10
    ) -> (key: String, candidates: [String])? {
        lexicon.longestBilingualMatch(
            direction: .chineseToEnglish,
            keys: keys,
            limit: limit
        )
    }
}
