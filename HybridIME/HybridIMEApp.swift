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

        let lexicon = StaticLexicon()
        bilingualDictionary = BilingualDictionary(lexicon: lexicon)
        associationDictionary = AssociationDictionary(lexicon: lexicon)
        cangjieDecoder = CangjieDecoder(lexicon: lexicon)
        isLoading = false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var inputMethodServer: IMKServer?
    private var applicationDeactivationObserver: NSObjectProtocol?

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
        applicationDeactivationObserver = NSWorkspace.shared
            .notificationCenter
            .addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    CandidateWindowController.shared.hide()
                }
            }
        InputResources.shared.preload()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let applicationDeactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                applicationDeactivationObserver
            )
        }
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
