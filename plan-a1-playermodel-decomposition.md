# Plan A1: PlayerModel Decomposition

## Summary

Decompose the 2918-line `PlayerModel` god class into focused, testable components, each with a single responsibility. The refactored `PlayerModel` becomes a thin coordinator that owns and wires together the extracted components.

## Current State

**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift` — 1494 lines (was 2918 at start, -1424, -49%)
**Progress:** Phase 1-8 complete. Phase 9a-e complete.

Phase 9e reduced PlayerModel from 1,762 to 1,494 lines (-268, -15.2% for 9e alone).

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

### Phase 9b: Shared State Object (Pattern 3) — ✅ COMPLETE

**Goal:** Eliminate ~150 lines of stored properties and pass-throughs from PlayerModel.
**Result:** Created `OrbitAudioBooks/State/PlaybackState.swift` (52 lines). 22 properties moved from PlayerModel stored properties into `@Observable PlaybackState`. PlayerModel accesses them via `private var state: PlaybackState { playbackController.state }` with public-facing computed pass-throughs for API compatibility. PlaybackController holds `let state = PlaybackState()` enabling direct access for Phase 9c method migration. Net line reduction: ~20 lines (most savings deferred to 9c).

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

### Phase 9c: Move Methods via Closures (Pattern 1) — ✅ COMPLETE

**Result:** 23 playback control methods migrated from PlayerModel to PlaybackController
in 4 tiers, using 15 coordinator closures. PlayerModel: 2,286 → 1,867 (-419 lines).
PlaybackController: 155 → 594 (+439 lines).

**Tier 1 — Speed, Loop, Volume Boost:**
- Moved: `setSpeed`, `setLoopMode`, `cycleLoopMode`
- New coordinators: `persistSpeed`, `persistLoopMode`, `hasBookmarks`

**Tier 2 — Navigation:**
- Moved: `nextTrack`, `previousTrackOrRestart`, `nextChapter`, `previousChapterOrRestart`, `seekToChapter`, `resumeAfterSeek`, `currentChapterForTime`
- New coordinators: `refreshProgress`

**Tier 3 — Skip, Seek, Bookmark Jump:**
- Moved: `skipBackward30`, `skipForward30`, `skipBackwardNavigation`, `skipForwardNavigation`, `seek(toSeconds:)`, `seek(toFraction:)`, `jumpToNextBookmark`, `jumpToPreviousBookmark`
- New coordinators: `enabledBookmarks`, `jumpToBookmark`, `refreshArtwork`

**Tier 4 — Core Playback + Loop Enforcement:**
- Moved: `pause`, `stop`, `play`, `togglePlayPause`, `applyChapterLoopIfNeeded`, `applyBookmarkLoopIfNeeded`
- New coordinators: `endBackgroundTask`, `saveProgress`, `stopSecurityScope`, `handleChapterEndSleepTimer`, `currentTrackBookmarks`, `isRewindEnabled`, `configureAudioSession`, `startSecurityScope`

**Full coordinator closure interface (15 total):**
```
// Phase 9a (6): smartRewind, jumpToChapterStartForHours, loadTrack,
//               persistAndSync, checkVoiceMemo, seekCompleted
// Tier 1 (3): persistSpeed, persistLoopMode, hasBookmarks
// Tier 2 (1): refreshProgress
// Tier 3 (3): enabledBookmarks, jumpToBookmark, refreshArtwork
// Tier 4 (8): endBackgroundTask, saveProgress, stopSecurityScope,
//             handleChapterEndSleepTimer, currentTrackBookmarks,
//             isRewindEnabled, configureAudioSession, startSecurityScope
```

**Impact:** ~500 lines moved from PlayerModel to PlaybackController. PlayerModel: 1,867.

### Phase 9d: Extract PlaylistManager — ✅ COMPLETE

**Result:** Created `OrbitAudioBooks/Services/PlaylistManager.swift` (147 lines). Used direct injection of `PlaybackState` and `Persistence` instead of coordinator closures — a cleaner pattern for data-access services. One coordinator for post-reset chapter refresh.

Moved: `loadTracks`, `moveTracks`, `moveChapters`, `toggleTrackEnabled`, `toggleChapterEnabled`, `resetPlaylist`.

Kept in PlayerModel (too many cross-cutting dependencies): `loadFolder`, `restoreLastSelectionIfPossible`, `persistSelection`.

PlayerModel: 1,867 → 1,762 (-105).

### Phase 9e: Shrink PlayerModel to Coordinator (Final) — ✅ COMPLETE

**Result:** PlayerModel reduced from 1,762 to 1,494 lines (-268, -15.2%). Six focused extractions:

1. **Bookmark CRUD dedup**: Removed duplicate logic from PlayerModel — methods now delegate directly to BookmarkStore's existing CRUD. Added `onDeleteFile`, `onBookmarksChanged`, and `storageKeyProvider` closures to BookmarkStore for file cleanup, artwork refresh, and loop mode management. Removed `persistBookmarks()` (inlined into `onPersist`). PlayerModel bookmark methods became thin context-gathering wrappers (~78 lines saved).

2. **TranscriptService** (new file): Extracted `loadTranscript(for:)` and `computeWordClouds()` into a dedicated `TranscriptService` using direct `PlaybackState` injection (same pattern as PlaylistManager). (~39 lines saved).

3. **SecurityScopeManager** (new file): Extracted all security-scoped resource management (start/stop selection, start/stop current file) into a dedicated service. Replaced 6 methods and 4 stored properties with clean delegation. (~23 lines saved).

4. **ArtworkCache thumbnail generation**: Added `generateThumbnails(from:displayScale:)` static method to ArtworkCache, consolidating display + watch thumbnail rendering. PlayerModel's `generateThumbnail(for:)` now delegates the image processing. (~20 lines saved).

5. **PlaybackController.enforceEnabledState**: Moved chapter/track enabled-state enforcement to PlaybackController, using existing `ChapterService.nextEnabledIndex` directly. Removed dead helpers `findNextEnabledTrackIndex()` and `findNextEnabledChapterIndex()`. (~27 lines saved).

6. **PlaybackController.handleTrackEnded**: Moved end-of-track handling to PlaybackController using existing coordinator closures (`coordinator_handleChapterEndSleepTimer`, `coordinator_persistAndSync`, `coordinator_refreshProgress`). Removed `applySpeedToCurrentItem()` and `evaluateSleepTimerAtChapterEnd()` wrappers, inlined `applyChapterLoopIfNeeded`/`applyBookmarkLoopIfNeeded`/`resumeAfterSeek`/`seekToChapter` delegate calls. (~81 lines saved).

**New files created:**
- `OrbitAudioBooks/Services/TranscriptService.swift`
- `OrbitAudioBooks/Services/SecurityScopeManager.swift`

**Files modified:**
- `PlayerModel.swift`: 1,762 → 1,494 (-268)
- `BookmarkStore.swift`: Added `onDeleteFile`, `onBookmarksChanged`, `storageKeyProvider` closures; updated `deleteBookmark` for file cleanup
- `ArtworkCache.swift`: Added `generateThumbnails(from:displayScale:)` static method
- `PlaybackController.swift`: Added `enforceEnabledState()`, `handleTrackEnded()`

Target: ~400-500 lines (thin coordinator owning service references + init wiring)

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
| Create | `OrbitAudioBooks/State/PlaybackState.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/PlaylistManager.swift` | ✅ |
| Create | `OrbitAudioBooks/Services/TranscriptService.swift` | ✅ (Phase 9e) |
| Create | `OrbitAudioBooks/Services/SecurityScopeManager.swift` | ✅ (Phase 9e) |
| Modify | `OrbitAudioBooks/ViewModels/PlayerModel.swift` | ✅ (1494 lines) |
| Modify | `OrbitAudioBooks/Orbit_AudioBooksApp.swift` | ✅ |
| Modify | `OrbitAudioBooks/Services/BookmarkStore.swift` | ✅ (Phase 9e) |
| Modify | `OrbitAudioBooks/Services/PlaybackController.swift` | ✅ (Phase 9e) |
| Modify | `OrbitAudioBooks/Services/ArtworkCache.swift` | ✅ (Phase 9e) |

## Dependencies

- **Blocked by:** Plan A5 (protocol extraction) ✅, Plan A6 (AudioEngine encapsulation) ✅
- **Conflicts with:** 
  - Plan M4B (folder audio) — ChapterService must support aggregated chapters
  - Plan DASH (Dashboard UI) — Dashboard modules bind to extracted components
  - Plan CAR (CarPlay) — CarPlay needs NowPlayingController and PlaybackController
  - Plan SQL Database — BookmarkStore would use SQL instead of UserDefaults

## Complexity

**Very Large.** The highest-risk refactoring in the project. Incremental, component-by-component approach validated — each phase builds and passes tests before the next.
