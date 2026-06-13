//
//  HybridIMEApp.swift
//  HybridIME
//
//  Created by Sunny Yu on 12/6/2026.
//

import AppKit
import Carbon
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

        registerAndEnableInputSource(
            at: Bundle.main.bundleURL,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func registerAndEnableInputSource(
        at bundleURL: URL,
        bundleIdentifier: String
    ) {
        let registrationStatus = TISRegisterInputSource(bundleURL as CFURL)
        guard registrationStatus == noErr else {
            NSLog("HybridIME registration failed: \(registrationStatus)")
            return
        }

        guard
            let inputSourceList = TISCreateInputSourceList(nil, true)?
                .takeRetainedValue() as? [TISInputSource]
        else {
            NSLog("HybridIME could not read the input source list")
            return
        }

        var foundMatchingSource = false
        for inputSource in inputSourceList {
            guard
                let bundleIDPointer = TISGetInputSourceProperty(
                    inputSource,
                    kTISPropertyBundleID
                )
            else {
                continue
            }

            let sourceBundleID = Unmanaged<CFString>
                .fromOpaque(bundleIDPointer)
                .takeUnretainedValue() as String
            guard sourceBundleID == bundleIdentifier else {
                continue
            }

            foundMatchingSource = true
            let enableStatus = TISEnableInputSource(inputSource)
            if enableStatus != noErr {
                NSLog("HybridIME enable failed: \(enableStatus)")
            }
        }

        if !foundMatchingSource {
            NSLog("HybridIME registration succeeded but no input source was found")
        }
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
