// SelectedNoteMonitor.swift: observes the note selected in Apple Notes.

import AppKit
import Foundation
import Observation

struct SelectedAppleNote: Equatable {
    let id: String
    let title: String
    let body: String
}

@MainActor
@Observable
final class SelectedNoteMonitor {
    enum State: Equatable {
        case waiting
        case selected(SelectedAppleNote)
        case unavailable(String)
    }

    private(set) var state: State = .waiting

    @ObservationIgnored private var lastNote: SelectedAppleNote?

    func run() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    private func refresh() {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Notes"
        ).isEmpty == false else {
            publish(.unavailable("Apple Notes を開いてメモを選択してください。"))
            return
        }

        let source = """
        tell application "Notes"
            set chosenNotes to selection
            if (count of chosenNotes) is 0 then return {}
            set chosenNote to item 1 of chosenNotes
            return {(id of chosenNote as text), (name of chosenNote as text), (body of chosenNote as text)}
        end tell
        """

        var errorInfo: NSDictionary?
        guard let descriptor = NSAppleScript(source: source)?
            .executeAndReturnError(&errorInfo) else {
            let message = (errorInfo?[NSAppleScript.errorMessage] as? String)
                ?? "Apple Notes の選択中メモを取得できません。"
            publish(.unavailable(message))
            return
        }

        guard descriptor.numberOfItems >= 3,
              let id = descriptor.atIndex(1)?.stringValue,
              let title = descriptor.atIndex(2)?.stringValue,
              let html = descriptor.atIndex(3)?.stringValue else {
            publish(.unavailable("Apple Notes でメモを選択してください。"))
            return
        }

        let note = SelectedAppleNote(
            id: id,
            title: title,
            body: Self.plainText(fromHTML: html)
        )
        guard note != lastNote else { return }
        lastNote = note
        publish(.selected(note))
    }

    private func publish(_ newState: State) {
        guard state != newState else { return }
        state = newState
    }

    private static func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return html
        }

        return attributed.string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
