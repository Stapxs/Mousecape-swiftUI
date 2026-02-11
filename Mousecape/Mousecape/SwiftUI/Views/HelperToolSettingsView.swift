//
//  HelperToolSettingsView.swift
//  Mousecape
//
//  Helper tool settings view for managing the login item daemon
//

import SwiftUI
import ServiceManagement

struct HelperToolSettingsView: View {
    private static let helperBundleIdentifier = "com.sdmj76.mousecloakhelper"

    @State private var isHelperInstalled = false
    @State private var showInstallAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

    var body: some View {
        Section("Helper Tool") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mousecape Helper")
                        .font(.headline)
                    Text(isHelperInstalled ? String(localized:"Installed and running") : String(localized:"Not installed"))
                        .font(.caption)
                        .foregroundStyle(isHelperInstalled ? .green : .secondary)
                }

                Spacer()

                Button(isHelperInstalled ? String(localized:"Uninstall") : String(localized:"Install")) {
                    toggleHelper()
                }
            }

            Text("Once installed, the helper tool will automatically apply cursors at system startup without manually applying them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            checkHelperStatus()
        }
        .alert(alertTitle, isPresented: $showInstallAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    private func checkHelperStatus() {
        let service = SMAppService.loginItem(identifier: Self.helperBundleIdentifier)
        isHelperInstalled = (service.status == .enabled)
    }

    private func toggleHelper() {
        let service = SMAppService.loginItem(identifier: Self.helperBundleIdentifier)
        let shouldInstall = !isHelperInstalled

        helperLog("=== Helper Toggle ===")
        helperLog("Action: \(shouldInstall ? "Install" : "Uninstall")")
        helperLog("Current SMAppService status: \(describeServiceStatus(service.status))")

        // Log diagnostic info before install to help debug error 78
        if shouldInstall {
            logDiagnosticInfo()
        }

        do {
            if shouldInstall {
                // Before installing, try to clean up any stale launchd state
                // This fixes error 78 when reinstalling after uninstall
                forceCleanupLaunchdState()

                helperLog("Calling SMAppService.register()...")
                try service.register()

                // Check status after registration
                let newStatus = service.status
                helperLog("After register - SMAppService status: \(describeServiceStatus(newStatus))")

                // Handle requiresApproval status (error -9)
                if newStatus == .requiresApproval {
                    helperLog("Helper requires user approval in System Settings")
                    isHelperInstalled = false
                    alertTitle = String(localized:"Approval Required")
                    alertMessage = String(localized:"Please approve Mousecape in System Settings > General > Login Items to enable the helper.")
                } else {
                    // Check actual launchd status
                    let launchdStatus = checkLaunchdStatus()
                    helperLog("After register - launchd: \(launchdStatus)")

                    // If launchd shows error 78, try to repair
                    if launchdStatus.contains("exit code: 78") || launchdStatus.contains("Not running") {
                        helperLog("Helper registered but not running, attempting repair...")
                        repairHelperAfterApproval(service: service)
                    }

                    isHelperInstalled = (newStatus == .enabled)
                    if isHelperInstalled {
                        alertTitle = String(localized:"Success")
                        alertMessage = String(localized:"The Mousecape helper was successfully installed.")
                    } else {
                        alertTitle = String(localized:"Warning")
                        alertMessage = String(localized:"Helper registered but may not be running. Please restart the app or reinstall the helper.")
                    }
                }
            } else {
                // First try launchctl bootout to fully remove from launchd
                forceCleanupLaunchdState()

                helperLog("Calling SMAppService.unregister()...")
                try service.unregister()

                helperLog("After unregister - SMAppService status: \(describeServiceStatus(service.status))")

                isHelperInstalled = false
                alertTitle = String(localized:"Success")
                alertMessage = String(localized:"The Mousecape helper was successfully uninstalled.")
            }
            helperLog("Operation completed successfully")
        } catch {
            helperLog("ERROR: \(error.localizedDescription)")
            helperLog("Error details: \(error)")

            // Check if this is actually a requiresApproval situation
            if service.status == .requiresApproval {
                helperLog("Status is requiresApproval despite error")
                isHelperInstalled = false
                alertTitle = String(localized:"Approval Required")
                alertMessage = String(localized:"Please approve Mousecape in System Settings > General > Login Items to enable the helper.")
            } else {
                // Log additional diagnostic info on failure
                logDiagnosticInfo()
                alertTitle = String(localized:"Error")
                alertMessage = error.localizedDescription
            }
        }
        showInstallAlert = true
    }

    /// Attempt to repair Helper after user approval
    private func repairHelperAfterApproval(service: SMAppService) {
        helperLog("--- Repair After Approval ---")

        // Force cleanup
        forceCleanupLaunchdState()

        // Wait a moment for launchd to settle
        Thread.sleep(forTimeInterval: 0.3)

        // Try to unregister and re-register
        do {
            try? service.unregister()
            helperLog("Unregistered for repair")

            Thread.sleep(forTimeInterval: 0.3)

            try service.register()
            helperLog("Re-registered for repair")

            let finalStatus = checkLaunchdStatus()
            helperLog("After repair - launchd: \(finalStatus)")
        } catch {
            helperLog("Repair failed: \(error.localizedDescription)")
        }
    }

    /// Log diagnostic information to help debug error 78
    private func logDiagnosticInfo() {
        helperLog("--- Diagnostic Info ---")

        // 1. Check app location
        if let appPath = Bundle.main.bundlePath as String? {
            helperLog("App location: \(appPath)")
            let isInApplications = appPath.hasPrefix("/Applications")
            helperLog("Is in /Applications: \(isInApplications)")
        }

        // 2. Check helper bundle exists
        if let helperURL = Bundle.main.url(forResource: "com.sdmj76.mousecloakhelper",
                                            withExtension: "app",
                                            subdirectory: "Contents/Library/LoginItems") {
            helperLog("Helper bundle: \(helperURL.path)")
            let exists = FileManager.default.fileExists(atPath: helperURL.path)
            helperLog("Helper exists: \(exists)")
        } else {
            helperLog("Helper bundle: NOT FOUND in app bundle!")
        }

        // 3. Check current launchd state
        let launchdStatus = checkLaunchdStatus()
        helperLog("Current launchd state: \(launchdStatus)")

        // 4. Check BTM (Background Task Management) status using sfltool
        let btmStatus = checkBTMStatus()
        helperLog("BTM registration: \(btmStatus)")

        helperLog("--- End Diagnostic ---")
    }

    /// Check BTM (Background Task Management) status
    private func checkBTMStatus() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sfltool")
        process.arguments = ["dumpbtm"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Find our helper in BTM output
            let lines = output.components(separatedBy: "\n")
            var foundHelper = false
            var result: [String] = []

            for (index, line) in lines.enumerated() {
                if line.contains(Self.helperBundleIdentifier) || line.contains("mousecloakhelper") {
                    foundHelper = true
                    // Get context: 2 lines before and 5 lines after
                    let start = max(0, index - 2)
                    let end = min(lines.count - 1, index + 5)
                    for i in start...end {
                        result.append(lines[i].trimmingCharacters(in: .whitespaces))
                    }
                    break
                }
            }

            if foundHelper {
                return result.joined(separator: " | ")
            } else {
                return "Not found in BTM database"
            }
        } catch {
            return "sfltool failed: \(error.localizedDescription)"
        }
    }

    /// Describe SMAppService.Status in human-readable form
    private func describeServiceStatus(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:
            return "notRegistered (0)"
        case .enabled:
            return "enabled (1)"
        case .requiresApproval:
            return "requiresApproval (2)"
        case .notFound:
            return "notFound (3)"
        @unknown default:
            return "unknown (\(status.rawValue))"
        }
    }

    /// Force cleanup launchd state using launchctl bootout
    /// This fixes error 78 when SMAppService.unregister() doesn't fully clean up
    private func forceCleanupLaunchdState() {
        let uid = getuid()
        helperLog("Running: launchctl bootout gui/\(uid)/\(Self.helperBundleIdentifier)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(uid)/\(Self.helperBundleIdentifier)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()
        helperLog("launchctl bootout exit code: \(process.terminationStatus)")
    }

    /// Check launchd status for the helper using launchctl list
    private func checkLaunchdStatus() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Find the line for our helper
            for line in output.components(separatedBy: "\n") {
                if line.contains(Self.helperBundleIdentifier) {
                    let parts = line.split(separator: "\t").map(String.init)
                    if parts.count >= 3 {
                        let pid = parts[0]
                        let exitCode = parts[1]
                        if pid == "-" {
                            return "Not running (exit code: \(exitCode))"
                        } else {
                            return "Running (PID: \(pid), exit code: \(exitCode))"
                        }
                    }
                    return line
                }
            }
            return "Not found in launchctl list"
        } catch {
            return "Check failed: \(error.localizedDescription)"
        }
    }

    /// Debug logging for helper operations
    private func helperLog(_ message: String) {
        #if DEBUG
        DebugLogger.shared.log(message, file: "HelperToolSettings", line: 0)
        #endif
    }
}
