import Foundation

final class AssociationDictionary: @unchecked Sendable {
    enum Language: String {
        case chinese
        case english
    }

    struct Suggestion {
        let text: String
        let key: String
        let language: Language
        let isMostRecentSelection: Bool
    }

    private typealias WeightedCandidate = StaticLexicon.WeightedCandidate

    private let lexicon: StaticLexicon
    private let learningStore: UserLearningStore

    init(bundle: Bundle = .main) {
        lexicon = StaticLexicon(bundle: bundle)
        learningStore = .shared
    }

    init(
        lexicon: StaticLexicon,
        learningStore: UserLearningStore = .shared
    ) {
        self.lexicon = lexicon
        self.learningStore = learningStore
    }

    func suggestions(
        for context: String,
        language: Language,
        limit: Int = 10
    ) -> [Suggestion] {
        guard limit > 0 else { return [] }

        let staticLookup: (key: String, candidates: [WeightedCandidate])?
        switch language {
        case .chinese:
            staticLookup = longestChineseMatch(for: context)
        case .english:
            let key = context.lowercased()
                .split(whereSeparator: \.isWhitespace)
                .last
                .map(String.init) ?? ""
            let candidates = lexicon.associationCandidates(
                language: .english,
                key: key
            )
            staticLookup = candidates.isEmpty ? nil : (key, candidates)
        }
        let learnedLookup = language == .chinese
            ? longestLearnedChineseMatch(for: context)
            : nil
        guard let lookup = preferredLookup(
            staticLookup: staticLookup,
            learnedLookup: learnedLookup
        ) else {
            return []
        }

        let mostRecentCandidate = mostRecentSelection(
            language: language,
            key: lookup.key
        )
        var candidates = lookup.candidates
        if language == .chinese {
            let learned = learnedCandidates(for: lookup.key)
            let existing = Set(candidates.map(\.text))
            candidates.append(
                contentsOf: learned
                    .filter { !existing.contains($0) }
                    .map { WeightedCandidate(text: $0, weight: 0) }
            )
        }
        return candidates
            .sorted {
                let leftIsMostRecent = $0.text == mostRecentCandidate
                let rightIsMostRecent = $1.text == mostRecentCandidate
                if leftIsMostRecent != rightIsMostRecent {
                    return leftIsMostRecent
                }
                let left = learnedCount(
                    language: language,
                    key: lookup.key,
                    candidate: $0.text
                )
                let right = learnedCount(
                    language: language,
                    key: lookup.key,
                    candidate: $1.text
                )
                if left != right {
                    return left > right
                }
                if $0.weight != $1.weight {
                    return $0.weight > $1.weight
                }
                return $0.text < $1.text
            }
            .prefix(limit)
            .map {
                Suggestion(
                    text: $0.text,
                    key: lookup.key,
                    language: language,
                    isMostRecentSelection: $0.text == mostRecentCandidate
                )
            }
    }

    func recordSelection(_ suggestion: Suggestion) {
        learningStore.recordAssociationSelection(
            language: suggestion.language.rawValue,
            key: suggestion.key,
            candidate: suggestion.text,
            incrementingCount: true
        )

        if suggestion.language == .chinese,
           let lastCharacter = suggestion.key.last
        {
            learningStore.recordAssociationSelection(
                language: Language.chinese.rawValue,
                key: String(lastCharacter),
                candidate: suggestion.text,
                incrementingCount: false
            )
        }
    }

    func recordChineseSequence(context: String, continuation: String) {
        guard !context.isEmpty, continuation.count == 1 else { return }
        learningStore.recordLearnedChinese(
            context: context,
            candidate: continuation
        )
        learningStore.recordAssociationSelection(
            language: Language.chinese.rawValue,
            key: context,
            candidate: continuation,
            incrementingCount: false
        )
    }

    private func longestChineseMatch(
        for context: String
    ) -> (key: String, candidates: [WeightedCandidate])? {
        let characters = Array(context.suffix(7))
        let keys = stride(
            from: characters.count,
            through: 1,
            by: -1
        ).map { length in
            String(characters.suffix(length))
        }
        return lexicon.longestAssociationMatch(
            language: .chinese,
            keys: keys
        )
    }

    private func longestLearnedChineseMatch(
        for context: String
    ) -> (key: String, candidates: [WeightedCandidate])? {
        let characters = Array(context.suffix(8))
        for length in stride(from: characters.count, through: 1, by: -1) {
            let key = String(characters.suffix(length))
            let candidates = learnedCandidates(for: key)
            if !candidates.isEmpty {
                return (
                    key,
                    candidates.map { WeightedCandidate(text: $0, weight: 0) }
                )
            }
        }
        return nil
    }

    private func preferredLookup(
        staticLookup: (key: String, candidates: [WeightedCandidate])?,
        learnedLookup: (key: String, candidates: [WeightedCandidate])?
    ) -> (key: String, candidates: [WeightedCandidate])? {
        switch (staticLookup, learnedLookup) {
        case (nil, nil): nil
        case (let lookup?, nil), (nil, let lookup?): lookup
        case (let staticLookup?, let learnedLookup?):
            staticLookup.key.count >= learnedLookup.key.count
                ? staticLookup
                : learnedLookup
        }
    }

    private func learnedCandidates(for key: String) -> [String] {
        learningStore.learnedChineseCandidates(for: key)
    }

    private func learnedCount(
        language: Language,
        key: String,
        candidate: String
    ) -> Int {
        learningStore.associationCount(
            language: language.rawValue,
            key: key,
            candidate: candidate
        )
    }

    private func mostRecentSelection(language: Language, key: String) -> String? {
        if let selection = learningStore.mostRecentAssociation(
            language: language.rawValue,
            key: key
        ) {
            return selection
        }

        guard language == .chinese, let lastCharacter = key.last else {
            return nil
        }
        return learningStore.mostRecentAssociation(
            language: Language.chinese.rawValue,
            key: String(lastCharacter)
        )
    }
}
