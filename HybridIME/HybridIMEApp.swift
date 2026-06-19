//
//  HybridIMEApp.swift
//  HybridIME
//
//  Created by Sunny Yu on 12/6/2026.
//

import AppKit
import InputMethodKit

@MainActor
final class InputResources {
    static let shared = InputResources()

    private(set) var cangjieDecoder: CangjieDecoder?
    private(set) var bilingualDictionary: BilingualDictionary?
    private(set) var associationDictionary: AssociationDictionary?
    private var isLoading = false

    private init() {}

    func preload() {
        guard !isLoading, cangjieDecoder == nil else { return }
        isLoading = true

        Task.detached(priority: .userInitiated) {
            let cangjieDecoder = CangjieDecoder()
            let bilingualDictionary = BilingualDictionary()
            let associationDictionary = AssociationDictionary()

            await MainActor.run {
                let resources = InputResources.shared
                resources.cangjieDecoder = cangjieDecoder
                resources.bilingualDictionary = bilingualDictionary
                resources.associationDictionary = associationDictionary
                resources.isLoading = false
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var inputMethodServer: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard
            let connectionName = Bundle.main.object(
                forInfoDictionaryKey: "InputMethodConnectionName"
            ) as? String,
            let bundleIdentifier = Bundle.main.bundleIdentifier
        else {
            assertionFailure("Missing input method bundle configuration")
            return
        }

        inputMethodServer = IMKServer(
            name: connectionName,
            bundleIdentifier: bundleIdentifier
        )
        InputResources.shared.preload()
    }
}

@main
enum HybridIMEApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
