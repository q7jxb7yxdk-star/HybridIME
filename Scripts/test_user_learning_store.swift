import Foundation

@main
enum UserLearningStoreTest {
    static func main() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = UserLearningStore(
            databaseURL: temporaryDirectory
                .appendingPathComponent("hybridime-user-learning.sqlite3")
        )

        try require(
            store.smartCandidates(code: "app").isEmpty,
            "new smart-candidate database"
        )
        try require(
            store.associationCount(
                language: "chinese",
                key: "我",
                candidate: "們"
            ) == 0,
            "new association database"
        )
        try require(
            store.mostRecentAssociation(language: "chinese", key: "我") == nil,
            "new recent-association database"
        )
        try require(
            store.learnedChineseCandidates(for: "我").isEmpty,
            "new learned-Chinese database"
        )

        store.recordSmartCandidate(code: "app", candidate: "昆")
        try require(
            store.smartCandidates(code: "app").first?.candidate == "昆",
            "smart-candidate update"
        )
        store.recordAssociationSelection(
            language: "chinese",
            key: "我",
            candidate: "們",
            incrementingCount: true
        )
        try require(
            store.associationCount(
                language: "chinese",
                key: "我",
                candidate: "們"
            ) == 1,
            "association-count update"
        )
        try require(
            store.mostRecentAssociation(language: "chinese", key: "我") == "們",
            "recent-association update"
        )
        store.recordLearnedChinese(context: "我", candidate: "想")
        try require(
            store.learnedChineseCandidates(for: "我").first == "想",
            "learned-Chinese update"
        )
        print("UserLearningStore: PASS")
    }

    private static func require(_ condition: Bool, _ name: String) throws {
        if !condition {
            throw TestError.failed(name)
        }
    }

    private enum TestError: Error {
        case failed(String)
    }
}
