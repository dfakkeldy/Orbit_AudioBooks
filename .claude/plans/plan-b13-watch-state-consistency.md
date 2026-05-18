# Plan B13: Watch State Consistency ✅ DONE (2026-05-16)

## Summary

Fix the watchOS app's inconsistent optimistic state updates by applying a uniform pattern: either always wait for iPhone confirmation with rollback, or always apply optimistic updates uniformly across all state properties.

## Current State

**File:** `Orbit Audiobooks Watch App/Views/ContentView.swift` lines 540-541

```swift
if sendCommand(isPlaying ? "pause" : "play") {
    isPlaying.toggle()
}
```

`isPlaying` is toggled optimistically when `sendCommand` returns `true` (message was sent). But other state properties — `currentTime`, `chapterTitle`, `trackTitle`, `speed`, `loopMode`, `sleepTimer` — are only updated when the iPhone sends back a state reply. This inconsistency means:

- Play/pause feels responsive (optimistic)
- Other controls feel laggy (waiting for reply)
- If the play/pause command fails silently after being "sent", the UI is out of sync with reality

## Proposed Fix

**Option A (Recommended): Consistent optimistic updates with rollback**

Apply optimistic updates to all mutating state properties in `sendCommand`, then roll back if the reply indicates failure or times out:

1. Before sending, snapshot current state.
2. Apply the optimistic mutation immediately.
3. If the reply indicates the command wasn't applied, or if no reply arrives within 3 seconds, restore the snapshot.

This makes ALL controls feel responsive, not just play/pause.

**Option B: No optimistic updates, wait for reply**

Remove the optimistic `isPlaying.toggle()` and instead only update `isPlaying` in the reply handler alongside all other state. This is simpler but makes play/pause feel laggy.

## Files to Modify

| File | Change |
|------|--------|
| `Orbit Audiobooks Watch App/Views/ContentView.swift` | Refactor `sendCommand` to apply optimistic updates uniformly with rollback timeout |

## Dependencies

- **Depends on:** Nothing
- **Blocked by:** Nothing
- **Conflicts with:** Plan A2 (Watch ContentView decomposition) — B13 should be done FIRST since it's a focused bug fix, then A2 can decompose the already-corrected state management into separate files

## Complexity

**Small.** ~30-50 lines changed in one file. Add a timeout timer and a snapshot/rollback pattern.
