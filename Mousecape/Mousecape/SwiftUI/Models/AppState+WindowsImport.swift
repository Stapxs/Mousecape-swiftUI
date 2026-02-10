//
//  AppState+WindowsImport.swift
//  Mousecape
//
//  Windows cursor folder import logic.
//  Extracted from AppState.swift for better code organization.
//

import AppKit

extension AppState {
    // MARK: - Windows Cursor Import

    /// Import Windows cursors from a folder and create a new cape
    func importWindowsCursorFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Windows Cursor Folder")
        panel.message = String(localized: "Choose a folder containing .cur and .ani files")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.processWindowsCursorFolderAsync(url)
            }
        }
    }

    /// Process a folder of Windows cursors (async version with loading state)
    fileprivate func processWindowsCursorFolderAsync(_ folderURL: URL) async {
        // Show loading overlay
        isLoading = true
        loadingMessage = String(localized:"Importing Windows cursors...")

        // Check for valid INF with [Scheme.Reg] section
        switch WindowsINFParser.findValidINF(in: folderURL) {
        case .success(let infMapping):
            // Use INF-based import (position-based mapping)
            await processWithINFMapping(folderURL: folderURL, infMapping: infMapping)
        case .failure(let error):
            debugLog("INF parsing failed: \(error.localizedDescription)")
            isLoading = false
            importResultMessage = "\(String(localized:"No valid install.inf file found.")) \(error.localizedUIDescription)"
            importResultIsSuccess = false
            showImportResult = true
        }
    }

    /// Generic scheme names that should be ignored in favor of folder name
    fileprivate var genericSchemeNames: Set<String> { ["default", "untitled", "cursor", "cursors", "scheme"] }

    /// Process Windows cursors using INF mapping (position-based)
    fileprivate func processWithINFMapping(folderURL: URL, infMapping: WindowsINFMapping) async {
        do {
            let results = try await WindowsCursorConverter.shared.convertFolderWithINFAsync(
                folderURL: folderURL,
                infMapping: infMapping
            )

            if results.isEmpty {
                isLoading = false
                importResultMessage = String(localized:"No valid cursor files found in the selected folder.")
                importResultIsSuccess = false
                showImportResult = true
                return
            }

            // Use scheme name from INF if it's specific, otherwise use folder name
            let baseName: String
            if let schemeName = infMapping.schemeName,
               !genericSchemeNames.contains(schemeName.lowercased()) {
                baseName = schemeName
            } else {
                baseName = sanitizeCapeNameFromFolder(folderURL)
            }
            let capeName = findUniqueName(baseName: baseName, author: "Imported")
            let newCape = CursorLibrary(name: capeName, author: "Imported")

            // Track which cursor types have already been added to avoid duplicates
            var addedCursorTypes: Set<String> = []

            var importedCount = 0
            for (position, result) in results {
                // Get macOS cursor types from position index
                let cursorTypes = WindowsINFParser.cursorTypes(forPosition: position)

                if cursorTypes.isEmpty {
                    debugLog("Skipping position \(position): no macOS equivalent")
                    continue
                }

                // Create and scale bitmap
                guard let originalBitmap = result.createBitmapImageRep() else {
                    debugLog("Failed to create bitmap for: \(result.filename)")
                    continue
                }

                let scaledBitmap: NSBitmapImageRep?
                if result.frameCount > 1 {
                    scaledBitmap = CursorImageScaler.scaleSpriteSheet(originalBitmap, frameCount: result.frameCount, originalFrameWidth: result.width, originalFrameHeight: result.height)
                } else {
                    scaledBitmap = CursorImageScaler.scaleImageToStandardSize(originalBitmap)
                }

                guard let finalBitmap = scaledBitmap else {
                    debugLog("Failed to scale bitmap for: \(result.filename)")
                    continue
                }

                // Calculate scaled hotspot
                let (hotspotPointsX, hotspotPointsY) = CursorImageScaler.calculateScaledHotspot(hotspotX: result.hotspotX, hotspotY: result.hotspotY, originalWidth: result.width, originalHeight: result.height)

                // Create a cursor for each mapped type (skip duplicates)
                for cursorType in cursorTypes {
                    // Skip if this cursor type was already added
                    if addedCursorTypes.contains(cursorType.rawValue) {
                        debugLog("Skipping duplicate cursor type: \(cursorType.rawValue) from position \(position)")
                        continue
                    }

                    let cursor = Cursor(identifier: cursorType.rawValue)
                    cursor.frameCount = result.frameCount
                    cursor.frameDuration = result.frameDuration
                    cursor.hotSpot = NSPoint(x: hotspotPointsX, y: hotspotPointsY)
                    cursor.size = NSSize(width: 32, height: 32)

                    if let bitmapCopy = finalBitmap.copy() as? NSBitmapImageRep {
                        cursor.setRepresentation(bitmapCopy, for: .scale200)
                    } else {
                        cursor.setRepresentation(finalBitmap, for: .scale200)
                    }

                    newCape.addCursor(cursor)
                    addedCursorTypes.insert(cursorType.rawValue)
                    importedCount += 1
                }
            }

            finishImport(newCape: newCape, capeName: capeName, importedCount: importedCount, fileCount: results.count)

        } catch {
            isLoading = false
            importResultMessage = "\(String(localized:"Failed to import Windows cursors:")) \(error.localizedDescription)"
            importResultIsSuccess = false
            showImportResult = true
        }
    }

    /// Finish the import process and save the cape
    fileprivate func finishImport(newCape: CursorLibrary, capeName: String, importedCount: Int, fileCount: Int) {
        if importedCount == 0 {
            isLoading = false
            importResultMessage = String(localized:"No cursors could be mapped to macOS cursor types.")
            importResultIsSuccess = false
            showImportResult = true
            return
        }

        // Save the new cape
        if let libraryURL = libraryController?.libraryURL {
            let identifier = generateIdentifier(name: capeName, author: "Imported")
            newCape.identifier = identifier
            newCape.fileURL = libraryURL.appendingPathComponent("\(identifier).cape")

            do {
                try newCape.save()

                // Add to library controller so it shows up in the list
                addCape(newCape)

                // Select the new cape
                selectedCape = capes.first { $0.identifier == identifier }

                debugLog("Imported \(importedCount) cursor(s) from \(fileCount) file(s)")

                // Show success message
                isLoading = false
                importResultMessage = "\(String(localized:"Successfully imported")) \(importedCount) \(String(localized:"cursor(s) from")) \(fileCount) \(String(localized:"file(s)."))"
                importResultIsSuccess = true
                showImportResult = true
            } catch {
                isLoading = false
                importResultMessage = "\(String(localized:"Failed to save cape:")) \(error.localizedDescription)"
                importResultIsSuccess = false
                showImportResult = true
            }
        } else {
            isLoading = false
            importResultMessage = String(localized:"Failed to access library directory.")
            importResultIsSuccess = false
            showImportResult = true
        }
    }

    /// Sanitize folder name for use as cape name
    fileprivate func sanitizeCapeNameFromFolder(_ folderURL: URL) -> String {
        let folderName = folderURL.lastPathComponent
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if name is valid
        if trimmed.isEmpty || trimmed.hasPrefix(".") {
            return "Imported Cursors"
        }

        // Filter to allowed characters
        let filtered = AppState.filterNameOrAuthor(trimmed)
        if filtered.isEmpty {
            return "Imported Cursors"
        }

        return filtered
    }
}
