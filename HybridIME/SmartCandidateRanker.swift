import Foundation

@MainActor
final class SmartCandidateRanker {
    struct Prediction {
        let candidate: String
    }

    static let shared = SmartCandidateRanker()

    private let learningStore = UserLearningStore.shared

    private init() {}

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
        let available = Set(availableCandidates)
        guard let best = learningStore.smartCandidates(code: code).first(where: {
            $0.lastUsed > 0 && available.contains($0.candidate)
        }) else { return nil }
        return Prediction(candidate: best.candidate)
    }
}
