import Foundation

@main
enum MacDictionaryTest {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestError.failed("database path is required")
        }
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let lexicon = StaticLexicon(
            databaseURL: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let learningStore = UserLearningStore(
            databaseURL: temporaryDirectory
                .appendingPathComponent("hybridime-user-learning.sqlite3")
        )
        let bilingual = BilingualDictionary(lexicon: lexicon)
        let associations = AssociationDictionary(
            lexicon: lexicon,
            learningStore: learningStore
        )

        try require(
            bilingual.chineseCandidates(for: "test", limit: 2) == ["測試", "實驗"],
            "bilingual API"
        )
        try require(
            bilingual.longestEnglishMatch(
                forChineseKeys: ["不存在", "測"],
                limit: 2
            )?.candidates == ["survey", "measure"],
            "batched translation API"
        )

        let initial = associations.suggestions(
            for: "我",
            language: .chinese,
            limit: 10
        )
        try require(initial.first?.text == "們", "Chinese association API")
        guard let selected = initial.first(where: { $0.text == "的" }) else {
            throw TestError.failed("association fixture")
        }
        associations.recordSelection(selected)
        let learned = associations.suggestions(
            for: "我",
            language: .chinese,
            limit: 10
        )
        try require(
            learned.first?.text == "的" && learned.first?.isMostRecentSelection == true,
            "association selection learning"
        )

        associations.recordChineseSequence(context: "測試", continuation: "版")
        let sequence = associations.suggestions(
            for: "測試",
            language: .chinese,
            limit: 10
        )
        try require(
            sequence.first?.text == "版" && sequence.first?.isMostRecentSelection == true,
            "learned Chinese sequence"
        )
        print("macOS dictionary integration: PASS")
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
