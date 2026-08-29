import Foundation
import SQLite3
import Darwin

/// Refreshes only the source-derived tables in the checked-in static lexicon.
/// `cangjie` is the canonical, immutable data source in that database.
@main
enum UpdateStaticLexicon {
    private static let expectedTableOrder = ["cangjie", "association", "bilingual"]
    private static let expectedCangjieRowCount: Int64 = 33_319
    private static let expectedCangjieCandidateCount = 36_862
    private static let expectedCangjieFingerprint: UInt64 = 0x8ddd_0f42_69ef_c2d4
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("update_static_lexicon: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        let projectRoot = try projectRoot(from: CommandLine.arguments)
        let sourceRoot = projectRoot.appendingPathComponent("HybridIME", isDirectory: true)
        let lexiconDirectory = projectRoot.appendingPathComponent(
            "HybridIMEKeyboard/LexiconData",
            isDirectory: true
        )
        let databaseURL = lexiconDirectory.appendingPathComponent("hybridime-lexicon.sqlite3")

        // Read and validate every external input before changing the canonical database.
        let bilingual = try bilingualRows(sourceRoot: sourceRoot)
        let associations = try associationRows(sourceRoot: sourceRoot)
        let notices = try noticeData(sourceRoot: sourceRoot)

        let database = try Database(url: databaseURL, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX)
        defer { database.close() }
        try verifyCanonicalDatabase(database)

        // Writing notices cannot leave a partially updated SQLite database: it happens before
        // the database transaction, and every write uses Foundation's atomic replacement.
        for (name, data) in notices {
            try data.write(to: lexiconDirectory.appendingPathComponent(name), options: .atomic)
        }

        let associationIsCurrent = try rowsMatch(
            associations,
            sql: "SELECT language, key, candidates FROM association ORDER BY language, key",
            database: database
        )
        let bilingualIsCurrent = try rowsMatch(
            bilingual,
            sql: "SELECT direction, key, candidates FROM bilingual ORDER BY direction, key",
            database: database
        )
        guard !associationIsCurrent || !bilingualIsCurrent else {
            print("Static lexicon is already source-equal; cangjie unchanged.")
            return
        }

        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try database.execute("DELETE FROM association")
            try database.execute("DELETE FROM bilingual")
            try insertAssociations(associations, into: database)
            try insertBilingual(bilingual, into: database)
            try verifyCanonicalDatabase(database)
            try database.execute("COMMIT")
        } catch {
            _ = try? database.execute("ROLLBACK")
            throw error
        }
        print("Updated association (\(associations.count) rows) and bilingual (\(bilingual.count) rows); cangjie unchanged.")
    }

    private static func projectRoot(from arguments: [String]) throws -> URL {
        guard arguments.count <= 2 else { throw Failure("usage: update_static_lexicon.swift [project-root]") }
        if let path = arguments.dropFirst().first {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func bilingualRows(sourceRoot: URL) throws -> [(Int32, String, String)] {
        var rows: [BilingualKey: String] = [:]
        for fields in try tsvRows(sourceRoot.appendingPathComponent("DictionaryData/cedict-index.tsv")) {
            guard fields.count >= 3, fields[0] == "e" || fields[0] == "z" else {
                throw Failure("invalid cedict-index row: \(fields)")
            }
            let direction: Int32 = fields[0] == "e" ? 0 : 1
            let key = direction == 0 ? fields[1].lowercased() : fields[1]
            rows[BilingualKey(direction: direction, key: key)] = try candidateString(Array(fields.dropFirst(2)))
        }
        for fields in try tsvRows(sourceRoot.appendingPathComponent("DictionaryData/dictionary-overrides.tsv")) {
            guard fields.count >= 3, ["add-e", "add-z", "replace-e", "replace-z"].contains(fields[0]) else {
                throw Failure("invalid dictionary override row: \(fields)")
            }
            let direction: Int32 = fields[0].hasSuffix("e") ? 0 : 1
            let key = direction == 0 ? fields[1].lowercased() : fields[1]
            let newCandidates = try candidates(Array(fields.dropFirst(2)))
            let identifier = BilingualKey(direction: direction, key: key)
            let existing = rows[identifier]?.split(separator: "\t").map(String.init) ?? []
            rows[identifier] = fields[0].hasPrefix("replace")
                ? newCandidates.joined(separator: "\t")
                : unique(newCandidates + existing).joined(separator: "\t")
        }
        return rows.map { ($0.key.direction, $0.key.key, $0.value) }
            .sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
    }

    private static func associationRows(sourceRoot: URL) throws -> [(Int32, String, String)] {
        let sources: [(Int32, String)] = [(0, "chinese-associations.tsv"), (1, "english-associations.tsv")]
        var rows: [AssociationKey: String] = [:]
        for (language, fileName) in sources {
            for fields in try tsvRows(sourceRoot.appendingPathComponent("AssociationData/\(fileName)")) {
                guard fields.count >= 3, fields.count.isMultiple(of: 2) == false else {
                    throw Failure("invalid association row in \(fileName): \(fields)")
                }
                let candidates = Array(fields.dropFirst())
                guard candidates.allSatisfy({ !$0.isEmpty }) else { throw Failure("empty association candidate") }
                rows[AssociationKey(language: language, key: fields[0])] = candidates.joined(separator: "\t")
            }
        }
        return rows.map { ($0.key.language, $0.key.key, $0.value) }
            .sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
    }

    private static func tsvRows(_ url: URL) throws -> [[String]] {
        try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \ .isNewline)
            .compactMap { line in
                let text = String(line)
                guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
                return text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            }
    }

    private static func candidateString(_ values: [String]) throws -> String {
        try candidates(values).joined(separator: "\t")
    }

    private static func candidates(_ values: [String]) throws -> [String] {
        guard values.allSatisfy({ !$0.isEmpty }) else { throw Failure("empty candidate") }
        return unique(values)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func noticeData(sourceRoot: URL) throws -> [(String, Data)] {
        let paths = [
            ("CangjieData/LICENSE-Rime-Cangjie.txt", "LICENSE-Rime-Cangjie.txt"),
            ("CangjieData/NOTICE.txt", "NOTICE-Rime-Cangjie.txt"),
            ("DictionaryData/LICENSE-CC-CEDICT.txt", "LICENSE-CC-CEDICT.txt"),
            ("DictionaryData/NOTICE-CC-CEDICT.txt", "NOTICE-CC-CEDICT.txt"),
            ("AssociationData/LICENSE-Rime-Essay.txt", "LICENSE-Rime-Essay.txt"),
            ("AssociationData/NOTICE-Rime-Essay.txt", "NOTICE-Rime-Essay.txt"),
            ("AssociationData/NOTICE-Tatoeba-CC0.txt", "NOTICE-Tatoeba-CC0.txt"),
        ]
        return try paths.map { (source, destination) in
            (destination, try Data(contentsOf: sourceRoot.appendingPathComponent(source)))
        }
    }

    private static func verifyCanonicalDatabase(_ database: Database) throws {
        guard try database.singleText("PRAGMA integrity_check") == "ok" else { throw Failure("canonical database integrity check failed") }
        guard try database.singleInt("PRAGMA user_version") == 2 else { throw Failure("canonical database user_version must be 2") }
        guard try database.textColumn("SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY rowid") == expectedTableOrder else {
            throw Failure("canonical database table order changed")
        }
        guard try database.singleInt("SELECT count(*) FROM cangjie") == expectedCangjieRowCount else {
            throw Failure("canonical cangjie table must contain \(expectedCangjieRowCount) rows")
        }
        let columns = try database.rows("PRAGMA table_info(cangjie)")
        guard columns.count == 2,
              columns[0]["name"] == "code", columns[0]["type"] == "TEXT", columns[0]["notnull"] == "1", columns[0]["pk"] == "1",
              columns[1]["name"] == "candidates", columns[1]["type"] == "TEXT", columns[1]["notnull"] == "1", columns[1]["pk"] == "0"
        else { throw Failure("canonical cangjie table structure changed") }

        let rows = try database.rows("SELECT code, candidates FROM cangjie ORDER BY code")
        var candidateCount = 0
        var fingerprint: UInt64 = 14_695_981_039_346_656_037
        for row in rows {
            guard let code = row["code"],
                  let payload = row["candidates"],
                  !code.isEmpty,
                  code.count <= 5,
                  code.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 })
            else { throw Failure("canonical cangjie code is invalid") }
            let candidates = payload.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard !candidates.isEmpty,
                  candidates.allSatisfy({ $0.count == 1 }),
                  Set(candidates).count == candidates.count
            else { throw Failure("canonical cangjie candidates are invalid for \(code)") }
            candidateCount += candidates.count
            for byte in "\(code)\t\(payload)\n".utf8 {
                fingerprint = (fingerprint ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        guard candidateCount == expectedCangjieCandidateCount,
              fingerprint == expectedCangjieFingerprint
        else { throw Failure("canonical cangjie content fingerprint changed") }
    }

    private static func insertAssociations(_ rows: [(Int32, String, String)], into database: Database) throws {
        let statement = try database.statement("INSERT INTO association(language, key, candidates) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        for (language, key, candidates) in rows {
            try bindAndStep(statement, values: [.int(language), .text(key), .text(candidates)])
        }
    }

    private static func insertBilingual(_ rows: [(Int32, String, String)], into database: Database) throws {
        let statement = try database.statement("INSERT INTO bilingual(direction, key, candidates) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        for (direction, key, candidates) in rows {
            try bindAndStep(statement, values: [.int(direction), .text(key), .text(candidates)])
        }
    }

    private static func bindAndStep(_ statement: OpaquePointer?, values: [Value]) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .int(let number): result = sqlite3_bind_int(statement, index, number)
            case .text(let text): result = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            }
            guard result == SQLITE_OK else { throw Failure("SQLite bind failed") }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure("SQLite insert failed") }
    }

    private static func rowsMatch(
        _ expected: [(Int32, String, String)],
        sql: String,
        database: Database
    ) throws -> Bool {
        let statement = try database.statement(sql)
        defer { sqlite3_finalize(statement) }
        for (kind, key, candidates) in expected {
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE { return false }
                throw Failure("SQLite comparison failed")
            }
            guard sqlite3_column_int(statement, 0) == kind,
                  let keyBytes = sqlite3_column_text(statement, 1),
                  let candidateBytes = sqlite3_column_text(statement, 2),
                  String(cString: keyBytes) == key,
                  String(cString: candidateBytes) == candidates
            else { return false }
        }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return true }
        if result == SQLITE_ROW { return false }
        throw Failure("SQLite comparison failed")
    }

    private struct BilingualKey: Hashable { let direction: Int32; let key: String }
    private struct AssociationKey: Hashable { let language: Int32; let key: String }
    private enum Value { case int(Int32), text(String) }
    fileprivate struct Failure: Error, CustomStringConvertible { let message: String; init(_ message: String) { self.message = message }; var description: String { message } }
}

private final class Database {
    private var handle: OpaquePointer?

    init(url: URL, flags: Int32) throws {
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else { throw UpdateStaticLexicon.Failure("could not open \(url.path)") }
    }

    func close() { sqlite3_close(handle); handle = nil }
    func execute(_ sql: String) throws { guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw UpdateStaticLexicon.Failure(errorMessage) } }
    func statement(_ sql: String) throws -> OpaquePointer? { var statement: OpaquePointer?; guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw UpdateStaticLexicon.Failure(errorMessage) }; return statement }
    func singleText(_ sql: String) throws -> String { guard let statement = try statement(sql) else { throw UpdateStaticLexicon.Failure("empty SQLite statement") }; defer { sqlite3_finalize(statement) }; guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { throw UpdateStaticLexicon.Failure(errorMessage) }; return String(cString: value) }
    func singleInt(_ sql: String) throws -> Int64 { guard let statement = try statement(sql) else { throw UpdateStaticLexicon.Failure("empty SQLite statement") }; defer { sqlite3_finalize(statement) }; guard sqlite3_step(statement) == SQLITE_ROW else { throw UpdateStaticLexicon.Failure(errorMessage) }; return sqlite3_column_int64(statement, 0) }
    func textColumn(_ sql: String) throws -> [String] { guard let statement = try statement(sql) else { throw UpdateStaticLexicon.Failure("empty SQLite statement") }; defer { sqlite3_finalize(statement) }; var result: [String] = []; while sqlite3_step(statement) == SQLITE_ROW { guard let value = sqlite3_column_text(statement, 0) else { throw UpdateStaticLexicon.Failure("unexpected NULL") }; result.append(String(cString: value)) }; return result }
    func rows(_ sql: String) throws -> [[String: String]] { guard let statement = try statement(sql) else { throw UpdateStaticLexicon.Failure("empty SQLite statement") }; defer { sqlite3_finalize(statement) }; var result: [[String: String]] = []; while sqlite3_step(statement) == SQLITE_ROW { var row: [String: String] = [:]; for index in 0..<sqlite3_column_count(statement) { guard let name = sqlite3_column_name(statement, index) else { throw UpdateStaticLexicon.Failure("invalid SQLite column") }; row[String(cString: name)] = sqlite3_column_text(statement, index).map(String.init(cString:)) ?? "" }; result.append(row) }; return result }
    private var errorMessage: String { handle.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "SQLite error" }
}
