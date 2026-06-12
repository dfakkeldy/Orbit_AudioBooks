import SwiftUI
import GRDB

struct ContentCardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerModel.self) private var model

    let card: ContentCard
    var onSaved: (() -> Void)?

    @State private var text: String
    @State private var title: String
    @State private var frontText: String = ""
    @State private var backText: String = ""

    init(card: ContentCard, onSaved: (() -> Void)? = nil) {
        self.card = card
        self.onSaved = onSaved
        _text = State(initialValue: card.cardType == .note || card.cardType == .transcription ? card.title : "")
        _title = State(initialValue: card.cardType == .bookmark ? card.title : "")
        if card.cardType == .flashcard {
            _frontText = State(initialValue: card.title)
            _backText = State(initialValue: card.subtitle ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch card.cardType {
                case .note, .transcription:
                    Section("Text") {
                        TextEditor(text: $text)
                            .frame(minHeight: 120)
                            .font(.body)
                    }
                case .bookmark:
                    Section("Title") {
                        TextField("Bookmark Title", text: $title)
                    }
                    Section("Note") {
                        TextEditor(text: $text)
                            .frame(minHeight: 100)
                            .font(.body)
                    }
                case .flashcard:
                    Section("Front") {
                        TextEditor(text: $frontText)
                            .frame(minHeight: 80)
                            .font(.body)
                    }
                    Section("Back") {
                        TextEditor(text: $backText)
                            .frame(minHeight: 80)
                            .font(.body)
                    }
                case .playbackSession, .plannedSession,
                     .voiceMemo, .chapterTransition, .imageAsset:
                    ContentUnavailableView(
                        "Not Editable",
                        systemImage: "lock",
                        description: Text("This item type cannot be edited.")
                    )
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if canSave {
                        Button("Save") { save() }
                    }
                }
            }
        }
    }

    private var navTitle: String {
        switch card.cardType {
        case .note, .transcription: return "Edit Note"
        case .bookmark: return "Edit Bookmark"
        case .flashcard: return "Edit Card"
        default: return "Edit"
        }
    }

    private var canSave: Bool {
        switch card.cardType {
        case .flashcard: return !frontText.isEmpty && !backText.isEmpty
        case .note, .transcription: return !text.isEmpty
        case .bookmark: return !title.isEmpty
        default: return false
        }
    }

    private func save() {
        guard let db = model.databaseService else { return }
        switch card.cardType {
        case .flashcard:
            let writer = db.writer
            do {
                var flashcard = try writer.read { db in try Flashcard.fetchOne(db, key: card.id) }
                guard var card = flashcard else { return }
                card.frontText = frontText
                card.backText = backText
                card.modifiedAt = Date().ISO8601Format()
                try writer.write { db in try card.update(db) }
            } catch { return }
        case .bookmark:
            break
        case .note, .transcription:
            break
        default:
            break
        }
        onSaved?()
        dismiss()
    }
}
