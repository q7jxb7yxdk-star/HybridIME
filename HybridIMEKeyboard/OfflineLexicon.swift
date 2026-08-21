import Foundation
import SQLite3

@MainActor
final class OfflineLexicon {
    struct WeightedCandidate {
        let text: String
        let weight: Int
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

    private var database: OpaquePointer?
    private var cache: [CacheKey: [String]] = [:]
    private var cacheOrder: [CacheKey] = []
    private let cacheLimit = 128

    init(bundle: Bundle = .main) {
        guard let url = Self.resourceURL(in: bundle) else {
            NSLog("HybridIMEKeyboard could not find hybridime-lexicon.sqlite3")
            return
        }

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            NSLog("HybridIMEKeyboard could not open the offline lexicon")
            if database != nil {
                sqlite3_close(database)
                database = nil
            }
            return
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func chineseCandidates(for english: String, limit: Int = 10) -> [String] {
        candidates(
            table: "bilingual",
            kindColumn: "direction",
            kind: 0,
            key: english.lowercased(),
            limit: limit
        )
    }

    func englishCandidates(for chinese: String, limit: Int = 10) -> [String] {
        candidates(
            table: "bilingual",
            kindColumn: "direction",
            kind: 1,
            key: chinese,
            limit: limit
        )
    }

    func associationCandidates(
        language: AssociationLanguage,
        key: String
    ) -> [WeightedCandidate] {
        let fields = candidates(
            table: "association",
            kindColumn: "language",
            kind: language.rawValue,
            key: key,
            limit: .max
        )
        guard fields.count >= 2 else { return [] }

        return stride(from: 0, to: fields.count - 1, by: 2).compactMap { index in
            guard let weight = Int(fields[index + 1]) else { return nil }
            return WeightedCandidate(text: fields[index], weight: weight)
        }
    }

    private func candidates(
        table: String,
        kindColumn: String,
        kind: Int,
        key: String,
        limit: Int
    ) -> [String] {
        guard limit > 0, !key.isEmpty, database != nil else { return [] }
        let cacheKey = CacheKey(table: table, kind: kind, key: key)
        if let cached = cache[cacheKey] {
            return Array(cached.prefix(limit))
        }

        let sql = "SELECT candidates FROM \(table) WHERE \(kindColumn) = ? AND key = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(kind))
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 2, key, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_text(statement, 0)
        else {
            store([], for: cacheKey)
            return []
        }

        let result = String(cString: bytes).components(separatedBy: "\t")
        store(result, for: cacheKey)
        return Array(result.prefix(limit))
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

    nonisolated private static func resourceURL(in bundle: Bundle) -> URL? {
        bundle.url(
            forResource: "hybridime-lexicon",
            withExtension: "sqlite3",
            subdirectory: "LexiconData"
        ) ?? bundle.url(
            forResource: "hybridime-lexicon",
            withExtension: "sqlite3"
        )
    }
}
