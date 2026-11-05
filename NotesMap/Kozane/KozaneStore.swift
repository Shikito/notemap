// KozaneStore.swift: local persistence and card arrangement state for Kozane.

import Foundation
import Observation

struct KozanePoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct KozaneCard: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var position: KozanePoint

    init(id: UUID = UUID(), text: String = "", position: KozanePoint) {
        self.id = id
        self.text = text
        self.position = position
    }
}

struct KozaneBundle: Codable, Equatable {
    var title: String
    var cards: [KozaneCard]
    var updatedAt: Date

    static let empty = KozaneBundle(title: "", cards: [], updatedAt: .now)
}

@MainActor
@Observable
final class KozaneStore {
    var bundle: KozaneBundle
    var selectedCardID: UUID?
    var saveError: String?

    @ObservationIgnored private let fileURL: URL

    init() {
        fileURL = Self.storageURL()
        bundle = Self.load(from: fileURL) ?? .empty
        selectedCardID = bundle.cards.first?.id
    }

    func addCard() {
        let index = bundle.cards.count
        let card = KozaneCard(
            position: KozanePoint(
                x: 180 + Double(index % 4) * 250,
                y: 140 + Double(index / 4) * 190
            )
        )
        bundle.cards.append(card)
        selectedCardID = card.id
        save()
    }

    func updateTitle(_ title: String) {
        bundle.title = title
        save()
    }

    func updateText(for id: UUID, text: String) {
        guard let index = bundle.cards.firstIndex(where: { $0.id == id }) else { return }
        bundle.cards[index].text = text
        selectedCardID = id
        save()
    }

    func moveCard(id: UUID, to position: KozanePoint) {
        guard let index = bundle.cards.firstIndex(where: { $0.id == id }) else { return }
        bundle.cards[index].position = position
    }

    func finishMovingCard() {
        save()
    }

    func selectCard(_ id: UUID) {
        selectedCardID = id
    }

    func deleteCard(id: UUID) {
        guard let index = bundle.cards.firstIndex(where: { $0.id == id }) else { return }
        bundle.cards.remove(at: index)
        selectedCardID = bundle.cards.last?.id
        save()
    }

    var composedText: String {
        bundle.cards
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if abs(lhs.position.y - rhs.position.y) < 60 {
                    return lhs.position.x < rhs.position.x
                }
                return lhs.position.y < rhs.position.y
            }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    func save() {
        bundle.updatedAt = .now
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(bundle)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static func storageURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("NotesMap", isDirectory: true)
            .appendingPathComponent("kozane.json")
    }

    private static func load(from url: URL) -> KozaneBundle? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KozaneBundle.self, from: data)
    }
}