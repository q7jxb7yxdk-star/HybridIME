import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
    private final class KeyPreviewView: UIView {
        private let shapeLayer = CAShapeLayer()
        private let titleLabel = UILabel()
        private let subtitleLabel = UILabel()
        private let labels = UIStackView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.22
            layer.shadowRadius = 1.5
            layer.shadowOffset = CGSize(width: 0, height: 1)

            shapeLayer.fillColor = UIColor.systemBackground.cgColor
            layer.insertSublayer(shapeLayer, at: 0)

            titleLabel.textColor = .label
            titleLabel.textAlignment = .center
            subtitleLabel.font = .systemFont(ofSize: 32, weight: .regular)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.textAlignment = .center

            labels.axis = .vertical
            labels.alignment = .center
            labels.spacing = -8
            labels.isUserInteractionEnabled = false
            labels.translatesAutoresizingMaskIntoConstraints = false
            labels.addArrangedSubview(titleLabel)
            labels.addArrangedSubview(subtitleLabel)
            addSubview(labels)
            NSLayoutConstraint.activate([
                labels.centerXAnchor.constraint(equalTo: centerXAnchor),
                labels.centerYAnchor.constraint(equalTo: topAnchor, constant: 33),
                labels.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func show(
            title: String,
            subtitle: String?,
            sourceSize: CGSize,
            usesHorizontalLabels: Bool
        ) {
            titleLabel.text = title
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = subtitle == nil
            labels.axis = subtitle != nil && usesHorizontalLabels ? .horizontal : .vertical
            labels.spacing = subtitle != nil && usesHorizontalLabels ? 2 : -8
            titleLabel.font = .systemFont(
                ofSize: subtitle == nil ? 31 : (usesHorizontalLabels ? 22 : 32),
                weight: .regular
            )
            subtitleLabel.font = .systemFont(
                ofSize: usesHorizontalLabels ? 22 : 32,
                weight: .regular
            )
            let stemWidth = min(sourceSize.width, bounds.width - 20)
            let stemLeft = (bounds.width - stemWidth) / 2
            let stemTop = bounds.height - sourceSize.height
            let cornerRadius: CGFloat = 17
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cornerRadius, y: 0))
            path.addLine(to: CGPoint(x: bounds.width - cornerRadius, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: bounds.width, y: cornerRadius),
                controlPoint: CGPoint(x: bounds.width, y: 0)
            )
            path.addLine(to: CGPoint(x: bounds.width, y: stemTop - cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: bounds.width - cornerRadius, y: stemTop),
                controlPoint: CGPoint(x: bounds.width, y: stemTop)
            )
            path.addLine(to: CGPoint(x: stemLeft + stemWidth, y: stemTop))
            path.addLine(to: CGPoint(x: stemLeft + stemWidth, y: bounds.height - cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: stemLeft + stemWidth - cornerRadius, y: bounds.height),
                controlPoint: CGPoint(x: stemLeft + stemWidth, y: bounds.height)
            )
            path.addLine(to: CGPoint(x: stemLeft + cornerRadius, y: bounds.height))
            path.addQuadCurve(
                to: CGPoint(x: stemLeft, y: bounds.height - cornerRadius),
                controlPoint: CGPoint(x: stemLeft, y: bounds.height)
            )
            path.addLine(to: CGPoint(x: stemLeft, y: stemTop))
            path.addLine(to: CGPoint(x: cornerRadius, y: stemTop))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: stemTop - cornerRadius),
                controlPoint: CGPoint(x: 0, y: stemTop)
            )
            path.addLine(to: CGPoint(x: 0, y: cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: cornerRadius, y: 0),
                controlPoint: CGPoint(x: 0, y: 0)
            )
            path.close()
            shapeLayer.path = path.cgPath
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            shapeLayer.frame = bounds
        }
    }

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
        case landscapePhone
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
        case cangjie(String, code: String)
        case raw(String)
        case dictionary(String)
        case translation(String, replacingPrefixCharacterCount: Int)
        case association(KeyboardAssociationDictionary.Suggestion)

        var text: String {
            switch self {
            case .cangjie(let text, _),
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
    private let keyPreview = KeyPreviewView()

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
    private var isAwaitingSecondSpace = false
    private var isCursorTrackpadAppearanceActive = false
    private var cursorTrackpadLabelVisibility: [ObjectIdentifier: Bool] = [:]
    private var cursorGestureStartPoint = CGPoint.zero
    private var cursorHorizontalGestureStep = 0
    private var cursorVerticalGestureStep = 0
    private var cursorPreferredColumn = 0
    private var deleteRepeatTimer: Timer?
    // 游標每移動一個字元所需的水平滑動距離（pt）；數值越小越靈敏。
    private let cursorMovementThreshold: CGFloat = 10
    // 每觸發一次上一行或下一行移動所需的垂直滑動距離（pt）；數值越小越靈敏。
    private let cursorVerticalMovementThreshold: CGFloat = 15
    // 找不到實際換行時，每次垂直移動所估算的字元數。數值越小則移動較短。
    private let cursorEstimatedCharactersPerLine = 10
    private let cursorFeedbackGenerator = UISelectionFeedbackGenerator()

    private var keyboardHeight: CGFloat {
        switch layoutMode {
        case .compact:
            traitCollection.userInterfaceIdiom == .phone ? 242 : 260
        case .landscapePhone:
            187
        case .wideIPad:
            isLandscapeInterfaceOrientation ? 353 : 265
        }
    }

    private var compactShiftDeleteKeyWidth: CGFloat {
        layoutMode == .landscapePhone ? 88 : 46
    }

    private var compactPageKeyWidth: CGFloat {
        layoutMode == .landscapePhone ? 66 : 43
    }

    private var compactReturnKeyWidth: CGFloat {
        layoutMode == .landscapePhone ? 138 : 93
    }

    private let wideIPadKeyHeight: CGFloat = 50

    private var isLandscapePhoneLayout: Bool {
        guard traitCollection.userInterfaceIdiom == .phone else { return false }
        return view.window?.windowScene != nil
            ? isLandscapeInterfaceOrientation
            : traitCollection.verticalSizeClass == .compact
    }

    private var isLandscapeInterfaceOrientation: Bool {
        view.window?.windowScene?.effectiveGeometry.interfaceOrientation.isLandscape ?? false
    }

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
        hasDictationKey = false
        layoutMode = initialLayoutMode()
        configureInterface()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            self.updateAppearance()
        }
        rebuildKeyboard()
        hasBuiltKeyboard = true
        refreshComposition()
        updateAppearance()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateLayoutModeIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        stopDeleteRepeat()
        setCursorTrackpadAppearance(active: false)
        resetCompositionState()
        super.viewWillDisappear(animated)
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
        candidateArea.setContentCompressionResistancePriority(.required, for: .vertical)

        keyboardStackView.axis = .vertical
        keyboardStackView.distribution = .fill
        keyboardStackView.spacing = 7
        keyboardStackView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        rootStack.addArrangedSubview(candidateArea)
        rootStack.addArrangedSubview(keyboardStackView)
        rootStack.axis = .vertical
        rootStack.spacing = 7
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        keyPreview.isHidden = true
        view.addSubview(keyPreview)

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        heightConstraint.priority = .required
        heightConstraint.isActive = true
        keyboardHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
        ])
    }

    private func rebuildKeyboard() {
        stopDeleteRepeat()
        setCursorTrackpadAppearance(active: false)
        hideKeyPreview()
        keyboardStackView.arrangedSubviews.forEach { arrangedView in
            keyboardStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        candidateArea.isHidden = false
        keyboardHeightConstraint?.constant = keyboardHeight
        keyboardStackView.distribution = .fillEqually
        compositionLabel.isHidden = true
        keyboardStackView.spacing = 5
        rootStack.spacing = 5

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
        if isLandscapePhoneLayout {
            nextMode = .landscapePhone
        } else if traitCollection.userInterfaceIdiom == .pad,
           traitCollection.horizontalSizeClass == .regular,
           view.bounds.width >= 700
        {
            nextMode = .wideIPad
        } else {
            nextMode = .compact
        }

        guard layoutMode != nextMode else {
            let nextHeight = keyboardHeight
            if keyboardHeightConstraint?.constant != nextHeight {
                keyboardHeightConstraint?.constant = nextHeight
            }
            return
        }
        layoutMode = nextMode
        guard hasBuiltKeyboard else { return }
        rebuildKeyboard()
    }

    private func initialLayoutMode() -> KeyboardLayoutMode {
        if isLandscapePhoneLayout {
            return .landscapePhone
        }

        return traitCollection.userInterfaceIdiom == .pad
            && traitCollection.horizontalSizeClass != .compact
            ? .wideIPad
            : .compact
    }

    private func loadDecoderIfNeeded() {
        guard decoder == nil else { return }
        decoder = CangjieDecoder(lexicon: offlineLexicon)
    }

    private func buildWideIPadLetterRows() {
        let deleteButton = makeDeleteButton(height: wideIPadKeyHeight)
        keyboardStackView.addArrangedSubview(
            makeWideIPadLetterRow(
                letterRows[0],
                trailingControls: [deleteButton],
                trailingControlWidthMultipliers: [1.25]
            )
        )

        let returnButton = makeReturnButton()
        keyboardStackView.addArrangedSubview(
            makeWideIPadLetterRow(
                letterRows[1],
                trailingControls: [returnButton],
                leadingSpacerCount: 1,
                trailingInsetInKeyWidths: 0.55,
                trailingControlWidthMultipliers: [1.25]
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
                trailingControls: [rightShiftButton],
                trailingKeyButtons: [commaButton, periodButton],
                leadingControlWidthMultipliers: [1],
                trailingControlWidthMultipliers: [1.25]
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
                leadingSpacerCount: 1,
                trailingInsetInKeyWidths: 0.55
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
                leadingSpacerCount: 1,
                trailingInsetInKeyWidths: 0.55
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
            installKeyPreview(on: button, title: key)
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
        trailingKeyButtons: [UIButton] = [],
        leadingSpacerCount: Int = 0,
        trailingInsetInKeyWidths: CGFloat = 0,
        leadingControlWidthMultipliers: [CGFloat] = [],
        trailingControlWidthMultipliers: [CGFloat] = []
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
            keyButtons: keyButtons + trailingKeyButtons,
            leadingControls: leadingControls,
            trailingControls: trailingControls,
            leadingInsetInKeyWidths: CGFloat(leadingSpacerCount) * 0.45,
            trailingInsetInKeyWidths: trailingInsetInKeyWidths,
            leadingControlWidthMultipliers: leadingControlWidthMultipliers,
            trailingControlWidthMultipliers: trailingControlWidthMultipliers
        )
    }

    private func makeWideIPadCharacterRow(
        _ keys: [String],
        trailingControls: [UIButton],
        leadingSpacerCount: Int = 0,
        trailingInsetInKeyWidths: CGFloat = 0
    ) -> UIView {
        let keyButtons = keys.map { key in
            let button = makeKey(title: key, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterSymbol(key) },
                for: .touchUpInside
            )
            installKeyPreview(on: button, title: key)
            return button
        }
        return makeWideIPadRow(
            keyButtons: keyButtons,
            trailingControls: trailingControls,
            leadingInsetInKeyWidths: CGFloat(leadingSpacerCount) * 0.45,
            trailingInsetInKeyWidths: trailingInsetInKeyWidths,
            trailingControlWidthMultipliers: [1.25]
        )
    }

    private func makeWideIPadSymbolRow(
        _ keys: [WideSymbolKey],
        trailingControls: [UIButton],
        leadingSpacerCount: Int = 0,
        trailingInsetInKeyWidths: CGFloat = 0
    ) -> UIView {
        let keyButtons = keys.map { makeWideIPadSymbolButton($0) }
        return makeWideIPadRow(
            keyButtons: keyButtons,
            trailingControls: trailingControls,
            leadingInsetInKeyWidths: CGFloat(leadingSpacerCount) * 0.45,
            trailingInsetInKeyWidths: trailingInsetInKeyWidths,
            trailingControlWidthMultipliers: [1.25]
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
            leadingInsetInKeyWidths: 2,
            trailingInsetInKeyWidths: 3
        )
    }

    private func makeWideIPadRow(
        keyButtons: [UIButton],
        leadingControls: [UIButton] = [],
        trailingControls: [UIButton] = [],
        leadingInsetInKeyWidths: CGFloat = 0,
        trailingInsetInKeyWidths: CGFloat = 0,
        leadingControlWidthMultipliers: [CGFloat] = [],
        trailingControlWidthMultipliers: [CGFloat] = []
    ) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        // iPadOS keeps letter keys uniform, but gives Shift, Delete and Return
        // about 1.25 key widths.  Its home row starts at a half-key inset rather
        // than at a full invisible key slot.
        guard let referenceKey = keyButtons.first else {
            return wrap(row, horizontalInset: 0)
        }

        let leadingInset = leadingInsetInKeyWidths > 0 ? UIView() : nil
        let trailingInset = trailingInsetInKeyWidths > 0 ? UIView() : nil
        if let leadingInset {
            row.addArrangedSubview(leadingInset)
        }
        leadingControls.forEach { row.addArrangedSubview($0) }
        keyButtons.forEach { row.addArrangedSubview($0) }
        trailingControls.forEach { row.addArrangedSubview($0) }
        if let trailingInset {
            row.addArrangedSubview(trailingInset)
        }

        // Activating cross-view constraints is safe only after every view has
        // joined this stack view; otherwise UIKit terminates the extension.
        if let leadingInset {
            leadingInset.widthAnchor.constraint(
                equalTo: referenceKey.widthAnchor,
                multiplier: leadingInsetInKeyWidths
            ).isActive = true
        }
        for keyButton in keyButtons.dropFirst() {
            keyButton.widthAnchor.constraint(equalTo: referenceKey.widthAnchor).isActive = true
        }
        let resolvedLeadingMultipliers = leadingControlWidthMultipliers.count == leadingControls.count
            ? leadingControlWidthMultipliers
            : Array(repeating: 1, count: leadingControls.count)
        let resolvedTrailingMultipliers = trailingControlWidthMultipliers.count == trailingControls.count
            ? trailingControlWidthMultipliers
            : Array(repeating: 1, count: trailingControls.count)
        for (control, multiplier) in zip(leadingControls, resolvedLeadingMultipliers) {
            control.widthAnchor.constraint(
                equalTo: referenceKey.widthAnchor,
                multiplier: multiplier
            ).isActive = true
        }
        for (control, multiplier) in zip(trailingControls, resolvedTrailingMultipliers) {
            control.widthAnchor.constraint(
                equalTo: referenceKey.widthAnchor,
                multiplier: multiplier
            ).isActive = true
        }
        if let trailingInset {
            trailingInset.widthAnchor.constraint(
                equalTo: referenceKey.widthAnchor,
                multiplier: trailingInsetInKeyWidths
            ).isActive = true
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
            height: wideIPadKeyHeight
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

        installKeyPreview(on: button, title: key.primary)

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
            installKeyPreview(on: button, title: key)
            return button
        }

        let usesAlternatePrimary = shiftState != .lowercased
        if usesAlternatePrimary {
            let button = makeKey(title: alternateKey, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterWidePunctuation(alternateKey) },
                for: .touchUpInside
            )
            installKeyPreview(on: button, title: alternateKey)
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
            height: wideIPadKeyHeight
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

        installKeyPreview(on: button, title: key)

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
            if !usesShift {
                installKeyPreview(on: button, title: displayedKey)
            }
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
        shiftButton.widthAnchor.constraint(
            equalToConstant: compactShiftDeleteKeyWidth
        ).isActive = true
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
        deleteButton.widthAnchor.constraint(
            equalToConstant: compactShiftDeleteKeyWidth
        ).isActive = true
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
        pageButton.widthAnchor.constraint(equalToConstant: compactPageKeyWidth).isActive = true
        row.addArrangedSubview(pageButton)

        var punctuationButtons: [UIButton] = []
        for key in punctuationKeys {
            let button = makeKey(title: key, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterSymbol(key) },
                for: .touchUpInside
            )
            installKeyPreview(on: button, title: key)
            row.addArrangedSubview(button)
            punctuationButtons.append(button)
        }
        equalizeWidths(punctuationButtons)

        let deleteButton = makeDeleteButton()
        deleteButton.widthAnchor.constraint(
            equalToConstant: compactShiftDeleteKeyWidth
        ).isActive = true
        row.addArrangedSubview(deleteButton)
        return wrap(row, horizontalInset: 0)
    }

    private func makeBottomRow() -> UIView {
        if layoutMode == .wideIPad {
            return makeWideIPadBottomRow()
        }

        if !needsInputModeSwitchKey {
            return makeCenteredCompactBottomRow()
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
        pageButton.widthAnchor.constraint(equalToConstant: compactPageKeyWidth).isActive = true
        row.addArrangedSubview(pageButton)

        if needsInputModeSwitchKey {
            let inputModeButton = makeInputModeButton()
            inputModeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
            row.addArrangedSubview(inputModeButton)
        }

        let spaceButton = makeSpaceButton()
        row.addArrangedSubview(spaceButton)

        for punctuation in [",", "."] {
            let button = makeKey(title: punctuation, role: .character)
            button.addAction(
                UIAction { [weak self] _ in self?.enterSymbol(punctuation) },
                for: .touchUpInside
            )
            installKeyPreview(on: button, title: punctuation)
            button.widthAnchor.constraint(
                equalToConstant: compactPageKeyWidth
            ).isActive = true
            row.addArrangedSubview(button)
        }

        let returnButton = makeReturnButton()
        returnButton.widthAnchor.constraint(equalToConstant: compactReturnKeyWidth).isActive = true
        row.addArrangedSubview(returnButton)

        return wrap(row, horizontalInset: 0)
    }

    private func makeCenteredCompactBottomRow() -> UIView {
        let row = UIView()

        let pageTitle = currentPage == .letters ? "123" : "ABC"
        let pageDestination = currentPage == .letters
            ? KeyboardPage.numbers
            : KeyboardPage.letters
        let pageButton = makePageButton(title: pageTitle, destination: pageDestination)

        let commaButton = makeKey(title: ",", role: .character)
        commaButton.addAction(
            UIAction { [weak self] _ in self?.enterSymbol(",") },
            for: .touchUpInside
        )
        installKeyPreview(on: commaButton, title: ",")

        let spaceButton = makeSpaceButton(minimumWidth: 44)

        let periodButton = makeKey(title: ".", role: .character)
        periodButton.addAction(
            UIAction { [weak self] _ in self?.enterSymbol(".") },
            for: .touchUpInside
        )
        installKeyPreview(on: periodButton, title: ".")

        let returnButton = makeReturnButton()

        let buttons = [pageButton, commaButton, spaceButton, periodButton, returnButton]
        buttons.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }

        NSLayoutConstraint.activate([
            pageButton.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            pageButton.topAnchor.constraint(equalTo: row.topAnchor),
            pageButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            pageButton.widthAnchor.constraint(equalToConstant: compactPageKeyWidth),

            commaButton.leadingAnchor.constraint(equalTo: pageButton.trailingAnchor, constant: 5),
            commaButton.topAnchor.constraint(equalTo: row.topAnchor),
            commaButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            commaButton.widthAnchor.constraint(equalToConstant: compactPageKeyWidth),

            spaceButton.leadingAnchor.constraint(equalTo: commaButton.trailingAnchor, constant: 5),
            spaceButton.trailingAnchor.constraint(equalTo: periodButton.leadingAnchor, constant: -5),
            spaceButton.topAnchor.constraint(equalTo: row.topAnchor),
            spaceButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            returnButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            returnButton.topAnchor.constraint(equalTo: row.topAnchor),
            returnButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            returnButton.widthAnchor.constraint(equalToConstant: compactPageKeyWidth),

            periodButton.trailingAnchor.constraint(equalTo: returnButton.leadingAnchor, constant: -5),
            periodButton.topAnchor.constraint(equalTo: row.topAnchor),
            periodButton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            periodButton.widthAnchor.constraint(equalToConstant: compactPageKeyWidth),
        ])

        return row
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
        let pageButton = makeKey(
            title: title,
            role: .control,
            fontSize: layoutMode == .wideIPad ? 22 : 14
        )
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

    private func makeSpaceButton(minimumWidth: CGFloat = 105) -> UIButton {
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
        spaceButton.widthAnchor.constraint(
            greaterThanOrEqualToConstant: minimumWidth
        ).isActive = true
        self.spaceButton = spaceButton
        return spaceButton
    }

    private func makeReturnButton() -> UIButton {
        let returnButton = makeIconKey(
            systemName: "arrow.turn.down.left",
            accessibilityLabel: "Return",
            role: .control
        )
        returnButton.addAction(
            UIAction { [weak self] _ in self?.commitReturn() },
            for: .touchUpInside
        )
        self.returnButton = returnButton
        return returnButton
    }

    private func makeDeleteButton(height: CGFloat? = nil) -> UIButton {
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
        let deleteGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleDeleteLongPress(_:))
        )
        deleteGesture.minimumPressDuration = 0.35
        deleteGesture.allowableMovement = 24
        deleteGesture.cancelsTouchesInView = true
        button.addGestureRecognizer(deleteGesture)
        return button
    }

    private func makeKey(
        title: String,
        role: KeyRole,
        fontSize: CGFloat = 21,
        height: CGFloat? = nil
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = keyColor(for: role)
        configuration   .background.cornerRadius = controlKeyCornerRadius(for: role)
        configuration.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(
                    ofSize: self.controlKeyFontSize(fontSize, for: role),
                    weight: .regular
                )
                return attributes
            }

        return configuredButton(
            configuration: configuration,
            normalColor: keyColor(for: role),
            accessibilityLabel: title,
            height: height ?? defaultKeyHeight
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

        let isLandscapePhone = layoutMode == .landscapePhone

        let rootLabel = UILabel()
        rootLabel.text = root
        rootLabel.font = .systemFont(
            ofSize: isLandscapePhone ? 17 : 21,
            weight: .regular
        )
        rootLabel.textColor = .label
        rootLabel.textAlignment = .center

        let letterLabel = UILabel()
        letterLabel.text = displayedLetter
        letterLabel.font = .systemFont(
            ofSize: isLandscapePhone ? 16 : 21,
            weight: .regular
        )
        letterLabel.textColor = .secondaryLabel
        letterLabel.textAlignment = .center

        let labels = UIStackView(arrangedSubviews: [rootLabel, letterLabel])
        labels.axis = isLandscapePhone ? .horizontal : .vertical
        labels.alignment = .center
        labels.spacing = isLandscapePhone ? 2 : -6
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(labels)
        NSLayoutConstraint.activate([
            labels.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor, constant: 2),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor, constant: -2),
        ])
        installKeyPreview(on: button, title: root, subtitle: displayedLetter)
        return button
    }

    private func installKeyPreview(
        on button: UIButton,
        title: String,
        subtitle: String? = nil
    ) {
        button.addAction(
            UIAction { [weak self, weak button] _ in
                guard let button else { return }
                self?.showKeyPreview(for: button, title: title, subtitle: subtitle)
            },
            for: .touchDown
        )
        button.addTarget(
            self,
            action: #selector(hideKeyPreview),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
    }

    private func showKeyPreview(for button: UIButton, title: String, subtitle: String?) {
        let sourceFrame = button.convert(button.bounds, to: view)
        let previewWidth: CGFloat
        if layoutMode == .landscapePhone {
            previewWidth = min(max(sourceFrame.width * 1.45, 46), 78)
        } else {
            previewWidth = min(max(sourceFrame.width * 1.55, 60), 102)
        }
        let previewHeight = sourceFrame.height + 66
        let previewX = min(
            max(sourceFrame.midX - previewWidth / 2, 3),
            view.bounds.width - previewWidth - 3
        )
        keyPreview.frame = CGRect(
            x: previewX,
            y: max(0, sourceFrame.maxY - previewHeight),
            width: previewWidth,
            height: previewHeight
        )
        keyPreview.show(
            title: title,
            subtitle: subtitle,
            sourceSize: sourceFrame.size,
            usesHorizontalLabels: layoutMode == .landscapePhone
        )
        keyPreview.isHidden = false
        view.bringSubviewToFront(keyPreview)
    }

    @objc
    private func hideKeyPreview() {
        keyPreview.isHidden = true
    }

    private func makeIconKey(
        systemName: String,
        accessibilityLabel: String,
        role: KeyRole,
        height: CGFloat? = nil
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemName)
        configuration.contentInsets = .zero
        configuration.preferredSymbolConfigurationForImage = controlKeySymbolConfiguration(for: role)
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = keyColor(for: role)
        configuration.background.cornerRadius = controlKeyCornerRadius(for: role)

        return configuredButton(
            configuration: configuration,
            normalColor: keyColor(for: role),
            accessibilityLabel: accessibilityLabel,
            height: height ?? defaultKeyHeight
        )
    }

    private func configuredButton(
        configuration: UIButton.Configuration,
        normalColor: UIColor,
        accessibilityLabel: String,
        height: CGFloat
    ) -> UIButton {
        let normalForegroundColor = configuration.baseForegroundColor
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accessibilityLabel
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.22
        button.layer.shadowRadius = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: height)
        heightConstraint.priority = UILayoutPriority(749)
        button.setContentCompressionResistancePriority(
            UILayoutPriority(748),
            for: .vertical
        )
        heightConstraint.isActive = true
        button.configurationUpdateHandler = { [weak self] button in
            guard var configuration = button.configuration else { return }
            if let self, self.isCursorTrackpadAppearanceActive {
                configuration.baseForegroundColor = .clear
                configuration.background.backgroundColor = self.cursorTrackpadKeyColor
            } else {
                configuration.baseForegroundColor = normalForegroundColor
                configuration.background.backgroundColor = button.isHighlighted
                    ? UIColor.systemGray2
                    : normalColor
            }
            button.configuration = configuration
        }
        return button
    }

    private var defaultKeyHeight: CGFloat {
        layoutMode == .wideIPad ? wideIPadKeyHeight : 42
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
        loadDecoderIfNeeded()
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

    @objc
    private func handleDeleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            stopDeleteRepeat()
            deleteBackward()

            let timer = Timer(
                timeInterval: 0.08,
                target: self,
                selector: #selector(repeatDeleteBackward),
                userInfo: nil,
                repeats: true
            )
            deleteRepeatTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .ended, .cancelled, .failed:
            stopDeleteRepeat()
        default:
            break
        }
    }

    @objc
    private func repeatDeleteBackward() {
        deleteBackward()
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }

    private func commitSpace() {
        if shiftState == .lowercased,
           buffer.isEmpty,
           pendingPunctuationSelection == nil,
           isAwaitingSecondSpace,
           textDocumentProxy.documentContextBeforeInput?.hasSuffix(" ") == true
        {
            let useFullWidth = PunctuationStrategy.usesFullWidth(
                before: textDocumentProxy.documentContextBeforeInput
            ) ?? false
            textDocumentProxy.deleteBackward()
            resetCompositionState()
            textDocumentProxy.insertText(useFullWidth ? "。" : ".")
            refreshComposition()
            return
        }

        isAwaitingSecondSpace = false
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
                isAwaitingSecondSpace = true
                refreshComposition()
            }
            return
        }

        if learnedCandidate == buffer, !buffer.isEmpty {
            let typedCode = buffer
            textDocumentProxy.insertText(" ")
            finishCommittedText(typedCode)
            isAwaitingSecondSpace = true
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
            isAwaitingSecondSpace = true
            return
        }
        resetCompositionState()
        textDocumentProxy.insertText(" ")
        isAwaitingSecondSpace = true
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
            setCursorTrackpadAppearance(active: true)
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
            updateSpaceButtonTitle("HybridIME", accessibilityLabel: "空格")
            setCursorTrackpadAppearance(active: false)
        default:
            break
        }

        spaceButton.isHighlighted = gesture.state == .began || gesture.state == .changed
    }

    private func setCursorTrackpadAppearance(active: Bool) {
        guard isCursorTrackpadAppearanceActive != active else { return }

        isCursorTrackpadAppearanceActive = active
        if active {
            hideKeyPreview()
        }
        updateCursorTrackpadLabelVisibility(in: keyboardStackView, hidden: active)
        if !active {
            cursorTrackpadLabelVisibility.removeAll()
        }
        refreshButtonAppearance(in: keyboardStackView)
    }

    private func updateCursorTrackpadLabelVisibility(
        in view: UIView,
        hidden: Bool
    ) {
        if let label = view as? UILabel {
            let identifier = ObjectIdentifier(label)
            if hidden {
                cursorTrackpadLabelVisibility[identifier] = label.isHidden
                label.isHidden = true
            } else if let wasHidden = cursorTrackpadLabelVisibility[identifier] {
                label.isHidden = wasHidden
            }
        }
        view.subviews.forEach {
            updateCursorTrackpadLabelVisibility(in: $0, hidden: hidden)
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
        case .cangjie(let text, let code):
            SmartCandidateRanker.shared.record(
                code: code,
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
        isAwaitingSecondSpace = false
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

        let hasCangjieCode = buffer.count <= 5
        let staticCangjieCandidates = hasCangjieCode
            ? decoder?.candidates(for: buffer, limit: .max) ?? []
            : []
        let rankedCangjieCandidates = SmartCandidateRanker.shared.rankedCandidates(
            code: buffer,
            candidates: staticCangjieCandidates,
            rootCandidate: hasCangjieCode
                ? decoder?.rootCandidate(for: buffer)
                : nil,
            limit: .max
        )
        let cangjieCandidates = decoder?.visibleCandidates(
            rankedCangjieCandidates,
            limit: 10
        ) ?? []
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
                ? cangjieCandidates.map(\.text)
                : cangjieCandidates.map(\.text) + [buffer]
        )
        learnedCandidate = prediction?.candidate
        if let learnedCandidate {
            if learnedCandidate == buffer {
                actions.removeAll { $0.text == buffer }
                actions.insert(.raw(buffer), at: 0)
            } else if let index = actions.firstIndex(where: { action in
                if case .cangjie(let text, _) = action {
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
        cangjieCandidates: [CangjieCandidate],
        limit: Int
    ) -> [CandidateAction] {
        var result: [CandidateAction] = []
        var translations: [CandidateAction] = []
        var seen: Set<String> = []

        func append(_ action: CandidateAction) {
            guard result.count < limit, seen.insert(action.text).inserted else {
                return
            }
            result.append(action)
        }

        let precedingChinese = chineseTextBeforeComposition()
        for candidate in cangjieCandidates where result.count < limit {
            append(.cangjie(candidate.text, code: candidate.code))
            let lookup = longestTranslationLookup(
                precedingChinese: precedingChinese,
                candidate: candidate.text
            )
            for translation in lookup.translations.prefix(2) {
                translations.append(
                    .translation(
                        translation,
                        replacingPrefixCharacterCount: lookup.prefix.count
                    )
                )
            }
        }
        translations.forEach { append($0) }
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
        isAwaitingSecondSpace = false
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
            button.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            button.addAction(
                UIAction { [weak self] _ in self?.selectCandidate(candidate) },
                for: .touchUpInside
            )
            candidateStackView.addArrangedSubview(button)
        }
        candidateScrollView.setContentOffset(.zero, animated: false)
    }

    private func updateAppearance() {
        view.overrideUserInterfaceStyle = .unspecified
        view.backgroundColor = .clear
        refreshButtonAppearance(in: rootStack)
    }

    private func refreshButtonAppearance(in view: UIView) {
        if let button = view as? UIButton {
            button.setNeedsUpdateConfiguration()
        }
        view.subviews.forEach { self.refreshButtonAppearance(in: $0) }
    }

    private func updateReturnKeyTitle() {
        guard var configuration = returnButton?.configuration else { return }
        configuration.title = nil
        configuration.image = UIImage(systemName: "arrow.turn.down.left")
        configuration.preferredSymbolConfigurationForImage =
            controlKeySymbolConfiguration(for: .control)
        returnButton?.accessibilityLabel = "Return"
        returnButton?.configuration = configuration
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

    private func controlKeyCornerRadius(for role: KeyRole) -> CGFloat {
        layoutMode == .wideIPad && role == .control ? 9 : 5
    }

    private func controlKeyFontSize(_ fontSize: CGFloat, for role: KeyRole) -> CGFloat {
        layoutMode == .wideIPad && role == .control ? max(fontSize, 22) : fontSize
    }

    private func controlKeySymbolConfiguration(for role: KeyRole) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(
            pointSize: layoutMode == .wideIPad && role == .control ? 22 : 18,
            weight: .regular
        )
    }

    private var keyboardBackgroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
                : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1)
        }
    }

    private var cursorTrackpadKeyColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1)
                : UIColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1)
        }
    }

    private var characterKeyColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1)
                : .white
        }
    }

    private var controlKeyColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1)
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
