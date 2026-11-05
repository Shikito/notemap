// KozaneView.swift: shows notes related to the note selected in Apple Notes.

import AppKit
import SwiftUI

struct KozaneView: View {
    let onArrangeNotes: () -> String?

    @State private var noteMonitor = SelectedNoteMonitor()
    @State private var similarityModel = KozaneSimilarityModel()
    @State private var selectedMatch: KozaneNoteMatch?
    @State private var notesArrangementError: String?

    var body: some View {
        VStack(spacing: 0) {
            KozaneHeaderView(
                noteState: noteMonitor.state,
                resultCount: similarityModel.matches.count,
                onArrangeNotes: {
                    notesArrangementError = onArrangeNotes()
                }
            )

            Divider()

            if let selectedMatch {
                KozaneNoteDetailView(
                    title: selectedMatch.title,
                    noteBody: selectedMatch.body,
                    score: selectedMatch.score,
                    onBack: { self.selectedMatch = nil },
                    onOpenInNotes: {
                        NSWorkspace.shared.open(selectedMatch.deepLink)
                    }
                )
            } else {
                KozaneRelatedNotesView(
                    state: similarityModel.state,
                    noteState: noteMonitor.state,
                    matches: similarityModel.matches,
                    onSelect: { self.selectedMatch = $0 }
                )
            }
        }
        .background(KozanePalette.paper)
        .preferredColorScheme(.light)
        .task {
            await noteMonitor.run()
        }
        .onChange(of: searchQuery) {
            selectedMatch = nil
        }
        .task(id: searchQuery) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await similarityModel.search(
                text: searchQuery.text,
                excluding: searchQuery.sourceNoteID,
                sourceTitle: searchQuery.sourceTitle
            )
        }
        .alert("Notes を横に並べられませんでした", isPresented: Binding(
            get: { notesArrangementError != nil },
            set: { if !$0 { notesArrangementError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notesArrangementError ?? "")
        }
    }

    private var searchQuery: KozaneNoteQuery {
        guard case .selected(let note) = noteMonitor.state else {
            return KozaneNoteQuery(text: "", sourceNoteID: nil, sourceTitle: nil)
        }
        return KozaneNoteQuery(
            text: note.title + "\n\n" + note.body,
            sourceNoteID: note.id,
            sourceTitle: note.title
        )
    }
}

private struct KozaneNoteQuery: Hashable {
    let text: String
    let sourceNoteID: String?
    let sourceTitle: String?
}

private struct KozaneHeaderView: View {
    let noteState: SelectedNoteMonitor.State
    let resultCount: Int
    let onArrangeNotes: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(KozanePalette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTitle)
                    .font(.headline)
                    .lineLimit(1)

                KozaneSyncStatusView(state: noteState)
            }

            Spacer()

            if resultCount > 0 {
                Text("\(resultCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(action: onArrangeNotes) {
                Label("Notes を横に並べる", systemImage: "rectangle.lefthalf.inset.filled")
            }
            .buttonStyle(.bordered)
            .help("通常サイズの Notes を左側へ配置します")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .background(KozanePalette.header)
    }

    private var selectedTitle: String {
        if case .selected(let note) = noteState {
            return note.title
        }
        return "Kozane"
    }
}

private struct KozaneRelatedNotesView: View {
    let state: KozaneSimilarityModel.State
    let noteState: SelectedNoteMonitor.State
    let matches: [KozaneNoteMatch]
    let onSelect: (KozaneNoteMatch) -> Void

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, proxy.size.width - 40)
            let columnWidth = max(0, (contentWidth - 12) / 2)
            let columns = [
                GridItem(.fixed(columnWidth), spacing: 12),
                GridItem(.fixed(columnWidth), spacing: 12)
            ]

            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 12) {
                switch state {
                case .idle:
                    KozaneIdleView(noteState: noteState)
                case .preparing:
                    KozaneSimilarityProgressView(
                        message: Localized.string(\.kozanePreparingEmbeddings)
                    )
                case .searching:
                    KozaneSimilarityProgressView(
                        message: Localized.string(\.kozaneCalculatingSimilarity)
                    )
                case .unavailable(let message):
                    ContentUnavailableView(
                        Localized.string(\.kozaneSearchUnavailable),
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case .ready:
                    if matches.isEmpty {
                        ContentUnavailableView(
                            Localized.string(\.kozaneNoMatches),
                            systemImage: "magnifyingglass",
                            description: Text(Localized.string(\.kozaneNoMatchesDescription))
                        )
                    } else {
                        ForEach(matches) { match in
                            KozaneNoteMatchRow(
                                title: match.title,
                                snippet: match.snippet,
                                score: match.score,
                                onOpen: { onSelect(match) }
                            )
                        }
                    }
                }
                }
                .padding(20)
                .frame(width: proxy.size.width, alignment: .top)
            }
        }
        .clipped()
    }
}

private struct KozaneIdleView: View {
    let noteState: SelectedNoteMonitor.State

    var body: some View {
        switch noteState {
        case .unavailable(let message):
            ContentUnavailableView(
                "Apple Notes を確認",
                systemImage: "note.text",
                description: Text(message)
            )
        case .waiting:
            KozaneSimilarityProgressView(message: "Apple Notes の選択を確認中…")
        case .selected:
            ContentUnavailableView(
                Localized.string(\.kozaneNoMatches),
                systemImage: "magnifyingglass"
            )
        }
    }
}

private struct KozaneSimilarityProgressView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct KozaneNoteDetailView: View {
    let title: String
    let noteBody: String
    let score: Double
    let onBack: () -> Void
    let onOpenInNotes: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Label(Localized.string(\.kozaneBackToRelated), systemImage: "chevron.backward")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(String(format: Localized.string(\.kozaneSimilarity), score))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: onOpenInNotes) {
                    Label(Localized.string(\.kozaneOpenInNotes), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(KozanePalette.header)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if noteBody.isEmpty {
                        Text(Localized.string(\.kozaneNoBody))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(noteBody)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct KozaneNoteMatchRow: View {
    let title: String
    let snippet: String
    let score: Double
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .foregroundStyle(KozanePalette.accent)

                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.up.forward")
                        .foregroundStyle(.tertiary)
                }

                Text(snippet.isEmpty ? Localized.string(\.kozaneNoBody) : snippet)
                    .font(.callout)
                    .foregroundStyle(snippet.isEmpty ? .tertiary : .secondary)
                    .lineLimit(5)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                Text(String(format: Localized.string(\.kozaneSimilarity), score))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(14)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(KozanePalette.cardBorder)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .help(Localized.string(\.kozaneReadHere))
    }
}

private struct KozaneSyncStatusView: View {
    let state: SelectedNoteMonitor.State

    var body: some View {
        HStack(spacing: 5) {
            switch state {
            case .waiting:
                ProgressView()
                    .controlSize(.small)
                Text("同期を開始中")
            case .selected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Notes と同期中")
            case .unavailable:
                Image(systemName: "exclamationmark.circle")
                Text("同期待ち")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private enum KozanePalette {
    static let paper = Color(red: 1.0, green: 0.99, blue: 0.94)
    static let header = Color(red: 1.0, green: 0.98, blue: 0.86)
    static let cardBorder = Color(red: 0.87, green: 0.82, blue: 0.64)
    static let accent = Color(red: 0.86, green: 0.61, blue: 0.04)
}
