import Foundation
import CoreText

struct CangjieDecoder: @unchecked Sendable {
    nonisolated private static let resourceName = "hybrid-cangjie5.dict"
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

        guard
            let url = resourceURL(in: bundle),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            NSLog("HybridIME could not load \(resourceName).tsv")
            return table
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            guard line.first != "#" else { continue }

            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }

            let code = String(fields[0]).lowercased()
            let candidates = fields.dropFirst().map(String.init)

            guard
                !code.isEmpty,
                code.allSatisfy({ $0.isASCII && $0.isLowercase }),
                candidates.allSatisfy({ $0.count == 1 })
            else {
                continue
            }

            var seen: Set<String> = []
            table[code] = candidates.filter { seen.insert($0).inserted }
        }

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

    nonisolated private static func resourceURL(
        in bundle: Bundle
    ) -> URL? {
        bundle.url(
            forResource: resourceName,
            withExtension: "tsv",
            subdirectory: "CangjieData"
        ) ?? bundle.url(
            forResource: resourceName,
            withExtension: "tsv"
        )
    }
}
