import Foundation

struct CangjieCandidate: Equatable {
    let text: String
    let code: String
}

@MainActor
final class SmartCandidateRanker {
    struct Prediction {
        let candidate: String
    }

    static let shared = SmartCandidateRanker()

    private let learningStore: KeyboardUserLearningStore

    init() {
        learningStore = .shared
    }

    init(learningStore: KeyboardUserLearningStore) {
        self.learningStore = learningStore
    }

    func record(
        code: String,
        candidate: String
    ) {
        let normalizedCode = code.lowercased()
        guard !normalizedCode.isEmpty, !candidate.isEmpty else { return }
        learningStore.recordSmartCandidate(
            code: normalizedCode,
            candidate: candidate
        )
    }

    func prediction(
        code: String,
        availableCandidates: [String]
    ) -> Prediction? {
        let normalizedCode = code.lowercased()
        let learned = Set(
            learningStore.smartCandidates(code: normalizedCode).map(\.candidate)
        )
        guard let candidate = rankedCandidates(
            code: normalizedCode,
            candidates: availableCandidates
        ).first(where: learned.contains) else { return nil }
        return Prediction(candidate: candidate)
    }

    func rankedCandidates(code: String, candidates: [String]) -> [String] {
        let normalizedCode = code.lowercased()
        let learned = Dictionary(
            uniqueKeysWithValues: learningStore.smartCandidates(code: normalizedCode).map {
                ($0.candidate, ($0.selectionCount, $0.lastUsed))
            }
        )
        return candidates.enumerated().sorted { left, right in
            let leftScore = learned[left.element] ?? (0, 0)
            let rightScore = learned[right.element] ?? (0, 0)
            if leftScore.0 != rightScore.0 {
                return leftScore.0 > rightScore.0
            }
            if leftScore.1 != rightScore.1 {
                return leftScore.1 > rightScore.1
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    func rankedCandidates(
        code: String,
        candidates: [CangjieCandidate],
        rootCandidate: CangjieCandidate?,
        limit: Int
    ) -> [CangjieCandidate] {
        guard limit > 0 else { return [] }
        let normalizedCode = code.lowercased()
        let staticByText = Dictionary(
            candidates.map { ($0.text, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let learned = learningStore.smartCandidates(codePrefix: normalizedCode)
            .compactMap { row -> CangjieCandidate? in
                staticByText[row.candidate]
            }
        let hasExactCandidate = candidates.contains {
            $0.code.lowercased() == normalizedCode
        }

        var result: [CangjieCandidate] = []
        var seen: Set<String> = []
        func append(_ candidate: CangjieCandidate?) {
            guard let candidate,
                  result.count < limit,
                  seen.insert(candidate.text).inserted
            else { return }
            result.append(candidate)
        }

        if normalizedCode.count == 1 {
            append(rootCandidate)
        }
        learned.forEach { append($0) }
        if normalizedCode.count > 1,
           learned.isEmpty,
           !candidates.isEmpty,
           !hasExactCandidate
        {
            append(rootCandidate)
        }
        candidates.forEach { append($0) }
        return result
    }

    func replaceLearning(
        code: String,
        candidate: String
    ) {
        let normalizedCode = code.lowercased()
        guard !normalizedCode.isEmpty, !candidate.isEmpty else { return }
        learningStore.replaceSmartCandidate(
            code: normalizedCode,
            candidate: candidate
        )
    }
}
