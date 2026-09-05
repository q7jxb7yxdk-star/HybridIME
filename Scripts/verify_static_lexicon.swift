import Foundation
import SQLite3
import Darwin

/// Read-only verification for the checked-in static lexicon.
@main
enum VerifyStaticLexicon {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(Data("verify_static_lexicon: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() throws {
        let root = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let databaseURL = root.appendingPathComponent("HybridIMEKeyboard/LexiconData/hybridime-lexicon.sqlite3")
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw Failure("could not open \(databaseURL.path) read-only") }
        defer { sqlite3_close(database) }

        try require(queryText(database, "PRAGMA integrity_check") == "ok", "integrity_check")
        try require(queryInt(database, "PRAGMA user_version") == 2, "user_version")
        try require(queryTextColumn(database, "SELECT name FROM sqlite_schema WHERE type = 'table' ORDER BY rowid") == ["cangjie", "association", "bilingual"], "table order")
        try require(queryInt(database, "SELECT count(*) FROM cangjie") == 33_318, "cangjie row count")
        let cangjieColumns = try queryRows(database, "PRAGMA table_info(cangjie)")
        try require(cangjieColumns.count == 2 && cangjieColumns[0]["name"] == "code" && cangjieColumns[0]["type"] == "TEXT" && cangjieColumns[0]["notnull"] == "1" && cangjieColumns[0]["pk"] == "1" && cangjieColumns[1]["name"] == "candidates" && cangjieColumns[1]["type"] == "TEXT" && cangjieColumns[1]["notnull"] == "1" && cangjieColumns[1]["pk"] == "0", "cangjie structure")
        try verifyCanonicalCangjie(database)

        let sourceRoot = root.appendingPathComponent("HybridIME")
        try compare("association", expectedAssociations(sourceRoot), queryDictionary(database, "SELECT language, key, candidates FROM association"))
        try compare("bilingual", expectedBilingual(sourceRoot), queryDictionary(database, "SELECT direction, key, candidates FROM bilingual"))
        print("Static lexicon: PASS (cangjie 33318, association and bilingual source-equal)")
    }

    private static func expectedAssociations(_ sourceRoot: URL) throws -> [String: String] { var expected: [String: String] = [:]; for (language, name) in [("0", "chinese-associations.tsv"), ("1", "english-associations.tsv")] { for fields in try rows(sourceRoot.appendingPathComponent("AssociationData/\(name)")) { guard fields.count >= 3, !fields.count.isMultiple(of: 2), Array(fields.dropFirst()).allSatisfy({ !$0.isEmpty }) else { throw Failure("invalid association row") }; expected[language + "\u{0}" + fields[0]] = Array(fields.dropFirst()).joined(separator: "\t") } }; return expected }
    private static func expectedBilingual(_ sourceRoot: URL) throws -> [String: String] { var expected: [String: String] = [:]; for fields in try rows(sourceRoot.appendingPathComponent("DictionaryData/cedict-index.tsv")) { guard fields.count >= 3, fields[0] == "e" || fields[0] == "z" else { throw Failure("invalid cedict row") }; let direction = fields[0] == "e" ? "0" : "1"; let key = direction == "0" ? fields[1].lowercased() : fields[1]; expected[direction + "\u{0}" + key] = try candidates(Array(fields.dropFirst(2))).joined(separator: "\t") }; for fields in try rows(sourceRoot.appendingPathComponent("DictionaryData/dictionary-overrides.tsv")) { guard fields.count >= 3, ["add-e", "add-z", "replace-e", "replace-z"].contains(fields[0]) else { throw Failure("invalid dictionary override") }; let direction = fields[0].hasSuffix("e") ? "0" : "1"; let key = direction == "0" ? fields[1].lowercased() : fields[1]; let identifier = direction + "\u{0}" + key; let additions = try candidates(Array(fields.dropFirst(2))); let existing = expected[identifier]?.split(separator: "\t").map(String.init) ?? []; expected[identifier] = (fields[0].hasPrefix("replace") ? additions : unique(additions + existing)).joined(separator: "\t") }; return expected }
    private static func rows(_ url: URL) throws -> [[String]] { try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \ .isNewline).compactMap { line in let text = String(line); return text.isEmpty || text.hasPrefix("#") ? nil : text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) } }
    private static func candidates(_ values: [String]) throws -> [String] { guard values.allSatisfy({ !$0.isEmpty }) else { throw Failure("empty candidate") }; return unique(values) }
    private static func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
    private static func compare(_ name: String, _ expected: [String: String], _ actual: [String: String]) throws { guard expected == actual else { let missing = expected.keys.filter { actual[$0] == nil }.prefix(3); let extra = actual.keys.filter { expected[$0] == nil }.prefix(3); throw Failure("\(name) differs; missing=\(missing), extra=\(extra)") }; print("\(name): PASS (\(actual.count) rows)") }
    private static func require(_ condition: Bool, _ description: String) throws { guard condition else { throw Failure("\(description): FAIL") }; print("\(description): PASS") }
    private static func verifyCanonicalCangjie(_ database: OpaquePointer?) throws {
        let rows = try queryRows(database, "SELECT code, candidates FROM cangjie ORDER BY code")
        var candidateCount = 0
        var fingerprint: UInt64 = 14_695_981_039_346_656_037
        for row in rows {
            guard let code = row["code"],
                  let payload = row["candidates"],
                  !code.isEmpty,
                  code.count <= 5,
                  code.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 })
            else { throw Failure("invalid canonical cangjie code") }
            let candidates = payload.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard !candidates.isEmpty,
                  candidates.allSatisfy({ $0.count == 1 }),
                  Set(candidates).count == candidates.count
            else { throw Failure("invalid canonical cangjie candidates for \(code)") }
            candidateCount += candidates.count
            for byte in "\(code)\t\(payload)\n".utf8 {
                fingerprint = (fingerprint ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        try require(candidateCount == 36_862, "cangjie candidate count")
        try require(fingerprint == 0xbbe2_c0b2_4139_27ec, "cangjie content fingerprint")
    }
    fileprivate struct Failure: Error, CustomStringConvertible { let message: String; init(_ message: String) { self.message = message }; var description: String { message } }
}

private func queryText(_ database: OpaquePointer?, _ sql: String) -> String? { var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }; defer { sqlite3_finalize(statement) }; guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }; return String(cString: value) }
private func queryInt(_ database: OpaquePointer?, _ sql: String) -> Int64? { var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }; defer { sqlite3_finalize(statement) }; guard sqlite3_step(statement) == SQLITE_ROW else { return nil }; return sqlite3_column_int64(statement, 0) }
private func queryTextColumn(_ database: OpaquePointer?, _ sql: String) -> [String] { var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }; defer { sqlite3_finalize(statement) }; var values: [String] = []; while sqlite3_step(statement) == SQLITE_ROW { if let value = sqlite3_column_text(statement, 0) { values.append(String(cString: value)) } }; return values }
private func queryRows(_ database: OpaquePointer?, _ sql: String) throws -> [[String: String]] { var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw VerifyStaticLexicon.Failure("SQLite query failed") }; defer { sqlite3_finalize(statement) }; var result: [[String: String]] = []; while sqlite3_step(statement) == SQLITE_ROW { var row: [String: String] = [:]; for index in 0..<sqlite3_column_count(statement) { guard let name = sqlite3_column_name(statement, index) else { throw VerifyStaticLexicon.Failure("invalid SQLite column") }; row[String(cString: name)] = sqlite3_column_text(statement, index).map(String.init(cString:)) ?? "" }; result.append(row) }; return result }
private func queryDictionary(_ database: OpaquePointer?, _ sql: String) throws -> [String: String] { var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw VerifyStaticLexicon.Failure("SQLite query failed") }; defer { sqlite3_finalize(statement) }; var result: [String: String] = [:]; while sqlite3_step(statement) == SQLITE_ROW { guard let kind = sqlite3_column_text(statement, 0), let key = sqlite3_column_text(statement, 1), let candidates = sqlite3_column_text(statement, 2) else { throw VerifyStaticLexicon.Failure("unexpected NULL") }; result[String(cString: kind) + "\u{0}" + String(cString: key)] = String(cString: candidates) }; return result }
