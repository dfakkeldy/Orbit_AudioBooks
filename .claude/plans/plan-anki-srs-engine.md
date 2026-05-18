# Plan ASRS: Spaced Repetition Engine & Data Model ✅ DONE (2026-05-18)

## Summary

Implement the core Spaced Repetition System (SRS) data model and the SM-2 algorithm. Create a new `Flashcard` model (or extend `Bookmark`) with SM-2 scheduling properties, and build a `SpacedRepetitionService` that computes interval, ease factor, and next review date from a user's grade.

## Current State

The app has a `Bookmark` model with `timestamp`, `title`, `trackId`, and `voiceMemoFileName` properties. There is no flashcard or SRS concept. Persistence is handled by `BookmarkStore` using `UserDefaults`-backed JSON encoding. The app uses AVFoundation (`AVAudioEngine` on iOS, `AVPlayer` on watch) for playback.

## Proposed Implementation

### 1. Flashcard Model

Create a new `Flashcard` model (or extend `Bookmark` if the flashcard concept is a superset of bookmark). Properties:

| Property | Type | Purpose |
|----------|------|---------|
| `frontText` | `String` | Front of card shown to user |
| `backText` | `String` | Back of card revealed on tap |
| `startTime` | `Double` | Start timestamp in the source media |
| `endTime` | `Double` | End timestamp in the source media |
| `targetMediaID` | `String` | Which media file this card belongs to |
| `triggerTiming` | `FlashcardTriggerTiming` | When to trigger: `.beginning`, `.end`, or `.manualOnly` |

SM-2 algorithm properties:

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `nextReviewDate` | `Date` | — | When the card is next due |
| `interval` | `Int` | 0 | Days until next review |
| `easeFactor` | `Double` | 2.5 | Spacing multiplier |
| `repetitions` | `Int` | 0 | Consecutive correct reviews |

### 2. FlashcardTriggerTiming Enum

```swift
enum FlashcardTriggerTiming: String, Codable {
    case beginning   // Trigger at startTime
    case end         // Trigger at endTime
    case manualOnly  // Only appear in daily review, never inline
}
```

### 3. SpacedRepetitionService

Implement the standard SM-2 algorithm:

| Grade | Label | Behavior |
|-------|-------|----------|
| 1 | Again | Reset interval to 0, reset repetitions to 0 |
| 2 | Hard | Increase interval by 1.2x, increment repetitions |
| 3 | Good | Increase interval by easeFactor, increment repetitions |
| 4 | Easy | Increase interval by easeFactor × 1.3, increment repetitions |

The service takes `(grade: Int, card: Flashcard)` and returns a new `Flashcard` with updated SM-2 properties and `nextReviewDate`.

### 4. Persistence

Ensure `Flashcard` is properly persisted. If extending `Bookmark`, add a migration path. If creating a standalone model, add a new `FlashcardStore` alongside `BookmarkStore` following the same `UserDefaults` + JSON pattern.

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/Models/Flashcard.swift` |
| Create | `OrbitAudioBooks/Services/SpacedRepetitionService.swift` |
| Create or Modify | `OrbitAudioBooks/Services/FlashcardStore.swift` |
| Modify | `OrbitAudioBooks/Services/BookmarkStore.swift` (if extending Bookmark) |

## Dependencies

- **Depends on:** Nothing. Self-contained data model + algorithm.
- **Blocked by:** Nothing.
- **Conflicts with:** Plan A1 (PlayerModel decomposition) — if A1 extracts `BookmarkStore`, the new `FlashcardStore` should follow the same extracted pattern. Coordinate on persistence layer location.

## Complexity

**Medium.** Pure logic with no UI. The SM-2 algorithm is ~30 lines. The model and store are ~100 lines following existing patterns.
