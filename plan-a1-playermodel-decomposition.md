# Plan A1: PlayerModel Decomposition

## Summary

Decompose the 2918-line `PlayerModel` god class into focused, testable components, each with a single responsibility. The refactored `PlayerModel` becomes a thin coordinator that owns and wires together the extracted components.

## Current State

**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift` — 2918 lines

Conflates: playback, bookmarks, voice memos, sleep timer, Watch connectivity, Now Playing, artwork caching, iCloud, security-scoped resources, chapters, transcripts, deep links, loop modes, and persistence.

All injected as a single `@Environment(PlayerModel.self)` concrete type.

## Target Architecture

```
OrbitAudioBooks/
├── ViewModels/
│   └── PlayerModel.swift              # Thin coordinator (~200 lines)
├── Services/
│   ├── AudioEngine.swift              # Already extracted
│   ├── PlaybackController.swift        # NEW: play, pause, skip, seek, speed, loop modes
│   ├── BookmarkStore.swift             # NEW: CRUD, voice memo recording, image cleanup
│   ├── SleepTimerManager.swift         # NEW: countdown, fade-out, pause-on-end
│   ├── NowPlayingController.swift      # NEW: MPNowPlayingInfoCenter, MPRemoteCommandCenter
│   ├── ChapterService.swift            # NEW: chapter parsing, chapter navigation
│   ├── ArtworkCache.swift              # NEW: artwork fetching and caching
│   ├── DeepLinkHandler.swift           # NEW: orbitaudio:// URL parsing (moved from PlayerDeepLink)
│   ├── Persistence.swift               # Extracted from private Persistence struct
│   ├── SettingsManager.swift           # Existing
│   ├── StoreManager.swift              # Existing
│   └── WatchSyncManager.swift          # Existing
```

### Component Responsibilities

**PlaybackController** (~400 lines)
- Play, pause, toggle
- Skip forward/backward (30s)
- Skip to next/previous chapter or track
- Seek to timestamp
- Speed adjustment
- Loop mode management (off, track, bookmark, playlist)
- AudioEngineDelegate conformance

**BookmarkStore** (~500 lines)
- CRUD operations on bookmarks
- Voice memo recording and playback
- Bookmark image capture and cleanup
- Bookmark Markdown export
- Orphaned file cleanup on launch
- Persistence to UserDefaults/disk
- `currentTrackBookmarks` filtering

**SleepTimerManager** (~200 lines)
- Timer countdown state
- Fade-out animation (via AudioEngine gain, not system volume)
- Pause-on-end option
- Timer duration presets
- `sleepTimerCountdownText` formatting

**NowPlayingController** (~200 lines)
- `MPNowPlayingInfoCenter` updates (title, artist, artwork, progress)
- `MPRemoteCommandCenter` handler registration and token retention
- Command routing to `PlaybackController`

**ChapterService** (~150 lines)
- Parse chapters from `AVAsset` metadata
- Chapter lookup by timestamp
- Chapter navigation (next, previous)
- Aggregate chapter list for folder-based audiobooks

**ArtworkCache** (~100 lines)
- Artwork fetching from embedded metadata
- Cover image scanning in audiobook directory
- In-memory cache with invalidation

**DeepLinkHandler** (~80 lines)
- Parse `orbitaudio://` URLs
- Handle `play`, `play?time=` actions
- Pending seek queue for pre-load deep links

**PlayerModel** (~200 lines)
- Owns all components as properties
- Initializes component graph
- Exposes `@Observable`-compatible computed properties for SwiftUI views
- Restores last selection on launch
- Folder/file URL management (security-scoped)
- Transcript integration pass-through

## Migration Strategy

Do NOT attempt a big-bang rewrite. Extract one component at a time, verify the build after each, and commit.

1. Extract `Persistence.swift` (lowest risk, already a private struct)
2. Extract `ChapterService.swift` (well-bounded, pure AVAsset parsing)
3. Extract `ArtworkCache.swift` (isolated concern)
4. Extract `DeepLinkHandler.swift` (small, no dependencies)
5. Extract `NowPlayingController.swift` (depends on PlaybackController — extract after step 6)
6. Extract `PlaybackController.swift` (core of the god class, largest extraction)
7. Extract `BookmarkStore.swift` (depends on PlaybackController for current time)
8. Extract `SleepTimerManager.swift` (depends on PlaybackController and AudioEngine)
9. Shrink `PlayerModel` to coordinator

At each step: build all targets, run unit tests, smoke test on simulator.

## Files to Modify/Create

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/Services/PlaybackController.swift` |
| Create | `OrbitAudioBooks/Services/BookmarkStore.swift` |
| Create | `OrbitAudioBooks/Services/SleepTimerManager.swift` |
| Create | `OrbitAudioBooks/Services/NowPlayingController.swift` |
| Create | `OrbitAudioBooks/Services/ChapterService.swift` |
| Create | `OrbitAudioBooks/Services/ArtworkCache.swift` |
| Create | `OrbitAudioBooks/Services/DeepLinkHandler.swift` |
| Create | `OrbitAudioBooks/Services/Persistence.swift` |
| Modify | `OrbitAudioBooks/ViewModels/PlayerModel.swift` |
| Modify | `OrbitAudioBooks/Orbit_AudioBooksApp.swift` (updated injection) |
| Modify | All views that reference `PlayerModel` directly (may need property pass-through) |

## Dependencies

- **Blocked by:** Plan A5 (protocol extraction) — extract protocols BEFORE decomposing so components communicate through protocols, not concrete references
- **Conflicts with:** 
  - Plan A6 (AudioEngine encapsulation) — coordinate so PlaybackController goes through AudioEngine's API
  - Plan Phase 2 (M4B folder audio) — ChapterService must support the aggregated chapter model
  - Plan Phase 3 (Dashboard UI) — Dashboard modules will bind to the extracted components
  - Plan Phase 4 (CarPlay) — CarPlay needs NowPlayingController and PlaybackController
  - Plan SQL Database — BookmarkStore would use SQL instead of UserDefaults

## Complexity

**Very Large.** This is the highest-risk refactoring in the project. Touches every iOS view and service. Must be done incrementally over multiple commits. Recommend doing A5 (protocols) first, then A1 component by component.
