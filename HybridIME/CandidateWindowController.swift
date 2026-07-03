import AppKit
import InputMethodKit

private final class CandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CandidateWindowController {
    static let shared = CandidateWindowController()

    private let panel: NSPanel
    private let codeLabel = NSTextField(labelWithString: "")
    private let rootsLabel = NSTextField(labelWithString: "")
    private let candidatesLabel = NSTextField(labelWithString: "")

    var isVisible: Bool {
        panel.isVisible
    }

    private init() {
        let contentStack = NSStackView(
            views: [candidatesLabel, rootsLabel, codeLabel]
        )
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 3
        contentStack.edgeInsets = NSEdgeInsets(
            top: 7,
            left: 10,
            bottom: 7,
            right: 10
        )

        codeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        codeLabel.textColor = .secondaryLabelColor
        codeLabel.lineBreakMode = .byClipping

        rootsLabel.font = .systemFont(ofSize: 17, weight: .regular)
        rootsLabel.textColor = .labelColor
        rootsLabel.lineBreakMode = .byClipping

        candidatesLabel.font = .systemFont(ofSize: 17, weight: .regular)
        candidatesLabel.textColor = .labelColor
        candidatesLabel.lineBreakMode = .byClipping

        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: background.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        panel = CandidatePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = background
        panel.level = .statusBar
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func show(
        code: String,
        candidates: [String],
        translationIndices: Set<Int> = [],
        smartPredictionIndex: Int? = nil,
        client: IMKTextInput?
    ) {
        guard !code.isEmpty else {
            hide()
            return
        }

        codeLabel.stringValue = code
        codeLabel.isHidden = false
        rootsLabel.stringValue = cangjieRoots(for: code)
        rootsLabel.isHidden = false
        candidatesLabel.attributedStringValue = candidateText(
            candidates,
            translationIndices: translationIndices,
            smartPredictionIndex: smartPredictionIndex
        )
        candidatesLabel.isHidden = candidates.isEmpty

        updatePanel(client: client)
    }

    func showPunctuation(
        candidates: [String],
        displayCandidates: [String]? = nil,
        shiftKeyCandidates: [String]? = nil,
        client: IMKTextInput?
    ) {
        guard !candidates.isEmpty else {
            hide()
            return
        }

        codeLabel.isHidden = true
        rootsLabel.isHidden = true
        if let shiftKeyCandidates {
            candidatesLabel.attributedStringValue = shiftKeyCandidateText(
                shiftKeyCandidates
            )
        } else {
            candidatesLabel.attributedStringValue = candidateText(
                displayCandidates ?? candidates
            )
        }
        candidatesLabel.isHidden = false

        updatePanel(client: client)
    }

    func showAssociations(
        candidates: [String],
        smartPredictionIndex: Int? = nil,
        client: IMKTextInput?
    ) {
        guard !candidates.isEmpty else {
            hide()
            return
        }

        codeLabel.isHidden = true
        rootsLabel.isHidden = true
        candidatesLabel.attributedStringValue = candidateText(
            candidates,
            smartPredictionIndex: smartPredictionIndex
        )
        candidatesLabel.isHidden = false

        updatePanel(client: client)
    }

    private func updatePanel(client: IMKTextInput?) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = panel.contentView?.fittingSize ?? .zero
        let panelSize = NSSize(
            width: min(max(120, ceil(fittingSize.width)), 520),
            height: ceil(fittingSize.height)
        )
        panel.setContentSize(panelSize)
        position(panelSize: panelSize, client: client)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
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

    private func shiftKeyCandidateText(_ candidates: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: 10,
                weight: .medium
            ),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let candidateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor.labelColor,
        ]

        result.append(
            NSAttributedString(
                string: "Shift：",
                attributes: keyAttributes
            )
        )

        for (index, candidate) in candidates.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  "))
            }
            let key = index == 9 ? "0" : String(index + 1)
            result.append(
                NSAttributedString(
                    string: "\(key) ",
                    attributes: keyAttributes
                )
            )
            result.append(
                NSAttributedString(
                    string: candidate,
                    attributes: candidateAttributes
                )
            )
        }

        return result
    }

    private func candidateText(
        _ candidates: [String],
        translationIndices: Set<Int> = [],
        smartPredictionIndex: Int? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, candidate) in candidates.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "   "))
            }

            let key = index == 9 ? "0" : String(index + 1)
            result.append(
                NSAttributedString(
                    string: "\(key) ",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(
                            ofSize: 10,
                            weight: .medium
                        ),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
            )
            result.append(
                NSAttributedString(
                    string: smartPredictionIndex == index
                        ? "\(candidate) ◆"
                        : candidate,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 17),
                        .foregroundColor: translationIndices.contains(index)
                            ? NSColor.secondaryLabelColor
                            : NSColor.labelColor,
                    ]
                )
            )
        }

        return result
    }

    private func position(panelSize: NSSize, client: IMKTextInput?) {
        var caretRect = NSRect(x: 0, y: 0, width: 1, height: 20)
        _ = client?.attributes(
            forCharacterIndex: 0,
            lineHeightRectangle: &caretRect
        )

        guard caretRect.origin != .zero else {
            let fallback = NSScreen.main?.visibleFrame ?? .zero
            panel.setFrameOrigin(
                NSPoint(
                    x: fallback.midX - panelSize.width / 2,
                    y: fallback.midY
                )
            )
            return
        }

        let screen = NSScreen.screens.first {
            $0.visibleFrame.contains(caretRect.origin)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let gap: CGFloat = 5

        var origin = NSPoint(
            x: caretRect.minX,
            y: caretRect.maxY + gap
        )

        if origin.y + panelSize.height > visibleFrame.maxY {
            origin.y = caretRect.minY - panelSize.height - gap
        }
        origin.x = min(
            max(origin.x, visibleFrame.minX),
            visibleFrame.maxX - panelSize.width
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY),
            visibleFrame.maxY - panelSize.height
        )

        panel.setFrameOrigin(origin)
    }
}
