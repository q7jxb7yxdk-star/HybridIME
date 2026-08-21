import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController,
    UICollectionViewDataSource,
    UICollectionViewDelegateFlowLayout
{
    private enum KeyboardPage {
        case letters
        case numbers
        case symbols
        case emoji
    }

    private enum EmojiCategory: CaseIterable {
        case frequentlyUsed
        case smileys
        case people
        case animals
        case food
        case activities
        case travel
        case objects
        case symbols
        case flags

        var symbolName: String {
            switch self {
            case .frequentlyUsed: "clock"
            case .smileys: "face.smiling"
            case .people: "person.2"
            case .animals: "pawprint"
            case .food: "carrot"
            case .activities: "soccerball"
            case .travel: "car"
            case .objects: "lightbulb"
            case .symbols: "heart"
            case .flags: "flag"
            }
        }

        var title: String {
            switch self {
            case .frequentlyUsed: "常用"
            case .smileys: "表情與情感"
            case .people: "人物與手勢"
            case .animals: "動物與自然"
            case .food: "飲食"
            case .activities: "活動"
            case .travel: "旅遊與地點"
            case .objects: "物件"
            case .symbols: "符號"
            case .flags: "旗幟"
            }
        }

        var emojis: [String] {
            switch self {
            case .frequentlyUsed:
                ["😀", "😂", "🥰", "😍", "😊", "😭", "😘", "👍",
                 "🙏", "👏", "🎉", "❤️", "🔥", "✨", "✅", "🤣",
                 "😁", "🥳", "😎", "🤔", "💪", "👌", "💯", "🚀",
                 "😄", "😅", "😉", "😋", "🤗", "🤩", "😴", "🙌"]
            case .smileys:
                ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣",
                 "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰",
                 "😘", "😋", "😜", "🤪", "🤨", "🧐", "🤓", "😎",
                 "🥳", "🤩", "🥺", "😢", "😭", "😤", "😡", "🤯"]
            case .people:
                ["👋", "🤚", "🖐️", "✋", "🖖", "👌", "🤌", "🤏",
                 "✌️", "🤞", "🫰", "🤟", "🤘", "🤙", "👈", "👉",
                 "👆", "👇", "☝️", "👍", "👎", "✊", "👏", "🙏"]
            case .animals:
                ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼",
                 "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔",
                 "🐧", "🐦", "🦄", "🐝", "🦋", "🌸", "🌈", "⭐️"]
            case .food:
                ["🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓",
                 "🍒", "🍑", "🥭", "🍍", "🥑", "🍔", "🍕", "🍜",
                 "🍣", "🍱", "🍰", "🍫", "☕️", "🍺", "🥂", "🥢"]
            case .activities:
                ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏉", "🎱",
                 "🏓", "🏸", "🥅", "⛳️", "🎣", "🤿", "🎽", "🛹",
                 "🎮", "🎲", "🎯", "🎸", "🎹", "🎤", "🎬", "🎨"]
            case .travel:
                ["🚗", "🚕", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒",
                 "🚲", "✈️", "🚀", "🚁", "⛵️", "🚢", "🚆", "🚇",
                 "🏠", "🏢", "🏥", "🏫", "🏖️", "🏕️", "🗻", "🌍"]
            case .objects:
                ["⌚️", "📱", "💻", "⌨️", "🖥️", "🖨️", "📷", "🎥",
                 "☎️", "📺", "📻", "⏰", "💡", "🔦", "🕯️", "🔋",
                 "💰", "💎", "🔧", "🔨", "🔒", "🔑", "🎁", "📌"]
            case .symbols:
                ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍",
                 "💔", "💕", "💞", "💓", "💗", "💖", "💘", "💝",
                 "✅", "❌", "⭕️", "❗️", "❓", "⚠️", "💯", "♻️"]
            case .flags:
                ["🇭🇰", "🇨🇳", "🇹🇼", "🇲🇴", "🇯🇵", "🇰🇷", "🇸🇬", "🇹🇭",
                 "🇬🇧", "🇺🇸", "🇨🇦", "🇦🇺", "🇳🇿", "🇫🇷", "🇩🇪", "🇮🇹",
                 "🇪🇸", "🇵🇹", "🇳🇱", "🇨🇭", "🇸🇪", "🇳🇴", "🇮🇳", "🇧🇷"]
            }
        }
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

    private final class EmojiCell: UICollectionViewCell {
        let label = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 34)
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                label.topAnchor.constraint(equalTo: contentView.topAnchor),
                label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private let decoder = CangjieDecoder()
    private let candidateScrollView = UIScrollView()
    private let candidateStackView = UIStackView()
    private let compositionLabel = UILabel()
    private let candidateArea = UIStackView()
    private let keyboardStackView = UIStackView()
    private let rootStack = UIStackView()

    private lazy var emojiCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 2
        layout.sectionInset = UIEdgeInsets(top: 2, left: 4, bottom: 8, right: 4)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: "EmojiCell")
        return collectionView
    }()

    private var returnButton: UIButton?
    private weak var spaceButton: UIButton?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var buffer = ""
    private var currentCandidates: [String] = []
    private var learnedCandidate: String?
    private var currentPage = KeyboardPage.letters
    private var selectedEmojiCategory = EmojiCategory.frequentlyUsed
    private var emojiCategoryButtons: [EmojiCategory: UIButton] = [:]
    private var shiftState = ShiftState.lowercased
    private var lastShiftTapTime: TimeInterval = 0
    private var cursorGestureStartX: CGFloat = 0
    private var cursorGestureStep = 0
    // 游標每移動一個字元所需的水平滑動距離（pt）；數值越小越靈敏。
    private let cursorMovementThreshold: CGFloat = 5
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

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInterface()
        rebuildKeyboard()
        refreshComposition()
        updateAppearance()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateAppearance()
        updateReturnKeyTitle()
    }

    private func configureInterface() {
        view.backgroundColor = keyboardBackgroundColor

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
        keyboardStackView.spacing = 7

        rootStack.addArrangedSubview(candidateArea)
        rootStack.addArrangedSubview(keyboardStackView)
        rootStack.axis = .vertical
        rootStack.spacing = 7
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: 260)
        heightConstraint.priority = .defaultHigh
        keyboardHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            heightConstraint,
        ])
    }

    private func rebuildKeyboard() {
        keyboardStackView.arrangedSubviews.forEach { arrangedView in
            keyboardStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        candidateArea.isHidden = currentPage == .emoji
        keyboardHeightConstraint?.constant = currentPage == .emoji ? 282 : 260
        compositionLabel.isHidden = currentPage == .letters
        keyboardStackView.spacing = currentPage == .letters ? 5 : 7
        rootStack.spacing = currentPage == .letters ? 5 : 7

        switch currentPage {
        case .letters:
            keyboardStackView.addArrangedSubview(
                makeCharacterRow(letterRows[0], horizontalInset: 0, usesShift: true)
            )
            keyboardStackView.addArrangedSubview(
                makeCharacterRow(letterRows[1], horizontalInset: 17, usesShift: true)
            )
            keyboardStackView.addArrangedSubview(makeLetterControlRow())
        case .numbers:
            numberRows.forEach {
                keyboardStackView.addArrangedSubview(
                    makeCharacterRow($0, horizontalInset: 0, usesShift: false)
                )
            }
            keyboardStackView.addArrangedSubview(
                makePunctuationRow(pageTitle: "#+=", destination: .symbols)
            )
        case .symbols:
            symbolRows.forEach {
                keyboardStackView.addArrangedSubview(
                    makeCharacterRow($0, horizontalInset: 0, usesShift: false)
                )
            }
            keyboardStackView.addArrangedSubview(
                makePunctuationRow(pageTitle: "123", destination: .numbers)
            )
        case .emoji:
            emojiCollectionView.reloadData()
            keyboardStackView.addArrangedSubview(makeEmojiSearchBar())
            keyboardStackView.addArrangedSubview(emojiCollectionView)
            keyboardStackView.addArrangedSubview(makeEmojiToolbar())
        }

        if currentPage != .emoji {
            keyboardStackView.addArrangedSubview(makeBottomRow())
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

    private func makeEmojiSearchBar() -> UIView {
        let searchBar = UIView()
        searchBar.backgroundColor = .secondarySystemFill
        searchBar.layer.cornerRadius = 20
        searchBar.isAccessibilityElement = true
        searchBar.accessibilityLabel = "搜尋表情符號，搜尋功能尚未提供"
        searchBar.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let imageView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 18,
            weight: .regular
        )
        imageView.tintColor = .secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "搜尋表情符號"
        label.font = .systemFont(ofSize: 18)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        searchBar.addSubview(imageView)
        searchBar.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: 14),
            imageView.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: searchBar.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
        ])
        return wrap(searchBar, horizontalInset: 6)
    }

    private func makeEmojiToolbar() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.spacing = 4

        let lettersButton = makeKey(title: "ABC", role: .control, fontSize: 14)
        lettersButton.addAction(
            UIAction { [weak self] _ in self?.switchPage(to: .letters) },
            for: .touchUpInside
        )
        lettersButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        row.addArrangedSubview(lettersButton)

        let categories = UIStackView()
        categories.axis = .horizontal
        categories.distribution = .fillEqually
        categories.spacing = 0
        emojiCategoryButtons.removeAll()

        for category in EmojiCategory.allCases {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: category.symbolName)
            configuration.preferredSymbolConfigurationForImage =
                UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            configuration.baseForegroundColor = .secondaryLabel
            configuration.contentInsets = .zero
            configuration.background.cornerRadius = 21
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = category.title
            button.addAction(
                UIAction { [weak self] _ in self?.scrollToEmojiCategory(category) },
                for: .touchUpInside
            )
            categories.addArrangedSubview(button)
            emojiCategoryButtons[category] = button
        }
        row.addArrangedSubview(categories)

        let deleteButton = makeDeleteButton()
        deleteButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(deleteButton)

        updateEmojiCategorySelection(selectedEmojiCategory)
        return wrap(row, horizontalInset: 0)
    }

    private func makeBottomRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        let pageTitle = currentPage == .letters ? "123" : "ABC"
        let pageDestination = currentPage == .letters
            ? KeyboardPage.numbers
            : KeyboardPage.letters
        let pageButton = makeKey(title: pageTitle, role: .control, fontSize: 14)
        pageButton.addAction(
            UIAction { [weak self] _ in self?.switchPage(to: pageDestination) },
            for: .touchUpInside
        )
        pageButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        row.addArrangedSubview(pageButton)

        let inputModeButton = makeIconKey(
            systemName: "face.smiling",
            accessibilityLabel: "表情符號",
            role: currentPage == .emoji ? .character : .control
        )
        inputModeButton.addAction(
            UIAction { [weak self] _ in self?.switchPage(to: .emoji) },
            for: .touchUpInside
        )
        inputModeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        row.addArrangedSubview(inputModeButton)

        let spaceButton = makeKey(title: "space", role: .character, fontSize: 16)
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
        row.addArrangedSubview(spaceButton)
        self.spaceButton = spaceButton

        let returnButton = makeKey(
            title: returnKeyTitle,
            role: .control,
            fontSize: 14
        )
        returnButton.addAction(
            UIAction { [weak self] _ in self?.commitReturn() },
            for: .touchUpInside
        )
        returnButton.widthAnchor.constraint(equalToConstant: 70).isActive = true
        row.addArrangedSubview(returnButton)
        self.returnButton = returnButton

        return wrap(row, horizontalInset: 0)
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
        button.heightAnchor.constraint(equalToConstant: height).isActive = true
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
        if page == .emoji {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollToEmojiCategory(self.selectedEmojiCategory, animated: false)
            }
        } else {
            refreshComposition()
        }
    }

    private func scrollToEmojiCategory(
        _ category: EmojiCategory,
        animated: Bool = true
    ) {
        guard let section = EmojiCategory.allCases.firstIndex(of: category) else { return }
        selectedEmojiCategory = category
        updateEmojiCategorySelection(category)
        emojiCollectionView.layoutIfNeeded()
        emojiCollectionView.scrollToItem(
            at: IndexPath(item: 0, section: section),
            at: .top,
            animated: animated
        )
    }

    private func updateEmojiCategorySelection(_ selectedCategory: EmojiCategory) {
        selectedEmojiCategory = selectedCategory
        for (category, button) in emojiCategoryButtons {
            guard var configuration = button.configuration else { continue }
            configuration.background.backgroundColor = category == selectedCategory
                ? characterKeyColor
                : .clear
            configuration.baseForegroundColor = category == selectedCategory
                ? .label
                : .secondaryLabel
            button.configuration = configuration
        }
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
        resetCompositionState()
        textDocumentProxy.insertText(symbol)
        refreshComposition()
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
        if learnedCandidate == buffer, !buffer.isEmpty {
            resetCompositionState()
            textDocumentProxy.insertText(" ")
            refreshComposition()
            return
        }
        if let learnedCandidate,
           replaceTypedCode(with: learnedCandidate)
        {
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
            cursorGestureStartX = gesture.location(in: view).x
            cursorGestureStep = 0
            resetCompositionState()
            refreshComposition()
            updateSpaceButtonTitle("移動游標", accessibilityLabel: "移動游標")
            cursorFeedbackGenerator.prepare()
        case .changed:
            let distance = gesture.location(in: view).x - cursorGestureStartX
            let step = Int(distance / cursorMovementThreshold)
            let offset = step - cursorGestureStep
            guard offset != 0 else { return }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            cursorGestureStep = step
            cursorFeedbackGenerator.selectionChanged()
            cursorFeedbackGenerator.prepare()
        case .ended, .cancelled, .failed:
            cursorGestureStartX = 0
            cursorGestureStep = 0
            updateSpaceButtonTitle("space", accessibilityLabel: "空格")
        default:
            break
        }

        spaceButton.isHighlighted = gesture.state == .began || gesture.state == .changed
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
        let typedCode = buffer
        if !typedCode.isEmpty {
            SmartCandidateRanker.shared.record(
                code: typedCode,
                candidate: candidate
            )
        }
        if candidate == typedCode {
            resetCompositionState()
            refreshComposition()
            return
        }
        if replaceTypedCode(with: candidate) {
            return
        }
        resetCompositionState()
        textDocumentProxy.insertText(candidate)
        refreshComposition()
    }

    private func replaceTypedCode(with replacement: String) -> Bool {
        guard !buffer.isEmpty,
              textDocumentProxy.documentContextBeforeInput?.hasSuffix(buffer) == true
        else { return false }

        for _ in buffer {
            textDocumentProxy.deleteBackward()
        }
        resetCompositionState()
        textDocumentProxy.insertText(replacement)
        refreshComposition()
        return true
    }

    private func resetCompositionState() {
        buffer = ""
        currentCandidates = []
        learnedCandidate = nil
    }

    private func refreshComposition() {
        var candidates = buffer.count <= 5
            ? decoder.candidates(for: buffer, limit: 10)
            : []
        let prediction = SmartCandidateRanker.shared.prediction(
            code: buffer,
            availableCandidates: buffer.isEmpty ? candidates : candidates + [buffer]
        )
        learnedCandidate = prediction?.candidate
        if let learnedCandidate {
            candidates.removeAll { $0 == learnedCandidate }
            candidates.insert(learnedCandidate, at: 0)
        }
        currentCandidates = candidates
        let roots = cangjieRoots(for: buffer)
        compositionLabel.text = buffer.isEmpty ? "" : "\(roots)  ·  \(buffer)"
        rebuildCandidateButtons()
    }

    private func rebuildCandidateButtons() {
        candidateStackView.arrangedSubviews.forEach { arrangedView in
            candidateStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        if currentPage == .emoji {
            return
        }

        guard !currentCandidates.isEmpty else {
            let placeholder = UILabel()
            placeholder.text = buffer.isEmpty ? "倉頡候選" : "沒有中文候選"
            placeholder.textColor = .secondaryLabel
            placeholder.font = .systemFont(ofSize: 16)
            candidateStackView.addArrangedSubview(placeholder)
            return
        }

        for candidate in currentCandidates {
            var configuration = UIButton.Configuration.plain()
            configuration.title = candidate
            configuration.baseForegroundColor = candidate == learnedCandidate
                ? .systemBlue
                : .label
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

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        EmojiCategory.allCases.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        EmojiCategory.allCases[section].emojis.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "EmojiCell",
            for: indexPath
        )
        guard let emojiCell = cell as? EmojiCell else { return cell }
        let category = EmojiCategory.allCases[indexPath.section]
        emojiCell.label.text = category.emojis[indexPath.item]
        emojiCell.accessibilityLabel = category.emojis[indexPath.item]
        return emojiCell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let category = EmojiCategory.allCases[indexPath.section]
        enterSymbol(category.emojis[indexPath.item])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let spacing: CGFloat = 4
        let availableWidth = collectionView.bounds.width - 8
        let columns = 8
        let width = floor(
            (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        )
        return CGSize(width: width, height: 40)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === emojiCollectionView,
              let firstVisibleSection = emojiCollectionView.indexPathsForVisibleItems
                .map(\.section)
                .min()
        else { return }
        updateEmojiCategorySelection(EmojiCategory.allCases[firstVisibleSection])
    }

    private func updateAppearance() {
        let darkAppearance = textDocumentProxy.keyboardAppearance == .dark
        view.overrideUserInterfaceStyle = darkAppearance ? .dark : .light
        view.backgroundColor = keyboardBackgroundColor
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
