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

    static let shared = SmartCandidateRanker(learningStore: .shared)

    private let learningStore: UserLearningStore

    init(learningStore: UserLearningStore) {
        self.learningStore = learningStore
    }

    func record(code: String, candidate: String) {
        learningStore.recordSmartCandidate(
            code: code,
            candidate: candidate
        )
    }

    func prediction(
        code: String,
        availableCandidates: [String]
    ) -> Prediction? {
        let learnedRows = learningStore.smartCandidates(code: code)
        // An explicit raw-English selection takes effect on the next input,
        // even when a Chinese candidate has a higher historical count.
        if let rawSelection = learnedRows.first(where: { $0.candidate == code }),
           rawSelection.lastUsed == learnedRows.map(\.lastUsed).max()
        {
            return Prediction(candidate: code)
        }

        let learned = Set(learnedRows.map(\.candidate))
        guard let candidate = rankedCandidates(
            code: code,
            candidates: availableCandidates
        ).first(where: learned.contains) else { return nil }
        return Prediction(candidate: candidate)
    }

    func rankedCandidates(code: String, candidates: [String]) -> [String] {
        let learned = Dictionary(
            uniqueKeysWithValues: learningStore.smartCandidates(code: code).map {
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
        let learnedRank = Dictionary(
            uniqueKeysWithValues: learned.enumerated().map {
                ($0.element.text, $0.offset)
            }
        )
        let orderedCandidates = candidates.enumerated().sorted { left, right in
            let leftCode = left.element.code.lowercased()
            let rightCode = right.element.code.lowercased()
            if leftCode.count != rightCode.count {
                return leftCode.count < rightCode.count
            }
            if leftCode != rightCode {
                return leftCode < rightCode
            }
            let leftRank = learnedRank[left.element.text] ?? Int.max
            let rightRank = learnedRank[right.element.text] ?? Int.max
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return left.offset < right.offset
        }.map(\.element)
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
        if (2...3).contains(normalizedCode.count),
           learned.isEmpty,
           !candidates.isEmpty,
           !hasExactCandidate
        {
            append(rootCandidate)
        }
        orderedCandidates.forEach { append($0) }
        return result
    }
}
