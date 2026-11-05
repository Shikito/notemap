// KozaneSimilarityModel.swift: semantic Apple Notes search for the selected slip.

import Foundation
import Observation

struct KozaneNoteMatch: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let snippet: String
    let body: String
    let score: Double
    let deepLink: URL
}

@MainActor
@Observable
final class KozaneSimilarityModel {
    enum State: Equatable {
        case idle
        case preparing
        case searching
        case ready
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var matches: [KozaneNoteMatch] = []

    @ObservationIgnored private var corpus: [CorpusEntry] = []
    @ObservationIgnored private var preparedEndpoint: URL?
    @ObservationIgnored private var preparedModel: String?

    func search(
        text: String,
        excluding sourceNoteID: String?,
        sourceTitle: String? = nil
    ) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            matches = []
            state = .idle
            return
        }

        do {
            let service = EmbeddingService(
                baseURL: OllamaPreferences.baseURL,
                model: OllamaPreferences.embedderModel
            )
            try await prepareCorpusIfNeeded(service: service)
            guard !Task.isCancelled else { return }

            state = .searching
            let queryVector = try await service.embed(String(query.prefix(4000)))
            guard !Task.isCancelled else { return }

            let corpusSnapshot = corpus
            let ranked = await Task.detached(priority: .userInitiated) {
                Self.rank(
                    queryVector: queryVector,
                    corpus: corpusSnapshot,
                    excluding: sourceNoteID,
                    sourceTitle: sourceTitle
                )
            }.value
            guard !Task.isCancelled else { return }

            matches = ranked
            state = .ready
        } catch {
            guard !Task.isCancelled else { return }
            matches = []
            state = .unavailable(error.localizedDescription)
        }
    }

    private func prepareCorpusIfNeeded(service: EmbeddingService) async throws {
        if !corpus.isEmpty,
           preparedEndpoint == service.baseURL,
           preparedModel == service.model {
            return
        }

        state = .preparing
        switch await service.checkAvailability() {
        case .success:
            break
        case .failure(let error):
            throw error
        }

        let documents = try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let database = try NoteStoreDatabase()
                return try database.read { db in
                    let notes = try NoteStoreQueries.listAllNotes(db)
                    let plaintext = try NoteStoreQueries.fetchPlaintextMap(db)
                    return notes.map { note in
                        let body = plaintext[note.id] ?? ""
                        return SearchDocument(
                            id: note.uuid.uppercased(),
                            title: note.title,
                            snippet: Self.snippet(from: body, title: note.title),
                            body: body,
                            deepLink: note.deepLink,
                            text: String(
                                (note.title + "\n\n" + body)
                                    .prefix(4000)
                            )
                        )
                    }
                }
            }
        }.value
        guard !Task.isCancelled else { return }

        let items = documents.map {
            EmbeddingManager.Item(uuid: $0.id, text: $0.text)
        }
        let vectors = try await EmbeddingManager(service: service)
            .embeddings(for: items)
        guard !Task.isCancelled else { return }

        corpus = documents.compactMap { document in
            guard let vector = vectors[document.id],
                  let deepLink = document.deepLink else {
                return nil
            }
            return CorpusEntry(
                id: document.id,
                title: document.title,
                snippet: document.snippet,
                body: document.body,
                deepLink: deepLink,
                vector: vector,
                norm: Self.norm(vector)
            )
        }
        preparedEndpoint = service.baseURL
        preparedModel = service.model
    }

    nonisolated private static func rank(
        queryVector: [Float],
        corpus: [CorpusEntry],
        excluding sourceNoteID: String?,
        sourceTitle: String?
    ) -> [KozaneNoteMatch] {
        let queryNorm = norm(queryVector)
        guard queryNorm > 0 else { return [] }

        return corpus
            .filter { entry in
                if let sourceNoteID,
                   sourceNoteID.localizedCaseInsensitiveContains(entry.id) {
                    return false
                }
                if let sourceTitle, entry.title == sourceTitle {
                    return false
                }
                return true
            }
            .compactMap { entry -> KozaneNoteMatch? in
                guard entry.vector.count == queryVector.count, entry.norm > 0 else {
                    return nil
                }
                let dot = zip(queryVector, entry.vector).reduce(Float.zero) {
                    $0 + $1.0 * $1.1
                }
                let score = Double(dot / (queryNorm * entry.norm))
                guard score.isFinite else { return nil }
                return KozaneNoteMatch(
                    id: entry.id,
                    title: entry.title,
                    snippet: entry.snippet,
                    body: entry.body,
                    score: score,
                    deepLink: entry.deepLink
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(12)
            .map { $0 }
    }

    nonisolated private static func snippet(from body: String, title: String) -> String {
        var cleaned = body
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if cleaned.hasPrefix(title) {
            cleaned.removeFirst(title.count)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(cleaned.prefix(280))
    }

    nonisolated private static func norm(_ vector: [Float]) -> Float {
        sqrt(vector.reduce(Float.zero) { $0 + $1 * $1 })
    }
}

private struct SearchDocument: Sendable {
    let id: String
    let title: String
    let snippet: String
    let body: String
    let deepLink: URL?
    let text: String
}

private struct CorpusEntry: Sendable {
    let id: String
    let title: String
    let snippet: String
    let body: String
    let deepLink: URL
    let vector: [Float]
    let norm: Float
}
