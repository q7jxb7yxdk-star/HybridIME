import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
    private enum KeyboardPage {
        case letters
        case numbers
        case symbols
    }

    private enum ShiftState {
        case lowercased
        case uppercased
        case capsLocked
    }

    private enum KeyRole {
        case character
        case control
    }

    private enum KeyboardLayoutMode: Equatable {
        case compact
        case wideIPad
    }

    private struct WideSymbolKey {
        let primary: String
        let alternate: String
    }

    private enum WideSymbolViewTag {
        static let labels = 7_001
        static let alternatePreview = 7_002
    }

    private struct PendingPunctuationSelection {
        let insertedText: String
        let definition: PunctuationDefinition
    }

    private enum CandidateAction {
        case cangjie(String)
        case raw(String)
        case dictionary(String)
        case translation(String, replacingPrefixCharacterCount: Int)
        case association(KeyboardAssociationDictionary.Suggestion)

        var text: String {
            switch self {
            case .cangjie(let text),
                 .raw(let text),
                 .dictionary(let text),
                 .translation(let text, _):
                text
            case .association(let suggestion):
                suggestion.text
            }
        }
    }

    private var decoder: CangjieDecoder?
    private var decoderLoadingTask: Task<Void, Never>?
    private lazy var offlineLexicon = OfflineLexicon()
    private lazy var associationDictionary = KeyboardAssociationDictionary(
        lexicon: offlineLexicon
    )
    private let candidateScrollView = UIScrollView()
    private let candidateStackView = UIStackView()
    private let compositionLabel = UILabel()
    private let candidateArea = UIStackView()
    private let keyboardStackView = UIStackView()
    private let rootStack = UIStackView()
    private let cursorTrackpadOverlay = UIView()

    private var returnButton: UIButton?
    private weak var spaceButton: UIButton?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var layoutMode = KeyboardLayoutMode.compact
    private var hasBuiltKeyboard = false
    private var buffer = ""
    private var currentCandidates: [String] = []
    private var currentCandidateActions: [CandidateAction] = []
    private var learnedCandidate: String?
    private var pendingPunctuationSelection: PendingPunctuationSelection?
    private var isSelectingAssociation = false
    private var associationContext = ""
    private var associationLanguage: KeyboardAssociationDictionary.Language?
    private var learnedChineseContext = ""
    private var currentPage = KeyboardPage.letters
    private var shiftState = ShiftState.lowercased
    private var lastShiftTapTime: TimeInterval = 0
    private var cursorGestureStartPoint = CGPoint.zero
    private var cursorHorizontalGestureStep = 0
    private var cursorVerticalGestureStep = 0
    private var cursorPreferredColumn = 0
    // 游標每移動一個字元所需的水平滑動距離（pt）；數值越小越靈敏。
    private let cursorMovementThreshold: CGFloat = 5
    // 每觸發一次上一行或下一行移動所需的垂直滑動距離（pt）；數值越小越靈敏。
    private let cursorVerticalMovementThreshold: CGFloat = 5
    // 找不到實際換行時，每次垂直移動所估算的字元數。數值越小則移動較短。
    private let cursorEstimatedCharactersPerLine = 10
    private let cursorFeedbackGenerator = UISelectionFeedbackGenerator()

    private let letterRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    private let numberRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
    ]

    private let symbolRows = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
    ]

    private let punctuationKeys = [".", ",", "?", "!", "'"]

    private let wideIPadNumberSecondRow: [WideSymbolKey] = [
        .init(primary: "@", alternate: "¥"),
        .init(primary: "#", alternate: "€"),
        .init(primary: "$", alternate: "£"),
        .init(primary: "&", alternate: "_"),
        .init(primary: "*", alternate: "^"),
        .init(primary: "(", alternate: "["),
        .init(primary: ")", alternate: "]"),
        .init(primary: "'", alternate: "{"),
        .init(primary: "\"", alternate: "}"),
    ]

    private let wideIPadNumberThirdRow: [WideSymbolKey] = [
        .init(primary: "%", alternate: "§"),
        .init(primary: "-", alternate: "|"),
        .init(primary: "+", alternate: "~"),
        .init(primary: "=", alternate: "…"),
        .init(primary: "/", alternate: "\\"),
        .init(primary: ";", alternate: "<"),
        .init(primary: ":", alternate: ">"),
        .init(primary: ",", alternate: "!"),
        .init(primary: ".", alternate: "?"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        layoutMode = traitCollection.userInterfaceIdiom == .pad
            && traitCollection.horizontalSizeClass != .compact
            ? .wideIPad
            : .compact
        configureInterface()
        rebuildKeyboard()
        hasBuiltKeyboard = true
        refreshComposition()
        updateAppearance()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLayoutModeIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        preloadDecoderIfNeeded()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAppearance()
        updateReturnKeyTitle()
    }

    private func configureInterface() {
        view.backgroundColor = .clear
        view.isOpaque = false

        candidateStackView.axis = .horizontal
        candidateStackView.alignment = .fill
        candidateStackView.spacing = 6
        candidateStackView.translatesAutoresizingMaskIntoConstraints = false

        candidateScrollView.showsHorizontalScrollIndicator = false
        candidateScrollView.alwaysBounceHorizontal = true
        candidateScrollView.addSubview(candidateStackView)
        candidateScrollView.heightAnchor.constraint(equalToConstant: 38).isActive = true

        NSLayoutConstraint.activate([
            candidateStackView.leadingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.leadingAnchor),
            candidateStackView.trailingAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.trailingAnchor),
            candidateStackView.topAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.topAnchor),
            candidateStackView.bottomAnchor.constraint(equalTo: candidateScrollView.contentLayoutGuide.bottomAnchor),
            candidateStackView.heightAnchor.constraint(equalTo: candidateScrollView.frameLayoutGuide.heightAnchor),
        ])

        compositionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        compositionLabel.textColor = .secondaryLabel
        compositionLabel.textAlignment = .center
        compositionLabel.adjustsFontSizeToFitWidth = true
        compositionLabel.minimumScaleFactor = 0.75
        compositionLabel.heightAnchor.constraint(equalToConstant: 15).isActive = true

        candidateArea.addArrangedSubview(candidateScrollView)
        candidateArea.addArrangedSubview(compositionLabel)
        candidateArea.axis = .vertical
        candidateArea.spacing = 1

        keyboardStackView.axis = .vertical
        keyboardStackView.distribution = .fill
        keyboardStackView.spacing = 7

        rootStack.addArrangedSubview(candidateArea)
        rootStack.addArrangedSubview(keyboardStackView)
        rootStack.axis = .vertical
        rootStack.spacing = 7
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        cursorTrackpadOverlay.backgroundColor = keyboardBackgroundColor
        cursorTrackpadOverlay.isUserInteractionEnabled = false
        cursorTrackpadOverlay.isHidden = true
        cursorTrackpadOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cursorTrackpadOverlay)

        let heightConstraint = view.heightAnchor.constraint(
            equalToConstant: layoutMode == .wideIPad ? 353 : 260
        )
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true
        keyboardHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            cursorTrackpadOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cursorTrackpadOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cursorTrackpadOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            cursorTrackpadOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func rebuildKeyboard() {
        keyboardStackView.arrangedSubviews.forEach { arrangedView in
            keyboardStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        candidateArea.isHidden = false
        keyboardHeightConstraint?.constant = layoutMode == .wideIPad ? 353 : 260
        keyboardStackView.distribution = layoutMode == .wideIPad ? .fillEqually : .fill
        if layoutMode == .wideIPad {
            compositionLabel.isHidden = true
            keyboardStackView.spacing = 5
            rootStack.spacing = 5
        } else {
            compositionLabel.isHidden = currentPage == .letters
            keyboardStackView.spacing = currentPage == .letters ? 5 : 7
            rootStack.spacing = currentPage == .letters ? 5 : 7
        }

        switch currentPage {
        case .letters:
            if layoutMode == .wideIPad {
                buildWideIPadLetterRows()
            } else {
                keyboardStackView.addArrangedSubview(
                    makeCharacterRow(letterRows[0], horizontalInset: 0, usesShift: true)
                )
                keyboardStackView.addArrangedSubview(
                    makeCharacterRow(letterRows[1], horizontalInset: 17, usesShift: true)
                )
                keyboardStackView.addArrangedSubview(makeLetterControlRow())
            }
        case .numbers:
            if layoutMode == .wideIPad {
                buildWideIPadNumberRows()
            } else {
                numberRows.forEach {
                    keyboardStackView.addArrangedSubview(
                        makeCharacterRow($0, horizontalInset: 0, usesShift: false)
                    )
                }
                keyboardStackView.addArrangedSubview(
                    makePunctuationRow(pageTitle: "#+=", destination: .symbols)
                )
            }
        case .symbols:
            if layoutMode == .wideIPad {
                buildWideIPadNumberAlternateRows()
            } else {
                symbolRows.forEach {
                    keyboardStackView.addArrangedSubview(
                        makeCharacterRow($0, horizontalInset: 0, usesShift: false)
                    )
                }
                keyboardStackView.addArrangedSubview(
                    makePunctuationRow(pageTitle: "123", destination: .numbers)
                )
            }
        }

        keyboardStackView.addArrangedSubview(makeBottomRow())
    }

    private func updateLayoutModeIfNeeded() {
        let nextMode: KeyboardLayoutMode
        if traitCollection.userInterfaceIdiom == .pad,
           traitCollection.horizontalSizeClass == .regular,
           view.bounds.width >= 700
        {
            nextMode = .wideIPad
        } else {
            nextMode = .compact
        }

        guard layoutMode != nextMode else { return }
        layoutMode = nextMode
        guard hasBuiltKeyboard else { return }
        rebuildKeyboard()
    }

    private func preloadDecoderIfNeeded() {
        guard decoder == nil, decoderLoadingTask == nil else { return }
        decoderLoadingTask = Task { [weak self] in
            let decoder = await Task.detached(priority: .userInitiated) {
                CangjieDecoder()
            }.value
            guard !Task.isCancelled, let self else { return }
            self.decoder = decoder
            self.decoderLoadingTask = nil
            if !self.buffer.isEmpty {
                self.refreshComposition()
            }
        }
    }

    private func buildWideIPadLetterRows() {
        let deleteButton = makeDeleteButton(height: 50)
        keyboardStackView.addArrangedSubview(
            makeWideIPadLetterRow(letterRows[0], trailingControls: [deleteButton])
        )

        let returnButton = makeReturnButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadLetterRow(
                letterRows[1],
                trailingControls: [returnButton],
                leadingSpacerCount: 1
            )
        )

        let leftShiftButton = makeShiftButton()
        let rightShiftButton = makeShiftButton()
        let commaButton = makeWidePunctuationButton(",", alternateKey: "!")
        let periodButton = makeWidePunctuationButton(".", alternateKey: "?")
        keyboardStackView.addArrangedSubview(
            makeWideIPadLetterRow(
                letterRows[2],
                leadingControls: [leftShiftButton],
                trailingControls: [commaButton, periodButton, rightShiftButton]
            )
        )
    }

    private func buildWideIPadSymbolRows(
        rows: [[String]],
        pageTitle: String,
        destination: KeyboardPage
    ) {
        guard let firstRow = rows.first, let secondRow = rows.dropFirst().first else { return }

        let deleteButton = makeDeleteButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadCharacterRow(firstRow, trailingControls: [deleteButton])
        )

        let returnButton = makeReturnButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadCharacterRow(secondRow, trailingControls: [returnButton])
        )

        keyboardStackView.addArrangedSubview(
            makeWideIPadPunctuationRow(pageTitle: pageTitle, destination: destination)
        )
    }

    private func buildWideIPadNumberRows() {
        let deleteButton = makeDeleteButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadCharacterRow(numberRows[0], trailingControls: [deleteButton])
        )

        let returnButton = makeReturnButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadSymbolRow(
                wideIPadNumberSecondRow,
                trailingControls: [returnButton],
                leadingSpacerCount: 1
            )
        )

        let pageButton = makePageButton(title: "#+=", destination: .symbols)
        let numberButtons = wideIPadNumberThirdRow.map { makeWideIPadSymbolButton($0) }
        let trailingPageButton = makePageButton(title: "#+=", destination: .symbols)
        keyboardStackView.addArrangedSubview(
            makeWideIPadRow(keyButtons: [pageButton] + numberButtons + [trailingPageButton])
        )
    }

    private func buildWideIPadNumberAlternateRows() {
        let deleteButton = makeDeleteButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadCharacterRow(numberRows[0], trailingControls: [deleteButton])
        )

        let alternateSecondRow = wideIPadNumberSecondRow.map(\.alternate)
        let returnButton = makeReturnButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadCharacterRow(
                alternateSecondRow,
                trailingControls: [returnButton],
                leadingSpacerCount: 1
            )
        )

        let leadingPageButton = makePageButton(title: "123", destination: .numbers)
        let alternateThirdRow = wideIPadNumberThirdRow.map(\.alternate)
        let alternateButtons = alternateThirdRow.map { key in
            let button = makeKey(title: key, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterSymbol(key) },
                for: .touchUpInside
            )
            return button
        }
        let trailingPageButton = makePageButton(title: "123", destination: .numbers)
        keyboardStackView.addArrangedSubview(
            makeWideIPadRow(
                keyButtons: [leadingPageButton] + alternateButtons + [trailingPageButton]
            )
        )
    }

    private func makeWideIPadLetterRow(
        _ keys: [String],
        leadingControls: [UIButton] = [],
        trailingControls: [UIButton] = [],
        leadingSpacerCount: Int = 0
    ) -> UIView {
        let keyButtons = keys.map { key in
            let displayedKey = shiftState == .lowercased ? key : key.uppercased()
            let button = makeLetterKey(letter: key, displayedLetter: displayedKey)
            button.addAction(
                UIAction { [weak self] _ in self?.enterLetter(key) },
                for: .touchUpInside
            )
            return button
        }
        return makeWideIPadRow(
            keyButtons: keyButtons,
            leadingControls: leadingControls,
            trailingControls: trailingControls,
            leadingSpacerCount: leadingSpacerCount
        )
    }

    private func makeWideIPadCharacterRow(
        _ keys: [String],
        trailingControls: [UIButton],
        leadingSpacerCount: Int = 0
    ) -> UIView {
        let keyButtons = keys.map { key in
            let button = makeKey(title: key, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterSymbol(key) },
                for: .touchUpInside
            )
            return button
        }
        return makeWideIPadRow(
            keyButtons: keyButtons,
            trailingControls: trailingControls,
            leadingSpacerCount: leadingSpacerCount
        )
    }

    private func makeWideIPadSymbolRow(
        _ keys: [WideSymbolKey],
        trailingControls: [UIButton],
        leadingSpacerCount: Int = 0
    ) -> UIView {
        let keyButtons = keys.map { makeWideIPadSymbolButton($0) }
        return makeWideIPadRow(
            keyButtons: keyButtons,
            trailingControls: trailingControls,
            leadingSpacerCount: leadingSpacerCount
        )
    }

    private func makeWideIPadPunctuationRow(
        pageTitle: String,
        destination: KeyboardPage
    ) -> UIView {
        let pageButton = makePageButton(title: pageTitle, destination: destination)
        let punctuationButtons = punctuationKeys.map { makeWidePunctuationButton($0) }
        return makeWideIPadRow(
            keyButtons: [pageButton] + punctuationButtons,
            leadingSpacerCount: 2
        )
    }

    private func makeWideIPadRow(
        keyButtons: [UIButton],
        leadingControls: [UIButton] = [],
        trailingControls: [UIButton] = [],
        leadingSpacerCount: Int = 0
    ) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fillEqually

        let slotCount = 11
        let occupiedSlotCount = leadingControls.count + keyButtons.count + trailingControls.count
        let leadingSpacers = min(leadingSpacerCount, max(0, slotCount - occupiedSlotCount))
        let trailingSpacers = max(0, slotCount - occupiedSlotCount - leadingSpacers)

        for _ in 0..<leadingSpacers {
            row.addArrangedSubview(UIView())
        }
        leadingControls.forEach { row.addArrangedSubview($0) }
        keyButtons.forEach { row.addArrangedSubview($0) }
        trailingControls.forEach { row.addArrangedSubview($0) }
        for _ in 0..<trailingSpacers {
            row.addArrangedSubview(UIView())
        }
        return wrap(row, horizontalInset: 0)
    }

    private func makeShiftButton() -> UIButton {
        let shiftButton = makeIconKey(
            systemName: shiftSymbolName,
            accessibilityLabel: "Shift",
            role: .control,
            height: 50
        )
        shiftButton.addAction(
            UIAction { [weak self] _ in self?.toggleShift() },
            for: .touchUpInside
        )
        return shiftButton
    }

    private func makeWideIPadSymbolButton(_ key: WideSymbolKey) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.background.backgroundColor = characterKeyColor
        configuration.background.cornerRadius = 5

        let button = configuredButton(
            configuration: configuration,
            normalColor: characterKeyColor,
            accessibilityLabel: "\(key.primary)，向下滑動輸入\(key.alternate)",
            height: 42
        )
        button.addAction(
            UIAction { [weak self] _ in self?.enterSymbol(key.primary) },
            for: .touchUpInside
        )

        let alternateLabel = UILabel()
        alternateLabel.text = key.alternate
        alternateLabel.font = .systemFont(ofSize: 14, weight: .regular)
        alternateLabel.textColor = .secondaryLabel
        alternateLabel.textAlignment = .center

        let primaryLabel = UILabel()
        primaryLabel.text = key.primary
        primaryLabel.font = .systemFont(ofSize: 21, weight: .regular)
        primaryLabel.textColor = .label
        primaryLabel.textAlignment = .center

        let usesLooserLabelSpacing = ["@", "#", "$", "&", "(", ")", "'", "\"", "/"]
            .contains(key.primary)
        let labelEdgeInset: CGFloat = usesLooserLabelSpacing ? 0 : 2
        let labels = UIStackView(arrangedSubviews: [alternateLabel, primaryLabel])
        labels.axis = .vertical
        labels.alignment = .center
        labels.spacing = usesLooserLabelSpacing ? 0 : -5
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.tag = WideSymbolViewTag.labels
        button.addSubview(labels)
        NSLayoutConstraint.activate([
            labels.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            labels.topAnchor.constraint(
                greaterThanOrEqualTo: button.topAnchor,
                constant: labelEdgeInset
            ),
            labels.bottomAnchor.constraint(
                lessThanOrEqualTo: button.bottomAnchor,
                constant: -labelEdgeInset
            ),
        ])

        installAlternateFlick(
            on: button,
            alternate: key.alternate
        )
        return button
    }

    private func installAlternateFlick(
        on button: UIButton,
        alternate: String
    ) {
        let previewLabel = UILabel()
        previewLabel.text = alternate
        previewLabel.font = .systemFont(ofSize: 21, weight: .regular)
        previewLabel.textColor = .label
        previewLabel.textAlignment = .center
        previewLabel.isHidden = true
        previewLabel.isUserInteractionEnabled = false
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.tag = WideSymbolViewTag.alternatePreview
        button.addSubview(previewLabel)
        NSLayoutConstraint.activate([
            previewLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            previewLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        let alternatePan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleWideSymbolAlternatePan(_:))
        )
        alternatePan.maximumNumberOfTouches = 1
        alternatePan.cancelsTouchesInView = true
        alternatePan.name = alternate
        button.addGestureRecognizer(alternatePan)
    }

    @objc
    private func handleWideSymbolAlternatePan(_ gesture: UIPanGestureRecognizer) {
        guard let button = gesture.view as? UIButton,
              let alternate = gesture.name
        else { return }

        let translation = gesture.translation(in: button)
        let selectsAlternate = translation.y >= 12
            && abs(translation.y) > abs(translation.x)

        switch gesture.state {
        case .began, .changed:
            setAlternateFlickPreview(selectsAlternate, on: button)
        case .ended:
            setAlternateFlickPreview(false, on: button)
            if selectsAlternate {
                enterSymbol(alternate)
            }
        case .cancelled, .failed:
            setAlternateFlickPreview(false, on: button)
        default:
            break
        }
    }

    private func setAlternateFlickPreview(
        _ isActive: Bool,
        on button: UIButton
    ) {
        button.viewWithTag(WideSymbolViewTag.labels)?.isHidden = isActive
        button.viewWithTag(WideSymbolViewTag.alternatePreview)?.isHidden = !isActive
        button.isHighlighted = isActive
    }

    private func makeWidePunctuationButton(
        _ key: String,
        alternateKey: String? = nil
    ) -> UIButton {
        guard let alternateKey else {
            let button = makeKey(title: key, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterSymbol(key) },
                for: .touchUpInside
            )
            return button
        }

        let usesAlternatePrimary = shiftState != .lowercased
        if usesAlternatePrimary {
            let button = makeKey(title: alternateKey, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterWidePunctuation(alternateKey) },
                for: .touchUpInside
            )
            return button
        }

        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.background.backgroundColor = characterKeyColor
        configuration.background.cornerRadius = 5

        let button = configuredButton(
            configuration: configuration,
            normalColor: characterKeyColor,
            accessibilityLabel: "\(key)，向下滑動或 Shift 輸入\(alternateKey)",
            height: 42
        )
        button.addAction(
            UIAction { [weak self] _ in self?.enterWidePunctuation(key) },
            for: .touchUpInside
        )

        let alternateLabel = UILabel()
        alternateLabel.text = alternateKey
        alternateLabel.font = .systemFont(ofSize: 14, weight: .regular)
        alternateLabel.textColor = .secondaryLabel
        alternateLabel.textAlignment = .center

        let primaryLabel = UILabel()
        primaryLabel.text = key
        primaryLabel.font = .systemFont(ofSize: 21, weight: .regular)
        primaryLabel.textColor = .label
        primaryLabel.textAlignment = .center

        let labels = UIStackView(arrangedSubviews: [alternateLabel, primaryLabel])
        labels.axis = .vertical
        labels.alignment = .center
        labels.spacing = -5
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.tag = WideSymbolViewTag.labels
        button.addSubview(labels)
        NSLayoutConstraint.activate([
            labels.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor, constant: 2),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor, constant: -2),
        ])

        installAlternateFlick(
            on: button,
            alternate: alternateKey
        )
        return button
    }

    private func enterWidePunctuation(_ symbol: String) {
        enterSymbol(symbol)
        if shiftState == .uppercased {
            shiftState = .lowercased
            rebuildKeyboard()
        }
    }

    private func makeCharacterRow(
        _ keys: [String],
        horizontalInset: CGFloat,
        usesShift: Bool
    ) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 5

        for key in keys {
            let displayedKey = usesShift && shiftState != .lowercased
                ? key.uppercased()
                : key
            let button = usesShift
                ? makeLetterKey(letter: key, displayedLetter: displayedKey)
                : makeKey(title: displayedKey, role: .character)
            button.addAction(
                UIAction { [weak self] _ in
                    if usesShift {
                        self?.enterLetter(key)
                    } else {
                        self?.enterSymbol(key)
                    }
                },
                for: .touchUpInside
            )
            row.addArrangedSubview(button)
        }

        return wrap(row, horizontalInset: horizontalInset)
    }

    private func makeLetterControlRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        let shiftButton = makeIconKey(
            systemName: shiftSymbolName,
            accessibilityLabel: "Shift",
            role: .control,
            height: 50
        )
        shiftButton.addAction(
            UIAction { [weak self] _ in self?.toggleShift() },
            for: .touchUpInside
        )
        shiftButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(shiftButton)

        var letterButtons: [UIButton] = []
        for key in letterRows[2] {
            let displayedKey = shiftState == .lowercased ? key : key.uppercased()
            let button = makeLetterKey(letter: key, displayedLetter: displayedKey)
            button.addAction(
                UIAction { [weak self] _ in self?.enterLetter(key) },
                for: .touchUpInside
            )
            row.addArrangedSubview(button)
            letterButtons.append(button)
        }
        equalizeWidths(letterButtons)

        let deleteButton = makeDeleteButton(height: 50)
        deleteButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(deleteButton)
        return wrap(row, horizontalInset: 0)
    }

    private func makePunctuationRow(
        pageTitle: String,
        destination: KeyboardPage
    ) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        let pageButton = makeKey(title: pageTitle, role: .control, fontSize: 14)
        pageButton.addAction(
            UIAction { [weak self] _ in self?.switchPage(to: destination) },
            for: .touchUpInside
        )
        pageButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        row.addArrangedSubview(pageButton)

        var punctuationButtons: [UIButton] = []
        for key in punctuationKeys {
            let button = makeKey(title: key, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterSymbol(key) },
                for: .touchUpInside
            )
            row.addArrangedSubview(button)
            punctuationButtons.append(button)
        }
        equalizeWidths(punctuationButtons)

        let deleteButton = makeDeleteButton()
        deleteButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(deleteButton)
        return wrap(row, horizontalInset: 0)
    }

    private func makeBottomRow() -> UIView {
        if layoutMode == .wideIPad {
            return makeWideIPadBottomRow()
        }

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        let pageTitle = currentPage == .letters ? "123" : "ABC"
        let pageDestination = currentPage == .letters
            ? KeyboardPage.numbers
            : KeyboardPage.letters
        let pageButton = makePageButton(title: pageTitle, destination: pageDestination)
        pageButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        row.addArrangedSubview(pageButton)

        let inputModeButton = makeInputModeButton()
        inputModeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(inputModeButton)

        let spaceButton = makeSpaceButton()
        row.addArrangedSubview(spaceButton)

        let returnButton = makeReturnButton()
        returnButton.widthAnchor.constraint(equalToConstant: 70).isActive = true
        row.addArrangedSubview(returnButton)

        return wrap(row, horizontalInset: 0)
    }

    private func makeWideIPadBottomRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        let inputModeButton = makeInputModeButton()
        row.addArrangedSubview(inputModeButton)
        inputModeButton.widthAnchor.constraint(
            equalTo: row.widthAnchor,
            multiplier: 0.085
        ).isActive = true

        let pageTitle = currentPage == .letters ? "123" : "ABC"
        let pageDestination = currentPage == .letters
            ? KeyboardPage.numbers
            : KeyboardPage.letters
        let leadingPageButton = makePageButton(title: pageTitle, destination: pageDestination)
        row.addArrangedSubview(leadingPageButton)
        leadingPageButton.widthAnchor.constraint(
            equalTo: row.widthAnchor,
            multiplier: 0.09
        ).isActive = true

        row.addArrangedSubview(makeSpaceButton())

        let trailingPageButton = makePageButton(title: pageTitle, destination: pageDestination)
        row.addArrangedSubview(trailingPageButton)
        trailingPageButton.widthAnchor.constraint(
            equalTo: row.widthAnchor,
            multiplier: 0.125
        ).isActive = true

        let dismissButton = makeIconKey(
            systemName: "keyboard.chevron.compact.down",
            accessibilityLabel: "收起鍵盤",
            role: .control
        )
        dismissButton.addAction(
            UIAction { [weak self] _ in self?.dismissKeyboard() },
            for: .touchUpInside
        )
        row.addArrangedSubview(dismissButton)
        dismissButton.widthAnchor.constraint(
            equalTo: row.widthAnchor,
            multiplier: 0.125
        ).isActive = true

        return wrap(row, horizontalInset: 0)
    }

    private func makePageButton(title: String, destination: KeyboardPage) -> UIButton {
        let pageButton = makeKey(title: title, role: .control, fontSize: 14)
        pageButton.addAction(
            UIAction { [weak self] _ in self?.switchPage(to: destination) },
            for: .touchUpInside
        )
        return pageButton
    }

    private func makeInputModeButton() -> UIButton {
        let inputModeButton = makeIconKey(
            systemName: "globe",
            accessibilityLabel: "切換鍵盤",
            role: .control
        )
        inputModeButton.addTarget(
            self,
            action: #selector(handleInputModeList(from:with:)),
            for: .allTouchEvents
        )
        return inputModeButton
    }

    private func makeSpaceButton() -> UIButton {
        let spaceButton = makeKey(title: "HybridIME", role: .character, fontSize: 16)
        spaceButton.accessibilityLabel = "空格"
        spaceButton.addAction(
            UIAction { [weak self] _ in self?.commitSpace() },
            for: .touchUpInside
        )
        let cursorGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleSpaceCursorGesture(_:))
        )
        cursorGesture.minimumPressDuration = 0.35
        cursorGesture.allowableMovement = 24
        cursorGesture.cancelsTouchesInView = true
        spaceButton.addGestureRecognizer(cursorGesture)
        spaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 105).isActive = true
        self.spaceButton = spaceButton
        return spaceButton
    }

    private func makeReturnButton() -> UIButton {
        let returnButton = makeKey(
            title: returnKeyTitle,
            role: .control,
            fontSize: 14
        )
        returnButton.addAction(
            UIAction { [weak self] _ in self?.commitReturn() },
            for: .touchUpInside
        )
        self.returnButton = returnButton
        return returnButton
    }

    private func makeDeleteButton(height: CGFloat = 42) -> UIButton {
        let button = makeIconKey(
            systemName: "delete.left",
            accessibilityLabel: "刪除",
            role: .control,
            height: height
        )
        button.addAction(
            UIAction { [weak self] _ in self?.deleteBackward() },
            for: .touchUpInside
        )
        return button
    }

    private func makeKey(
        title: String,
        role: KeyRole,
        fontSize: CGFloat = 21,
        height: CGFloat = 42
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = keyColor(for: role)
        configuration.background.cornerRadius = 5
        configuration.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: fontSize, weight: .regular)
                return attributes
            }

        return configuredButton(
            configuration: configuration,
            normalColor: keyColor(for: role),
            accessibilityLabel: title,
            height: height
        )
    }

    private func makeLetterKey(
        letter: String,
        displayedLetter: String
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.background.backgroundColor = characterKeyColor
        configuration.background.cornerRadius = 5

        let root = cangjieRoots(for: letter)
        let button = configuredButton(
            configuration: configuration,
            normalColor: characterKeyColor,
            accessibilityLabel: "\(displayedLetter)，倉頡字根\(root)",
            height: 50
        )

        let rootLabel = UILabel()
        rootLabel.text = root
        rootLabel.font = .systemFont(ofSize: 21, weight: .regular)
        rootLabel.textColor = .label
        rootLabel.textAlignment = .center

        let letterLabel = UILabel()
        letterLabel.text = displayedLetter
        letterLabel.font = .systemFont(ofSize: 21, weight: .regular)
        letterLabel.textColor = .secondaryLabel
        letterLabel.textAlignment = .center

        let labels = UIStackView(arrangedSubviews: [rootLabel, letterLabel])
        labels.axis = .vertical
        labels.alignment = .center
        labels.spacing = -6
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(labels)
        NSLayoutConstraint.activate([
            labels.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor, constant: 2),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor, constant: -2),
        ])
        return button
    }

    private func makeIconKey(
        systemName: String,
        accessibilityLabel: String,
        role: KeyRole,
        height: CGFloat = 42
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.contentInsets = .zero
        configuration.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = keyColor(for: role)
        configuration.background.cornerRadius = 5

        return configuredButton(
            configuration: configuration,
            normalColor: keyColor(for: role),
            accessibilityLabel: accessibilityLabel,
            height: height
        )
    }

    private func configuredButton(
        configuration: UIButton.Configuration,
        normalColor: UIColor,
        accessibilityLabel: String,
        height: CGFloat
    ) -> UIButton {
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.22
        button.layer.shadowRadius = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: height)
        if layoutMode == .wideIPad {
            heightConstraint.priority = UILayoutPriority(749)
        }
        heightConstraint.isActive = true
        button.configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            configuration.background.backgroundColor = button.isHighlighted
                ? UIColor.systemGray2
                : normalColor
            button.configuration = configuration
        }
        return button
    }

    private func wrap(
        _ row: UIView,
        horizontalInset: CGFloat
    ) -> UIView {
        let container = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func equalizeWidths(_ buttons: [UIButton]) {
        guard let first = buttons.first else { return }
        buttons.dropFirst().forEach {
            $0.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
        }
    }

    private func switchPage(to page: KeyboardPage) {
        if page != currentPage {
            resetCompositionState()
        }
        currentPage = page
        if page != .letters {
            shiftState = .lowercased
        }
        rebuildKeyboard()
        refreshComposition()
    }

    private func toggleShift() {
        let now = ProcessInfo.processInfo.systemUptime
        let isDoubleTap = now - lastShiftTapTime < 0.4
        lastShiftTapTime = now

        switch shiftState {
        case .lowercased:
            shiftState = .uppercased
        case .uppercased:
            shiftState = isDoubleTap ? .capsLocked : .lowercased
        case .capsLocked:
            shiftState = .lowercased
        }
        rebuildKeyboard()
    }

    private func enterLetter(_ key: String) {
        if pendingPunctuationSelection != nil {
            resetCompositionState()
        }
        if isSelectingAssociation {
            dismissAssociation(clearContext: false)
        }
        let text = shiftState == .lowercased ? key : key.uppercased()
        textDocumentProxy.insertText(text)
        buffer.append(text)
        refreshComposition()

        if shiftState == .uppercased {
            shiftState = .lowercased
            rebuildKeyboard()
        }
    }

    private func enterSymbol(_ symbol: String) {
        if let punctuation = PunctuationStrategy.definition(for: symbol) {
            beginPunctuationSelection(punctuation)
            return
        }
        resetCompositionState()
        textDocumentProxy.insertText(symbol)
        refreshComposition()
    }

    private func beginPunctuationSelection(_ punctuation: PunctuationDefinition) {
        let forceFullWidth = punctuationFullWidthPreferenceForCurrentComposition()

        if !buffer.isEmpty,
           forceFullWidth == true,
           let learnedCandidate
        {
            _ = replaceTypedCode(with: learnedCandidate)
        } else {
            resetCompositionState()
        }

        let useFullWidth = forceFullWidth
            ?? PunctuationStrategy.usesFullWidth(
                before: textDocumentProxy.documentContextBeforeInput
            )
            ?? false
        let defaultCandidate = PunctuationStrategy.defaultCandidate(
            for: punctuation,
            useFullWidth: useFullWidth
        )

        resetCompositionState()
        currentCandidates = PunctuationStrategy.orderedCandidates(
            for: punctuation,
            defaultCandidate: defaultCandidate
        )
        textDocumentProxy.insertText(defaultCandidate)
        pendingPunctuationSelection = PendingPunctuationSelection(
            insertedText: defaultCandidate,
            definition: punctuation
        )
        rebuildCandidateButtons()
    }

    private func punctuationFullWidthPreferenceForCurrentComposition() -> Bool? {
        guard !buffer.isEmpty else { return nil }
        guard let learnedCandidate,
              learnedCandidate != buffer,
              PunctuationStrategy.isChinese(learnedCandidate)
        else { return false }
        return true
    }

    private func deleteBackward() {
        if !buffer.isEmpty,
           textDocumentProxy.documentContextBeforeInput?.hasSuffix(buffer) == true
        {
            buffer.removeLast()
        } else {
            resetCompositionState()
        }
        textDocumentProxy.deleteBackward()
        refreshComposition()
    }

    private func commitSpace() {
        if shiftState != .lowercased {
            let typedCode = buffer
            if !typedCode.isEmpty {
                SmartCandidateRanker.shared.replaceLearning(
                    code: typedCode,
                    candidate: typedCode
                )
            }
            resetCompositionState()
            if shiftState == .uppercased {
                shiftState = .lowercased
                rebuildKeyboard()
            }
            refreshComposition()
            return
        }

        if isSelectingAssociation {
            if case .association(let suggestion) = currentCandidateActions.first,
               suggestion.isMostRecentSelection
            {
                commitAssociation(suggestion)
            } else {
                resetCompositionState()
                textDocumentProxy.insertText(" ")
                refreshComposition()
            }
            return
        }

        if learnedCandidate == buffer, !buffer.isEmpty {
            let typedCode = buffer
            textDocumentProxy.insertText(" ")
            finishCommittedText(typedCode)
            return
        }
        if let learnedCandidate,
           replaceTypedCode(with: learnedCandidate, showingAssociations: true)
        {
            return
        }

        let typedCode = buffer
        if !typedCode.isEmpty {
            textDocumentProxy.insertText(" ")
            finishCommittedText(typedCode)
            return
        }
        resetCompositionState()
        textDocumentProxy.insertText(" ")
        refreshComposition()
    }

    @objc
    private func handleSpaceCursorGesture(_ gesture: UILongPressGestureRecognizer) {
        guard let spaceButton = gesture.view as? UIButton else { return }

        switch gesture.state {
        case .began:
            cursorGestureStartPoint = gesture.location(in: view)
            cursorHorizontalGestureStep = 0
            cursorVerticalGestureStep = 0
            cursorPreferredColumn = currentCursorColumn
            resetCompositionState()
            refreshComposition()
            setCursorTrackpadMode(active: true)
            updateSpaceButtonTitle("移動游標", accessibilityLabel: "移動游標")
            cursorFeedbackGenerator.prepare()
        case .changed:
            let location = gesture.location(in: view)
            let horizontalDistance = location.x - cursorGestureStartPoint.x
            let verticalDistance = location.y - cursorGestureStartPoint.y

            var didMove = false
            let horizontalStep = Int(horizontalDistance / cursorMovementThreshold)
            let horizontalOffset = horizontalStep - cursorHorizontalGestureStep
            if horizontalOffset != 0 {
                textDocumentProxy.adjustTextPosition(
                    byCharacterOffset: horizontalOffset
                )
                cursorHorizontalGestureStep = horizontalStep
                cursorPreferredColumn = currentCursorColumn
                didMove = true
            }

            let verticalStep = Int(verticalDistance / cursorVerticalMovementThreshold)
            let lineOffset = verticalStep - cursorVerticalGestureStep
            if lineOffset != 0 {
                if moveCursorByLogicalLines(lineOffset) {
                    didMove = true
                }
                cursorVerticalGestureStep = verticalStep
            }

            if didMove {
                cursorFeedbackGenerator.selectionChanged()
                cursorFeedbackGenerator.prepare()
            }
        case .ended, .cancelled, .failed:
            cursorGestureStartPoint = .zero
            cursorHorizontalGestureStep = 0
            cursorVerticalGestureStep = 0
            cursorPreferredColumn = 0
            setCursorTrackpadMode(active: false)
            updateSpaceButtonTitle("HybridIME", accessibilityLabel: "空格")
        default:
            break
        }

        spaceButton.isHighlighted = gesture.state == .began || gesture.state == .changed
    }

    private func setCursorTrackpadMode(active: Bool) {
        cursorTrackpadOverlay.isHidden = !active
        cursorTrackpadOverlay.alpha = active ? 0.94 : 0
        if active {
            view.bringSubviewToFront(cursorTrackpadOverlay)
        }
    }

    private var currentCursorColumn: Int {
        let beforeCursor = textDocumentProxy.documentContextBeforeInput ?? ""
        guard let newline = beforeCursor.lastIndex(of: "\n") else {
            return beforeCursor.count
        }
        return beforeCursor[beforeCursor.index(after: newline)...].count
    }

    private func moveCursorByLogicalLines(_ lineOffset: Int) -> Bool {
        let direction = lineOffset > 0 ? 1 : -1
        var didMove = false
        for _ in 0..<abs(lineOffset) {
            let movedToLogicalLine = direction > 0
                ? moveCursorToNextLogicalLine()
                : moveCursorToPreviousLogicalLine()
            let moved = movedToLogicalLine || moveCursorByEstimatedLine(direction)
            guard moved else { break }
            didMove = true
        }
        return didMove
    }

    private func moveCursorByEstimatedLine(_ direction: Int) -> Bool {
        textDocumentProxy.adjustTextPosition(
            byCharacterOffset: direction * cursorEstimatedCharactersPerLine
        )
        return true
    }

    private func moveCursorToPreviousLogicalLine() -> Bool {
        guard let beforeCursor = textDocumentProxy.documentContextBeforeInput,
              let newline = beforeCursor.lastIndex(of: "\n")
        else { return false }

        let currentLineStart = beforeCursor.index(after: newline)
        let currentColumn = beforeCursor[currentLineStart...].count
        let previousText = beforeCursor[..<newline]
        let previousLineStart = previousText.lastIndex(of: "\n").map {
            previousText.index(after: $0)
        } ?? previousText.startIndex
        let previousLineLength = previousText[previousLineStart...].count
        let targetColumn = min(cursorPreferredColumn, previousLineLength)
        let offset = -(currentColumn + 1 + previousLineLength - targetColumn)
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        return true
    }

    private func moveCursorToNextLogicalLine() -> Bool {
        guard let afterCursor = textDocumentProxy.documentContextAfterInput,
              let newline = afterCursor.firstIndex(of: "\n")
        else { return false }

        let currentLineRemainder = afterCursor[..<newline].count
        let nextLineStart = afterCursor.index(after: newline)
        let remainingText = afterCursor[nextLineStart...]
        let nextLineEnd = remainingText.firstIndex(of: "\n") ?? remainingText.endIndex
        let nextLineLength = remainingText[..<nextLineEnd].count
        let targetColumn = min(cursorPreferredColumn, nextLineLength)
        let offset = currentLineRemainder + 1 + targetColumn
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        return true
    }

    private func updateSpaceButtonTitle(
        _ title: String,
        accessibilityLabel: String
    ) {
        guard let spaceButton, var configuration = spaceButton.configuration else { return }
        configuration.title = title
        spaceButton.configuration = configuration
        spaceButton.accessibilityLabel = accessibilityLabel
    }

    private func commitReturn() {
        resetCompositionState()
        textDocumentProxy.insertText("\n")
        refreshComposition()
    }

    private func selectCandidate(_ candidate: String) {
        if pendingPunctuationSelection != nil {
            selectPunctuationCandidate(candidate)
            return
        }

        guard let index = currentCandidates.firstIndex(of: candidate),
              currentCandidateActions.indices.contains(index)
        else { return }

        switch currentCandidateActions[index] {
        case .cangjie(let text):
            SmartCandidateRanker.shared.record(
                code: buffer,
                candidate: text
            )
            _ = replaceTypedCode(with: text, showingAssociations: true)
        case .raw(let text):
            finishCommittedText(text)
        case .dictionary(let text):
            _ = replaceTypedCode(with: text, showingAssociations: true)
        case .translation(let text, let prefixCharacterCount):
            commitTranslation(
                text,
                replacingPrefixCharacterCount: prefixCharacterCount
            )
        case .association(let suggestion):
            commitAssociation(suggestion)
        }
    }

    private func selectPunctuationCandidate(_ candidate: String) {
        guard let pendingPunctuationSelection,
              currentCandidates.contains(candidate)
        else { return }

        defer {
            resetCompositionState()
            refreshComposition()
        }
        guard candidate != pendingPunctuationSelection.insertedText else { return }
        guard textDocumentProxy.documentContextBeforeInput?.hasSuffix(
            pendingPunctuationSelection.insertedText
        ) == true else { return }

        for _ in pendingPunctuationSelection.insertedText {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(candidate)
    }

    private func replaceTypedCode(
        with replacement: String,
        showingAssociations: Bool = false
    ) -> Bool {
        guard !buffer.isEmpty,
              textDocumentProxy.documentContextBeforeInput?.hasSuffix(buffer) == true
        else { return false }

        for _ in buffer {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(replacement)
        if showingAssociations {
            finishCommittedText(replacement)
        } else {
            resetCompositionState()
            refreshComposition()
        }
        return true
    }

    private func resetCompositionState() {
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        learnedCandidate = nil
        pendingPunctuationSelection = nil
        isSelectingAssociation = false
        associationContext = ""
        associationLanguage = nil
        learnedChineseContext = ""
    }

    private func refreshComposition() {
        guard !buffer.isEmpty else {
            currentCandidateActions = []
            currentCandidates = []
            learnedCandidate = nil
            compositionLabel.text = ""
            rebuildCandidateButtons()
            return
        }

        let cangjieCandidates = buffer.count <= 5
            ? decoder?.candidates(for: buffer, limit: 10) ?? []
            : []
        let dictionaryCandidates = offlineLexicon.chineseCandidates(
            for: buffer,
            limit: 10
        )
        var actions = candidateActions(
            dictionaryCandidates: dictionaryCandidates,
            cangjieCandidates: cangjieCandidates,
            limit: 10
        )
        let prediction = SmartCandidateRanker.shared.prediction(
            code: buffer,
            availableCandidates: buffer.isEmpty
                ? cangjieCandidates
                : cangjieCandidates + [buffer]
        )
        learnedCandidate = prediction?.candidate
        if let learnedCandidate {
            if learnedCandidate == buffer {
                actions.removeAll { $0.text == buffer }
                actions.insert(.raw(buffer), at: 0)
            } else if let index = actions.firstIndex(where: { action in
                if case .cangjie(let text) = action {
                    return text == learnedCandidate
                }
                return false
            }) {
                let action = actions.remove(at: index)
                actions.insert(action, at: 0)
            } else {
                self.learnedCandidate = nil
            }
        }
        currentCandidateActions = actions
        currentCandidates = actions.map(\.text)
        isSelectingAssociation = false
        let roots = cangjieRoots(for: buffer)
        compositionLabel.text = buffer.isEmpty ? "" : "\(roots)  ·  \(buffer)"
        rebuildCandidateButtons()
    }

    private func candidateActions(
        dictionaryCandidates: [String],
        cangjieCandidates: [String],
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

        let precedingChinese = chineseTextBeforeComposition()
        for candidate in cangjieCandidates where result.count < limit {
            append(.cangjie(candidate))
            let lookup = longestTranslationLookup(
                precedingChinese: precedingChinese,
                candidate: candidate
            )
            for translation in lookup.translations.prefix(2) {
                append(
                    .translation(
                        translation,
                        replacingPrefixCharacterCount: lookup.prefix.count
                    )
                )
            }
        }
        for candidate in dictionaryCandidates {
            append(.dictionary(candidate))
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
            let translations = offlineLexicon.englishCandidates(
                for: prefix + candidate,
                limit: 2
            )
            if !translations.isEmpty {
                return (prefix, translations)
            }
        }
        return ("", [])
    }

    private func chineseTextBeforeComposition() -> String {
        guard !buffer.isEmpty,
              let text = textDocumentProxy.documentContextBeforeInput,
              text.hasSuffix(buffer)
        else { return "" }

        let end = text.index(text.endIndex, offsetBy: -buffer.count)
        let preceding = text[..<end]
        let trailingChinese = String(
            preceding.reversed()
                .prefix {
                    PunctuationStrategy.isChinese(String($0))
                }
                .reversed()
        )
        return String(trailingChinese.suffix(16))
    }

    private func commitTranslation(
        _ text: String,
        replacingPrefixCharacterCount prefixCharacterCount: Int
    ) {
        let prefix = String(chineseTextBeforeComposition().suffix(prefixCharacterCount))
        let expectedSuffix = prefix + buffer
        guard !buffer.isEmpty,
              textDocumentProxy.documentContextBeforeInput?.hasSuffix(expectedSuffix) == true
        else { return }

        for _ in expectedSuffix {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(text)
        finishCommittedText(text, forcedLanguage: .english)
    }

    private func commitAssociation(
        _ suggestion: KeyboardAssociationDictionary.Suggestion
    ) {
        associationDictionary.recordSelection(suggestion)
        let insertedText = suggestion.language == .english
            ? suggestion.text + " "
            : suggestion.text
        textDocumentProxy.insertText(insertedText)
        learnCommittedText(suggestion.text)

        let context = suggestion.language == .chinese
            ? associationContext + suggestion.text
            : suggestion.text
        clearActiveComposition()
        showAssociations(context: context, language: suggestion.language)
    }

    private func finishCommittedText(
        _ text: String,
        forcedLanguage: KeyboardAssociationDictionary.Language? = nil
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            resetCompositionState()
            refreshComposition()
            return
        }

        let language = forcedLanguage ?? associationLanguage(for: cleanText)
        let previousContext = associationContext
        let previousLanguage = associationLanguage
        learnCommittedText(cleanText)
        clearActiveComposition()

        guard let language else {
            associationContext = ""
            associationLanguage = nil
            rebuildCandidateButtons()
            return
        }
        let context = language == .chinese && previousLanguage == language
            && !previousContext.isEmpty
            ? previousContext + cleanText
            : cleanText
        showAssociations(context: context, language: language)
    }

    private func showAssociations(
        context: String,
        language: KeyboardAssociationDictionary.Language
    ) {
        let suggestions = associationDictionary.suggestions(
            for: context,
            language: language,
            limit: 10
        )
        guard !suggestions.isEmpty else {
            dismissAssociation(clearContext: true)
            compositionLabel.text = ""
            rebuildCandidateButtons()
            return
        }

        associationContext = context
        associationLanguage = language
        currentCandidateActions = suggestions.map(CandidateAction.association)
        currentCandidates = suggestions.map(\.text)
        learnedCandidate = suggestions.first(where: \.isMostRecentSelection)?.text
        isSelectingAssociation = true
        compositionLabel.text = ""
        rebuildCandidateButtons()
    }

    private func dismissAssociation(clearContext: Bool) {
        if isSelectingAssociation {
            clearActiveComposition()
        }
        if clearContext {
            associationContext = ""
            associationLanguage = nil
        }
    }

    private func clearActiveComposition() {
        buffer = ""
        currentCandidates = []
        currentCandidateActions = []
        learnedCandidate = nil
        pendingPunctuationSelection = nil
        isSelectingAssociation = false
    }

    private func associationLanguage(
        for text: String
    ) -> KeyboardAssociationDictionary.Language? {
        guard !text.isEmpty else { return nil }
        if text.allSatisfy({
            PunctuationStrategy.isChinese(String($0))
        }) {
            return .chinese
        }
        if text.allSatisfy({
            $0.isASCII && ($0.isLetter || $0 == "'" || $0.isWhitespace)
        }) {
            return .english
        }
        return nil
    }

    private func learnCommittedText(_ text: String) {
        guard !text.isEmpty, text.allSatisfy({
            PunctuationStrategy.isChinese(String($0))
        }) else {
            learnedChineseContext = ""
            return
        }

        for character in text {
            let continuation = String(character)
            if !learnedChineseContext.isEmpty {
                associationDictionary.recordChineseSequence(
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

    private func rebuildCandidateButtons() {
        candidateStackView.arrangedSubviews.forEach { arrangedView in
            candidateStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        guard !currentCandidates.isEmpty else {
            let placeholder = UILabel()
            placeholder.text = buffer.isEmpty ? "倉頡／字典候選" : "沒有候選"
            placeholder.textColor = .secondaryLabel
            placeholder.font = .systemFont(ofSize: 16)
            candidateStackView.addArrangedSubview(placeholder)
            return
        }

        for (index, candidate) in currentCandidates.enumerated() {
            var configuration = UIButton.Configuration.plain()
            if let pendingPunctuationSelection {
                configuration.title = PunctuationStrategy.displayTitle(
                    for: candidate,
                    punctuation: pendingPunctuationSelection.definition
                )
            } else {
                configuration.title = candidate
            }
            let isTranslation = currentCandidateActions.indices.contains(index) && {
                if case .translation = currentCandidateActions[index] {
                    return true
                }
                return false
            }()
            configuration.baseForegroundColor = pendingPunctuationSelection == nil
                && candidate == learnedCandidate
                ? .systemBlue
                : isTranslation ? .secondaryLabel : .label
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 5,
                leading: 10,
                bottom: 5,
                trailing: 10
            )
            configuration.background.backgroundColor = characterKeyColor
            configuration.background.cornerRadius = 5
            configuration.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes
                    attributes.font = .systemFont(ofSize: 18)
                    return attributes
                }

            let button = UIButton(configuration: configuration)
            button.addAction(
                UIAction { [weak self] _ in self?.selectCandidate(candidate) },
                for: .touchUpInside
            )
            candidateStackView.addArrangedSubview(button)
        }
        candidateScrollView.setContentOffset(.zero, animated: false)
    }

    private func updateAppearance() {
        let darkAppearance = textDocumentProxy.keyboardAppearance == .dark
        view.overrideUserInterfaceStyle = darkAppearance ? .dark : .light
        view.backgroundColor = .clear
    }

    private func updateReturnKeyTitle() {
        guard var configuration = returnButton?.configuration else { return }
        configuration.title = returnKeyTitle
        returnButton?.configuration = configuration
    }

    private var returnKeyTitle: String {
        switch textDocumentProxy.returnKeyType {
        case .go:
            "前往"
        case .search:
            "搜尋"
        case .send:
            "傳送"
        case .done:
            "完成"
        case .next:
            "下一步"
        case .continue:
            "繼續"
        default:
            "return"
        }
    }

    private var shiftSymbolName: String {
        switch shiftState {
        case .lowercased:
            "shift"
        case .uppercased:
            "shift.fill"
        case .capsLocked:
            "capslock.fill"
        }
    }

    private var keyboardBackgroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1)
                : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
        }
    }

    private var characterKeyColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1)
                : .white
        }
    }

    private var controlKeyColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.25, green: 0.25, blue: 0.27, alpha: 1)
                : UIColor(red: 0.67, green: 0.69, blue: 0.72, alpha: 1)
        }
    }

    private func keyColor(for role: KeyRole) -> UIColor {
        switch role {
        case .character:
            characterKeyColor
        case .control:
            controlKeyColor
        }
    }

    private func cangjieRoots(for code: String) -> String {
        let roots: [Character: Character] = [
            "a": "日", "b": "月", "c": "金", "d": "木",
            "e": "水", "f": "火", "g": "土", "h": "竹",
            "i": "戈", "j": "十", "k": "大", "l": "中",
            "m": "一", "n": "弓", "o": "人", "p": "心",
            "q": "手", "r": "口", "s": "尸", "t": "廿",
            "u": "山", "v": "女", "w": "田", "x": "難",
            "y": "卜", "z": "重",
        ]
        return String(code.lowercased().compactMap { roots[$0] })
    }
}
