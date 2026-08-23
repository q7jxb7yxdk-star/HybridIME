import Foundation

@main
enum StaticLexiconTest {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestError.failed("database path is required")
        }
        let lexicon = StaticLexicon(
            databaseURL: URL(fileURLWithPath: CommandLine.arguments[1])
        )

        try require(
            lexicon.cangjieCandidates(code: "A", limit: 2) == ["日", "曰"],
            "Cangjie lookup preserves source order"
        )
        try require(
            lexicon.cangjieCandidates(code: "a", limit: 1) == ["日"],
            "Cangjie lookup limit"
        )
        try require(
            lexicon.bilingualCandidates(
                direction: .englishToChinese,
                key: "test",
                limit: 2
            ) == ["測試", "實驗"],
            "English-to-Chinese lookup"
        )
        try require(
            lexicon.longestBilingualMatch(
                direction: .chineseToEnglish,
                keys: ["不存在", "測"],
                limit: 2
            )?.candidates == ["survey", "measure"],
            "batched longest bilingual lookup"
        )
        let chineseAssociation = lexicon.longestAssociationMatch(
            language: .chinese,
            keys: ["__missing_association_key__", "我"]
        )
        try require(
            chineseAssociation?.key == "我"
                && chineseAssociation?.candidates.first?.text == "們",
            "batched Chinese association lookup"
        )
        try require(
            lexicon.associationCandidates(
                language: .english,
                key: "hello"
            ).first?.text == "hi",
            "English association lookup"
        )
        print("StaticLexicon: PASS")
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
