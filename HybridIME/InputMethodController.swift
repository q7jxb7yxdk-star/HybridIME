import AppKit
import InputMethodKit

@objc(HybridIMEInputController)
@MainActor
final class InputMethodController: IMKInputController {
    private enum CandidateAction {
        case commit(String)
        case translate(String, replacingPrefixUTF16Length: Int)
        case associate(AssociationDictionary.Suggestion)

        var text: String {
            switch self {
            case .commit(let text), .translate(let text, _):
                text
            case .associate(let suggestion):
                suggestion.text
            }
        }

        var isTranslation: Bool {
            if case .translate = self {
                return true
            }
            return false
        }
    }

    private let decoder = CangjieDecoder()
    private let bilingualDictionary = BilingualDictionary.shared
    private let associationDictionary = AssociationDictionary.shared
    private var buffer = ""
    private var currentCandidates: [String] = []
    private var currentCandidateActions: [CandidateAction] = []
    private var isSelectingPunctuation = false
    private var isSelectingAssociation = false
    private var associationContext = ""
    private var associationLanguage: AssociationDictionary.Language?
    private var lastCommittedCharacter: Character?

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            dismissAssociation(clearContext: true)
            return false
        }

        switch event.keyCode {
        case 49:
            if isSelectingAssociation {
                dismissAssociation(clearContext: true)
                return false
            }
            guard !buffer.isEmpty else { return false }
            if isSelectingPunctuation {
                commitCandidate(at: 0, to: sender)
            } else {
                commitEnglish(to: sender, appendingSpace: true)
            }
            return true
        case 36, 76:
            guard !buffer.isEmpty || isSelectingAssociation else {
                return false
            }
            commitCandidate(at: 0, to: sender)
            return true
        case 51:
            if isSelectingAssociation {
                dismissAssociation(clearContext: true)
                return false
            }
            guard !buffer.isEmpty else { return false }
            if isSelectingPunctuation {
                clearComposition()
                return true
            }
            buffer.removeLast()
            refreshComposition(client: sender)
            return true
        case 53:
            if isSelectingAssociation {
                dismissAssociation(clearContext: true)
                return true
            }
            guard !buffer.isEmpty else { return false }
            clearComposition()
            return true
        default:
            break
        }

        if
            let index = candidateIndex(for: event),
            !buffer.isEmpty || isSelectingAssociation
        {
            commitCandidate(at: index, to: sender)
            return true
        }

        if
            let character = event.characters?.first,
            let punctuation = punctuationPair(for: character)
        {
            dismissAssociation(clearContext: true)
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
            dismissAssociation(clearContext: true)
            if !buffer.isEmpty {
                commitDefault(to: sender)
            }
            return false
        }

        dismissAssociation(clearContext: false)
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
        if let index = currentCandidates.firstIndex(of: candidateString.string) {
            commitCandidate(at: index, to: client())
        } else {
            commit(candidateString.string, to: client())
        }
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
        isSelectingAssociation = false
        isSelectingPunctuation = false
        let dictionaryCandidates = bilingualDictionary.chineseCandidates(
            for: buffer,
            limit: 10
        )
        let cangjieCandidates = buffer.count <= 5
            ? decoder.candidates(for: buffer.lowercased(), limit: 10)
            : []
        currentCandidateActions = candidateActions(
            dictionaryCandidates: dictionaryCandidates,
            cangjieCandidates: cangjieCandidates,
            client: sender as? IMKTextInput,
            limit: 10
        )
        currentCandidates = currentCandidateActions.map(\.text)
        updateComposition()

        if buffer.isEmpty {
            CandidateWindowController.shared.hide()
        } else {
            CandidateWindowController.shared.show(
                code: buffer,
                candidates: currentCandidates,
                translationIndices: Set(
                    currentCandidateActions.indices.filter {
                        currentCandidateActions[$0].isTranslation
                    }
                ),
                client: sender as? IMKTextInput
            )
        }
    }

    private func candidateActions(
        dictionaryCandidates: [String],
        cangjieCandidates: [String],
        client: IMKTextInput?,
        limit: Int
    ) -> [CandidateAction] {
        var result: [CandidateAction] = []
        var seen: Set<String> = []

        func append(_ action: CandidateAction) {
            guard result.count < limit, seen.insert(action.text).inserted else {
                return
            }
            result.append(action)
        }

        let precedingChinese = chineseTextBeforeComposition(in: client)
        for candidate in cangjieCandidates where result.count < limit {
            append(.commit(candidate))

            let lookup = longestTranslationLookup(
                precedingChinese: precedingChinese,
                candidate: candidate
            )
            for translation in lookup.translations.prefix(2) {
                append(
                    .translate(
                        translation,
                        replacingPrefixUTF16Length: lookup.prefix.utf16.count
                    )
                )
            }
        }
        for candidate in dictionaryCandidates {
            append(.commit(candidate))
        }
        return result
    }

    private func longestTranslationLookup(
        precedingChinese: String,
        candidate: String
    ) -> (prefix: String, translations: [String]) {
        let characters = Array(precedingChinese)
        for length in stride(from: characters.count, through: 0, by: -1) {
            let prefix = String(characters.suffix(length))
            let translations = bilingualDictionary.englishCandidates(
                for: prefix + candidate,
                limit: 2
            )
            if !translations.isEmpty {
                return (prefix, translations)
            }
        }
        return ("", [])
    }

    private func chineseTextBeforeComposition(
        in client: IMKTextInput?
    ) -> String {
        guard let textClient = client as? NSTextInputClient else {
            return ""
        }

        let markedRange = textClient.markedRange()
        let selection = textClient.selectedRange()
        let compositionLocation = markedRange.location != NSNotFound
            ? markedRange.location
            : selection.location
        guard compositionLocation != NSNotFound, compositionLocation > 0 else {
            return ""
        }

        let maximumUTF16Length = 24
        let start = max(0, compositionLocation - maximumUTF16Length)
        guard let text = textClient.attributedSubstring(
            forProposedRange: NSRange(
                location: start,
                length: compositionLocation - start
            ),
            actualRange: nil
        )?.string else {
            return ""
        }

        return String(text.reversed().prefix(while: isChinese).reversed())
    }

    private func clearComposition() {
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        isSelectingPunctuation = false
        isSelectingAssociation = false
        associationContext = ""
        associationLanguage = nil
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
        guard currentCandidateActions.indices.contains(index) else {
            commitEnglish(to: sender)
            return
        }
        switch currentCandidateActions[index] {
        case .commit(let text):
            commit(text, to: sender)
        case .translate(let text, let prefixLength):
            commitTranslation(
                text,
                replacingPrefixUTF16Length: prefixLength,
                to: sender
            )
        case .associate(let suggestion):
            associationDictionary.recordSelection(suggestion)
            commitAssociation(suggestion, to: sender)
        }
    }

    private func commit(_ text: String, to sender: Any?) {
        (sender as? IMKTextInput)?.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        lastCommittedCharacter = text.last
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        isSelectingPunctuation = false
        isSelectingAssociation = false

        if let language = associationLanguage(for: text) {
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let context: String
            if associationLanguage == language, !associationContext.isEmpty {
                context = language == .chinese
                    ? associationContext + cleanText
                    : cleanText
            } else {
                context = cleanText
            }
            showAssociations(
                context: context,
                language: language,
                client: sender as? IMKTextInput
            )
        } else {
            dismissAssociation(clearContext: true)
        }
    }

    private func commitTranslation(
        _ text: String,
        replacingPrefixUTF16Length prefixLength: Int,
        to sender: Any?
    ) {
        guard
            prefixLength > 0,
            let textClient = sender as? NSTextInputClient
        else {
            commit(text, to: sender)
            return
        }

        let markedRange = textClient.markedRange()
        let selection = textClient.selectedRange()
        let compositionLocation = markedRange.location != NSNotFound
            ? markedRange.location
            : selection.location
        guard
            compositionLocation != NSNotFound,
            compositionLocation >= prefixLength
        else {
            commit(text, to: sender)
            return
        }

        let compositionLength = markedRange.location != NSNotFound
            ? markedRange.length
            : 0
        (sender as? IMKTextInput)?.insertText(
            text,
            replacementRange: NSRange(
                location: compositionLocation - prefixLength,
                length: prefixLength + compositionLength
            )
        )
        lastCommittedCharacter = text.last
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        isSelectingPunctuation = false
        isSelectingAssociation = false
        showAssociations(
            context: text,
            language: .english,
            client: sender as? IMKTextInput
        )
    }

    private func commitAssociation(
        _ suggestion: AssociationDictionary.Suggestion,
        to sender: Any?
    ) {
        let insertedText = suggestion.language == .english
            ? suggestion.text + " "
            : suggestion.text
        (sender as? IMKTextInput)?.insertText(
            insertedText,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        lastCommittedCharacter = insertedText.last

        let context = suggestion.language == .chinese
            ? associationContext + suggestion.text
            : suggestion.text
        showAssociations(
            context: context,
            language: suggestion.language,
            client: sender as? IMKTextInput
        )
    }

    private func showAssociations(
        context: String,
        language: AssociationDictionary.Language,
        client: IMKTextInput?
    ) {
        let suggestions = associationDictionary.suggestions(
            for: context,
            language: language,
            limit: 10
        )
        guard !suggestions.isEmpty else {
            dismissAssociation(clearContext: true)
            return
        }

        associationContext = context
        associationLanguage = language
        currentCandidateActions = suggestions.map(CandidateAction.associate)
        currentCandidates = suggestions.map(\.text)
        isSelectingAssociation = true
        isSelectingPunctuation = false
        CandidateWindowController.shared.showAssociations(
            candidates: currentCandidates,
            client: client
        )
    }

    private func dismissAssociation(clearContext: Bool) {
        guard isSelectingAssociation || clearContext else { return }
        isSelectingAssociation = false
        currentCandidates = []
        currentCandidateActions = []
        CandidateWindowController.shared.hide()
        if clearContext {
            associationContext = ""
            associationLanguage = nil
        }
    }

    private func associationLanguage(
        for text: String
    ) -> AssociationDictionary.Language? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy(isChinese) {
            return .chinese
        }
        if trimmed.allSatisfy({
            $0.isASCII && ($0.isLetter || $0 == "'" || $0.isWhitespace)
        }) {
            return .english
        }
        return nil
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
        dismissAssociation(clearContext: true)
        let useFullWidth = characterBeforeCursor(in: client).map(isChinese) ?? false
        let defaultCandidate = useFullWidth
            ? punctuation.chineseDefault ?? punctuation.fullWidth
            : punctuation.halfWidth
        currentCandidates = [defaultCandidate]
        currentCandidates.append(
            contentsOf: punctuation.candidates.filter { $0 != defaultCandidate }
        )
        currentCandidateActions = currentCandidates.map(CandidateAction.commit)
        buffer = currentCandidates[0]
        isSelectingPunctuation = true
        isSelectingAssociation = false
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
