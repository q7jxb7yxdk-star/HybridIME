import Foundation
import CoreText

struct CangjieDecoder: @unchecked Sendable {
    private static let glyphAvailabilityCache = NSCache<NSString, NSNumber>()
    private static let baseFont = CTFontCreateUIFontForLanguage(
        .system,
        17,
        nil
    ) ?? CTFontCreateWithName("Helvetica" as CFString, 17, nil)

    private let lexicon: StaticLexicon

    nonisolated init(lexicon: StaticLexicon) {
        self.lexicon = lexicon
    }

    @MainActor
    func candidates(for code: String, limit: Int = 10) -> [String] {
        guard limit > 0 else { return [] }
        return Array(
            lexicon.cangjieCandidates(code: code, limit: .max)
                .lazy
                .filter(Self.hasGlyph)
                .prefix(limit)
        )
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
}
