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

        let notesBounds = AppleScriptBounds(
            left: Int(notesFrame.minX.rounded()),
            top: Int((screen.frame.maxY - notesFrame.maxY).rounded()),
            right: Int(notesFrame.maxX.rounded()),
            bottom: Int((screen.frame.maxY - notesFrame.minY).rounded())
        )
        return arrangeCompanionNotesWindow(with: notesBounds)
    }

    private static func arrangeCompanionNotesWindow(with bounds: AppleScriptBounds) -> String? {
        // 通常サイズの Notes ウィンドウがあれば再利用する。すべてがフルスクリーン
        // のときだけ新規ウィンドウを作るため、操作のたびにウィンドウは増えない。
        let source = """
        tell application "Notes" to activate
        tell application "System Events"
            tell process "Notes"
                set companionWindow to missing value
                repeat with noteWindow in windows
                    try
                        if value of attribute "AXFullScreen" of noteWindow is false then
                            set companionWindow to noteWindow
                            exit repeat
                        end if
                    end try
                end repeat

                if companionWindow is missing value then
                    try
                        click menu item "New Window" of menu "Window" of menu bar 1
                    on error
                        click menu item "新規ウインドウ" of menu "ウインドウ" of menu bar 1
                    end try
                    delay 0.4
                    set companionWindow to front window
                end if

                if companionWindow is not missing value then
                    set position of companionWindow to {\(bounds.left), \(bounds.top)}
                    set size of companionWindow to {\(bounds.right - bounds.left), \(bounds.bottom - bounds.top)}
                end if
            end tell
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return "Notes を操作するスクリプトを作れませんでした。"
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        guard let error else {
            return nil
        }
        return error[NSAppleScript.errorMessage] as? String
            ?? "macOS が Notes または System Events の操作を許可しませんでした。"
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
