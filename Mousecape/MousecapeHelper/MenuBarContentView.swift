//
//  MenuBarContentView.swift
//  MousecapeHelper
//
//  Created by Claude Code on 2026-03-06.
//

import SwiftUI
import AppKit
import Combine

struct MenuBarCape: Identifiable, Hashable {
    let identifier: String
    let name: String
    let path: String

    var id: String { identifier }
}

// Observable state manager for cursor name
@MainActor
class CursorState: ObservableObject {
    @Published var currentCapeName: String = ""
    @Published var currentCapeIdentifier: String?
    @Published var installedCapes: [MenuBarCape] = []
    @Published var applyingCapeIdentifier: String?
    private var observer: NSObjectProtocol?
    private var cfObserverContext: UnsafeMutableRawPointer?
    private let domain = "com.sdmj76.Mousecape" as CFString

    init() {
        // Store observer context for CFNotificationCenter
        cfObserverContext = Unmanaged.passUnretained(self).toOpaque()

        // Initial refresh
        refresh()

        // Listen for preference changes from main app
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sdmj76.Mousecape.cursorChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        // Also listen for CFPreferences changes
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            cfObserverContext,
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let state = Unmanaged<CursorState>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    state.refresh()
                }
            },
            "com.sdmj76.Mousecape.preferencesChanged" as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        if let observer = observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let context = cfObserverContext {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                context,
                CFNotificationName("com.sdmj76.Mousecape.preferencesChanged" as CFString),
                nil
            )
        }
    }

    func refresh() {
        // Use CFPreferences API with kCFPreferencesAnyHost (same as main app)
        CFPreferencesSynchronize(
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        let value = CFPreferencesCopyValue(
            "MCAppliedCursor" as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )

        if let capeIdentifier = value as? String {
            currentCapeIdentifier = capeIdentifier
        } else {
            currentCapeIdentifier = nil
        }

        installedCapes = loadInstalledCapes()
        if let currentCapeIdentifier,
           let currentCape = installedCapes.first(where: { $0.identifier == currentCapeIdentifier }) {
            currentCapeName = currentCape.name
        } else if let currentCapeIdentifier {
            currentCapeName = displayName(fromIdentifier: currentCapeIdentifier)
        } else {
            currentCapeName = ""
        }
    }

    func applyCape(_ cape: MenuBarCape) {
        applyingCapeIdentifier = cape.identifier
        updateAutomaticAppearanceBinding(for: cape)

        let currentIdentifier = readString(forKey: "MCAppliedCursor")
        let isReapply = currentIdentifier == cape.identifier
        let success = cape.path.withCString {
            isReapply ? ApplyCapeAtPathReapply($0) : ApplyCapeAtPath($0)
        }
        applyingCapeIdentifier = nil

        if success {
            currentCapeIdentifier = cape.identifier
            currentCapeName = cape.name
        } else {
            debugLog("Failed to apply cape from menu bar: \(cape.path)")
        }

        refresh()
    }

    private func updateAutomaticAppearanceBinding(for cape: MenuBarCape) {
        guard readBool(forKey: "MCAutoAppearanceCapeEnabled") else {
            return
        }

        let key = isSystemDarkAppearance ? "MCDarkAppearanceCape" : "MCLightAppearanceCape"
        CFPreferencesSetValue(
            key as CFString,
            cape.identifier as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )

        debugLog("Menu bar automatic appearance cape binding updated: \(key) -> \(cape.identifier)")
    }

    func resetCursors() {
        ResetCursorsToDefault()
        refresh()
    }

    private func loadInstalledCapes() -> [MenuBarCape] {
        guard let capesDirectory = capesDirectory else { return [] }
        let fileManager = FileManager.default
        guard let capeURLs = try? fileManager.contentsOfDirectory(
            at: capesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let directoryPath = capesDirectory.standardizedFileURL.path
        return capeURLs.compactMap { url in
            guard url.pathExtension == "cape" else { return nil }
            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.path.hasPrefix(directoryPath + "/"),
                  fileManager.isReadableFile(atPath: standardizedURL.path)
            else { return nil }

            let identifier = standardizedURL.deletingPathExtension().lastPathComponent
            let name = capeName(at: standardizedURL) ?? displayName(fromIdentifier: identifier)
            return MenuBarCape(identifier: identifier, name: name, path: standardizedURL.path)
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var capesDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Mousecape", isDirectory: true)
            .appendingPathComponent("capes", isDirectory: true)
            .standardizedFileURL
    }

    private func capeName(at url: URL) -> String? {
        guard let dictionary = NSDictionary(contentsOf: url),
              let name = dictionary["CapeName"] as? String
        else { return nil }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
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

    private var isSystemDarkAppearance: Bool {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return true
        }

        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func displayName(fromIdentifier identifier: String) -> String {
        identifier
            .split(separator: ".")
            .last
            .map(String.init) ?? identifier
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject var cursorState: CursorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Display current cape name if available
            if !cursorState.currentCapeName.isEmpty {
                Text(String(localized: "Current Cursor: \(cursorState.currentCapeName)"))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }

            Menu(String(localized: "Switch Cursor")) {
                if cursorState.installedCapes.isEmpty {
                    Text(String(localized: "No Capes"))
                } else {
                    ForEach(cursorState.installedCapes) { cape in
                        Toggle(
                            isOn: Binding(
                                get: {
                                    cursorState.currentCapeIdentifier == cape.identifier
                                },
                                set: { _ in
                                    cursorState.applyCape(cape)
                                }
                            )
                        ) {
                            Text(cape.name)
                        }
                        .disabled(cursorState.applyingCapeIdentifier != nil)
                    }
                }
            }

            Button(String(localized: "Reset Cursors")) {
                cursorState.resetCursors()
            }

            Divider()

            Button(String(localized: "Open Mousecape")) {
                openMainApp()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(String(localized: "Quit Mousecape")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func openMainApp() {
        // Helper is located at: Mousecape.app/Contents/Library/LoginItems/MousecapeHelper.app
        // Navigate up to find main app: MousecapeHelper.app -> LoginItems -> Library -> Contents -> Mousecape.app
        let helperURL = Bundle.main.bundleURL
        let mainAppURL = helperURL
            .deletingLastPathComponent() // Remove MousecapeHelper.app -> LoginItems/
            .deletingLastPathComponent() // Remove LoginItems/ -> Library/
            .deletingLastPathComponent() // Remove Library/ -> Contents/
            .deletingLastPathComponent() // Remove Contents/ -> Mousecape.app/

        NSWorkspace.shared.open(mainAppURL)
    }

}

#Preview {
    MenuBarContentView()
}
