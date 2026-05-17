# Plan A1: PlayerModel Decomposition

## Summary

Decompose the 2918-line `PlayerModel` god class into focused, testable components, each with a single responsibility. The refactored `PlayerModel` becomes a thin coordinator that owns and wires together the extracted components.

## Current State

**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift` — 2306 lines (was 2918 at start)
**Progress:** Phase 1-8 complete (services created). Phase 9 in progress (removing duplication, extracting coordination).

Conflates: playback, bookmarks, voice memos, sleep timer, Watch connectivity, Now Playing, artwork caching, iCloud, security-scoped resources, chapters, transcripts, deep links, loop modes, and persistence.

All injected as a single `@Environment(PlayerModel.self)` concrete type.

## Target Architecture

```
OrbitAudioBooks/
├── ViewModels/
│   └── PlayerModel.swift              # Thin coordinator (~400-500 lines)
├── State/
│   └── PlaybackState.swift            # NEW: shared mutable state (tracks, chapters, progress)
├── Services/
│   ├── AudioEngine.swift              # Already extracted
│   ├── PlaybackController.swift        # State + playback logic + delegate callbacks
│   ├── BookmarkStore.swift             # CRUD, voice memo recording, image cleanup
│   ├── SleepTimerManager.swift         # Countdown, fade-out, pause-on-end
│   ├── NowPlayingController.swift      # MPNowPlayingInfoCenter, MPRemoteCommandCenter
│   ├── ChapterService.swift            # Chapter parsing, chapter navigation
│   ├── ArtworkCache.swift              # Artwork fetching, caching, iCloud, thumbnails
│   ├── DeepLinkHandler.swift           # orbitaudio:// URL parsing
│   ├── Persistence.swift               # UserDefaults/disk persistence
│   ├── SettingsManager.swift           # Existing
│   ├── StoreManager.swift              # Existing
│   └── WatchSyncManager.swift          # Existing
```

## Migration Strategy

Do NOT attempt a big-bang rewrite. Extract one component at a time, verify the build after each, and commit.

### Phase 1-8: Service Extraction ✅ COMPLETE

1. ✅ Extract `Persistence.swift` (lowest risk, already a private struct)
2. ✅ Extract `ChapterService.swift` (well-bounded, pure AVAsset parsing)
3. ✅ Extract `ArtworkCache.swift` (isolated concern)
4. ✅ Extract `DeepLinkHandler.swift` (small, no dependencies)
5. ✅ Extract `NowPlayingController.swift` (depends on PlaybackController — extracted after step 6)
6. ✅ Extract `PlaybackController.swift` (core of the god class, largest extraction)
7. ✅ Extract `BookmarkStore.swift` (depends on PlaybackController for current time)
8. ✅ Extract `SleepTimerManager.swift` (depends on PlaybackController and AudioEngine)

### Phase 9a: Remove Duplication ✅ COMPLETE

- ✅ Voice memo dedup — remove duplicate engine, playback, trigger logic from PlayerModel. BookmarkStore is now the single owner of voice memo playback state.
- ✅ Bookmark data consolidation — `model.bookmarks` is a pass-through to `bookmarkStore.bookmarks`. Single source of truth.
- ✅ iCloud/file helpers → ArtworkCache — `ensureItemIsAvailable`, `loadImageFile`, `folderArtworkImage` moved to ArtworkCache as static methods. Thin wrappers removed.
- ✅ PlaybackController expansion — coordinator closure pattern established (`coordinator_smartRewind`, `coordinator_persistAndSync`, etc.), computation helpers moved.

### Phase 9b: Shared State Object (Pattern 3) — NEXT

**Goal:** Eliminate ~150 lines of stored properties and pass-throughs from PlayerModel.

Create `OrbitAudioBooks/State/PlaybackState.swift`:

```swift
@Observable
final class PlaybackState {
    // Playlist
    var folderURL: URL? = nil
    var tracks: [Track] = []
    var currentIndex: Int = 0

    // Playback
    var isPlaying: Bool = false
    var currentTitle: String = String(localized: "No track selected")
    var currentSubtitle: String = ""

    // Progress
    var progressFraction: Double = 0.0
    var progressText: String = "--:--"
    var elapsedText: String = "--:--"
    var durationSeconds: Double? = nil

    // Chapters
    var chapters: [Chapter] = []
    var currentChapterIndex: Int? = nil

    // Flags
    var isManualSeeking: Bool = false
    var isSeekingForChapterBoundary: Bool = false
    var pauseTimestamp: Date? = nil

    // Artwork
    var thumbnailImage: UIImage? = nil
    var currentDisplayArtwork: UIImage? = nil
    var currentDisplayArtworkVersion: Int = 0
    var watchThumbnailData: Data? = nil

    // Transcript
    var transcription: [TranscriptionSegment] = []
    var chapterWordClouds: [Int: [WordFrequency]] = [:]
    var rollingWordClouds: [(startTime: TimeInterval, frequencies: [WordFrequency])] = []
}
```

**Steps:**
1. Create `OrbitAudioBooks/State/PlaybackState.swift`
2. Add `let state = PlaybackState()` to both PlayerModel and PlaybackController
3. Replace PlayerModel's stored properties with `state.xxx` references
4. Replace PlaybackController's pass-throughs with `state.xxx` references
5. Build and verify

**Impact:** ~150 lines removed from PlayerModel. PlaybackController gets direct access to tracks/chapters for navigation without a massive delegate protocol.

### Phase 9c: Move Methods via Closures (Pattern 1) — AFTER 9b

**Goal:** Move ~500 lines of playback control methods from PlayerModel to PlaybackController.

**Prerequisites:** Phase 9b (shared state object) must be complete. PlaybackController must have access to `PlaybackState` and coordinator closures.

**Methods to move:**

| Method | Lines | Dependencies |
|--------|-------|-------------|
| `play()` | ~65 | state, coordinator_smartRewind, coordinator_loadTrack, coordinator_checkVoiceMemo, coordinator_persistAndSync |
| `pause()` | ~20 | state, coordinator_persistAndSync |
| `togglePlayPause()` | 2 | state |
| `nextTrack()` | ~15 | state, coordinator_loadTrack |
| `previousTrackOrRestart()` | ~25 | state, coordinator_loadTrack |
| `nextChapter()` | ~20 | state, coordinator_loadTrack, ChapterService |
| `previousChapterOrRestart()` | ~25 | state, ChapterService |
| `skipBackward30()` | ~25 | state |
| `skipForward30()` | ~25 | state |
| `skipBackwardNavigation()` | ~15 | state |
| `skipForwardNavigation()` | ~15 | state |
| `seek(toSeconds:)` | ~20 | state |
| `seek(toFraction:)` | ~20 | state |
| `setSpeed(_:)` | ~12 | state, coordinator_persistAndSync, Persistence |
| `setVolumeBoost(enabled:)` | 2 | state |
| `setLoopMode(_:)` | ~8 | state, Persistence |
| `cycleLoopMode()` | ~10 | state, BookmarkStore |
| `jumpToNextBookmark()` | ~6 | state, BookmarkStore |
| `jumpToPreviousBookmark()` | ~6 | state, BookmarkStore |
| `smartRewindAmount(for:)` | ~35 | SettingsManager |
| `shouldJumpToChapterStartForHoursLevel(pausedDuration:)` | ~5 | SettingsManager |
| `applyChapterLoopIfNeeded()` | ~50 | state |
| `applyBookmarkLoopIfNeeded()` | ~35 | state, BookmarkStore |
| `stop()` | ~14 | state |

**New coordinator closures needed:**

```swift
// Already wired (Phase 9a):
coordinator_smartRewind         // smart rewind computation
coordinator_jumpToChapterStart  // chapter-start-on-resume decision
coordinator_loadTrack           // prepareToPlay(index:autoplay:)
coordinator_persistAndSync      // updateNowPlaying + syncToWatch
coordinator_checkVoiceMemo      // bookmarkStore.checkVoiceMemoTrigger
coordinator_seekCompleted       // updateCurrentChapterFromPlayerTime

// Additional needed for Phase 9c:
coordinator_persistSpeed        // persistence.saveSpeed(for:speed:)
coordinator_persistLoopMode     // persistence.saveLoopMode(for:loopMode:)
coordinator_persistProgress     // persistence.saveBookProgress(...)
coordinator_persistOrder        // persistence.saveOrder(for:ids:)
```

**Impact:** ~500 lines moved from PlayerModel to PlaybackController. PlayerModel drops to ~1,700 lines.

### Phase 9d: Extract Folder/Loading to PlaylistManager (Future)

After 9c, the remaining big block is folder/track loading and security-scoped resource management (~200 lines). This can move to a new `PlaylistManager` service using the same closure pattern.

### Phase 9e: Shrink PlayerModel to Coordinator (Final)

After 9a-9d:
- PlayerModel: ~400-500 lines
- Owns: service references, init() wiring, pass-through computed properties
- Remaining: watch message dispatch (~100 lines), transcript/wordcloud coordination (~50 lines), Persistence wiring, a few coordination methods that don't fit elsewhere

## Files to Modify/Create

| Action | File | Status |
|--------|------|--------|
| Create | `OrbitAudioBooks/Services/PlaybackController.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/BookmarkStore.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/SleepTimerManager.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/NowPlayingController.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/ChapterService.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/ArtworkCache.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/DeepLinkHandler.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/Persistence.swift` | ✅ |
| Create | `OrbitAudioBooks/State/PlaybackState.swift` | ⏳ Next |
| Modify | `OrbitAudioBooks/ViewModels/PlayerModel.swift` | 🔄 |
| Modify | `OrbitAudioBooks/Orbit_AudioBooksApp.swift` | ✅ |

## Dependencies

- **Blocked by:** Plan A5 (protocol extraction) ✅, Plan A6 (AudioEngine encapsulation) ✅
- **Conflicts with:** 
  - Plan M4B (folder audio) — ChapterService must support aggregated chapters
  - Plan DASH (Dashboard UI) — Dashboard modules bind to extracted components
  - Plan CAR (CarPlay) — CarPlay needs NowPlayingController and PlaybackController
  - Plan SQL Database — BookmarkStore would use SQL instead of UserDefaults

## Complexity

**Very Large.** The highest-risk refactoring in the project. Incremental, component-by-component approach validated — each phase builds and passes tests before the next.
