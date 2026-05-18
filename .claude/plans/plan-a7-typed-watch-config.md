# Plan A7: Typed Watch Configuration

## Summary

Replace the stringly-typed watch layout configuration with proper Swift enums and `Codable` serialization.

## Current State

**File:** `Orbit Audiobooks Watch App/Views/ContentView.swift` lines 101-118

Watch layout is stored as comma-separated strings parsed at runtime:

```swift
enum WatchSlotConfiguration {
    // Uses comma-separated string parsing
}
```

And in `SettingsManager.swift`, the layout is persisted as a raw string to UserDefaults. This is fragile — typos are runtime errors, not compile-time errors.

## Proposed Fix

1. Define `WatchSlotConfiguration` as a proper `Codable` enum (already partially done but parsed from strings)
2. Store as JSON-encoded data in UserDefaults instead of raw strings
3. Add a migration step to convert existing string-format layouts to the new JSON format
4. Remove string parsing code

### Current format (example):
```
"playPause,skipBack,skipForward,scrub,volume,loop,sleep,bookmark"
```

### New format:
```swift
enum WatchAction: String, Codable, CaseIterable {
    case playPause, skipBack, skipForward, scrub, volume, loop, sleep, bookmark
}

struct WatchLayout: Codable {
    var actions: [WatchAction]
    var artworkLayout: WatchArtworkLayout
    var backgroundStyle: WatchBackgroundStyle
}
```

Stored as JSON in UserDefaults under a new key, with migration from the old string format on first read.

## Files to Modify

| File | Change |
|------|--------|
| `Orbit Audiobooks Watch App/Views/ContentView.swift` | Replace string parsing with JSON decoding |
| `OrbitAudioBooks/Services/SettingsManager.swift` | Update storage format and add migration |
| `OrbitAudioBooks/Views/WatchAppSettingsView.swift` | Update picker to use typed enum |

## Dependencies

- **Depends on:** Plan A3 (deduplication) — after A3, `WatchSlotConfiguration` lives in the shared package so both iOS and watchOS use the same definition
- **Conflicts with:** Plan A2 (Watch decomposition) — coordinate so A2 extracts the file first, then A7 changes the storage format. Minor.

## Complexity

**Small.** ~30-40 lines changed. Straightforward migration with a one-time conversion from old string format.
