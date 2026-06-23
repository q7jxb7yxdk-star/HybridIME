import Foundation

@MainActor
final class SmartCandidateRanker {
    struct Prediction {
        let candidate: String
        let selectionCount: Int
    }

    static let shared = SmartCandidateRanker()

    private let defaults = UserDefaults.standard
    private let minimumSelections = 1

    private init() {}

    func record(
        code: String,
        candidate: String
    ) {
        let normalizedCode = code.lowercased()
        guard !normalizedCode.isEmpty, !candidate.isEmpty else { return }

        let candidateKey = key(
            code: normalizedCode,
            suffix: "candidate.\(candidate)"
        )
        defaults.set(
            defaults.integer(forKey: candidateKey) + 1,
            forKey: candidateKey
        )
        defaults.set(
            Date().timeIntervalSince1970,
            forKey: key(
                code: normalizedCode,
                suffix: "recent.\(candidate)"
            )
        )

        var candidates = defaults.stringArray(
            forKey: key(
                code: normalizedCode,
                suffix: "candidates"
            )
        ) ?? []
        if !candidates.contains(candidate) {
            candidates.append(candidate)
            defaults.set(
                candidates,
                forKey: key(
                    code: normalizedCode,
                    suffix: "candidates"
                )
            )
        }
    }

    func prediction(
        code: String,
        availableCandidates: [String]
    ) -> Prediction? {
        let normalizedCode = code.lowercased()
        let candidatesKey = key(
            code: normalizedCode,
            suffix: "candidates"
        )
        let learnedCandidates = defaults.stringArray(forKey: candidatesKey) ?? []

        let available = Set(availableCandidates)
        let best = learnedCandidates
            .filter { available.contains($0) }
            .map { candidate in
                (
                    candidate,
                    defaults.integer(
                        forKey: key(
                            code: normalizedCode,
                            suffix: "candidate.\(candidate)"
                        )
                    ),
                    defaults.double(
                        forKey: key(
                            code: normalizedCode,
                            suffix: "recent.\(candidate)"
                        )
                    )
                )
            }
            .max {
                if $0.1 != $1.1 {
                    return $0.1 < $1.1
                }
                if $0.2 != $1.2 {
                    return $0.2 < $1.2
                }
                return $0.0 > $1.0
            }
        guard let best, best.1 >= minimumSelections else { return nil }
        return Prediction(
            candidate: best.0,
            selectionCount: best.1
        )
    }

    private func key(
        code: String,
        suffix: String
    ) -> String {
        "smartCandidate.v2.\(code).\(suffix)"
    }
}
