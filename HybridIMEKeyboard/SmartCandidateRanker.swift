import Foundation

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
        let available = Set(availableCandidates)
        guard let best = learningStore.smartCandidates(code: normalizedCode)
            .first(where: {
                $0.lastUsed > 0 && available.contains($0.candidate)
            })
        else { return nil }
        return Prediction(candidate: best.candidate)
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
