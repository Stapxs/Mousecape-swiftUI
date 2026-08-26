//
//  MousecapeHelperApp.swift
//  MousecapeHelper
//
//  Created by Claude Code on 2026-03-06.
//

import SwiftUI
import ServiceManagement

// MARK: - Menu Bar Visibility State

/// Shared state for menu bar icon visibility, controlled by main app via CFPreferences + DistributedNotification
@Observable
@MainActor
class MenuBarState {
    static let shared = MenuBarState()
    var isVisible: Bool = true

    init() {
        isVisible = Self.readFromPreferences()
    }

    func updateFromPreferences() {
        isVisible = Self.readFromPreferences()
    }

    private static func readFromPreferences() -> Bool {
        // Synchronize to flush latest values from disk
        CFPreferencesSynchronize(
            "com.sdmj76.Mousecape" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let value = CFPreferencesCopyValue(
            "launchHelperWithApp" as CFString,
            "com.sdmj76.Mousecape" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let result = (value as? NSNumber)?.boolValue ?? true
        debugLog("Menu bar visibility read: \(result)")
        return result
    }
}

// MARK: - Automatic Appearance Cape Switching

@MainActor
final class AppearanceCapeSwitcher: NSObject {
    static let shared = AppearanceCapeSwitcher()

    private enum AppearanceSlot {
        case light
        case dark
    }

    private struct Configuration {
        let isEnabled: Bool
        let lightIdentifier: String?
        let darkIdentifier: String?
    }

    private let domain = "com.sdmj76.Mousecape" as CFString
    private let preferencesChangedNotification = "com.sdmj76.Mousecape.preferencesChanged" as CFString
    private var isStarted = false
    private var cfObserverContext: UnsafeMutableRawPointer?

    private override init() {
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        cfObserverContext = Unmanaged.passUnretained(self).toOpaque()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            cfObserverContext,
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let switcher = Unmanaged<AppearanceCapeSwitcher>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    switcher.applyMatchingCape(reason: "preferences changed")
                }
            },
            preferencesChangedNotification,
            nil,
            .deliverImmediately
        )

        debugLog("Appearance cape switcher started")
        applyMatchingCape(reason: "startup")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        if let context = cfObserverContext {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                context,
                CFNotificationName(preferencesChangedNotification),
                nil
            )
        }
    }

    @objc private func systemAppearanceChanged() {
        applyMatchingCape(reason: "system appearance changed")
    }

    private func applyMatchingCape(reason: String) {
        let configuration = readConfiguration()
        guard configuration.isEnabled else {
            debugLog("Appearance cape switcher skipped (\(reason)): disabled")
            return
        }

        guard let target = resolvedTarget(from: configuration, for: currentAppearanceSlot) else {
            debugLog("Appearance cape switcher skipped (\(reason)): no configured cape is available")
            return
        }

        let currentIdentifier = readString(forKey: "MCAppliedCursor")
        guard currentIdentifier != target.identifier else {
            debugLog("Appearance cape switcher skipped (\(reason)): \(target.identifier) is already applied")
            return
        }

        let success = target.path.withCString { ApplyCapeAtPathReapply($0) }
        debugLog("Appearance cape switcher applied \(target.identifier) (\(reason)): \(success ? "success" : "failed")")
    }

    private func resolvedTarget(from configuration: Configuration, for slot: AppearanceSlot) -> (identifier: String, path: String)? {
        let primaryIdentifier = slot == .dark ? configuration.darkIdentifier : configuration.lightIdentifier
        if let target = targetCape(for: primaryIdentifier) {
            return target
        }

        let fallbackIdentifier = slot == .dark ? configuration.lightIdentifier : configuration.darkIdentifier
        return targetCape(for: fallbackIdentifier)
    }

    private func targetCape(for identifier: String?) -> (identifier: String, path: String)? {
        guard let identifier = identifier,
              !identifier.isEmpty,
              !identifier.contains("/"),
              !identifier.contains(".."),
              let capesDirectory = capesDirectory
        else { return nil }

        let capeURL = capesDirectory
            .appendingPathComponent(identifier, isDirectory: false)
            .appendingPathExtension("cape")
            .standardizedFileURL
        let directoryPath = capesDirectory.standardizedFileURL.path

        guard capeURL.path.hasPrefix(directoryPath + "/"),
              FileManager.default.fileExists(atPath: capeURL.path)
        else { return nil }

        return (identifier, capeURL.path)
    }

    private var currentAppearanceSlot: AppearanceSlot {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return .dark
        }

        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private var capesDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Mousecape", isDirectory: true)
            .appendingPathComponent("capes", isDirectory: true)
    }

    private func readConfiguration() -> Configuration {
        CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return Configuration(
            isEnabled: readBool(forKey: "MCAutoAppearanceCapeEnabled"),
            lightIdentifier: readString(forKey: "MCLightAppearanceCape"),
            darkIdentifier: readString(forKey: "MCDarkAppearanceCape")
        )
    }

    private func readString(forKey key: String) -> String? {
        CFPreferencesCopyValue(
            key as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String
    }

    private func readBool(forKey key: String) -> Bool {
        let value = CFPreferencesCopyValue(
            key as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )

        if let boolValue = value as? Bool {
            return boolValue
        }
        return (value as? NSNumber)?.boolValue ?? false
    }
}

// MARK: - App

@main
struct MousecapeHelperApp: App {
    @NSApplicationDelegateAdaptor(HelperAppDelegate.self) var appDelegate
    @StateObject private var cursorState = CursorState()
    @State private var menuBarState = MenuBarState.shared

    var body: some Scene {
        @Bindable var state = menuBarState
        MenuBarExtra("Mousecape", image: "MenuBarIcon", isInserted: $state.isVisible) {
            MenuBarContentView()
                .environmentObject(cursorState)
                .onAppear {
                    // Refresh state when menu opens
                    cursorState.refresh()
                }
        }
    }
}

// MARK: - App Delegate

class HelperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize logging
        #if DEBUG
        MCLoggerInit()
        #endif
        debugLog("MousecapeHelper started")

        // Single instance check — exit if another Helper is already running
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.sdmj76.MousecapeHelper"
        let runningApps = NSWorkspace.shared.runningApplications
        let duplicate = runningApps.contains { app in
            app.bundleIdentifier == myBundleID && app.processIdentifier != myPID
        }
        if duplicate {
            debugLog("Another Helper instance is already running, exiting")
            NSApp.terminate(nil)
            return
        }

        // Start session monitoring to keep cursors persistent
        startSessionMonitor()
        debugLog("Session monitor started")

        AppearanceCapeSwitcher.shared.start()

        // Listen for menu bar visibility changes from main app
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMenuBarVisibilityChanged),
            name: NSNotification.Name("com.sdmj76.Mousecape.menuBarVisibilityChanged"),
            object: nil
        )
    }

    @objc private func handleMenuBarVisibilityChanged() {
        DispatchQueue.main.async {
            MenuBarState.shared.updateFromPreferences()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("MousecapeHelper terminating")
        #if DEBUG
        MCLoggerClose()
        #endif
    }
}
