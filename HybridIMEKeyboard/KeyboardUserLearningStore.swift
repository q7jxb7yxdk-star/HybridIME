import Foundation
import SQLite3

@MainActor
final class KeyboardUserLearningStore {
    static let shared = KeyboardUserLearningStore()

    private var database: OpaquePointer?

    private init() {
        openDatabase(at: Self.databaseURL())
    }

    init(databaseURL: URL) {
        openDatabase(at: databaseURL)
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func recordSmartCandidate(code: String, candidate: String) {
        let normalizedCode = code.lowercased()
        guard !normalizedCode.isEmpty, !candidate.isEmpty else { return }
        let timestamp = nextTimestamp(
            table: "smart_candidate",
            keyColumn: "code",
            key: normalizedCode
        )
        execute(
            """
            INSERT INTO smart_candidate(code, candidate, selection_count, last_used)
            VALUES (?, ?, 1, ?)
            ON CONFLICT(code, candidate) DO UPDATE SET
                selection_count = smart_candidate.selection_count + 1,
                last_used = excluded.last_used
            """,
            strings: [normalizedCode, candidate],
            double: timestamp
        )
    }

    func replaceSmartCandidate(code: String, candidate: String) {
        let normalizedCode = code.lowercased()
        guard !normalizedCode.isEmpty, !candidate.isEmpty else { return }
        let timestamp = nextTimestamp(
            table: "smart_candidate",
            keyColumn: "code",
            key: normalizedCode
        )
        execute(
            "DELETE FROM smart_candidate WHERE code = ?",
            strings: [normalizedCode]
        )
        execute(
            """
            INSERT INTO smart_candidate(code, candidate, selection_count, last_used)
            VALUES (?, ?, 1, ?)
            """,
            strings: [normalizedCode, candidate],
            double: timestamp
        )
    }

    func smartCandidates(
        code: String
    ) -> [(candidate: String, selectionCount: Int, lastUsed: Double)] {
        let normalizedCode = code.lowercased()
        guard !normalizedCode.isEmpty else { return [] }
        return queryRows(
            """
            SELECT candidate, selection_count, last_used FROM smart_candidate
            WHERE code = ?
            ORDER BY selection_count DESC, last_used DESC, candidate ASC
            """,
            strings: [normalizedCode]
        ).compactMap { row -> (
            candidate: String,
            selectionCount: Int,
            lastUsed: Double
        )? in
            guard
                row.count == 3,
                let selectionCount = Int(row[1]),
                let timestamp = Double(row[2])
            else { return nil }
            return (row[0], selectionCount, timestamp)
        }
    }

    func smartCandidates(
        codePrefix: String
    ) -> [(candidate: String, code: String, selectionCount: Int, lastUsed: Double)] {
        let normalizedPrefix = codePrefix.lowercased()
        guard !normalizedPrefix.isEmpty else { return [] }
        return queryRows(
            """
            SELECT candidate, code, selection_count, last_used
            FROM smart_candidate
            WHERE code >= ? AND code < ?
            ORDER BY selection_count DESC, last_used DESC, code ASC, candidate ASC
            """,
            strings: [normalizedPrefix, normalizedPrefix + "{"]
        ).compactMap { row -> (
            candidate: String,
            code: String,
            selectionCount: Int,
            lastUsed: Double
        )? in
            guard
                row.count == 4,
                let selectionCount = Int(row[2]),
                let lastUsed = Double(row[3])
            else { return nil }
            return (row[0], row[1], selectionCount, lastUsed)
        }.reduce(
            into: [String: (
                candidate: String,
                code: String,
                selectionCount: Int,
                lastUsed: Double
            )]()
        ) { result, row in
            if var existing = result[row.candidate] {
                existing.selectionCount += row.selectionCount
                existing.lastUsed = max(existing.lastUsed, row.lastUsed)
                result[row.candidate] = existing
            } else {
                result[row.candidate] = row
            }
        }.values.sorted {
            if $0.selectionCount != $1.selectionCount {
                return $0.selectionCount > $1.selectionCount
            }
            if $0.lastUsed != $1.lastUsed {
                return $0.lastUsed > $1.lastUsed
            }
            if $0.code != $1.code { return $0.code < $1.code }
            return $0.candidate < $1.candidate
        }
    }

    func associationCount(
        language: String,
        key: String,
        candidate: String
    ) -> Int {
        return Int(
            scalarText(
                """
                SELECT selection_count FROM association_selection
                WHERE language = ? AND context = ? AND candidate = ?
                """,
                strings: [language, key, candidate]
            ) ?? "0"
        ) ?? 0
    }

    func mostRecentAssociation(language: String, key: String) -> String? {
        scalarText(
            """
            SELECT candidate FROM association_selection
            WHERE language = ? AND context = ? AND last_selected > 0
            ORDER BY last_selected DESC, candidate ASC LIMIT 1
            """,
            strings: [language, key]
        )
    }

    func recordAssociationSelection(
        language: String,
        key: String,
        candidate: String,
        incrementingCount: Bool
    ) {
        let timestamp = nextTimestamp(
            table: "association_selection",
            keyColumn: "context",
            key: key,
            secondaryColumn: "language",
            secondaryValue: language
        )
        execute(
            """
            INSERT INTO association_selection(
                language, context, candidate, selection_count, last_selected
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(language, context, candidate) DO UPDATE SET
                selection_count = association_selection.selection_count + excluded.selection_count,
                last_selected = excluded.last_selected
            """,
            strings: [language, key, candidate],
            integer: incrementingCount ? 1 : 0,
            double: timestamp
        )
    }

    func learnedChineseCandidates(for key: String) -> [String] {
        return queryRows(
            """
            SELECT candidate FROM learned_chinese
            WHERE context = ? ORDER BY position ASC, candidate ASC LIMIT 10
            """,
            strings: [key]
        ).compactMap(\.first)
    }

    func recordLearnedChinese(context: String, candidate: String) {
        guard !context.isEmpty, !candidate.isEmpty else { return }
        execute(
            "UPDATE learned_chinese SET position = position + 1 WHERE context = ?",
            strings: [context]
        )
        execute(
            """
            INSERT INTO learned_chinese(context, candidate, position)
            VALUES (?, ?, 0)
            ON CONFLICT(context, candidate) DO UPDATE SET position = 0
            """,
            strings: [context, candidate]
        )
        execute(
            "DELETE FROM learned_chinese WHERE context = ? AND position >= 10",
            strings: [context]
        )
    }

    private func openDatabase(at url: URL?) {
        guard let url else {
            NSLog("HybridIMEKeyboard could not create the user learning directory")
            return
        }
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            NSLog("HybridIMEKeyboard could not open the user learning database")
            closeDatabase()
            return
        }
        sqlite3_exec(database, "PRAGMA journal_mode = WAL", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA synchronous = NORMAL", nil, nil, nil)
        createSchema()
    }

    private func createSchema() {
        sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil)
        sqlite3_exec(
            database,
            """
            CREATE TABLE IF NOT EXISTS smart_candidate (
                code TEXT NOT NULL,
                candidate TEXT NOT NULL,
                selection_count INTEGER NOT NULL DEFAULT 1,
                last_used REAL NOT NULL,
                PRIMARY KEY(code, candidate)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS association_selection (
                language TEXT NOT NULL,
                context TEXT NOT NULL,
                candidate TEXT NOT NULL,
                selection_count INTEGER NOT NULL DEFAULT 0,
                last_selected REAL NOT NULL DEFAULT 0,
                PRIMARY KEY(language, context, candidate)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS learned_chinese (
                context TEXT NOT NULL,
                candidate TEXT NOT NULL,
                position INTEGER NOT NULL,
                PRIMARY KEY(context, candidate)
            ) WITHOUT ROWID;
            """,
            nil,
            nil,
            nil
        )
        if !tableColumns("smart_candidate").contains("selection_count") {
            sqlite3_exec(
                database,
                """
                ALTER TABLE smart_candidate
                ADD COLUMN selection_count INTEGER NOT NULL DEFAULT 1
                """,
                nil,
                nil,
                nil
            )
        }
        sqlite3_exec(database, "PRAGMA user_version = 2", nil, nil, nil)
        sqlite3_exec(database, "COMMIT", nil, nil, nil)
    }

    private func tableColumns(_ table: String) -> Set<String> {
        Set(queryRows("PRAGMA table_info(\(table))", strings: []).compactMap { row in
            row.count > 1 ? row[1] : nil
        })
    }

    private func nextTimestamp(
        table: String,
        keyColumn: String,
        key: String,
        secondaryColumn: String? = nil,
        secondaryValue: String? = nil
    ) -> Double {
        var sql = "SELECT MAX(" + (table == "smart_candidate" ? "last_used" : "last_selected")
            + ") FROM \(table) WHERE \(keyColumn) = ?"
        var values = [key]
        if let secondaryColumn, let secondaryValue {
            sql += " AND \(secondaryColumn) = ?"
            values.append(secondaryValue)
        }
        let previous = Double(scalarText(sql, strings: values) ?? "0") ?? 0
        return max(Date().timeIntervalSince1970, previous.nextUp)
    }

    private func execute(
        _ sql: String,
        strings: [String],
        integer: Int? = nil,
        double: Double? = nil
    ) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bind(strings: strings, integer: integer, double: double, to: statement)
        sqlite3_step(statement)
    }

    private func scalarText(_ sql: String, strings: [String]) -> String? {
        queryRows(sql, strings: strings).first?.first
    }

    private func queryRows(_ sql: String, strings: [String]) -> [[String]] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind(strings: strings, integer: nil, double: nil, to: statement)

        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { index in
                guard let bytes = sqlite3_column_text(statement, index) else { return "" }
                return String(cString: bytes)
            })
        }
        return rows
    }

    private func bind(
        strings: [String],
        integer: Int?,
        double: Double?,
        to statement: OpaquePointer?
    ) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var index: Int32 = 1
        for string in strings {
            sqlite3_bind_text(statement, index, string, -1, transient)
            index += 1
        }
        if let integer {
            sqlite3_bind_int64(statement, index, sqlite3_int64(integer))
            index += 1
        }
        if let double {
            sqlite3_bind_double(statement, index, double)
        }
    }

    private func closeDatabase() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    nonisolated private static func databaseURL() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport.appendingPathComponent(
            "HybridIME",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent("hybridime-user-learning.sqlite3")
        } catch {
            NSLog("HybridIMEKeyboard could not prepare Application Support: \(error)")
            return nil
        }
    }
}
