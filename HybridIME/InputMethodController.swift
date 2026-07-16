import AppKit
import InputMethodKit

@objc(HybridIMEInputController)
@MainActor
final class InputMethodController: IMKInputController {
    private enum CandidateAction {
        case commit(String)
        case dictionaryCommit(String)
        case translate(String, replacingPrefixUTF16Length: Int)
        case associate(AssociationDictionary.Suggestion)

        var text: String {
            switch self {
            case .commit(let text),
                 .dictionaryCommit(let text),
                 .translate(let text, _):
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

    private var buffer = ""
    private var currentCandidates: [String] = []
    private var currentCandidateActions: [CandidateAction] = []
    private var smartPredictionIndex: Int?
    private var isEnglishCompositionContext = false
    private var isSelectingPunctuation = false
    private var isSelectingAssociation = false
    private var associationContext = ""
    private var associationLanguage: AssociationDictionary.Language?
    private var lastCommittedCharacter: Character?
    private var nextPunctuationUsesFullWidth: Bool?
    private var lastPassthroughPunctuationUsesFullWidth: Bool?
    private var learnedChineseContext = ""
    private var suppressAssociationsUntilNextInput = false

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([
            .keyDown,
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .mouseCancelled,
        ]).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else {
            resetState(updatingComposition: false)
            return false
        }

        guard event.type == .keyDown else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            learnedChineseContext = ""
            dismissAssociation(clearContext: true)
            return false
        }

        if isSpaceEvent(event) {
            return handleSpace(
                event: event,
                client: sender
            )
        }

        switch event.keyCode {
        case 36, 76:
            guard !buffer.isEmpty || isSelectingAssociation else {
                return false
            }
            if !currentCandidateActions.isEmpty {
                commitCandidate(at: 0, to: sender)
            } else {
                commitEnglish(to: sender)
            }
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
            guard !buffer.isEmpty || CandidateWindowController.shared.isVisible else {
                return false
            }
            if shouldCommitEnglishOnEscape {
                commitWithoutAssociations(
                    buffer,
                    to: sender,
                    suppressingFollowingAssociations: true
                )
                return true
            }
            cancelCompositionPreservingFocus()
            return true
        default:
            break
        }

        if shouldReleaseCompositionForSystemKey(event) {
            releaseCompositionForSystemKey()
            return false
        }

        if
            let index = candidateIndex(for: event),
            !shouldContinueNumericPunctuationInput(event),
            !isInvalidPunctuationCandidateIndex(index),
            !buffer.isEmpty || isSelectingAssociation
        {
            commitCandidate(at: index, to: sender)
            return true
        }

        if
            let character = event.characters?.first,
            let punctuation = punctuationPair(for: character)
        {
            let forceFullWidth = punctuationFullWidthPreferenceForCurrentComposition()
            learnedChineseContext = ""
            dismissAssociation(clearContext: true)
            if !buffer.isEmpty {
                commitBeforePunctuation(to: sender)
            }
            beginPunctuationSelection(
                punctuation,
                forceFullWidth: forceFullWidth,
                client: sender as? IMKTextInput
            )
            return true
        }

        if isSelectingPunctuation {
            suppressAssociationsUntilNextInput = false
            commitCandidate(at: 0, to: sender)
        }

        suppressAssociationsUntilNextInput = false
        guard
            let characters = event.characters,
            characters.count == 1,
            characters.unicodeScalars.allSatisfy({
                CharacterSet.letters.contains($0) && $0.isASCII
            })
        else {
            dismissAssociation(clearContext: true)
            if buffer.isEmpty {
                lastPassthroughPunctuationUsesFullWidth =
                    punctuationUsesFullWidthForPassthroughInput(event)
            }
            if !buffer.isEmpty {
                commitDefault(to: sender)
            }
            return false
        }

        dismissAssociation(clearContext: false)
        isSelectingPunctuation = false
        lastPassthroughPunctuationUsesFullWidth = nil
        buffer.append(characters)
        refreshComposition(client: sender)
        return true
    }

    private func isSpaceEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 49 ||
            event.characters == " " ||
            event.characters == "\u{00A0}" ||
            event.charactersIgnoringModifiers == " " ||
            event.charactersIgnoringModifiers == "\u{00A0}"
    }

    private func handleSpace(
        event: NSEvent,
        client sender: Any?
    ) -> Bool {
        let isShiftSpace =
            event.modifierFlags.contains(.shift) ||
            event.cgEvent?.flags.contains(.maskShift) == true ||
            event.characters == "\u{00A0}" ||
            event.charactersIgnoringModifiers == "\u{00A0}"
        if !isShiftSpace {
            suppressAssociationsUntilNextInput = false
        }
        if isSelectingAssociation {
            if smartPredictionIndex == 0 {
                commitCandidate(at: 0, to: sender)
                return true
            }
            dismissAssociation(clearContext: true)
            return false
        }
        guard !buffer.isEmpty else { return false }
        if isSelectingPunctuation {
            suppressAssociationsUntilNextInput = false
            commitCandidate(at: 0, to: sender)
        } else if
            !isShiftSpace,
            shouldCommitSmartPredictionOnSpace
        {
            commitCandidate(at: 0, to: sender)
        } else if
            !isShiftSpace,
            !isEnglishCompositionContext,
            let smartPredictionIndex
        {
            commitCandidate(at: smartPredictionIndex, to: sender)
        } else if isShiftSpace {
            commitWithoutAssociations(
                buffer,
                to: sender,
                suppressingFollowingAssociations: true
            )
        } else {
            commitEnglish(
                to: sender,
                appendingSpace: true
            )
        }
        return true
    }

    private var shouldCommitSmartPredictionOnSpace: Bool {
        guard smartPredictionIndex == 0 else { return false }
        guard currentCandidateActions.indices.contains(0) else { return false }
        if case .commit(let text) = currentCandidateActions[0] {
            return text.allSatisfy(isChinese)
        }
        return false
    }

    private var shouldCommitEnglishOnEscape: Bool {
        guard !isSelectingPunctuation else { return false }
        guard !buffer.isEmpty else { return false }
        return !currentCandidateActions.contains { action in
            if case .commit(let text) = action {
                return text.allSatisfy(isChinese)
            }
            return false
        }
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
        commitDefault(to: sender, showingAssociations: false)
    }

    override func deactivateServer(_ sender: Any!) {
        resetState(updatingComposition: false)
        super.deactivateServer(sender)
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
        let dictionaryCandidates = bilingualDictionary?.chineseCandidates(
            for: buffer,
            limit: 10
        ) ?? []
        let cangjieCandidates = buffer.count <= 5
            ? cangjieDecoder?.candidates(
                for: buffer.lowercased(),
                limit: 10
            ) ?? []
            : []
        currentCandidateActions = candidateActions(
            dictionaryCandidates: dictionaryCandidates,
            cangjieCandidates: cangjieCandidates,
            client: sender as? IMKTextInput,
            limit: 10
        )
        currentCandidates = currentCandidateActions.map(\.text)
        isEnglishCompositionContext = englishTextBeforeComposition(
            in: sender as? IMKTextInput
        )
        let prediction = isEnglishCompositionContext
            ? nil
            : smartCandidateRanker.prediction(
                code: buffer,
                availableCandidates: currentCandidateActions.compactMap {
                    guard case .commit(let text) = $0, text.allSatisfy(isChinese) else {
                        return nil
                    }
                    return text
                }
            )
        if
            let prediction,
            let index = currentCandidateActions.firstIndex(
                where: { $0.text == prediction.candidate }
            )
        {
            let action = currentCandidateActions.remove(at: index)
            currentCandidateActions.insert(action, at: 0)
            currentCandidates = currentCandidateActions.map(\.text)
            smartPredictionIndex = 0
        } else {
            smartPredictionIndex = nil
        }
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
                smartPredictionIndex: smartPredictionIndex,
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
            append(.dictionaryCommit(candidate))
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
            let translations = bilingualDictionary?.englishCandidates(
                for: prefix + candidate,
                limit: 2
            ) ?? []
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
        resetState(updatingComposition: true)
    }

    private func cancelCompositionPreservingFocus() {
        resetState(updatingComposition: true)
    }

    private func shouldReleaseCompositionForSystemKey(_ event: NSEvent) -> Bool {
        guard hasActiveComposition else { return false }
        let characters = event.characters ?? ""
        let charactersIgnoringModifiers = event.charactersIgnoringModifiers ?? ""
        return characters.isEmpty && charactersIgnoringModifiers.isEmpty
    }

    private var hasActiveComposition: Bool {
        !buffer.isEmpty ||
            isSelectingPunctuation ||
            isSelectingAssociation ||
            CandidateWindowController.shared.isVisible
    }

    private func releaseCompositionForSystemKey() {
        resetState(updatingComposition: true)
    }

    private func resetState(updatingComposition: Bool) {
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        smartPredictionIndex = nil
        isEnglishCompositionContext = false
        isSelectingPunctuation = false
        isSelectingAssociation = false
        associationContext = ""
        associationLanguage = nil
        learnedChineseContext = ""
        if updatingComposition {
            updateComposition()
        }
        CandidateWindowController.shared.hide()
    }

    private func commitEnglish(to sender: Any?, appendingSpace: Bool = false) {
        guard !buffer.isEmpty else { return }
        commit(buffer + (appendingSpace ? " " : ""), to: sender)
    }

    private func commitDefault(
        to sender: Any?,
        showingAssociations: Bool = true
    ) {
        if isSelectingPunctuation {
            commitCandidate(
                at: 0,
                to: sender,
                showingAssociations: showingAssociations
            )
        } else {
            if showingAssociations {
                commitEnglish(to: sender)
            } else {
                commitWithoutAssociations(buffer, to: sender)
            }
        }
    }

    private func commitBeforePunctuation(to sender: Any?) {
        if punctuationFullWidthPreferenceForCurrentComposition() == true {
            commitCandidate(
                at: 0,
                to: sender,
                showingAssociations: false
            )
        } else {
            commitWithoutAssociations(buffer, to: sender)
        }
    }

    private func commitCandidate(
        at index: Int,
        to sender: Any?,
        showingAssociations: Bool = true
    ) {
        guard currentCandidateActions.indices.contains(index) else {
            if showingAssociations {
                commitEnglish(to: sender)
            } else {
                commitWithoutAssociations(buffer, to: sender)
            }
            return
        }
        switch currentCandidateActions[index] {
        case .commit(let text):
            recordSmartSelection(text)
            if showingAssociations {
                commit(text, to: sender)
            } else {
                commitWithoutAssociations(text, to: sender)
            }
        case .dictionaryCommit(let text):
            if showingAssociations {
                commit(text, to: sender)
            } else {
                commitWithoutAssociations(text, to: sender)
            }
        case .translate(let text, let prefixLength):
            recordSmartSelection(text)
            commitTranslation(
                text,
                replacingPrefixUTF16Length: prefixLength,
                to: sender
            )
        case .associate(let suggestion):
            commitAssociation(suggestion, to: sender)
        }
    }

    private func recordSmartSelection(_ candidate: String) {
        guard
            !isSelectingPunctuation,
            !isSelectingAssociation,
            !buffer.isEmpty,
            candidate.allSatisfy(isChinese)
        else {
            return
        }
        smartCandidateRanker.record(
            code: buffer,
            candidate: candidate
        )
    }

    private func commitWithoutAssociations(
        _ text: String,
        to sender: Any?,
        suppressingFollowingAssociations: Bool = false
    ) {
        guard !text.isEmpty else {
            resetState(updatingComposition: false)
            return
        }
        suppressAssociationsUntilNextInput = suppressingFollowingAssociations
        (sender as? IMKTextInput)?.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        lastCommittedCharacter = text.last
        setNextPunctuationContext(from: text)
        learnCommittedText(text)
        resetState(updatingComposition: false)
    }

    private func commit(_ text: String, to sender: Any?) {
        (sender as? IMKTextInput)?.insertText(
            text,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        lastCommittedCharacter = text.last
        setNextPunctuationContext(from: text)
        learnCommittedText(text)
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        smartPredictionIndex = nil
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
        setNextPunctuationContext(from: text)
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        smartPredictionIndex = nil
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
        associationDictionary?.recordSelection(suggestion)
        let insertedText = suggestion.language == .english
            ? suggestion.text + " "
            : suggestion.text
        (sender as? IMKTextInput)?.insertText(
            insertedText,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        lastCommittedCharacter = insertedText.last
        setNextPunctuationContext(from: suggestion.text)
        learnCommittedText(suggestion.text)

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
        if suppressAssociationsUntilNextInput {
            dismissAssociation(clearContext: true)
            return
        }

        let suggestions = associationDictionary?.suggestions(
            for: context,
            language: language,
            limit: 10
        ) ?? []
        guard !suggestions.isEmpty else {
            dismissAssociation(clearContext: true)
            return
        }

        associationContext = context
        associationLanguage = language
        currentCandidateActions = suggestions.map(CandidateAction.associate)
        currentCandidates = suggestions.map(\.text)
        smartPredictionIndex = suggestions.firstIndex {
            $0.isMostRecentSelection
        }
        isSelectingAssociation = true
        isSelectingPunctuation = false
        CandidateWindowController.shared.showAssociations(
            candidates: currentCandidates,
            smartPredictionIndex: smartPredictionIndex,
            client: client
        )
    }

    private func dismissAssociation(clearContext: Bool) {
        guard isSelectingAssociation || clearContext else { return }
        isSelectingAssociation = false
        currentCandidates = []
        currentCandidateActions = []
        smartPredictionIndex = nil
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

    private func setNextPunctuationContext(from text: String) {
        guard let contextCharacter = punctuationContextCharacter(in: text) else {
            return
        }
        if isChinese(contextCharacter) {
            nextPunctuationUsesFullWidth = true
        } else if contextCharacter.isASCII &&
            (contextCharacter.isLetter || contextCharacter.isNumber)
        {
            nextPunctuationUsesFullWidth = false
        }
    }

    private func learnCommittedText(_ text: String) {
        guard !text.isEmpty, text.allSatisfy(isChinese) else {
            learnedChineseContext = ""
            return
        }

        for character in text {
            let continuation = String(character)
            if !learnedChineseContext.isEmpty {
                associationDictionary?.recordChineseSequence(
                    context: learnedChineseContext,
                    continuation: continuation
                )
            }
            learnedChineseContext.append(character)
            if learnedChineseContext.count > 8 {
                learnedChineseContext.removeFirst(
                    learnedChineseContext.count - 8
                )
            }
        }
    }

    private func beginPunctuationSelection(
        _ punctuation: (
            halfWidth: String,
            fullWidth: String,
            candidates: [String],
            chineseDefault: String?
        ),
        forceFullWidth: Bool? = nil,
        client: IMKTextInput?
    ) {
        dismissAssociation(clearContext: true)
        let useFullWidth = forceFullWidth
            ?? punctuationUsesFullWidthBeforeCursor(in: client)
            ?? nextPunctuationUsesFullWidth
            ?? lastPassthroughPunctuationUsesFullWidth
            ?? true
        nextPunctuationUsesFullWidth = nil
        lastPassthroughPunctuationUsesFullWidth = nil
        let defaultCandidate = defaultPunctuationCandidate(
            for: punctuation,
            useFullWidth: useFullWidth
        )
        currentCandidates = [defaultCandidate]
        currentCandidates.append(
            contentsOf: punctuation.candidates.filter { $0 != defaultCandidate }
        )
        currentCandidateActions = currentCandidates.map(CandidateAction.commit)
        smartPredictionIndex = nil
        buffer = currentCandidates[0]
        isSelectingPunctuation = true
        isSelectingAssociation = false
        updateComposition()
        CandidateWindowController.shared.showPunctuation(
            candidates: currentCandidates,
            displayCandidates: punctuationDisplayCandidates(
                for: currentCandidates,
                punctuation: punctuation
            ),
            shiftKeyCandidates: shiftKeyCandidates(
                for: currentCandidates,
                punctuation: punctuation
            ),
            client: client
        )
    }

    private func defaultPunctuationCandidate(
        for punctuation: (
            halfWidth: String,
            fullWidth: String,
            candidates: [String],
            chineseDefault: String?
        ),
        useFullWidth: Bool
    ) -> String {
        if punctuation.chineseDefault == punctuation.halfWidth {
            return punctuation.halfWidth
        }
        guard useFullWidth else {
            return punctuation.halfWidth
        }
        return punctuation.chineseDefault ?? punctuation.fullWidth
    }

    private func punctuationFullWidthPreferenceForCurrentComposition() -> Bool? {
        guard !buffer.isEmpty else { return nil }
        guard
            let firstAction = currentCandidateActions.first,
            case .commit(let text) = firstAction,
            text.allSatisfy(isChinese)
        else {
            return false
        }
        return true
    }

    private func shiftKeyCandidates(
        for candidates: [String],
        punctuation: (
            halfWidth: String,
            fullWidth: String,
            candidates: [String],
            chineseDefault: String?
        )
    ) -> [String]? {
        guard ["$", "."].contains(punctuation.halfWidth) else {
            return nil
        }
        return candidates
    }

    private func punctuationDisplayCandidates(
        for candidates: [String],
        punctuation: (
            halfWidth: String,
            fullWidth: String,
            candidates: [String],
            chineseDefault: String?
        )
    ) -> [String]? {
        let labeledHalfWidthPunctuation: Set<String> = [
            "'", "\"", "`", ";", "\\", "?", "(", ")", ":", "!",
        ]
        guard labeledHalfWidthPunctuation.contains(punctuation.halfWidth) else {
            return nil
        }

        return candidates.map { candidate in
            if candidate == punctuation.halfWidth {
                return "半 \(candidate)"
            }
            if candidate == punctuation.fullWidth {
                return "全 \(candidate)"
            }
            return candidate
        }
    }

    private func isInvalidPunctuationCandidateIndex(_ index: Int) -> Bool {
        isSelectingPunctuation && !currentCandidateActions.indices.contains(index)
    }

    private func shouldContinueNumericPunctuationInput(_ event: NSEvent) -> Bool {
        guard isSelectingPunctuation, ["$", "."].contains(buffer) else {
            return false
        }
        guard !isShiftModified(event) else { return false }
        guard let character = event.charactersIgnoringModifiers?.first else {
            return false
        }
        return character.isNumber
    }

    private func isShiftModified(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.shift) ||
            event.cgEvent?.flags.contains(.maskShift) == true
    }

    private func punctuationUsesFullWidthForPassthroughInput(
        _ event: NSEvent
    ) -> Bool? {
        let characters = event.charactersIgnoringModifiers ?? event.characters
        guard characters?.count == 1, let character = characters?.first else {
            return nil
        }
        if character.isNumber {
            return false
        }
        return nil
    }

    private func punctuationUsesFullWidthBeforeCursor(
        in client: IMKTextInput?
    ) -> Bool? {
        guard let textClient = client as? NSTextInputClient else {
            return nil
        }

        let selection = textClient.selectedRange()
        guard selection.location != NSNotFound, selection.location > 0 else {
            return nil
        }

        let contextLength = min(64, selection.location)
        if
            let text = textClient.attributedSubstring(
                forProposedRange: NSRange(
                    location: selection.location - contextLength,
                    length: contextLength
                ),
                actualRange: nil
            )?.string,
            let character = punctuationContextCharacter(in: text)
        {
            return isChinese(character)
        }

        guard
            let substring = textClient.attributedSubstring(
                forProposedRange: NSRange(
                    location: selection.location - 1,
                    length: 1
                ),
                actualRange: nil
            )?.string,
            let character = substring.last
        else {
            return nil
        }
        return isChinese(character)
    }

    private func punctuationContextCharacter(in text: String) -> Character? {
        for character in text.reversed() {
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

    private func englishTextBeforeComposition(
        in client: IMKTextInput?
    ) -> Bool {
        guard let textClient = client as? NSTextInputClient else {
            return lastCommittedCharacter.map {
                $0.isASCII && ($0.isLetter || $0.isNumber)
            } ?? false
        }

        let markedRange = textClient.markedRange()
        let selection = textClient.selectedRange()
        let location = markedRange.location != NSNotFound
            ? markedRange.location
            : selection.location
        guard
            location != NSNotFound,
            location > 0,
            let text = textClient.attributedSubstring(
                forProposedRange: NSRange(
                    location: max(0, location - 64),
                    length: min(64, location)
                ),
                actualRange: nil
            )?.string
        else {
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let sentenceStart = trimmed.lastIndex {
            ".!?。！？\n".contains($0)
        }.map { trimmed.index(after: $0) } ?? trimmed.startIndex
        let fragment = trimmed[sentenceStart...]
        let latinLetters = fragment.filter { $0.isASCII && $0.isLetter }.count
        let chineseCharacters = fragment.filter(isChinese).count
        return latinLetters > 0 && chineseCharacters == 0
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
        case "$":
            candidates = ["$", "¥", "£", "€", "₹", "₺", "＄"]
            chineseDefault = "$"
        case "`", "-", "+", "=":
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
            chineseDefault = "/"
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
        return (
            String(character),
            String(fullWidth),
            candidates,
            chineseDefault
        )
    }

    private func candidateIndex(for event: NSEvent) -> Int? {
        if let character = event.charactersIgnoringModifiers?.first {
            if character == "0" {
                return 9
            }
            if
                let number = character.wholeNumberValue,
                (1...9).contains(number)
            {
                return number - 1
            }
        }

        switch event.keyCode {
        case 18:
            return 0
        case 19:
            return 1
        case 20:
            return 2
        case 21:
            return 3
        case 23:
            return 4
        case 22:
            return 5
        case 26:
            return 6
        case 28:
            return 7
        case 25:
            return 8
        case 29:
            return 9
        case 83:
            return 0
        case 84:
            return 1
        case 85:
            return 2
        case 86:
            return 3
        case 87:
            return 4
        case 88:
            return 5
        case 89:
            return 6
        case 91:
            return 7
        case 92:
            return 8
        case 82:
            return 9
        default:
            return nil
        }
    }

    private var cangjieDecoder: CangjieDecoder? {
        InputResources.shared.cangjieDecoder
    }

    private var bilingualDictionary: BilingualDictionary? {
        InputResources.shared.bilingualDictionary
    }

    private var associationDictionary: AssociationDictionary? {
        InputResources.shared.associationDictionary
    }

    private var smartCandidateRanker: SmartCandidateRanker {
        SmartCandidateRanker.shared
    }
}
