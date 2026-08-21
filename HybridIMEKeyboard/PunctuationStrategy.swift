import Foundation

struct PunctuationDefinition {
    let halfWidth: String
    let fullWidth: String
    let candidates: [String]
    let chineseDefault: String?
}

enum PunctuationStrategy {
    private static let labeledHalfWidthPunctuation: Set<String> = [
        "`", "~", "!", "%", "^", "&", "(", ")", "-", "+", "\\",
        "|", ";", ":", "'", "\"", "/", "?", "@", "#",
    ]

    static func definition(for text: String) -> PunctuationDefinition? {
        guard text.count == 1, let character = text.first else { return nil }
        return definition(for: character)
    }

    static func defaultCandidate(
        for punctuation: PunctuationDefinition,
        useFullWidth: Bool
    ) -> String {
        if punctuation.chineseDefault == punctuation.halfWidth {
            return punctuation.halfWidth
        }
        guard useFullWidth else { return punctuation.halfWidth }
        return punctuation.chineseDefault ?? punctuation.fullWidth
    }

    static func orderedCandidates(
        for punctuation: PunctuationDefinition,
        defaultCandidate: String
    ) -> [String] {
        [defaultCandidate] + punctuation.candidates.filter { $0 != defaultCandidate }
    }

    static func displayTitle(
        for candidate: String,
        punctuation: PunctuationDefinition
    ) -> String {
        guard labeledHalfWidthPunctuation.contains(punctuation.halfWidth) else {
            return candidate
        }
        if candidate == punctuation.halfWidth {
            return "半 \(candidate)"
        }
        if candidate == punctuation.fullWidth {
            return "全 \(candidate)"
        }
        return candidate
    }

    static func usesFullWidth(before text: String?) -> Bool? {
        guard let text, let character = contextCharacter(in: text) else {
            return nil
        }
        return isChinese(character)
    }

    static func isChinese(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(isChinese)
    }

    private static func contextCharacter(in text: String) -> Character? {
        for character in text.suffix(64).reversed() {
            if character.isWhitespace || character.isNewline {
                continue
            }
            if isChinese(character) {
                return character
            }
            if character.isASCII && (character.isLetter || character.isNumber) {
                return character
            }
            if ".!?。！？,，、;；:：".contains(character) {
                break
            }
        }
        return nil
    }

    private static func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3007,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2FA1F,
                 0x30000...0x323AF:
                true
            default:
                false
            }
        }
    }

    private static func definition(for character: Character) -> PunctuationDefinition? {
        let fullWidthByHalfWidth: [Character: Character] = [
            "!": "！", "\"": "＂", "#": "＃", "$": "＄",
            "%": "％", "&": "＆", "'": "＇", "(": "（",
            ")": "）", "*": "＊", "+": "＋", ",": "，",
            "-": "－", ".": "。", "/": "／", ":": "：",
            ";": "；", "<": "＜", "=": "＝", ">": "＞",
            "?": "？", "@": "＠", "[": "［", "\\": "＼",
            "]": "］", "^": "＾", "_": "＿", "`": "｀",
            "{": "｛", "|": "｜", "}": "｝", "~": "～",
        ]
        guard let fullWidth = fullWidthByHalfWidth[character] else {
            return nil
        }

        let candidates: [String]
        let chineseDefault: String?
        switch character {
        case "$":
            candidates = ["$", "¥", "£", "€", "₹", "₺", "＄"]
            chineseDefault = "$"
        case "\"", "'", "#", "%", "&", "+", "-", "=", "@", "^", "`", "|":
            candidates = [String(character), String(fullWidth)]
            chineseDefault = String(character)
        case ".":
            candidates = [".", "。", "⋯⋯"]
            chineseDefault = nil
        case ",":
            candidates = [",", "，", "、"]
            chineseDefault = nil
        case "*":
            candidates = ["*", "＊", "×"]
            chineseDefault = "*"
        case "/":
            candidates = ["/", "／", "÷"]
            chineseDefault = nil
        case "<":
            candidates = ["<", "＜", "←"]
            chineseDefault = "<"
        case ">":
            candidates = [">", "＞", "→"]
            chineseDefault = ">"
        case "[":
            candidates = ["[", "「", "〔", "［", "【", "〖"]
            chineseDefault = "「"
        case "]":
            candidates = ["]", "」", "〕", "］", "】", "〗"]
            chineseDefault = "」"
        case "{":
            candidates = ["{", "『", "｛"]
            chineseDefault = "『"
        case "}":
            candidates = ["}", "』", "｝"]
            chineseDefault = "』"
        default:
            candidates = [String(character), String(fullWidth)]
            chineseDefault = nil
        }
        return PunctuationDefinition(
            halfWidth: String(character),
            fullWidth: String(fullWidth),
            candidates: candidates,
            chineseDefault: chineseDefault
        )
    }
}
