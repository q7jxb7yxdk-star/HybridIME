import Foundation

@MainActor
final class SmartCandidateRanker {
    struct Prediction {
        let candidate: String
    }

    static let shared = SmartCandidateRanker()

    private let defaults = UserDefaults.standard

    private init() {}

    func record(
        code: String,
        candidate: String
    ) {
        let normalizedCode = code.lowercased()
        guard !normalizedCode.isEmpty, !candidate.isEmpty else { return }

        var candidates = defaults.stringArray(
            forKey: key(
                code: normalizedCode,
                suffix: "candidates"
            )
        ) ?? []
        let mostRecentTimestamp = candidates
            .map {
                defaults.double(
                    forKey: key(
                        code: normalizedCode,
                        suffix: "recent.\($0)"
                    )
                )
            }
            .max() ?? 0
        let timestamp = max(
            Date().timeIntervalSince1970,
            mostRecentTimestamp.nextUp
        )
        defaults.set(
            timestamp,
            forKey: key(
                code: normalizedCode,
                suffix: "recent.\(candidate)"
            )
        )

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
                return $0.0 > $1.0
            }
        guard let best, best.1 > 0 else { return nil }
        return Prediction(candidate: best.0)
    }

    private func key(
        code: String,
        suffix: String
    ) -> String {
        "smartCandidate.v2.\(code).\(suffix)"
    }
}
