# Plan A3: Cross-Target Code Deduplication

## Summary

Eliminate duplicated code across iOS, macOS, watchOS, and Widget targets by creating a shared utility module or SPM package for common types and functions.

## Current Duplications

| Item | Locations | Lines |
|------|-----------|-------|
| `formatTime` / `formatHMS` / `formatTimestamp` / `formatDuration` | `PlayerModel.swift:1727`, `Bookmarks.swift:785`, `PlaylistView.swift:42,52`, `Watch Bookmarks.swift:102`, `MacContentView.swift:324`, `TranscriptionManager.swift:397` | 7 implementations, ~5-10 lines each |
| `AppGroupDefaults` + `suiteName` | `Watch ContentView.swift:8-23`, `Widget AppIntent.swift:4-16`, `SettingsManager.swift` | 3 copies, ~15 lines each |
| `TranscriptionSegment` | iOS (`OrbitAudioBooks/Models/TranscriptionSegment.swift`), macOS (inline or separate) | 2 definitions |
| `WordFrequency` | iOS (`OrbitAudioBooks/Models/WordFrequency.swift`), `Watch ContentView.swift:149` | 2 definitions |
| AVPlayer setup code | `PlayerModel.swift` (via AudioEngine), `MacPlayerModel.swift` | Similar patterns |
| `WatchAction` / layout enums | Watch `ContentView.swift`, iOS `WatchAppSettingsView.swift` | 2 copies |

## Approach

### Option A (Recommended): Shared SPM Package

Create a `OrbitShared` SPM package containing:
- `TimeFormatting.swift` — single `formatHMS(_:)` implementation
- `AppGroupDefaults.swift` — single shared implementation
- Shared models: `TranscriptionSegment`, `WordFrequency`, `WatchAction`, `WatchSlotConfiguration`
- Shared constants: suite name, URL scheme

All four targets depend on `OrbitShared`.

### Option B: Shared File Folder

Add a `Shared/` folder referenced by all targets. Simpler than SPM but less clean for dependency management.

## Migration Strategy

1. Create `OrbitShared` package with `TimeFormatting.swift` and `AppGroupDefaults.swift`
2. Add package dependency to all four targets
3. Replace iOS impls, verify build
4. Replace macOS impls, verify build
5. Replace watchOS impls, verify build
6. Replace Widget impls, verify build
7. Add shared models one at a time

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `Shared/OrbitShared/Package.swift` |
| Create | `Shared/OrbitShared/Sources/OrbitShared/TimeFormatting.swift` |
| Create | `Shared/OrbitShared/Sources/OrbitShared/AppGroupDefaults.swift` |
| Create | `Shared/OrbitShared/Sources/OrbitShared/Models/TranscriptionSegment.swift` |
| Create | `Shared/OrbitShared/Sources/OrbitShared/Models/WordFrequency.swift` |
| Create | `Shared/OrbitShared/Sources/OrbitShared/Models/WatchAction.swift` |
| Create | `Shared/OrbitShared/Sources/OrbitShared/Models/WatchSlotConfiguration.swift` |
| Modify | `Orbit Audiobooks.xcodeproj/project.pbxproj` (add package dependency) |
| Modify | All files with duplicated implementations (replace with `import OrbitShared`) |

## Dependencies

- **Blocked by:** A2 (Watch decomposition) — extract Watch types to files first, THEN deduplicate across targets
- **Conflicts with:** Plan Phase 2 (M4B folders) — if shared models change, both plans need to agree on the shared model shape; coordinate the `Chapter` model between them

## Complexity

**Medium.** SPM setup is straightforward but touches every target. Regression risk is low since we're replacing implementations with identical behavior.
