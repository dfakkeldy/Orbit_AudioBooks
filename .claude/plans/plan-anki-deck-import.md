# Plan ADI: JSON Deck Import

## Summary

Allow users to import pre-made flashcard decks via JSON files. Define a `Codable` import format, build a parser, and add a `.fileImporter` entry point in the UI.

## Current State

There is no flashcard deck concept or file import mechanism in the app. The `BookmarkStore` handles JSON encoding/decoding for persistence. `SettingsView` has sections for display, store, and watch settings — a natural place to add an import action.

## Proposed Implementation

### 1. FlashcardDeckImport Model

Define a `Codable` struct matching the import format:

```swift
struct FlashcardDeckImport: Codable {
    let deckName: String
    let targetMediaID: String
    let cards: [ImportedCard]
    
    struct ImportedCard: Codable {
        let frontText: String
        let backText: String
        let startTime: Double
        let endTime: Double
        let triggerTiming: String  // "beginning", "end", or "manualOnly"
    }
}
```

### 2. Import Utility

Create a utility function that:
1. Parses the JSON file
2. Validates each card (non-empty text, valid time ranges, known `triggerTiming`)
3. Maps to `Flashcard` models with default SM-2 properties (interval=0, easeFactor=2.5, repetitions=0, nextReviewDate=now)
4. Inserts into `FlashcardStore`
5. Returns success with count or throws a descriptive error

```swift
enum DeckImportError: LocalizedError {
    case fileReadFailed(Error)
    case invalidJSON(Error)
    case invalidTriggerTiming(String, cardIndex: Int)
    case emptyDeck
    
    var errorDescription: String? { ... }
}

func importDeck(from url: URL, store: FlashcardStore) throws -> Int {
    let data = try Data(contentsOf: url)
    let deck = try JSONDecoder().decode(FlashcardDeckImport.self, from: data)
    guard !deck.cards.isEmpty else { throw DeckImportError.emptyDeck }
    
    for (i, card) in deck.cards.enumerated() {
        guard let timing = FlashcardTriggerTiming(rawValue: card.triggerTiming) else {
            throw DeckImportError.invalidTriggerTiming(card.triggerTiming, cardIndex: i)
        }
        let flashcard = Flashcard(
            frontText: card.frontText,
            backText: card.backText,
            startTime: card.startTime,
            endTime: card.endTime,
            targetMediaID: deck.targetMediaID,
            triggerTiming: timing
        )
        store.insert(flashcard)
    }
    
    return deck.cards.count
}
```

### 3. UI Entry Point

Add an "Import Deck" button in Settings (or Library view):

```swift
.fileImporter(
    isPresented: $showingFileImporter,
    allowedContentTypes: [.json],
    allowsMultipleSelection: false
) { result in
    switch result {
    case .success(let urls):
        guard let url = urls.first else { return }
        do {
            let count = try importDeck(from: url, store: flashcardStore)
            alertMessage = "Imported \(count) cards from deck."
        } catch {
            alertMessage = error.localizedDescription
        }
        showingAlert = true
    case .failure(let error):
        alertMessage = error.localizedDescription
        showingAlert = true
    }
}
```

### 4. Example JSON Format

Document the expected format for deck authors:

```json
{
  "deckName": "Chapter 1 Vocabulary",
  "targetMediaID": "my-audiobook.m4b",
  "cards": [
    {
      "frontText": "What does 'ephemeral' mean?",
      "backText": "Lasting for a very short time.",
      "startTime": 45.0,
      "endTime": 52.0,
      "triggerTiming": "beginning"
    },
    {
      "frontText": "Summarize the first paragraph.",
      "backText": "The author introduces the setting as a small coastal village in winter.",
      "startTime": 120.0,
      "endTime": 135.0,
      "triggerTiming": "end"
    }
  ]
}
```

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/Models/FlashcardDeckImport.swift` |
| Create | `OrbitAudioBooks/Services/DeckImportService.swift` |
| Modify | `OrbitAudioBooks/Views/SettingsView.swift` (add Import Deck button) |

## Dependencies

- **Depends on:** Plan ASRS (Flashcard model, FlashcardStore)
- **Blocked by:** Nothing.
- **Conflicts with:** Plan L10N (SettingsView) — L10N is done, but the import button text must use `String(localized:)`.

## Complexity

**Small.** File import is a single `.fileImporter` modifier. The parser is ~30 lines. The model is a simple `Codable` struct. The entire feature is ~100 lines across 3 files.
