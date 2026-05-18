# Plan ADR: Daily Review UI (Traditional Anki Mode) ✅ DONE (2026-05-18)

## Summary

Build a dedicated Daily Review interface where users review cards that are due, loading specific media snippets on demand. This operates independently of the main audiobook player — the user opens it as a separate tab or sheet to review all due cards across all media files.

## Current State

The app has a tab-based navigation (Chapters/Bookmarks via `PlaylistView`) and a settings sheet. There is no flashcard review UI. The `AudioEngine` can load and play files on demand, and `PlayerModel` manages playback state.

## Proposed Implementation

### 1. DailyReviewViewModel

Query the database for all `Flashcard` objects where `nextReviewDate <= Date()`, across all media files. Sort by due date (oldest first).

```swift
@Observable
final class DailyReviewViewModel {
    private(set) var dueCards: [Flashcard] = []
    private(set) var currentIndex: Int = 0
    private(set) var isRevealed: Bool = false
    private(set) var isPlayingSnippet: Bool = false
    
    var currentCard: Flashcard? {
        guard dueCards.indices.contains(currentIndex) else { return nil }
        return dueCards[currentIndex]
    }
    
    var totalCount: Int { dueCards.count }
    var remainingCount: Int { max(0, dueCards.count - currentIndex) }
    
    func loadDueCards(store: FlashcardStore) {
        dueCards = store.dueCards()
        currentIndex = 0
    }
    
    func gradeCard(_ grade: Int, service: SpacedRepetitionService, store: FlashcardStore) {
        guard let card = currentCard else { return }
        let updated = service.grade(grade: grade, card: card)
        store.save(updated)
        advance()
    }
    
    func advance() {
        currentIndex += 1
        isRevealed = false
    }
}
```

### 2. DailyReviewView

A full-screen or sheet-based SwiftUI view:

- Header showing "Due: X of Y remaining"
- Card front: `frontText` in large type
- "Reveal Answer" button → shows `backText`
- On reveal: load the associated media file in a background `AVPlayer`, seek to `startTime`, play until `endTime`, then pause
- 4 grading buttons (Again/Hard/Good/Easy)
- On grade: process SM-2 update, save to store, instantly load the next due card
- Empty state: "All caught up!" with a celebratory icon when no cards are due

### 3. Background Snippet Player

Use a separate `AVPlayer` instance (not the main audio engine) to avoid disrupting the current audiobook playback state:

```swift
private let snippetPlayer = AVPlayer()

func playSnippet(mediaID: String, startTime: Double, endTime: Double) {
    // Construct URL from mediaID, load AVPlayerItem
    // Seek to startTime
    // Add boundary observer at endTime to auto-pause
    // Play
}
```

### 4. Navigation Entry Point

Add a "Daily Review" button or tab visible when due cards exist. Options:
- A badge on the existing Bookmarks/Playlist tab showing due count
- A dedicated top-level tab
- A section in Settings with a due count and "Start Review" button
- A home screen widget complication showing due count

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/ViewModels/DailyReviewViewModel.swift` |
| Create | `OrbitAudioBooks/Views/DailyReviewView.swift` |
| Modify | `OrbitAudioBooks/Views/ContentView.swift` (add entry point) |
| Modify | `OrbitAudioBooks/ViewModels/PlayerModel.swift` (coordinate snippet player) |

## Dependencies

- **Depends on:** Plan ASRS (Flashcard model, SM-2 algorithm, FlashcardStore)
- **Blocked by:** Nothing specific — operates independently of the main player
- **Conflicts with:** Plan A1 (PlayerModel) — only for the snippet player integration; otherwise independent

## Complexity

**Medium.** Pure UI + ViewModel with a lightweight background player. No real-time audio pipeline changes. The snippet player is a separate `AVPlayer` instance, so it doesn't touch the main `AudioEngine`.
