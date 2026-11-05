// KozaneView.swift: a light card surface for composing prose from small slips.

import AppKit
import SwiftUI

struct KozaneView: View {
    @State private var store = KozaneStore()
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                workSurface
                    .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
                sourceRail
                    .frame(minWidth: 230, idealWidth: 280, maxWidth: 340, maxHeight: .infinity)
            }
        }
        .background(KozanePalette.paper)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "note.text")
                .foregroundStyle(KozanePalette.accent)

            TextField("Untitled draft", text: Binding(
                get: { store.bundle.title },
                set: { store.updateTitle($0) }
            ))
            .textFieldStyle(.plain)
            .font(.headline)
            .frame(maxWidth: 320)

            Spacer()

            Text("\(store.bundle.cards.count) cards")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                store.addCard()
            } label: {
                Label("New card", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(KozanePalette.accent)

            Button {
                copyForAppleNotes()
            } label: {
                Label(didCopy ? "Copied" : "Copy for Apple Notes", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(store.composedText.isEmpty)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(KozanePalette.header)
    }

    private var workSurface: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                KozanePalette.board

                if store.bundle.cards.isEmpty {
                    ContentUnavailableView(
                        "Start writing",
                        systemImage: "rectangle.and.pencil.and.ellipsis",
                        description: Text("Add a card, then write and arrange your small pieces of prose here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                ForEach(store.bundle.cards) { card in
                    KozaneCardView(
                        text: Binding(
                            get: { store.bundle.cards.first(where: { $0.id == card.id })?.text ?? "" },
                            set: { store.updateText(for: card.id, text: $0) }
                        ),
                        position: card.position,
                        isSelected: store.selectedCardID == card.id,
                        onSelect: { store.selectCard(card.id) },
                        onMove: { store.moveCard(id: card.id, to: $0) },
                        onMoveEnd: { store.finishMovingCard() },
                        onDelete: { store.deleteCard(id: card.id) }
                    )
                    .position(x: card.position.x, y: card.position.y)
                }
            }
            .clipShape(Rectangle())
        }
    }

    private var sourceRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Related Notes", systemImage: "sparkle.magnifyingglass")
                .font(.headline)

            Text("While you write, related Apple Notes and kozane will appear here. Phase 1 keeps this space quiet so the cards and the writing come first.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Label("Apple Notes stays the original", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(KozanePalette.rail)
    }

    private func copyForAppleNotes() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.composedText, forType: .string)
        didCopy = true
    }
}

private struct KozaneCardView: View {
    @Binding var text: String
    let position: KozanePoint
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (KozanePoint) -> Void
    let onMoveEnd: () -> Void
    let onDelete: () -> Void

    @State private var dragOrigin: KozanePoint?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)

                Text("Kozane")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove card")
            }
            .padding(.horizontal, 8)
            .background(KozanePalette.cardHeader)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.white)
                .onTapGesture(perform: onSelect)
        }
        .frame(width: 230, height: 160)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? KozanePalette.accent : KozanePalette.cardBorder, lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
        .onTapGesture(perform: onSelect)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let origin = dragOrigin ?? position
                dragOrigin = origin
                onMove(KozanePoint(
                    x: max(130, origin.x + value.translation.width),
                    y: max(90, origin.y + value.translation.height)
                ))
            }
            .onEnded { _ in
                dragOrigin = nil
                onMoveEnd()
            }
    }
}

private enum KozanePalette {
    static let paper = Color(red: 1.0, green: 0.99, blue: 0.94)
    static let header = Color(red: 1.0, green: 0.98, blue: 0.86)
    static let board = Color(red: 0.99, green: 0.97, blue: 0.88)
    static let rail = Color(red: 1.0, green: 0.98, blue: 0.90)
    static let cardHeader = Color(red: 1.0, green: 0.94, blue: 0.68)
    static let cardBorder = Color(red: 0.87, green: 0.82, blue: 0.64)
    static let accent = Color(red: 0.86, green: 0.61, blue: 0.04)
}