import Foundation

@MainActor
struct BilingualDictionary {
    static let shared = BilingualDictionary()

    private let englishToChinese: [String: [String]]
    private let chineseToEnglish: [String: [String]]

    init(bundle: Bundle = .main) {
        let tables = Self.loadTables(from: bundle)
        englishToChinese = tables.englishToChinese
        chineseToEnglish = tables.chineseToEnglish
    }

    func chineseCandidates(for english: String, limit: Int = 10) -> [String] {
        guard limit > 0 else { return [] }
        return Array(
            (englishToChinese[english.lowercased()] ?? []).prefix(limit)
        )
    }

    func englishCandidates(for chinese: String, limit: Int = 10) -> [String] {
        guard limit > 0 else { return [] }
        return Array((chineseToEnglish[chinese] ?? []).prefix(limit))
    }

    private static func loadTables(
        from bundle: Bundle
    ) -> (
        englishToChinese: [String: [String]],
        chineseToEnglish: [String: [String]]
    ) {
        guard
            let url = bundle.url(
                forResource: "cedict-index",
                withExtension: "tsv",
                subdirectory: "DictionaryData"
            ) ?? bundle.url(
                forResource: "cedict-index",
                withExtension: "tsv"
            ),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            NSLog("HybridIME could not load cedict-index.tsv")
            return ([:], [:])
        }

        var englishToChinese: [String: [String]] = [:]
        var chineseToEnglish: [String: [String]] = [:]

        for line in contents.split(whereSeparator: \.isNewline) {
            guard line.first != "#" else { continue }
            let fields = line.split(
                separator: "\t",
                omittingEmptySubsequences: false
            )
            guard fields.count >= 3 else { continue }

            let direction = fields[0]
            let key = String(fields[1])
            let candidates = fields.dropFirst(2).map(String.init)
            switch direction {
            case "e":
                englishToChinese[key] = candidates
            case "z":
                chineseToEnglish[key] = candidates
            default:
                continue
            }
        }
        applyOverrides(
            from: bundle,
            englishToChinese: &englishToChinese,
            chineseToEnglish: &chineseToEnglish
        )
        return (englishToChinese, chineseToEnglish)
    }

    private static func applyOverrides(
        from bundle: Bundle,
        englishToChinese: inout [String: [String]],
        chineseToEnglish: inout [String: [String]]
    ) {
        guard
            let url = bundle.url(
                forResource: "dictionary-overrides",
                withExtension: "tsv",
                subdirectory: "DictionaryData"
            ) ?? bundle.url(
                forResource: "dictionary-overrides",
                withExtension: "tsv"
            ),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            guard line.first != "#" else { continue }
            let fields = line.split(separator: "\t")
            guard fields.count >= 3 else { continue }

            let operation = fields[0]
            let key = String(fields[1])
            let candidates = fields.dropFirst(2).map(String.init)
            switch operation {
            case "add-e":
                moveToFront(
                    candidates,
                    for: key.lowercased(),
                    in: &englishToChinese
                )
            case "add-z":
                moveToFront(candidates, for: key, in: &chineseToEnglish)
            case "replace-e":
                englishToChinese[key.lowercased()] = unique(candidates)
            case "replace-z":
                chineseToEnglish[key] = unique(candidates)
            default:
                continue
            }
        }
    }

    private static func moveToFront(
        _ candidates: [String],
        for key: String,
        in table: inout [String: [String]]
    ) {
        for candidate in candidates.reversed() {
            table[key, default: []].removeAll { $0 == candidate }
            table[key, default: []].insert(candidate, at: 0)
        }
    }

    private static func unique(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }
}
