//
//  HybridIMEApp.swift
//  HybridIME
//
//  Created by Sunny Yu on 12/6/2026.
//

import AppKit
import InputMethodKit
import SwiftUI

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
    }
}

@main
struct HybridIMEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
