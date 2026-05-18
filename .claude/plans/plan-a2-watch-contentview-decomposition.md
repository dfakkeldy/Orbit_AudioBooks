# Plan A2: Watch ContentView Decomposition

## Summary

Decompose the 1827-line `Watch ContentView.swift` monolith into separate files for model types, the view model, views, and the voice recorder, following the same pattern as the iOS target.

## Current State

**File:** `Orbit Audiobooks Watch App/Views/ContentView.swift` — 1827 lines

Contains in one file:
- `AppGroupDefaults` enum (lines 8-23)
- `WatchAction` enum (lines 56-97)
- `WatchSlotConfiguration` enum (lines 101-118)
- `WatchBookmark` struct (lines 121-146)
- `WatchWordFrequency` struct (lines 149-155)
- `WatchViewModel` class with `WCSessionDelegate` (lines 158-679)
- `WatchBookmarkError` enum (lines 681-698)
- `WatchVoiceMemoRecorder` class (lines 701-796)
- `ToggleTraitModifier` ViewModifier (lines 799-814)
- `ContentView` struct (lines 816-950)
- `WatchArtworkLayout` enum (lines 952-955)
- `WatchBackgroundStyle` enum (lines 957-961)
- `WatchControlBackground` view (lines 962-983)
- `WordCloudPage` view (lines 986-1040)
- `PlayerPage` view (lines 1043-1827)

## Target Structure

```
Orbit Audiobooks Watch App/
├── Models/
│   ├── WatchBookmark.swift
│   ├── WatchWordFrequency.swift
│   ├── WatchAction.swift
│   └── WatchSlotConfiguration.swift
├── Services/
│   ├── WatchViewModel.swift
│   ├── WatchVoiceMemoRecorder.swift
│   └── AppGroupDefaults.swift (shared, deduplicated per A3)
├── Views/
│   ├── ContentView.swift          # Top-level tab/container (~100 lines)
│   ├── PlayerPage.swift           # Main playback UI (~600 lines)
│   ├── WordCloudPage.swift        # Word cloud display (~60 lines)
│   ├── Bookmarks.swift            # Already exists (112 lines)
│   ├── WatchControlBackground.swift
│   └── Components/
│       └── ToggleTraitModifier.swift
```

## Migration Strategy

1. Extract model types to `Models/` directory (zero-risk, pure data)
2. Extract `WatchViewModel` to `Services/` (core logic)
3. Extract `WatchVoiceMemoRecorder` to `Services/`
4. Extract `PlayerPage` to its own file (largest single piece)
5. Extract remaining views
6. Slim `ContentView` to tab/container only

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `Orbit Audiobooks Watch App/Models/WatchBookmark.swift` |
| Create | `Orbit Audiobooks Watch App/Models/WatchWordFrequency.swift` |
| Create | `Orbit Audiobooks Watch App/Models/WatchAction.swift` |
| Create | `Orbit Audiobooks Watch App/Models/WatchSlotConfiguration.swift` |
| Create | `Orbit Audiobooks Watch App/Services/WatchViewModel.swift` |
| Create | `Orbit Audiobooks Watch App/Services/WatchVoiceMemoRecorder.swift` |
| Create | `Orbit Audiobooks Watch App/Views/PlayerPage.swift` |
| Create | `Orbit Audiobooks Watch App/Views/WordCloudPage.swift` |
| Create | `Orbit Audiobooks Watch App/Views/WatchControlBackground.swift` |
| Create | `Orbit Audiobooks Watch App/Views/Components/ToggleTraitModifier.swift` |
| Modify | `Orbit Audiobooks Watch App/Views/ContentView.swift` (slim to ~100 lines) |

## Dependencies

- **Blocked by:** Plan B13 (watch state consistency) — fix the state management bug FIRST, then decompose the corrected code
- **Conflicts with:** Plan A3 (deduplication) — A3 will deduplicate `AppGroupDefaults` and `WatchBookmark`/`Bookmark` types across targets; do A2 first (just move, don't change) then A3 (deduplicate across targets)

## Complexity

**Medium.** Pure refactoring with no behavior change. Each extraction is mechanical. Build verification after each step catches issues immediately.
