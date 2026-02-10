//
//  EditOverlayView.swift
//  Mousecape
//
//  Edit overlay view that covers the main interface
//  Slides in from the right with animation
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Windows Cursor UTType Extensions

extension UTType {
    /// Windows static cursor file (.cur)
    static var windowsCursor: UTType {
        UTType(filenameExtension: "cur") ?? .data
    }

    /// Windows animated cursor file (.ani)
    static var windowsAnimatedCursor: UTType {
        UTType(filenameExtension: "ani") ?? .data
    }
}

// MARK: - Edit Detail Content (right panel content only, used in HomeView)

struct EditDetailContent: View {
    let cape: CursorLibrary
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.showCapeInfo {
                CapeInfoView(cape: cape)
            } else if let cursor = appState.editingSelectedCursor {
                CursorDetailView(cursor: cursor, cape: cape)
                    .id(cursor.id)  // Force view recreation when cursor changes
            } else {
                ContentUnavailableView(
                    "Select a Cursor",
                    systemImage: "cursorarrow.click",
                    description: Text("Choose a cursor from the list to edit")
                )
            }
        }
        .onAppear {
            // Invalidate cache to ensure we get fresh cursor data
            cape.invalidateCursorCache()
            // Select first cursor when opening
            if appState.editingSelectedCursor == nil {
                appState.editingSelectedCursor = cape.cursors.first
            }
        }
        // Edit mode toolbar (navigationTitle is now in HomeView)
        .toolbar {
            // Flexible spacer pushes buttons to the right (macOS 26+ only)
            AdaptiveToolbarSpacer(.flexible)

            // Main action buttons group
            ToolbarItemGroup {
                Button(action: {
                    appState.showAddCursorSheet = true
                }) {
                    Image(systemName: "plus")
                }
                .help("Add Cursor")

                Button(action: {
                    appState.showDeleteCursorConfirmation = true
                }) {
                    Image(systemName: "minus")
                }
                .help("Delete Cursor")
                .disabled(appState.editingSelectedCursor == nil)

                Button(action: {
                    appState.showCapeInfo.toggle()
                    if appState.showCapeInfo {
                        appState.editingSelectedCursor = nil
                    }
                }) {
                    Image(systemName: appState.showCapeInfo ? "info.circle.fill" : "info.circle")
                }
                .help("Cape Info")
            }

            AdaptiveToolbarSpacer(.fixed)

            // Done button (rightmost, standalone with green color)
            ToolbarItem {
                Button(action: {
                    appState.requestCloseEdit()
                }) {
                    Image(systemName: "checkmark")
                }
                .help("Done")
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

// MARK: - Edit Overlay View (legacy, full screen)

struct EditOverlayView: View {
    let cape: CursorLibrary
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            // Left sidebar: Cursor list (same style as HomeView/SettingsView)
            CursorListView(
                cape: cape,
                selection: $appState.editingSelectedCursor
            )
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            // Right side: Content area
            detailContent
                .scrollContentBackground(.hidden)
        }
        .onAppear {
            // Invalidate cache to ensure we get fresh cursor data
            cape.invalidateCursorCache()
            // Select first cursor when opening
            if appState.editingSelectedCursor == nil {
                appState.editingSelectedCursor = cape.cursors.first
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.showCapeInfo {
            CapeInfoView(cape: cape)
        } else if let cursor = appState.editingSelectedCursor {
            CursorDetailView(cursor: cursor, cape: cape)
                .id(cursor.id)  // Force view recreation when cursor changes
        } else {
            ContentUnavailableView(
                "Select a Cursor",
                systemImage: "cursorarrow.click",
                description: Text("Choose a cursor from the list to edit")
            )
        }
    }
}

// MARK: - Cursor List View (for Edit)

struct CursorListView: View {
    let cape: CursorLibrary
    @Binding var selection: Cursor?
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(cape.cursors, id: \.id, selection: $selection) { cursor in
            CursorListRow(cursor: cursor, currentIdentifier: cursor.identifier)
                .tag(cursor)
                .contextMenu {
                    Button("Duplicate") {
                        duplicateCursor()
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        appState.showDeleteCursorConfirmation = true
                    }
                }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .id(appState.cursorListRefreshTrigger)  // Force list refresh when trigger changes
        .onChange(of: selection) { _, newValue in
            // When user selects a cursor, dismiss the cape info view
            if newValue != nil && appState.showCapeInfo {
                appState.showCapeInfo = false
            }
        }
    }

    private func duplicateCursor() {
        guard let cursor = selection else { return }
        // Create a copy with a modified identifier
        let newCursor = Cursor(identifier: cursor.identifier + ".copy")
        newCursor.frameDuration = cursor.frameDuration
        newCursor.frameCount = cursor.frameCount
        newCursor.size = cursor.size
        newCursor.hotSpot = cursor.hotSpot

        // Copy representations
        for scale in CursorScale.allCases {
            if let rep = cursor.representation(for: scale) {
                newCursor.setRepresentation(rep, for: scale)
            }
        }

        cape.addCursor(newCursor)
        selection = newCursor
        appState.markAsChanged()
    }
}

// MARK: - Cursor List Row

struct CursorListRow: View {
    let cursor: Cursor
    /// Pass the identifier to force refresh when type changes
    var currentIdentifier: String?

    private var displayName: String {
        let identifier = currentIdentifier ?? cursor.identifier
        if let type = CursorType(rawValue: identifier) {
            return type.displayName
        }
        // Fallback: extract name from identifier
        let name = identifier.components(separatedBy: ".").last ?? "Cursor"
        var result = ""
        for char in name {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result += String(char)
        }
        return result.isEmpty ? "Cursor" : result
    }

    var body: some View {
        HStack {
            // Preview thumbnail
            if let image = cursor.previewImage(size: 32) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                let identifier = currentIdentifier ?? cursor.identifier
                Image(systemName: CursorType(rawValue: identifier)?.previewSymbol ?? "cursorarrow")
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                if cursor.isAnimated {
                    Text("\(cursor.frameCount) \(String(localized:"frames"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Cursor Detail View

struct CursorDetailView: View {
    @Bindable var cursor: Cursor
    let cape: CursorLibrary
    @Environment(AppState.self) private var appState
    @State private var hotspotX: Double = 0
    @State private var hotspotY: Double = 0
    @State private var frameCount: Int = 1
    @State private var fps: Double = 1  // Frames per second
    @State private var isLoadingValues = true  // Prevent onChange during load
    @State private var selectedType: CursorType = .arrow
    @State private var previewRefreshTrigger: Int = 0  // Force preview refresh
    @State private var availableTypes: [CursorType] = CursorType.allCases

    // MARK: - Validation

    /// Maximum allowed hotspot value (32x32 cursor, hot spot must be < size)
    /// Use the constant from MCDefs.h for consistency with apply.m
    private var maxHotspot: CGFloat { CGFloat(MCMaxHotspotValue) }

    /// Check if hotspot X is valid (0 <= x <= MCMaxHotspotValue)
    private var isHotspotXValid: Bool { hotspotX >= 0 && hotspotX <= maxHotspot }

    /// Check if hotspot Y is valid (0 <= y <= MCMaxHotspotValue)
    private var isHotspotYValid: Bool { hotspotY >= 0 && hotspotY <= maxHotspot }

    /// Check if frame count is valid (>= 1)
    private var isFrameCountValid: Bool { frameCount >= 1 }

    /// Check if FPS is valid (> 0)
    private var isFPSValid: Bool { fps > 0 }

    // Calculate available cursor types (current type + types not used by other cursors)
    private func calculateAvailableTypes() -> [CursorType] {
        let otherCursorIdentifiers = Set(cape.cursors
            .filter { $0.id != cursor.id }
            .map { $0.identifier })
        return CursorType.allCases.filter { type in
            !otherCursorIdentifiers.contains(type.rawValue)
        }
    }

    // Calculate frame duration from FPS
    private var frameDuration: Double {
        fps > 0 ? 1.0 / fps : 0
    }

    // Picker types - ensure selectedType is always included to avoid "invalid selection" warning
    private var pickerTypes: [CursorType] {
        if availableTypes.contains(selectedType) {
            return availableTypes
        } else {
            // Add current selection to the list if not present
            return [selectedType] + availableTypes
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Combined preview + drop zone
                CursorPreviewDropZone(
                    cursor: cursor,
                    refreshTrigger: previewRefreshTrigger
                )

                // Properties panel
                VStack(alignment: .leading, spacing: 16) {
                    // Type section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.headline)

                        Picker("", selection: $selectedType) {
                            ForEach(pickerTypes) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 200, alignment: .leading)
                        .id(previewRefreshTrigger)  // Force picker refresh
                        .onChange(of: selectedType) { oldValue, newValue in
                            guard !isLoadingValues else { return }
                            guard newValue != oldValue else { return }
                            let oldIdentifier = cursor.identifier
                            let newIdentifier = newValue.rawValue
                            cursor.identifier = newIdentifier
                            appState.cursorListRefreshTrigger += 1
                            appState.registerUndo(
                                undo: { [weak cursor] in
                                    cursor?.identifier = oldIdentifier
                                    if let type = CursorType(rawValue: oldIdentifier) {
                                        self.selectedType = type
                                    }
                                    self.appState.cursorListRefreshTrigger += 1
                                },
                                redo: { [weak cursor] in
                                    cursor?.identifier = newIdentifier
                                    self.selectedType = newValue
                                    self.appState.cursorListRefreshTrigger += 1
                                }
                            )
                        }

                        Text(selectedType.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Hotspot section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hotspot")
                            .font(.headline)

                        HStack(spacing: 16) {
                            HStack {
                                Text("X:")
                                TextField("X", value: $hotspotX, format: .number.precision(.fractionLength(1)))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(isHotspotXValid ? Color.clear : Color.red, lineWidth: 2)
                                    )
                                    .onChange(of: hotspotX) { oldValue, newValue in
                                        guard !isLoadingValues else { return }
                                        guard newValue != oldValue else { return }

                                        // Validate: must be in range [0, 32)
                                        let clamped = min(max(0, newValue), maxHotspot)
                                        if clamped != newValue {
                                            // Invalid input, revert to old value
                                            hotspotX = oldValue
                                            return
                                        }

                                        let capturedOld = oldValue
                                        cursor.hotSpot = NSPoint(x: CGFloat(clamped), y: cursor.hotSpot.y)
                                        previewRefreshTrigger += 1
                                        appState.registerUndo(
                                            undo: { [weak cursor] in
                                                cursor?.hotSpot = NSPoint(x: CGFloat(capturedOld), y: cursor?.hotSpot.y ?? 0)
                                                self.hotspotX = capturedOld
                                                self.previewRefreshTrigger += 1
                                            },
                                            redo: { [weak cursor] in
                                                cursor?.hotSpot = NSPoint(x: CGFloat(clamped), y: cursor?.hotSpot.y ?? 0)
                                                self.hotspotX = clamped
                                                self.previewRefreshTrigger += 1
                                            }
                                        )
                                    }
                            }
                            HStack {
                                Text("Y:")
                                TextField("Y", value: $hotspotY, format: .number.precision(.fractionLength(1)))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(isHotspotYValid ? Color.clear : Color.red, lineWidth: 2)
                                    )
                                    .onChange(of: hotspotY) { oldValue, newValue in
                                        guard !isLoadingValues else { return }
                                        guard newValue != oldValue else { return }

                                        // Validate: must be in range [0, 32)
                                        let clamped = min(max(0, newValue), maxHotspot)
                                        if clamped != newValue {
                                            // Invalid input, revert to old value
                                            hotspotY = oldValue
                                            return
                                        }

                                        let capturedOld = oldValue
                                        cursor.hotSpot = NSPoint(x: cursor.hotSpot.x, y: CGFloat(clamped))
                                        previewRefreshTrigger += 1
                                        appState.registerUndo(
                                            undo: { [weak cursor] in
                                                cursor?.hotSpot = NSPoint(x: cursor?.hotSpot.x ?? 0, y: CGFloat(capturedOld))
                                                self.hotspotY = capturedOld
                                                self.previewRefreshTrigger += 1
                                            },
                                            redo: { [weak cursor] in
                                                cursor?.hotSpot = NSPoint(x: cursor?.hotSpot.x ?? 0, y: CGFloat(clamped))
                                                self.hotspotY = clamped
                                                self.previewRefreshTrigger += 1
                                            }
                                        )
                                    }
                            }
                        }

                    }

                    Divider()

                    // Animation section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Animation")
                            .font(.headline)

                        HStack {
                            Text("Frames:")
                            TextField("Frames", value: $frameCount, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isFrameCountValid ? Color.clear : Color.red, lineWidth: 2)
                                )
                                .onChange(of: frameCount) { oldValue, newValue in
                                    guard !isLoadingValues else { return }
                                    guard newValue != oldValue else { return }
                                    let capturedOld = oldValue
                                    let actualNew = max(1, newValue)
                                    cursor.frameCount = actualNew
                                    previewRefreshTrigger += 1
                                    appState.registerUndo(
                                        undo: { [weak cursor] in
                                            cursor?.frameCount = capturedOld
                                            self.frameCount = capturedOld
                                            self.previewRefreshTrigger += 1
                                        },
                                        redo: { [weak cursor] in
                                            cursor?.frameCount = actualNew
                                            self.frameCount = actualNew
                                            self.previewRefreshTrigger += 1
                                        }
                                    )
                                }
                        }

                        HStack {
                            Text("Speed:")
                            TextField("Speed", value: $fps, format: .number.precision(.fractionLength(1)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(isFPSValid ? Color.clear : Color.red, lineWidth: 2)
                                )
                                .onChange(of: fps) { oldValue, newValue in
                                    guard !isLoadingValues else { return }
                                    guard newValue != oldValue else { return }
                                    let capturedOld = oldValue
                                    let actualNew = max(0.1, newValue)
                                    let newDuration = 1.0 / actualNew
                                    cursor.frameDuration = CGFloat(newDuration)
                                    previewRefreshTrigger += 1
                                    appState.registerUndo(
                                        undo: { [weak cursor] in
                                            let oldDuration = capturedOld > 0 ? 1.0 / capturedOld : 0
                                            cursor?.frameDuration = CGFloat(oldDuration)
                                            self.fps = capturedOld
                                            self.previewRefreshTrigger += 1
                                        },
                                        redo: { [weak cursor] in
                                            cursor?.frameDuration = CGFloat(newDuration)
                                            self.fps = actualNew
                                            self.previewRefreshTrigger += 1
                                        }
                                    )
                                }
                            Text("frames/sec")
                                .foregroundStyle(.secondary)
                        }

                        if cursor.isAnimated {
                            Text("Duration: \(String(format: "%.3f", frameDuration))s per frame, \(String(format: "%.2f", Double(frameCount) * frameDuration))s total")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .adaptiveGlass(in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .onAppear {
            loadCursorValues()
        }
        .onChange(of: cursor.id) { _, _ in
            loadCursorValues()
        }
        .onChange(of: appState.cursorListRefreshTrigger) { _, _ in
            // Refresh preview and reload values when image is imported
            previewRefreshTrigger += 1
            loadCursorValues()
        }
    }

    private func loadCursorValues() {
        isLoadingValues = true
        hotspotX = Double(cursor.hotSpot.x)
        hotspotY = Double(cursor.hotSpot.y)
        frameCount = cursor.frameCount
        // Calculate FPS from frame duration
        let duration = Double(cursor.frameDuration)
        fps = duration > 0 ? 1.0 / duration : 1.0
        // Refresh available types
        availableTypes = calculateAvailableTypes()
        // Load cursor type
        if let type = CursorType(rawValue: cursor.identifier) {
            selectedType = type
        } else if let firstAvailable = availableTypes.first {
            selectedType = firstAvailable
        }
        // Delay resetting the flag to ensure onChange doesn't fire during load
        DispatchQueue.main.async {
            isLoadingValues = false
        }
    }
}

// MARK: - Cursor Preview Drop Zone (Combined preview + image drop)

struct CursorPreviewDropZone: View {
    @Bindable var cursor: Cursor
    var refreshTrigger: Int = 0
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false
    @State private var showFilePicker = false
    @State private var localRefreshTrigger = 0

    private let targetScale: CursorScale = .scale200  // Always use 2x HiDPI

    /// Supported image types for file picker
    private var supportedImageTypes: [UTType] {
        var types: [UTType] = [.png, .jpeg, .tiff, .gif]
        types.append(contentsOf: [.windowsCursor, .windowsAnimatedCursor])
        return types
    }

    /// Check if cursor has any valid image representation
    private var hasImage: Bool {
        cursor.hasAnyRepresentation
    }

    var body: some View {
        ZStack {
            if hasImage {
                // Show cursor preview with hotspot
                AnimatingCursorView(
                    cursor: cursor,
                    showHotspot: true,
                    refreshTrigger: refreshTrigger + localRefreshTrigger,
                    scale: 3
                )
            } else {
                // Empty state - prompt to add image
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text("Drag image or click to select")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Recommended: 64×64 px (HiDPI 2x)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Drag overlay indicator
            if isTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentColor.opacity(0.1))
                    )
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture {
            showFilePicker = true
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleURLDrop(urls)
        } isTargeted: { isTargeted in
            self.isTargeted = isTargeted
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedImageTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .help(hasImage ? String(localized:"Click or drag to replace image") : String(localized:"Click or drag to add image"))
    }

    private func handleURLDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        return loadImage(from: url)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                _ = loadImage(from: url)
            }
        case .failure(let error):
            debugLog("File import error: \(error)")
        }
    }

    private func loadImage(from url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else {
            debugLog("Failed to access security scoped resource: \(url)")
            return false
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Check if it's a Windows cursor file
        let ext = url.pathExtension.lowercased()
        if ext == "cur" || ext == "ani" {
            return loadWindowsCursor(from: url)
        }

        // Check if it's a GIF file - handle animation
        if ext == "gif" {
            return loadGIFImage(from: url)
        }

        guard let image = NSImage(contentsOf: url) else {
            debugLog("Failed to load image from: \(url)")
            appState.validationErrorMessage = String(localized:"Unsupported image format. Supported formats: PNG, JPEG, TIFF, GIF, CUR, ANI.")
            appState.showValidationError = true
            return false
        }

        // Get original image dimensions
        guard let originalBitmap = CursorImageScaler.getOriginalBitmapRep(from: image) else {
            debugLog("Failed to get bitmap rep from image")
            return false
        }

        let originalWidth = originalBitmap.pixelsWide
        let originalHeight = originalBitmap.pixelsHigh

        // Check if image is square
        let isSquare = originalWidth == originalHeight
        if !isSquare {
            // Show warning but continue with import
            appState.imageImportWarningMessage = "Image is not square (\(originalWidth)×\(originalHeight)). It will be scaled to fit and centered."
            appState.showImageImportWarning = true
        }

        // Scale image to standard size (64x64) with aspect fit and center
        guard let scaledBitmap = CursorImageScaler.scaleImageToStandardSize(originalBitmap) else {
            debugLog("Failed to scale image")
            return false
        }

        cursor.setRepresentation(scaledBitmap, for: targetScale)

        // Set cursor size to 32x32 points (since we use 2x scale)
        cursor.size = NSSize(width: 32, height: 32)

        appState.markAsChanged()

        // Trigger refresh - both local preview and cursor list
        localRefreshTrigger += 1
        appState.cursorListRefreshTrigger += 1

        debugLog("Image imported successfully: \(originalWidth)x\(originalHeight) → \(CursorImageScaler.standardCursorSize)x\(CursorImageScaler.standardCursorSize)")
        return true
    }

    // MARK: - GIF Import

    /// Load an animated GIF file and extract all frames
    private func loadGIFImage(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else {
            debugLog("Failed to read GIF data from: \(url)")
            return false
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            debugLog("Failed to create image source from GIF")
            return false
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 0 else {
            debugLog("GIF has no frames")
            return false
        }

        // For single-frame GIFs, treat as static image
        if frameCount == 1 {
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                debugLog("Failed to get first GIF frame")
                return false
            }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let scaledBitmap = CursorImageScaler.scaleImageToStandardSize(bitmap) else {
                debugLog("Failed to scale GIF image")
                return false
            }

            cursor.setRepresentation(scaledBitmap, for: targetScale)
            cursor.size = NSSize(width: 32, height: 32)
            cursor.frameCount = 1
            cursor.frameDuration = 0.0

            appState.markAsChanged()
            localRefreshTrigger += 1
            appState.cursorListRefreshTrigger += 1

            debugLog("Static GIF imported successfully")
            return true
        }

        // Multi-frame GIF - extract all frames
        var frames: [NSBitmapImageRep] = []
        var totalDuration: Double = 0.0
        var frameWidth: Int = 0
        var frameHeight: Int = 0
        var failedFrames = 0

        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, i, nil) else {
                failedFrames += 1
                debugLog("Failed to decode GIF frame \(i)")
                continue
            }

            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            frames.append(bitmap)

            if i == 0 {
                frameWidth = bitmap.pixelsWide
                frameHeight = bitmap.pixelsHigh
            }

            // Get frame duration from GIF properties
            if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) as? [String: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                // Try unclamped delay time first, then delay time
                if let delay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double, delay > 0 {
                    totalDuration += delay
                } else if let delay = gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double, delay > 0 {
                    totalDuration += delay
                } else {
                    totalDuration += 0.1  // Default 100ms per frame
                }
            } else {
                totalDuration += 0.1
            }
        }

        guard !frames.isEmpty else {
            debugLog("Failed to extract any frames from GIF")
            return false
        }

        // Warn if too many frames failed to decode
        if failedFrames > 0 {
            let failureRate = Double(failedFrames) / Double(frameCount)
            debugLog("GIF import: \(failedFrames)/\(frameCount) frames failed to decode (\(String(format: "%.1f%%", failureRate * 100)))")

            if failureRate > 0.2 {
                // More than 20% frames failed - show warning to user
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = String(localized:"gif_decode_warning_title")
                    alert.informativeText = String(format: String(localized:"gif_decode_warning_message"), failedFrames, frameCount)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: String(localized:"ok"))
                    alert.runModal()
                }
            }
        }

        // Downsample frames to maximum 24 if needed (system limit)
        let maxFrameCount = CursorImageScaler.maxFrameCount
        if frames.count > maxFrameCount {
            let originalFrameCount = frames.count
            let downsampledFrames = CursorImageScaler.downsampleFrames(frames, targetCount: maxFrameCount)
            debugLog("GIF downsampled: \(originalFrameCount) → \(downsampledFrames.count) frames")
            frames = downsampledFrames
            // totalDuration already represents the correct total animation time;
            // dividing by the new frame count below gives the correct per-frame duration.
        }

        // Calculate average frame duration
        let avgFrameDuration = totalDuration / Double(frames.count)

        // Create a sprite sheet (all frames stacked vertically)
        guard let spriteSheet = CursorImageScaler.createSpriteSheet(from: frames, frameWidth: frameWidth, frameHeight: frameHeight) else {
            debugLog("Failed to create sprite sheet from GIF frames")
            return false
        }

        // Scale the sprite sheet
        guard let scaledSpriteSheet = CursorImageScaler.scaleSpriteSheet(spriteSheet, frameCount: frames.count, originalFrameWidth: frameWidth, originalFrameHeight: frameHeight) else {
            debugLog("Failed to scale GIF sprite sheet")
            return false
        }

        cursor.setRepresentation(scaledSpriteSheet, for: targetScale)
        cursor.size = NSSize(width: 32, height: 32)
        cursor.frameCount = frames.count
        cursor.frameDuration = CGFloat(avgFrameDuration)

        appState.markAsChanged()
        localRefreshTrigger += 1
        appState.cursorListRefreshTrigger += 1

        debugLog("Animated GIF imported: \(frameWidth)x\(frameHeight), \(frames.count) frames, \(String(format: "%.3f", avgFrameDuration))s/frame")
        return true
    }

    // MARK: - Windows Cursor Import

    /// Load a Windows cursor file (.cur or .ani)
    private func loadWindowsCursor(from url: URL) -> Bool {
        do {
            let result = try WindowsCursorConverter.shared.convert(fileURL: url)

            // Create bitmap from result
            guard let originalBitmap = result.createBitmapImageRep() else {
                debugLog("Failed to create bitmap from Windows cursor")
                return false
            }

            // For animated cursors, set frame count and duration
            // (downsampling already handled by WindowsCursorConverter if needed)
            if result.frameCount > 1 {
                cursor.frameCount = result.frameCount
                cursor.frameDuration = result.frameDuration
            } else {
                cursor.frameCount = 1
                cursor.frameDuration = 0.0
            }

            // Calculate scale factor for hotspot adjustment
            let originalWidth = CGFloat(result.width)
            let originalHeight = CGFloat(result.height)
            let targetSizeF = CGFloat(CursorImageScaler.standardCursorSize)

            // For animated cursors, the sprite sheet height is frameCount * height
            // We need to scale the entire sprite sheet
            let frameCount = result.frameCount
            let singleFrameHeight = originalHeight

            // Scale factor (same as PNG import logic)
            let scale = min(targetSizeF / originalWidth, targetSizeF / singleFrameHeight)
            let scaledWidth = originalWidth * scale
            let scaledHeight = singleFrameHeight * scale

            // Offset for centering (in pixels)
            let offsetX = (targetSizeF - scaledWidth) / 2
            let offsetY = (targetSizeF - scaledHeight) / 2

            // Scale hotspot proportionally (in pixels)
            let scaledHotspotXPixels = CGFloat(result.hotspotX) * scale + offsetX
            let scaledHotspotYPixels = CGFloat(result.hotspotY) * scale + offsetY

            // Convert from pixels to points (divide by 2 for 2x HiDPI)
            // This is the KEY fix: hotspot is in points, not pixels
            var scaledHotspotX = scaledHotspotXPixels / 2.0
            var scaledHotspotY = scaledHotspotYPixels / 2.0

            // Clamp hotspot to valid range [0, MCMaxHotspotValue]
            // This prevents CGSRegisterCursorWithImages from failing with CGError=1000
            // Use the same constant as defined in MCDefs.h
            scaledHotspotX = min(max(0, scaledHotspotX), CGFloat(MCMaxHotspotValue))
            scaledHotspotY = min(max(0, scaledHotspotY), CGFloat(MCMaxHotspotValue))

            // Set hotspot (in points)
            cursor.hotSpot = NSPoint(x: scaledHotspotX, y: scaledHotspotY)

            // Set size to 32x32 points (since we use 2x scale, same as PNG import)
            cursor.size = NSSize(width: 32, height: 32)

            // Scale the bitmap to standard size (64x64 per frame)
            if frameCount > 1 {
                // Animated cursor: scale each frame and stack vertically
                guard let scaledBitmap = CursorImageScaler.scaleSpriteSheet(originalBitmap, frameCount: frameCount, originalFrameWidth: Int(originalWidth), originalFrameHeight: Int(singleFrameHeight)) else {
                    debugLog("Failed to scale animated cursor sprite sheet")
                    return false
                }
                cursor.setRepresentation(scaledBitmap, for: targetScale)
            } else {
                // Static cursor: scale to 64x64
                guard let scaledBitmap = CursorImageScaler.scaleImageToStandardSize(originalBitmap) else {
                    debugLog("Failed to scale Windows cursor")
                    return false
                }
                cursor.setRepresentation(scaledBitmap, for: targetScale)
            }

            appState.markAsChanged()

            // Trigger refresh
            localRefreshTrigger += 1
            appState.cursorListRefreshTrigger += 1

            let frameInfo = result.frameCount > 1 ? " (\(result.frameCount) frames)" : ""
            debugLog("Windows cursor imported: \(result.width)x\(result.height)\(frameInfo) → \(CursorImageScaler.standardCursorSize)x\(CursorImageScaler.standardCursorSize)")
            return true

        } catch {
            debugLog("Failed to convert Windows cursor: \(error.localizedDescription)")
            appState.imageImportWarningMessage = "Failed to import Windows cursor: \(error.localizedDescription)"
            appState.showImageImportWarning = true
            return false
        }
    }
}

// MARK: - Preview

#Preview {
    EditOverlayView(cape: CursorLibrary(name: "Test Cape", author: "Test"))
        .environment(AppState.shared)
}
