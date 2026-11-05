// ContentView.swift: Hauptfenster-Inhalt.
//
// Holt die Link-Map-HTML aus LinkMapBuilder und zeigt sie in einer WebView.
// Verwaltet den Loading-State und reagiert auf Refresh-Anfragen (⌘R / Menü).
//
// Beim ersten Start (oder wenn der User onboardingDone gelöscht hat) zeigt
// die View OnboardingView statt direkt die Karte zu laden, der User muss
// einmalig Full Disk Access erteilen.

import SwiftUI
import AppKit
import ApplicationServices

struct ContentView: View {
    @StateObject private var model = LinkMapModel()
    @State private var showOnboarding = !OnboardingModel.hasCompletedOnboarding
    @State private var selectedView: NotesMapPrimaryView = .map

    /// True wenn entweder First-Launch ODER FDA wurde nachträglich entzogen
    /// (App lief mal, dann hat der User in den Settings das Häkchen entfernt).
    /// In beiden Fällen wollen wir die schöne OnboardingView zeigen, nicht
    /// die generische ErrorView.
    var shouldShowOnboarding: Bool {
        showOnboarding || model.needsFullDiskAccess
    }

    var body: some View {
        Group {
            if selectedView == .kozane {
                KozaneView(onArrangeNotes: KozaneSideBySideCoordinator.arrange)
            } else {
                ZStack {
                    if shouldShowOnboarding {
                        OnboardingView(onComplete: {
                            showOnboarding = false
                            // FDA wurde gerade gewährt, Build erneut anstoßen.
                            if model.needsFullDiskAccess {
                                model.regenerate()
                            }
                        })
                    } else if let html = model.html {
                        WebView(html: html, baseURL: model.baseURL)
                            .ignoresSafeArea()
                    } else if let error = model.errorMessage {
                        ErrorView(message: error, retry: { model.regenerate() })
                    } else {
                        LoadingView(message: model.statusMessage)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $selectedView) {
                    Text(Localized.string(\.viewMap)).tag(NotesMapPrimaryView.map)
                    Text(Localized.string(\.viewKozane)).tag(NotesMapPrimaryView.kozane)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
        }
        .task(id: shouldShowOnboarding) {
            // Erst nach Abschluss von Onboarding loslegen, sonst rennt der
            // initialLoad in einen FDA-Fehler bevor der User die Berechtigung
            // erteilt hat.
            if !shouldShowOnboarding && model.html == nil {
                await model.initialLoad()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .linkMapRefreshRequested)) { _ in
            // Silent-Refresh: HTML bleibt sichtbar, im Hintergrund neu laden.
            // Wenn noch kein HTML da ist (Startup), fällt silentRefresh
            // faktisch auf initialLoad zurück (Build setzt html beim Fertig).
            model.silentRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .linkMapHeightmapRequested)) { _ in
            // User hat die Heightmap-Ansicht angefordert. prepareHeightmap ist
            // idempotent, mehrfache Klicks während eines laufenden Batches
            // werden ignoriert.
            model.prepareHeightmap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .linkMapHeightmapLabelsRequested)) { note in
            // 3D-View hat Peak-Cluster geschickt → Ollama-Labels generieren.
            guard let info = note.userInfo else { return }
            model.requestPeakLabels(userInfo: info)
        }
    }
}

private enum NotesMapPrimaryView: Hashable {
    case map
    case kozane
}

/// Kozane を開く時だけ、現在の画面を二分して Notes と NoteMap を並べる。
/// Notes のウィンドウ操作を許可しない場合でも、Notes の起動と NoteMap の右配置は行う。
@MainActor
private enum KozaneSideBySideCoordinator {
    static func arrange() -> String? {
        guard let noteMapWindow = NSApp.keyWindow ?? NSApp.mainWindow,
              let screen = noteMapWindow.screen ?? NSScreen.main else {
            return "NoteMap のウィンドウが見つかりません。"
        }

        let visibleFrame = screen.visibleFrame
        let halfWidth = floor(visibleFrame.width / 2)
        let notesFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: halfWidth,
            height: visibleFrame.height
        )
        let noteMapFrame = NSRect(
            x: visibleFrame.minX + halfWidth,
            y: visibleFrame.minY,
            width: visibleFrame.width - halfWidth,
            height: visibleFrame.height
        )

        noteMapWindow.setFrame(noteMapFrame, display: true, animate: true)
        kozaneWindow = noteMapWindow

        let notesBounds = AppleScriptBounds(
            left: Int(notesFrame.minX.rounded()),
            top: Int((screen.frame.maxY - notesFrame.maxY).rounded()),
            right: Int(notesFrame.maxX.rounded()),
            bottom: Int((screen.frame.maxY - notesFrame.minY).rounded())
        )
        return arrangeCompanionNotesWindow(with: notesBounds)
    }

    private static let companionProcessIdentifierKey = "kozaneNotesCompanionProcessIdentifier"
    private static var companionProcessIdentifier: pid_t? = {
        let identifier = UserDefaults.standard.integer(forKey: companionProcessIdentifierKey)
        return identifier > 0 ? pid_t(identifier) : nil
    }()
    private static var kozaneWindow: NSWindow?

    private static func arrangeCompanionNotesWindow(with bounds: AppleScriptBounds) -> String? {
        let promptOption = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(promptOption) else {
            return "システム設定 > プライバシーとセキュリティ > アクセシビリティで NotesMap を許可してから、もう一度試してください。"
        }

        if let companion = existingCompanionApplication() {
            return position(companion, in: bounds)
        }

        let notesURL = URL(fileURLWithPath: "/System/Applications/Notes.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: notesURL, configuration: configuration) { application, _ in
            guard let application else { return }

            let processIdentifier = application.processIdentifier
            Task { @MainActor in
                companionProcessIdentifier = processIdentifier
                UserDefaults.standard.set(
                    processIdentifier,
                    forKey: companionProcessIdentifierKey
                )
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let companion = existingCompanionApplication() else { return }
                _ = position(companion, in: bounds)
            }
        }
        return nil
    }

    private static func existingCompanionApplication() -> NSRunningApplication? {
        guard let processIdentifier = companionProcessIdentifier else { return nil }

        let companion = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.Notes")
            .first(where: { $0.processIdentifier == processIdentifier && !$0.isTerminated })

        if companion == nil {
            companionProcessIdentifier = nil
            UserDefaults.standard.removeObject(forKey: companionProcessIdentifierKey)
        }
        return companion
    }

    private static func companionWindowElement(in applicationElement: AXUIElement) -> AXUIElement? {
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
        let focusedWindow {
            return unsafeBitCast(focusedWindow, to: AXUIElement.self)
        }

        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windows
        ) == .success,
        let windows = windows as? [AXUIElement] else {
            return nil
        }
        return windows.first
    }

    private static func position(
        _ application: NSRunningApplication,
        in bounds: AppleScriptBounds
    ) -> String? {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let windowElement = companionWindowElement(in: applicationElement) else {
            return "Kozane 用に起動した Notes のウィンドウが見つかりません。"
        }

        // 新しく起動した Notes が、既存の全画面 Notes の Split View に合流するのを防ぐ。
        // ここで操作するのは Kozane 専用プロセスのウィンドウだけである。
        _ = AXUIElementSetAttributeValue(
            windowElement,
            "AXFullScreen" as CFString,
            kCFBooleanFalse
        )

        var position = CGPoint(x: bounds.left, y: bounds.top)
        var size = CGSize(width: bounds.right - bounds.left, height: bounds.bottom - bounds.top)
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return "Notes ウィンドウの位置を作れませんでした。"
        }

        let positionResult = AXUIElementSetAttributeValue(
            windowElement,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            windowElement,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        guard positionResult == .success, sizeResult == .success else {
            return "macOS が Kozane 用 Notes の配置変更を許可しませんでした。"
        }
        kozaneWindow?.makeKeyAndOrderFront(nil)
        return nil
    }

    private struct AppleScriptBounds: Sendable {
        let left: Int
        let top: Int
        let right: Int
        let bottom: Int
    }
}

// MARK: - LoadingView

private struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ErrorView

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(Localized.string(\.errorTitle))
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .textSelection(.enabled)
            Button(Localized.string(\.errorRetry), action: retry)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
