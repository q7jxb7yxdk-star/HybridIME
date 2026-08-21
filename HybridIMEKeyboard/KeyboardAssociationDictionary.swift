import Foundation

@MainActor
final class KeyboardAssociationDictionary {
    enum Language: String {
        case chinese
        case english

        var lexiconLanguage: OfflineLexicon.AssociationLanguage {
            switch self {
            case .chinese: .chinese
            case .english: .english
            }
        }
    }

    struct Suggestion {
        let text: String
        let key: String
        let language: Language
        let isMostRecentSelection: Bool
    }

    private let lexicon: OfflineLexicon
    private let defaults = UserDefaults.standard
    private var recentSelections: [String: String] = [:]
    private var learnedChineseCandidates: [String: [String]] = [:]

    init(lexicon: OfflineLexicon) {
        self.lexicon = lexicon
    }

    func suggestions(
        for context: String,
        language: Language,
        limit: Int = 10
    ) -> [Suggestion] {
        guard limit > 0 else { return [] }

        let staticLookup: (key: String, candidates: [OfflineLexicon.WeightedCandidate])?
        switch language {
        case .chinese:
            staticLookup = longestStaticChineseMatch(for: context)
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
                    .map { OfflineLexicon.WeightedCandidate(text: $0, weight: 0) }
            )
        }

        return candidates
            .sorted {
                let leftIsMostRecent = $0.text == mostRecentCandidate
                let rightIsMostRecent = $1.text == mostRecentCandidate
                if leftIsMostRecent != rightIsMostRecent {
                    return leftIsMostRecent
                }
                let leftCount = learnedCount(
                    language: language,
                    key: lookup.key,
                    candidate: $0.text
                )
                let rightCount = learnedCount(
                    language: language,
                    key: lookup.key,
                    candidate: $1.text
                )
                if leftCount != rightCount {
                    return leftCount > rightCount
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
        let key = learningKey(
            language: suggestion.language,
            key: suggestion.key,
            candidate: suggestion.text
        )
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        storeMostRecent(
            suggestion.text,
            language: suggestion.language,
            key: suggestion.key
        )

        if suggestion.language == .chinese,
           let lastCharacter = suggestion.key.last
        {
            storeMostRecent(
                suggestion.text,
                language: .chinese,
                key: String(lastCharacter)
            )
        }
    }

    func recordChineseSequence(context: String, continuation: String) {
        guard !context.isEmpty, continuation.count == 1 else { return }

        var candidates = learnedCandidates(for: context)
        candidates.removeAll { $0 == continuation }
        candidates.insert(continuation, at: 0)
        if candidates.count > 10 {
            candidates.removeLast(candidates.count - 10)
        }
        learnedChineseCandidates[context] = candidates
        defaults.set(candidates, forKey: learnedCandidatesKey(context))
        storeMostRecent(continuation, language: .chinese, key: context)
    }

    private func longestStaticChineseMatch(
        for context: String
    ) -> (key: String, candidates: [OfflineLexicon.WeightedCandidate])? {
        let characters = Array(context.suffix(16))
        for length in stride(from: characters.count, through: 1, by: -1) {
            let key = String(characters.suffix(length))
            let candidates = lexicon.associationCandidates(
                language: .chinese,
                key: key
            )
            if !candidates.isEmpty {
                return (key, candidates)
            }
        }
        return nil
    }

    private func longestLearnedChineseMatch(
        for context: String
    ) -> (key: String, candidates: [OfflineLexicon.WeightedCandidate])? {
        let characters = Array(context.suffix(8))
        for length in stride(from: characters.count, through: 1, by: -1) {
            let key = String(characters.suffix(length))
            let candidates = learnedCandidates(for: key)
            if !candidates.isEmpty {
                return (
                    key,
                    candidates.map {
                        OfflineLexicon.WeightedCandidate(text: $0, weight: 0)
                    }
                )
            }
        }
        return nil
    }

    private func preferredLookup(
        staticLookup: (key: String, candidates: [OfflineLexicon.WeightedCandidate])?,
        learnedLookup: (key: String, candidates: [OfflineLexicon.WeightedCandidate])?
    ) -> (key: String, candidates: [OfflineLexicon.WeightedCandidate])? {
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
        if let cached = learnedChineseCandidates[key] {
            return cached
        }
        let candidates = defaults.stringArray(
            forKey: learnedCandidatesKey(key)
        ) ?? []
        learnedChineseCandidates[key] = candidates
        return candidates
    }

    private func learnedCount(
        language: Language,
        key: String,
        candidate: String
    ) -> Int {
        defaults.integer(
            forKey: learningKey(
                language: language,
                key: key,
                candidate: candidate
            )
        )
    }

    private func mostRecentSelection(language: Language, key: String) -> String? {
        let recentKey = recentSelectionKey(language: language, key: key)
        if let selection = recentSelections[recentKey]
            ?? defaults.string(forKey: recentKey)
        {
            return selection
        }
        guard language == .chinese, let lastCharacter = key.last else {
            return nil
        }
        let fallbackKey = recentSelectionKey(
            language: .chinese,
            key: String(lastCharacter)
        )
        return recentSelections[fallbackKey]
            ?? defaults.string(forKey: fallbackKey)
    }

    private func storeMostRecent(_ candidate: String, language: Language, key: String) {
        let recentKey = recentSelectionKey(language: language, key: key)
        recentSelections[recentKey] = candidate
        defaults.set(candidate, forKey: recentKey)
    }

    private func learningKey(
        language: Language,
        key: String,
        candidate: String
    ) -> String {
        "association.\(language.rawValue).\(key).\(candidate)"
    }

    private func recentSelectionKey(language: Language, key: String) -> String {
        "association.\(language.rawValue).\(key).recent"
    }

    private func learnedCandidatesKey(_ key: String) -> String {
        "association.chinese.\(key).learnedCandidates"
    }
}
