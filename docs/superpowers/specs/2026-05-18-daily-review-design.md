# Daily Review UI — Design Spec

**Date:** 2026-05-18
**Status:** Approved
**Plan reference:** plan-anki-daily-review.md

## Summary

Wire the orphaned `FlashcardReviewCard` and `FlashcardReviewSession` views into the app with a `DailyReviewViewModel`, media snippet playback, and three navigation entry points (dashboard card, timeline row, dedicated tab). The review flow uses the existing SM-2 algorithm (`SpacedRepetitionService`) and `FlashcardDAO` for persistence.

## Pre-existing Components

| Component | File | Status |
|-----------|------|--------|
| `Flashcard` GRDB record + SM-2 algorithm | `Shared/Database/Flashcard.swift` | Prod-ready |
| `FlashcardDAO` (CRUD + due queries + grading) | `Shared/Database/DAOs/FlashcardDAO.swift` | Prod-ready |
| `FlashcardReviewCard` (card face + 6-grade buttons) | `OrbitAudioBooks/Views/FlashcardReviewCard.swift` | Orphaned — needs minor label updates |
| `FlashcardReviewSession` (progress + wrapper) | `OrbitAudioBooks/Views/FlashcardReviewSession.swift` | Orphaned — needs ViewModel integration |

## New Components

### DailyReviewViewModel

`@Observable` class at `OrbitAudioBooks/ViewModels/DailyReviewViewModel.swift`.

**State:**
- `dueCards: [Flashcard]` — loaded once on init from `FlashcardDAO.allDueCards()`
- `currentIndex: Int = 0`
- `isRevealed: Bool = false`
- `isPlayingSnippet: Bool = false`
- `snippetPlayer: SnippetPlayer?`

**Computed:**
- `currentCard: Flashcard?` — `dueCards[safe: currentIndex]`
- `progress: (current: Int, total: Int)` — `(currentIndex + 1, dueCards.count)`
- `isComplete: Bool` — `currentIndex >= dueCards.count`

**Methods:**
- `loadDueCards(db: DatabaseWriter)` — queries `FlashcardDAO.allDueCards()`, resets index
- `reveal()` — sets `isRevealed = true`, starts snippet playback if card has media timestamps
- `gradeCard(_ grade: Int)` — calls `FlashcardDAO.grade(cardID:grade:)`, logs `flashcardReviewed` timeline event, calls `advance()`
- `advance()` — stops snippet if playing, increments `currentIndex`, resets `isRevealed`
- `cleanup()` — stops snippet player, called on dismiss

### SnippetPlayer

New struct/class at `OrbitAudioBooks/Services/SnippetPlayer.swift`.

Follows the exact same pattern as `BookmarkStore` voice memo playback:
1. `play(url: URL, startTime: TimeInterval, endTime: TimeInterval)` — creates separate `AVAudioEngine` + `AVAudioPlayerNode`, loads `AVAudioFile`, schedules segment from `startTime` to `endTime`, plays
2. `stop()` — stops node + engine, tears down
3. Completion callback: `onPlaybackEnded: (() -> Void)?`

**Audio session management:** Reuses `PlayerModel`'s existing `prepareAudioForVoiceMemo()` / `resumeAudioForMainPlayer()` pattern through new callbacks:
- `onSnippetWillPlay: (() -> Void)?` — PlayerModel sets this to pause main engine + switch session
- `onSnippetDidEnd: (() -> Void)?` — PlayerModel sets this to restore session + resume main player

## Modified Components

### FlashcardReviewCard

**File:** `OrbitAudioBooks/Views/FlashcardReviewCard.swift`

**Changes:**
- Add labels to middle grade buttons: "Hard" on buttons 1-2, "Good" on buttons 3-4
- Accept optional `snippetIsPlaying: Bool` binding to show a "Playing snippet..." indicator

### FlashcardReviewSession

**File:** `OrbitAudioBooks/Views/FlashcardReviewSession.swift`

**Changes:**
- Replace `cards: [Flashcard]` and `onGrade: (Flashcard, Int) -> Void` parameters with `viewModel: DailyReviewViewModel`
- Call `viewModel.reveal()` on card tap (instead of local `isRevealed` state)
- Call `viewModel.gradeCard(grade)` on grade button tap
- Show "All Done" state when `viewModel.isComplete`
- Add snippet playback indicator in the card area

### UpcomingReviewsModuleView

**File:** `OrbitAudioBooks/Views/UpcomingReviewsModuleView.swift`

**Changes:**
- Make the entire card a `Button` that sets a `showingReview` binding
- Expose the due count via a `@Binding` or state

### DashboardShelf

**File:** `OrbitAudioBooks/Views/DashboardShelf.swift`

**Changes:**
- Pass `$showingReview` binding to `UpcomingReviewsModuleView`

### TimelineTab

**File:** `OrbitAudioBooks/Views/TimelineTab.swift`

**Changes:**
- Add a row below `DashboardShelf` that appears when due count > 0: "N cards due for review" with a chevron, tappable to open review session
- Track due count via `@State` queried in `onAppear`

### RootTabView

**File:** `OrbitAudioBooks/Views/RootTabView.swift`

**Changes:**
- Add optional 4th "Review" tab with `systemImage: "rectangle.stack.fill"` and `.badge(dueCount)` when `dueCount > 0`
- Pass `$showingReview` state to `DashboardShelf` and `TimelineTab`
- Sheet presenting `FlashcardReviewSession(viewModel: reviewViewModel)` bound to `$showingReview`
- On appear of any review-triggering element, create `DailyReviewViewModel` and store in `@State`

### PlayerModel

**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift`

**Changes:**
- Add `snippetPlayer = SnippetPlayer()` property
- Wire `snippetPlayer.onSnippetWillPlay` and `onSnippetDidEnd` in `init()` to the existing audio session pause/resume methods
- Expose `var isPlayingSnippet: Bool { snippetPlayer.isPlaying }`
- Add `func logFlashcardReviewed(cardID: String, grade: Int, audiobookID: String)` for timeline event logging

### Timeline Integration

**File:** `OrbitAudioBooks/Services/TimelineService.swift` (or new method in PlayerModel)

**Changes:**
- Log `flashcardReviewed` events via `RealTimeEventDAO` when a card is graded
- These appear as `TimelineContentCard` entries in the `TimelineContentView` timeline

## Navigation Entry Points

```
User sees due count
  ├── DashboardShelf → UpcomingReviewsModuleView (tap)
  ├── TimelineTab → "N cards due" row (tap)
  └── RootTabView → Review tab badge (tap)
        │
        └── Opens .sheet: FlashcardReviewSession(viewModel:)
              │
              ├── FlashcardReviewCard (front → reveal → back + grade buttons)
              ├── SnippetPlayer plays source audio segment
              └── On complete → dismiss sheet
```

## Data Flow

```
FlashcardDAO.allDueCards()
  → DailyReviewViewModel.dueCards
    → FlashcardReviewSession (progress + card display)
      → User taps card → viewModel.reveal()
        → SnippetPlayer.play(sourceURL, startTime, endTime)
          → onSnippetWillPlay → PlayerModel.prepareAudioForSnippet()
            → audioEngine.pause(), switch audio session
      → User taps grade → viewModel.gradeCard(grade)
        → FlashcardDAO.grade(cardID, grade)
          → SpacedRepetitionService.apply(grade, card) → SM-2 update
          → Persist updated card to SQLite
        → RealTimeEventDAO.insert(flashcardReviewed event)
        → viewModel.advance()
          → SnippetPlayer.stop()
          → onSnippetDidEnd → PlayerModel.resumeAudioForMainPlayer()
            → restore session, resume if was playing
  → All cards reviewed → dismiss sheet
    → UpcomingReviewsModuleView refreshes count (now 0 or lower)
```

## Files

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/ViewModels/DailyReviewViewModel.swift` |
| Create | `OrbitAudioBooks/Services/SnippetPlayer.swift` |
| Modify | `OrbitAudioBooks/Views/FlashcardReviewCard.swift` — grade labels, snippet indicator |
| Modify | `OrbitAudioBooks/Views/FlashcardReviewSession.swift` — ViewModel integration |
| Modify | `OrbitAudioBooks/Views/UpcomingReviewsModuleView.swift` — tappable |
| Modify | `OrbitAudioBooks/Views/DashboardShelf.swift` — pass binding |
| Modify | `OrbitAudioBooks/Views/TimelineTab.swift` — due-row |
| Modify | `OrbitAudioBooks/Views/RootTabView.swift` — review tab + sheet |
| Modify | `OrbitAudioBooks/ViewModels/PlayerModel.swift` — snippet callbacks |

## Verification

1. Build compiles
2. When due cards exist: dashboard card shows count and is tappable, launches review session
3. Review session shows front of first card, tap reveals back + grade buttons
4. Tapping a grade button advances to next card
5. Snippet plays source audio segment when card has valid media timestamps
6. Main player pauses during snippet, resumes after
7. Session dismisses on last grade or Done button
8. Due count refreshes after session (fewer cards remaining)
9. When no due cards: dashboard shows 0, timeline row hidden, tab hidden
10. Timeline shows `flashcardReviewed` events after grading sessions
