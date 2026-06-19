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
    }

    private struct WeightedCandidate {
        let text: String
        let weight: Int
    }

    private let chinese: [String: [WeightedCandidate]]
    private let english: [String: [WeightedCandidate]]
    private let defaults = UserDefaults.standard

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
        guard let lookup else { return [] }

        return lookup.candidates
            .sorted {
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
                    language: language
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

    private func learningKey(
        language: Language,
        key: String,
        candidate: String
    ) -> String {
        "association.\(language.rawValue).\(key).\(candidate)"
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
