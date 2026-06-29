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

    private struct WeightedCandidate {
        let text: String
        let weight: Int
    }

    private let chinese: [String: [WeightedCandidate]]
    private let english: [String: [WeightedCandidate]]
    private let defaults = UserDefaults.standard
    private var recentSelections: [String: String] = [:]
    private var learnedChineseCandidates: [String: [String]] = [:]

    nonisolated init(bundle: Bundle = .main) {
        chinese = Self.loadTable(
            named: "chinese-associations",
            from: bundle
        )
        english = Self.loadTable(
            named: "english-associations",
            from: bundle
        )
    }

    func suggestions(
        for context: String,
        language: Language,
        limit: Int = 10
    ) -> [Suggestion] {
        guard limit > 0 else { return [] }

        let lookup: (key: String, candidates: [WeightedCandidate])?
        switch language {
        case .chinese:
            lookup = longestChineseMatch(for: context)
        case .english:
            let key = context.lowercased()
                .split(whereSeparator: \.isWhitespace)
                .last
                .map(String.init) ?? ""
            lookup = english[key].map { (key, $0) }
        }
        let learnedLookup = language == .chinese
            ? longestLearnedChineseMatch(for: context)
            : nil
        guard let lookup = preferredLookup(
            staticLookup: lookup,
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
        let key = learningKey(
            language: suggestion.language,
            key: suggestion.key,
            candidate: suggestion.text
        )
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        let recentKey = recentSelectionKey(
            language: suggestion.language,
            key: suggestion.key
        )
        recentSelections[recentKey] = suggestion.text
        defaults.set(suggestion.text, forKey: recentKey)

        if
            suggestion.language == .chinese,
            let lastCharacter = suggestion.key.last
        {
            let fallbackKey = recentSelectionKey(
                language: .chinese,
                key: String(lastCharacter)
            )
            recentSelections[fallbackKey] = suggestion.text
            defaults.set(suggestion.text, forKey: fallbackKey)
        }
    }

    func recordChineseSequence(context: String, continuation: String) {
        guard
            !context.isEmpty,
            continuation.count == 1
        else {
            return
        }

        var candidates = learnedCandidates(for: context)
        candidates.removeAll { $0 == continuation }
        candidates.insert(continuation, at: 0)
        if candidates.count > 10 {
            candidates.removeLast(candidates.count - 10)
        }
        learnedChineseCandidates[context] = candidates
        defaults.set(candidates, forKey: learnedCandidatesKey(context))

        let recentKey = recentSelectionKey(
            language: .chinese,
            key: context
        )
        recentSelections[recentKey] = continuation
        defaults.set(continuation, forKey: recentKey)
    }

    private func longestChineseMatch(
        for context: String
    ) -> (key: String, candidates: [WeightedCandidate])? {
        let characters = Array(context)
        for length in stride(from: characters.count, through: 1, by: -1) {
            let key = String(characters.suffix(length))
            if let candidates = chinese[key] {
                return (key, candidates)
            }
        }
        return nil
    }

    private func longestLearnedChineseMatch(
        for context: String
    ) -> (key: String, candidates: [WeightedCandidate])? {
        let key = String(context.suffix(8))
        let candidates = learnedCandidates(for: key)
        guard !candidates.isEmpty else {
            return nil
        }
        return (
            key,
            candidates.map {
                WeightedCandidate(text: $0, weight: 0)
            }
        )
    }

    private func preferredLookup(
        staticLookup: (key: String, candidates: [WeightedCandidate])?,
        learnedLookup: (key: String, candidates: [WeightedCandidate])?
    ) -> (key: String, candidates: [WeightedCandidate])? {
        switch (staticLookup, learnedLookup) {
        case (nil, nil):
            nil
        case (let lookup?, nil), (nil, let lookup?):
            lookup
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

    private func mostRecentSelection(
        language: Language,
        key: String
    ) -> String? {
        let recentKey = recentSelectionKey(
            language: language,
            key: key
        )
        if let selection = recentSelections[recentKey]
            ?? defaults.string(forKey: recentKey)
        {
            return selection
        }

        guard language == .chinese, let lastCharacter = key.last else {
            return nil
        }
        let fallbackRecentKey = recentSelectionKey(
            language: .chinese,
            key: String(lastCharacter)
        )
        return recentSelections[fallbackRecentKey]
            ?? defaults.string(forKey: fallbackRecentKey)
    }

    private func learningKey(
        language: Language,
        key: String,
        candidate: String
    ) -> String {
        "association.\(language.rawValue).\(key).\(candidate)"
    }

    private func recentSelectionKey(
        language: Language,
        key: String
    ) -> String {
        "association.\(language.rawValue).\(key).recent"
    }

    private func learnedCandidatesKey(_ key: String) -> String {
        "association.chinese.\(key).learnedCandidates"
    }

    nonisolated private static func loadTable(
        named name: String,
        from bundle: Bundle
    ) -> [String: [WeightedCandidate]] {
        guard
            let url = bundle.url(
                forResource: name,
                withExtension: "tsv",
                subdirectory: "AssociationData"
            ) ?? bundle.url(forResource: name, withExtension: "tsv"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            NSLog("HybridIME could not load \(name).tsv")
            return [:]
        }

        var table: [String: [WeightedCandidate]] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            guard line.first != "#" else { continue }
            let fields = line.split(
                separator: "\t",
                omittingEmptySubsequences: false
            )
            guard fields.count >= 3, fields.count % 2 == 1 else { continue }

            let key = String(fields[0])
            var candidates: [WeightedCandidate] = []
            var index = 1
            while index + 1 < fields.count {
                if let weight = Int(fields[index + 1]) {
                    candidates.append(
                        WeightedCandidate(
                            text: String(fields[index]),
                            weight: weight
                        )
                    )
                }
                index += 2
            }
            if !candidates.isEmpty {
                table[key] = candidates
            }
        }
        return table
    }
}
