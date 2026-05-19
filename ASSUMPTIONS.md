# ASSUMPTIONS.md — Phase 3: Twitter Feed Timeline UI (Resumed)

## Context
Phase 1 (schema V4) and Phase 2 (ingestion factory) are complete and committed to main.
Agent 6147 (feature/twitter-feed-6147) completed an initial implementation of Phase 3.
This worktree (feature/twitter-feed-9530) resumes and completes Phase 3, building on the
6147 implementation with fixes and refinements.

## Resume Point
Ported the following from feature/twitter-feed-6147 (commit 8a5c5e7):
- Shared/MediaPlayable.swift
- OrbitAudioBooks/ViewModels/TimelineFeedViewModel.swift
- OrbitAudioBooks/Views/TimelineFeedView.swift
- OrbitAudioBooks/Views/Components/TimeGapCell.swift
- OrbitAudioBooks/Views/Components/TimelineTweetCell.swift
- OrbitAudioBooks/Views/TimelineTab.swift (modified to use TimelineFeedView)

The TimelineItem model and TimelineDAO already exist in main (from Phase 1/2).

## Assumptions Made During Implementation

### 1. MediaPlayable Protocol
Created as a minimal protocol with `audioStartTime`, `audioEndTime?`, and `title` so
TimelineItem can conform. This allows future video types to share the same feed infrastructure.

### 2. Playback Tracking State Machine
Implemented as `@Observable` class `TimelineFeedViewModel` with three states:
- `following` — auto-scroll follows playback position
- `paused` — user manually scrolled away, holds position
- `jumping` — "Go to Right Now" transition in progress
Transition back to `following` after 5 seconds of inactivity or when user taps "Go to Right Now".

### 3. Time-Windowed Pagination
ViewModel holds a rolling window of ~200 items (±5 minutes around current position).
Pages load in chunks of 50 items. Older chunks are evicted from the in-memory array.

### 4. ScrollView Architecture
Using `ScrollView { LazyVStack }` with `scrollPosition(id:)` (iOS 17+) rather than
`ScrollViewReader` + `proxy.scrollTo()`.

### 5. Integration Pattern
TimelineTab replaces `PlaylistTimelineView(timeScale: timeScale)` with `TimelineFeedView()`.
The feed view reads PlayerModel from the environment and passes it to the ViewModel.

### 6. No pbxproj modifications needed
All new files are in existing Xcode groups that use folder references or are auto-discovered.
If compilation fails due to missing file references, the pbxproj will need updating.

### 7. VoiceOver Auto-Scroll Suppression
`isFollowingPlayback` is set to `false` when VoiceOver is active. The user navigates
the feed manually via swipe when VoiceOver is active.

### 8. Watch Connectivity
The watch app continues to use sparse-only mode (existing behavior). No watch-side
changes in this phase.
