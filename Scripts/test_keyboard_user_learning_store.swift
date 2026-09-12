import Foundation
import SQLite3

@main
struct KeyboardUserLearningStoreTests {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HybridIME-KeyboardUserLearningStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("learning.sqlite3")
        try createLegacyDatabase(at: databaseURL)

        let store = KeyboardUserLearningStore(databaseURL: databaseURL)

        precondition(
            store.smartCandidates(code: "APP").first?.candidate == "舊"
                && store.smartCandidates(code: "app").first?.selectionCount == 1,
            "Legacy smart candidate was not migrated"
        )
        store.recordSmartCandidate(code: "app", candidate: "舊")
        precondition(
            store.smartCandidates(code: "app").first?.selectionCount == 2,
            "Migrated smart-candidate count was not incremented"
        )
        let ranker = SmartCandidateRanker(learningStore: store)
        let staticCandidates = ["甲", "乙", "丙", "丁"]
        precondition(
            ranker.rankedCandidates(code: "tie", candidates: ["甲", "乙"])
                == ["甲", "乙"]
                && ranker.prediction(code: "tie", availableCandidates: ["甲", "乙"])?
                    .candidate == "甲",
            "Static order did not break an exact learned-score tie"
        )
        precondition(
            ranker.rankedCandidates(code: "rank", candidates: staticCandidates)
                == staticCandidates,
            "Unused candidates did not preserve static order"
        )
        store.recordSmartCandidate(code: "rank", candidate: "乙")
        store.recordSmartCandidate(code: "rank", candidate: "丙")
        precondition(
            ranker.rankedCandidates(code: "rank", candidates: staticCandidates)
                == ["丙", "乙", "甲", "丁"],
            "Recency did not break an equal-frequency tie"
        )
        store.recordSmartCandidate(code: "rank", candidate: "乙")
        precondition(
            ranker.rankedCandidates(code: "rank", candidates: staticCandidates)
                == ["乙", "丙", "甲", "丁"],
            "Selection frequency did not take priority"
        )
        let prefixCandidates = [
            CangjieCandidate(text: "㳉", code: "eb"),
            CangjieCandidate(text: "測", code: "ebcn"),
            CangjieCandidate(text: "測", code: "ebxx"),
            CangjieCandidate(text: "深", code: "ebcd"),
        ]
        let rootCandidate = CangjieCandidate(text: "水", code: "e")
        precondition(
            ranker.rankedCandidates(
                code: "eb",
                candidates: prefixCandidates,
                rootCandidate: rootCandidate,
                limit: 3
            ) == [prefixCandidates[0], prefixCandidates[1], prefixCandidates[3]],
            "Exact multi-code candidate did not suppress root fallback"
        )
        precondition(
            ranker.rankedCandidates(
                code: "ebc",
                candidates: [prefixCandidates[1], prefixCandidates[3]],
                rootCandidate: rootCandidate,
                limit: 3
            ) == [rootCandidate, prefixCandidates[1], prefixCandidates[3]],
            "Descendant-only prefix did not retain root fallback"
        )
        precondition(
            ranker.rankedCandidates(
                code: "qwlj",
                candidates: [CangjieCandidate(text: "擇", code: "qwlj")],
                rootCandidate: CangjieCandidate(text: "手", code: "q"),
                limit: 3
            ) == [CangjieCandidate(text: "擇", code: "qwlj")],
            "Unlearned exact code injected a root candidate"
        )
        precondition(
            ranker.rankedCandidates(
                code: "good",
                candidates: [],
                rootCandidate: CangjieCandidate(text: "土", code: "g"),
                limit: 3
            ).isEmpty,
            "Missing Cangjie prefix injected a root candidate"
        )
        store.recordSmartCandidate(code: "ebcn", candidate: "測")
        store.recordSmartCandidate(code: "ebcn", candidate: "測")
        store.recordSmartCandidate(code: "ebxx", candidate: "測")
        store.recordSmartCandidate(code: "ebcd", candidate: "深")
        store.recordSmartCandidate(code: "ebcd", candidate: "深")
        precondition(
            store.smartCandidates(codePrefix: "EB").prefix(2).map(\.selectionCount) == [3, 2],
            "Prefix descendant aggregation failed"
        )
        precondition(
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
            "Learned descendant did not replace fallback or preserve its full code"
        )
        precondition(
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
            "Single-code root was not pinned before learned descendant"
        )
        store.replaceSmartCandidate(code: "app", candidate: "app")
        precondition(
            store.smartCandidates(code: "app").map(\.candidate) == ["app"],
            "Shift-Space replacement did not clear the old learned candidate"
        )

        precondition(
            store.associationCount(language: "chinese", key: "你", candidate: "好") == 0,
            "New association database was not empty"
        )
        store.recordAssociationSelection(
            language: "chinese",
            key: "你",
            candidate: "好",
            incrementingCount: true
        )
        precondition(
            store.associationCount(language: "chinese", key: "你", candidate: "好") == 1,
            "Association count was not incremented"
        )
        precondition(
            store.mostRecentAssociation(language: "chinese", key: "你") == "好",
            "Recent association was not recorded"
        )

        precondition(
            store.learnedChineseCandidates(for: "世").isEmpty,
            "New learned Chinese database was not empty"
        )
        store.recordLearnedChinese(context: "世", candidate: "界")
        store.recordLearnedChinese(context: "世", candidate: "好")
        store.recordLearnedChinese(context: "世", candidate: "新")
        precondition(
            store.learnedChineseCandidates(for: "世") == ["新", "好", "界"],
            "Learned Chinese sequence was not reordered"
        )

        precondition(query(databaseURL, sql: "PRAGMA integrity_check") == "ok")
        precondition(query(databaseURL, sql: "PRAGMA user_version") == "2")
        print("KeyboardUserLearningStore tests passed")
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

    private enum TestError: Error {
        case failed(String)
    }
}
