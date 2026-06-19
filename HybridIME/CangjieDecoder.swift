import Foundation
import CoreText

struct CangjieDecoder: @unchecked Sendable {
    nonisolated private static let resourceNames = [
        "cangjie5.base.dict",
        "cangjie5.extended.dict",
    ]
    private static let glyphAvailabilityCache = NSCache<NSString, NSNumber>()
    private static let baseFont = CTFontCreateUIFontForLanguage(
        .system,
        17,
        nil
    ) ?? CTFontCreateWithName("Helvetica" as CFString, 17, nil)

    private let table: [String: [String]]

    nonisolated init(bundle: Bundle = .main) {
        table = Self.loadTable(from: bundle)
    }

    @MainActor
    func candidates(for code: String, limit: Int = 10) -> [String] {
        guard limit > 0 else { return [] }
        return Array(
            (table[code.lowercased()] ?? [])
                .lazy
                .filter(Self.hasGlyph)
                .prefix(limit)
        )
    }

    nonisolated private static func loadTable(
        from bundle: Bundle
    ) -> [String: [String]] {
        var table: [String: [String]] = [:]
        var seenByCode: [String: Set<String>] = [:]

        for resourceName in resourceNames {
            guard
                let url = resourceURL(
                    named: resourceName,
                    in: bundle
                ),
                let contents = try? String(contentsOf: url, encoding: .utf8)
            else {
                NSLog("HybridIME could not load \(resourceName).yaml")
                continue
            }

            for line in contents.split(whereSeparator: \.isNewline) {
                guard
                    !line.isEmpty,
                    line.first != "#",
                    let tabIndex = line.firstIndex(of: "\t")
                else {
                    continue
                }

                let character = String(line[..<tabIndex])
                let codeStart = line.index(after: tabIndex)
                let code = line[codeStart...]
                    .prefix(while: { $0 != "\t" })
                    .lowercased()

                guard
                    character.count == 1,
                    !code.isEmpty,
                    code.allSatisfy({ $0.isASCII && $0.isLowercase })
                else {
                    continue
                }

                if seenByCode[code, default: []].insert(character).inserted {
                    table[code, default: []].append(character)
                }
            }
        }

        applyOverrides(from: bundle, to: &table)
        return table
    }

    private static func hasGlyph(for character: String) -> Bool {
        if let cached = glyphAvailabilityCache.object(
            forKey: character as NSString
        ) {
            return cached.boolValue
        }

        let replacement = CTFontCreateForString(
            baseFont,
            character as CFString,
            CFRange(location: 0, length: character.utf16.count)
        )
        guard CTFontCopyPostScriptName(replacement) != "LastResort" as CFString else {
            glyphAvailabilityCache.setObject(
                false,
                forKey: character as NSString
            )
            return false
        }

        var characters = Array(character.utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)

        let result = CTFontGetGlyphsForCharacters(
            replacement,
            &characters,
            &glyphs,
            characters.count
        ) && glyphs.contains { $0 != 0 }
        glyphAvailabilityCache.setObject(
            NSNumber(value: result),
            forKey: character as NSString
        )
        return result
    }

    nonisolated private static func applyOverrides(
        from bundle: Bundle,
        to table: inout [String: [String]]
    ) {
        guard
            let url = bundle.url(
                forResource: "macOS-overrides",
                withExtension: "tsv"
            ),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            NSLog("HybridIME could not load macOS-overrides.tsv")
            return
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            guard line.first != "#" else { continue }

            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }

            let operation = fields[0]
            let code = fields[1].lowercased()
            let candidates = fields.dropFirst(2).map(String.init)

            guard
                !code.isEmpty,
                code.allSatisfy({ $0.isASCII && $0.isLowercase }),
                candidates.allSatisfy({ $0.count == 1 })
            else {
                continue
            }

            switch operation {
            case "add":
                for candidate in candidates.reversed() {
                    table[code, default: []].removeAll { $0 == candidate }
                    table[code, default: []].insert(candidate, at: 0)
                }
            case "remove":
                let candidatesToRemove = Set(candidates)
                table[code]?.removeAll { candidatesToRemove.contains($0) }
            case "replace":
                var seen: Set<String> = []
                table[code] = candidates.filter { seen.insert($0).inserted }
            default:
                continue
            }
        }
    }

    nonisolated private static func resourceURL(
        named resourceName: String,
        in bundle: Bundle
    ) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: "yaml",
            subdirectory: "CangjieData"
        ) ?? bundle.url(
            forResource: resourceName,
            withExtension: "yaml"
        )
    }
}
