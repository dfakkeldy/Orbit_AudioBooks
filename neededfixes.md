# Orbit Audiobooks — Code Audit: Needed Fixes

**Date:** 2026-05-16 | **Branch:** `main`
**Updated:** 2026-05-18 — all 16 items resolved.

---

## Critical/High-Severity

### B1 — Per-book playback speed silently broken ✅ FIXED
**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift`  
**Category:** Data Integrity / Bug

### B2 — MPRemoteCommand handler tokens discarded ✅ FIXED
**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift`  
**Category:** API Misuse / Potential Crash

### B3 — NotificationCenter observer token leaked (TranscriptStore) ✅ FIXED
**File:** `Orbit Audiobooks macOS/Views/TranscriptStore.swift`  
**Category:** Resource Management / Bug

### B4 — Main thread blocked during transcription (macOS) ✅ FIXED
**File:** `Orbit Audiobooks macOS/Views/TranscriptionManager.swift`  
**Category:** Performance / Concurrency

### B5 — Force-unwrap on document directory (Bookmarks) ✅ FIXED
**File:** `OrbitAudioBooks/Views/Bookmarks.swift`  
**Category:** Potential Crash

### B6 — Production `print()` calls leak full file system paths ✅ FIXED
**Files:** `PlayerModel.swift`, `AudioEngine.swift`, `WatchSyncManager.swift`, `TranscriptStore.swift`, `TranscriptionManager.swift`  
**Category:** Privacy / Data Leakage

---

## Medium-Severity

### B7 — Skip forward/backward incorrectly scaled by playback speed ✅ FIXED
**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift`  
**Category:** Logic Error

### B8 — Speed 10.0 left in speed cycle ✅ FIXED
**File:** `OrbitAudioBooks/Views/BottomToolbarView.swift`  
**Category:** User-Facing Bug

### B9 — Bookmark loop mode: silent failure with <2 bookmarks ✅ FIXED
**Files:** `OrbitAudioBooks/ViewModels/PlayerModel.swift`  
**Category:** Logic Error / UX

### B10 — Watch bookmark row play button does nothing ✅ FIXED
**File:** `Orbit Audiobooks Watch App/Views/Bookmarks.swift`  
**Category:** Dead Feature

### B11 — Watch voice recorder doesn't check microphone permission ✅ FIXED
**File:** `Orbit Audiobooks Watch App/Views/ContentView.swift`  
**Category:** Error Handling Gap

### B12 — MPVolumeView hidden slider hack (App Review risk) ✅ FIXED
**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift` (now in `Services/AudioEngine.swift` + `PlaybackController.swift`)  
**Category:** Private API / App Review Risk

Hidden `MPVolumeView` at offscreen coordinates retrieves internal `UISlider` to set system volume.

**Fix:** Replaced with `setGain(_:)` / `fadeGain(to:duration:)` API on AudioEngine (Plan A6). Volume slider removed. Done 2026-05-15.

### B13 — Watch optimistic state updates inconsistent ✅ FIXED
**Files:** Watch `ContentView.swift`, `WatchViewModel.swift`, Widget `AppIntent.swift`  
**Category:** State Management

Watch toggles `isPlaying` optimistically before command confirmation, but not for other state.

**Fix:** Consistent optimistic updates with rollback across all watch controls. Done 2026-05-16.

### B14 — Widget WCSession delegate overrides iOS app's delegate ✅ FIXED
**File:** `Orbit Audiobooks Widget/Models/AppIntent.swift`  
**Category:** IPC Conflict

### B15 — SettingsManager App Group fallback silently breaks watch config ✅ FIXED
**File:** `OrbitAudioBooks/Services/SettingsManager.swift`  
**Category:** Data Integrity

### B16 — Bookmark voice memo/image file cleanup swallows errors in release
**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift` lines 2477-2490  
**Category:** Resource Management

Cleanup is now attempted (was `try?`), but failures are only logged in `#if DEBUG`. Release builds silently swallow failed file removals, leaving orphaned files.

**Fix:** Log failures in release via `os_log`. Consider orphaned file cleanup on app launch.

---

## Architecture Issues (for future refactoring)

### A1 — PlayerModel is a ~2600-line god class
**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift`

Conflates playback, bookmarks, voice memos, sleep timer, Watch connectivity, artwork caching, iCloud, Now Playing, security-scoped resources, chapters, transcripts, and persistence.

### A2 — Watch ContentView is a ~1744-line monolith
**File:** `Orbit Audiobooks Watch App/Views/ContentView.swift`

Contains AppGroupDefaults, enums, models, view model, voice recorder, and 10+ sub-views in one file.

### A3 — Significant code duplication across targets
- `formatTime`/`formatHMS`: 7 implementations
- `AppGroupDefaults` + `suiteName`: 3 copies
- `TranscriptionSegment`: 2 definitions
- AVPlayer setup: iOS and macOS both implement
- Watch layout enums: duplicate between iOS and watchOS

### A4 — Missing accessibility on key elements
- Scrubber Slider has no `accessibilityLabel` or `accessibilityValue`
- Album artwork has no accessibility labels
- Fixed font sizes in transport controls

### A5 — Concrete types injected via `@Environment` with no protocols
`PlayerModel`, `SettingsManager`, `StoreManager` are injected as concrete types, making unit testing impossible.

### A6 — `audioEngine.player` exposed as `private(set)`, breaking encapsulation
**File:** `OrbitAudioBooks/Services/AudioEngine.swift`

PlayerModel directly manipulates the AVPlayer instead of going through AudioEngine's API.

### A7 — Stringly-typed watch layout configuration
Watch layout stored as comma-separated strings parsed at runtime.

---

## 2026-05-19 — Post PR #12 Merge

### B17 — TimelineFeedViewModel: silent catch blocks swallow DB errors
**File:** `OrbitAudioBooks/ViewModels/TimelineFeedViewModel.swift`
**Category:** Error Handling / Observability

Four async methods (`loadNextPage`, `loadPreviousPage`, `reloadGranularity`, `loadInitialWindow`) use bare `catch {}` or `catch { items = [] }` — DB failures produce no diagnostic output and no user-visible feedback. If the feed goes blank the user sees whatever the empty state renders, with no clue that a query failed.

**Fix (23 lines, deferred 2026-05-19):**

1. Add `import os.log` and `private let logger = Logger(...)` to the class.
2. Add `private(set) var loadError: String?` published property.
3. Replace each silent catch with:
   - `logger.error("Failed to load ...: \(error.localizedDescription)")`
   - `loadError = error.localizedDescription` (for `loadInitialWindow` and `reloadGranularity` where items are fully replaced)
   - Clear `loadError = nil` on each successful load.
4. The feed view can bind `loadError` in its empty state to show a meaningful error instead of a generic "no content" message.

**Diff reference:** commit `aa63d1c` on deleted branch `fix/timeline-feed-vm-error-handling`.
