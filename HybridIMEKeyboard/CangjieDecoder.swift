import Foundation
import CoreText

struct CangjieDecoder: @unchecked Sendable {
    private static let glyphAvailabilityCache = NSCache<NSString, NSNumber>()
    private static let baseFont = CTFontCreateUIFontForLanguage(
        .system,
        17,
        nil
    ) ?? CTFontCreateWithName("Helvetica" as CFString, 17, nil)

    private let lexicon: OfflineLexicon

    init(lexicon: OfflineLexicon) {
        self.lexicon = lexicon
    }

    @MainActor
    func candidates(for code: String, limit: Int = 10) -> [CangjieCandidate] {
        guard limit > 0 else { return [] }
        let staticCandidates = lexicon.cangjieCandidates(codePrefix: code)
        var result: [CangjieCandidate] = []
        var seen: Set<String> = []
        for candidate in staticCandidates {
            guard seen.insert(candidate.text).inserted else { continue }
            result.append(
                CangjieCandidate(text: candidate.text, code: candidate.code)
            )
            if result.count == limit { break }
        }
        return result
    }

    @MainActor
    func visibleCandidates(
        _ candidates: [CangjieCandidate],
        limit: Int
    ) -> [CangjieCandidate] {
        guard limit > 0 else { return [] }
        return Array(candidates.lazy.filter { Self.hasGlyph(for: $0.text) }.prefix(limit))
    }

    @MainActor
    func rootCandidate(for code: String) -> CangjieCandidate? {
        guard let root = code.lowercased().first else { return nil }
        return lexicon.cangjieCandidates(for: String(root), limit: .max)
            .first(where: Self.hasGlyph)
            .map { CangjieCandidate(text: $0, code: String(root)) }
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
