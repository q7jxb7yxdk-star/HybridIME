import Foundation
import SQLite3

@main
enum UserLearningStoreTest {
    @MainActor
    static func main() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let databaseURL = temporaryDirectory
            .appendingPathComponent("hybridime-user-learning.sqlite3")
        try createLegacyDatabase(at: databaseURL)
        let store = UserLearningStore(databaseURL: databaseURL)

        try require(
            store.smartCandidates(code: "APP").first?.candidate == "舊"
                && store.smartCandidates(code: "app").first?.selectionCount == 1,
            "legacy smart-candidate migration"
        )
        store.recordSmartCandidate(code: "app", candidate: "舊")
        try require(
            store.smartCandidates(code: "app").first?.selectionCount == 2,
            "migrated smart-candidate count increment"
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

        let ranker = SmartCandidateRanker(learningStore: store)
        let staticCandidates = ["甲", "乙", "丙", "丁"]
        try require(
            ranker.rankedCandidates(code: "tie", candidates: ["甲", "乙"])
                == ["甲", "乙"]
                && ranker.prediction(code: "tie", availableCandidates: ["甲", "乙"])?
                    .candidate == "甲",
            "static order breaks exact learned-score ties"
        )
        try require(
            ranker.rankedCandidates(code: "rank", candidates: staticCandidates)
                == staticCandidates,
            "unused candidates preserve static order"
        )
        store.recordSmartCandidate(code: "rank", candidate: "乙")
        store.recordSmartCandidate(code: "rank", candidate: "丙")
        try require(
            ranker.rankedCandidates(code: "rank", candidates: staticCandidates)
                == ["丙", "乙", "甲", "丁"],
            "recent use breaks equal-frequency ties"
        )
        store.recordSmartCandidate(code: "rank", candidate: "乙")
        try require(
            ranker.rankedCandidates(code: "rank", candidates: staticCandidates)
                == ["乙", "丙", "甲", "丁"],
            "selection frequency takes priority"
        )
        let prefixCandidates = [
            CangjieCandidate(text: "㳉", code: "eb"),
            CangjieCandidate(text: "測", code: "ebcn"),
            CangjieCandidate(text: "測", code: "ebxx"),
            CangjieCandidate(text: "深", code: "ebcd"),
        ]
        let rootCandidate = CangjieCandidate(text: "水", code: "e")
        try require(
            ranker.rankedCandidates(
                code: "eb",
                candidates: prefixCandidates,
                rootCandidate: rootCandidate,
                limit: 3
            ) == [prefixCandidates[0], prefixCandidates[1], prefixCandidates[3]],
            "exact multi-code candidate suppresses root fallback"
        )
        try require(
            ranker.rankedCandidates(
                code: "ebc",
                candidates: [prefixCandidates[1], prefixCandidates[3]],
                rootCandidate: rootCandidate,
                limit: 3
            ) == [rootCandidate, prefixCandidates[1], prefixCandidates[3]],
            "descendant-only prefix retains root fallback"
        )
        try require(
            ranker.rankedCandidates(
                code: "qwlj",
                candidates: [CangjieCandidate(text: "擇", code: "qwlj")],
                rootCandidate: CangjieCandidate(text: "手", code: "q"),
                limit: 3
            ) == [CangjieCandidate(text: "擇", code: "qwlj")],
            "unlearned exact code does not inject a root candidate"
        )
        try require(
            ranker.rankedCandidates(
                code: "good",
                candidates: [],
                rootCandidate: CangjieCandidate(text: "土", code: "g"),
                limit: 3
            ).isEmpty,
            "missing Cangjie prefix does not inject a root candidate"
        )
        store.recordSmartCandidate(code: "ebcn", candidate: "測")
        store.recordSmartCandidate(code: "ebcn", candidate: "測")
        store.recordSmartCandidate(code: "ebxx", candidate: "測")
        store.recordSmartCandidate(code: "ebcd", candidate: "深")
        store.recordSmartCandidate(code: "ebcd", candidate: "深")
        try require(
            store.smartCandidates(codePrefix: "EB").prefix(2).map(\.selectionCount) == [3, 2],
            "prefix descendant aggregation"
        )
        try require(
            ranker.rankedCandidates(
                code: "eb",
                candidates: prefixCandidates,
                rootCandidate: rootCandidate,
                limit: 3
            ) == [
                CangjieCandidate(text: "測", code: "ebcn"),
                prefixCandidates[3],
                prefixCandidates[0],
            ],
            "learned descendant replaces multi-code fallback and preserves full code"
        )
        try require(
            ranker.rankedCandidates(
                code: "e",
                candidates: prefixCandidates,
                rootCandidate: rootCandidate,
                limit: 3
            ).prefix(3) == [
                rootCandidate,
                CangjieCandidate(text: "測", code: "ebcn"),
                prefixCandidates[3],
            ],
            "single-code root remains pinned before a learned descendant"
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
        try require(query(databaseURL, sql: "PRAGMA integrity_check") == "ok", "integrity")
        try require(query(databaseURL, sql: "PRAGMA user_version") == "2", "schema version")
        print("UserLearningStore: PASS")
    }

    private static func createLegacyDatabase(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            throw TestError.failed("create legacy database")
        }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE smart_candidate (
            code TEXT NOT NULL,
            candidate TEXT NOT NULL,
            last_used REAL NOT NULL,
            PRIMARY KEY(code, candidate)
        ) WITHOUT ROWID;
        INSERT INTO smart_candidate(code, candidate, last_used)
        VALUES ('app', '舊', 100);
        INSERT INTO smart_candidate(code, candidate, last_used)
        VALUES ('tie', '甲', 100), ('tie', '乙', 100);
        PRAGMA user_version = 1;
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestError.failed("seed legacy database")
        }
    }

    private static func query(_ databaseURL: URL, sql: String) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: bytes)
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
