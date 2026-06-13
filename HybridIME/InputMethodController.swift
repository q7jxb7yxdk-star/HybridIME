import AppKit
import InputMethodKit

@objc(HybridIMEInputController)
@MainActor
final class InputMethodController: IMKInputController {
    private let decoder = CangjieDecoder()
    private let bilingualDictionary = BilingualDictionary.shared
    private var buffer = ""
    private var currentCandidates: [String] = []
    private var isSelectingPunctuation = false
    private var lastCommittedCharacter: Character?

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            commitDefault(to: sender)
            return false
        }

        switch event.keyCode {
        case 49:
            guard !buffer.isEmpty else { return false }
            if isSelectingPunctuation {
                commitCandidate(at: 0, to: sender)
            } else {
                commitEnglish(to: sender, appendingSpace: true)
            }
            return true
        case 36, 76:
            guard !buffer.isEmpty else { return false }
            commitCandidate(at: 0, to: sender)
            return true
        case 51:
            guard !buffer.isEmpty else { return false }
            if isSelectingPunctuation {
                clearComposition()
                return true
            }
            buffer.removeLast()
            refreshComposition(client: sender)
            return true
        case 53:
            guard !buffer.isEmpty else { return false }
            clearComposition()
            return true
        default:
            break
        }

        if let index = candidateIndex(for: event), !buffer.isEmpty {
            commitCandidate(at: index, to: sender)
            return true
        }

        if
            let character = event.characters?.first,
            let punctuation = punctuationPair(for: character)
        {
            if !buffer.isEmpty {
                commitDefault(to: sender)
            }
            beginPunctuationSelection(
                punctuation,
                client: sender as? IMKTextInput
            )
            return true
        }

        if isSelectingPunctuation {
            commitCandidate(at: 0, to: sender)
        }

        guard
            let characters = event.characters,
            characters.count == 1,
            characters.unicodeScalars.allSatisfy({
                CharacterSet.letters.contains($0) && $0.isASCII
            })
        else {
            if !buffer.isEmpty {
                commitDefault(to: sender)
            }
            return false
        }

        isSelectingPunctuation = false
        buffer.append(characters)
        refreshComposition(client: sender)
        return true
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        currentCandidates
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let candidateString else { return }
        commit(candidateString.string, to: client())
    }

    override func commitComposition(_ sender: Any!) {
        commitDefault(to: sender)
    }

    override func composedString(_ sender: Any!) -> Any! {
        buffer
    }

    override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: buffer)
    }

    private func refreshComposition(client sender: Any?) {
        isSelectingPunctuation = false
        let dictionaryCandidates = bilingualDictionary.chineseCandidates(
            for: buffer,
            limit: 10
        )
        let cangjieCandidates = buffer.count <= 5
            ? decoder.candidates(for: buffer.lowercased(), limit: 10)
            : []
        currentCandidates = mergedCandidates(
            dictionaryCandidates,
            cangjieCandidates,
            limit: 10
        )
        updateComposition()

        if buffer.isEmpty {
            CandidateWindowController.shared.hide()
        } else {
            CandidateWindowController.shared.show(
                code: buffer,
                candidates: currentCandidates,
                client: sender as? IMKTextInput
            )
        }
    }

    private func mergedCandidates(
        _ groups: [String]...,
        limit: Int
    ) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for candidate in groups.joined() where seen.insert(candidate).inserted {
            result.append(candidate)
            if result.count == limit {
                break
            }
        }
        return result
    }

    private func clearComposition() {
        buffer = ""
        currentCandidates = []
        isSelectingPunctuation = false
        updateComposition()
        CandidateWindowController.shared.hide()
    }

    private func commitEnglish(to sender: Any?, appendingSpace: Bool = false) {
        guard !buffer.isEmpty else { return }
        commit(buffer + (appendingSpace ? " " : ""), to: sender)
    }

    private func commitDefault(to sender: Any?) {
        if isSelectingPunctuation {
            commitCandidate(at: 0, to: sender)
        } else {
            commitEnglish(to: sender)
        }
    }

    private func commitCandidate(at index: Int, to sender: Any?) {
        guard currentCandidates.indices.contains(index) else {
            commitEnglish(to: sender)
            return
        }
        commit(currentCandidates[index], to: sender)
    }

    private func commit(_ text: String, to sender: Any?) {
        (sender as? IMKTextInput)?.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        lastCommittedCharacter = text.last
        buffer = ""
        currentCandidates = []
        isSelectingPunctuation = false
        CandidateWindowController.shared.hide()
    }

    private func beginPunctuationSelection(
        _ punctuation: (
            halfWidth: String,
            fullWidth: String,
            candidates: [String],
            chineseDefault: String?
        ),
        client: IMKTextInput?
    ) {
        let useFullWidth = characterBeforeCursor(in: client).map(isChinese) ?? false
        let defaultCandidate = useFullWidth
            ? punctuation.chineseDefault ?? punctuation.fullWidth
            : punctuation.halfWidth
        currentCandidates = [defaultCandidate]
        currentCandidates.append(
            contentsOf: punctuation.candidates.filter { $0 != defaultCandidate }
        )
        buffer = currentCandidates[0]
        isSelectingPunctuation = true
        updateComposition()
        CandidateWindowController.shared.showPunctuation(
            candidates: currentCandidates,
            client: client
        )
    }

    private func characterBeforeCursor(in client: IMKTextInput?) -> Character? {
        guard let textClient = client as? NSTextInputClient else {
            return lastCommittedCharacter
        }

        let selection = textClient.selectedRange()
        guard
            selection.location != NSNotFound,
            selection.location > 0,
            let substring = textClient.attributedSubstring(
                forProposedRange: NSRange(
                    location: selection.location - 1,
                    length: 1
                ),
                actualRange: nil
            )?.string,
            let character = substring.last
        else {
            return lastCommittedCharacter
        }
        return character
    }

    private func isChinese(_ character: Character) -> Bool {
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

    private func punctuationPair(
        for character: Character
    ) -> (
        halfWidth: String,
        fullWidth: String,
        candidates: [String],
        chineseDefault: String?
    )? {
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
        return (
            String(character),
            String(fullWidth),
            candidates,
            chineseDefault
        )
    }

    private func candidateIndex(for event: NSEvent) -> Int? {
        guard let character = event.charactersIgnoringModifiers?.first else {
            return nil
        }
        if character == "0" {
            return 9
        }
        guard let number = character.wholeNumberValue, (1...9).contains(number) else {
            return nil
        }
        return number - 1
    }
}
