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

        let store = KeyboardUserLearningStore(databaseURL: databaseURL)

        precondition(
            store.smartCandidates(code: "APP").isEmpty,
            "New smart-candidate database was not empty"
        )
        store.recordSmartCandidate(code: "app", candidate: "昆")
        store.recordSmartCandidate(code: "app", candidate: "甲")
        precondition(
            store.smartCandidates(code: "app").first?.candidate == "甲",
            "Most recent smart candidate was not promoted"
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
        precondition(query(databaseURL, sql: "PRAGMA user_version") == "1")
        print("KeyboardUserLearningStore tests passed")
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
}
