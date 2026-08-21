import Foundation
import SQLite3

final class StaticLexicon: @unchecked Sendable {
    struct WeightedCandidate {
        let text: String
        let weight: Int
    }

    enum BilingualDirection: Int {
        case englishToChinese = 0
        case chineseToEnglish = 1
    }

    enum AssociationLanguage: Int {
        case chinese = 0
        case english = 1
    }

    private struct CacheKey: Hashable {
        let table: String
        let kind: Int
        let key: String
    }

    private let lock = NSLock()
    private var database: OpaquePointer?
    private var cache: [CacheKey: [String]] = [:]
    private var cacheOrder: [CacheKey] = []
    private let cacheLimit = 256

    init(bundle: Bundle = .main) {
        openDatabase(at: Self.resourceURL(in: bundle))
    }

    init(databaseURL: URL) {
        openDatabase(at: databaseURL)
    }

    private func openDatabase(at url: URL?) {
        guard let url else {
            NSLog("HybridIME could not find hybridime-lexicon.sqlite3")
            return
        }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            NSLog("HybridIME could not open the static lexicon")
            closeDatabase()
            return
        }
        sqlite3_exec(database, "PRAGMA query_only = ON", nil, nil, nil)
        sqlite3_exec(database, "PRAGMA cache_size = -4096", nil, nil, nil)
    }

    deinit {
        closeDatabase()
    }

    func bilingualCandidates(
        direction: BilingualDirection,
        key: String,
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }
        return Array(
            payload(
                table: "bilingual",
                kindColumn: "direction",
                kind: direction.rawValue,
                key: key
            ).prefix(limit)
        )
    }

    func longestBilingualMatch(
        direction: BilingualDirection,
        keys: [String],
        limit: Int
    ) -> (key: String, candidates: [String])? {
        guard limit > 0 else { return nil }
        guard let match = firstPayload(
            table: "bilingual",
            kindColumn: "direction",
            kind: direction.rawValue,
            keys: keys
        ) else { return nil }
        return (match.key, Array(match.payload.prefix(limit)))
    }

    func associationCandidates(
        language: AssociationLanguage,
        key: String
    ) -> [WeightedCandidate] {
        weightedCandidates(
            from: payload(
                table: "association",
                kindColumn: "language",
                kind: language.rawValue,
                key: key
            )
        )
    }

    func longestAssociationMatch(
        language: AssociationLanguage,
        keys: [String]
    ) -> (key: String, candidates: [WeightedCandidate])? {
        guard let match = firstPayload(
            table: "association",
            kindColumn: "language",
            kind: language.rawValue,
            keys: keys
        ) else { return nil }
        return (match.key, weightedCandidates(from: match.payload))
    }

    private func payload(
        table: String,
        kindColumn: String,
        kind: Int,
        key: String
    ) -> [String] {
        firstPayload(
            table: table,
            kindColumn: kindColumn,
            kind: kind,
            keys: [key]
        )?.payload ?? []
    }

    private func firstPayload(
        table: String,
        kindColumn: String,
        kind: Int,
        keys: [String]
    ) -> (key: String, payload: [String])? {
        let orderedKeys = Array(keys.filter { !$0.isEmpty }.prefix(32))
        guard !orderedKeys.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var missingKeys: [String] = []
        for key in orderedKeys {
            let cacheKey = CacheKey(table: table, kind: kind, key: key)
            if cache[cacheKey] == nil {
                missingKeys.append(key)
            }
        }
        if !missingKeys.isEmpty {
            loadPayloads(
                table: table,
                kindColumn: kindColumn,
                kind: kind,
                keys: missingKeys
            )
        }

        for key in orderedKeys {
            let cacheKey = CacheKey(table: table, kind: kind, key: key)
            if let payload = cache[cacheKey], !payload.isEmpty {
                return (key, payload)
            }
        }
        return nil
    }

    private func loadPayloads(
        table: String,
        kindColumn: String,
        kind: Int,
        keys: [String]
    ) {
        guard let database, !keys.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ",")
        let sql = "SELECT key, candidates FROM \(table) "
            + "WHERE \(kindColumn) = ? AND key IN (\(placeholders))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(kind))
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, key) in keys.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 2), key, -1, transient)
        }

        var loaded: [String: [String]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW,
              let keyBytes = sqlite3_column_text(statement, 0),
              let payloadBytes = sqlite3_column_text(statement, 1)
        {
            loaded[String(cString: keyBytes)] = String(cString: payloadBytes)
                .components(separatedBy: "\t")
        }
        for key in keys {
            store(
                loaded[key] ?? [],
                for: CacheKey(table: table, kind: kind, key: key)
            )
        }
    }

    private func weightedCandidates(from fields: [String]) -> [WeightedCandidate] {
        guard fields.count >= 2 else { return [] }
        return stride(from: 0, to: fields.count - 1, by: 2).compactMap { index in
            guard let weight = Int(fields[index + 1]) else { return nil }
            return WeightedCandidate(text: fields[index], weight: weight)
        }
    }

    private func store(_ value: [String], for key: CacheKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
        }
        cache[key] = value
        while cacheOrder.count > cacheLimit {
            let removed = cacheOrder.removeFirst()
            cache.removeValue(forKey: removed)
        }
    }

    private func closeDatabase() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    nonisolated private static func resourceURL(in bundle: Bundle) -> URL? {
        bundle.url(
            forResource: "hybridime-lexicon",
            withExtension: "sqlite3"
        )
    }
}
