# Plan B16: Bookmark Cleanup Error Logging in Release

## Summary

Ensure voice memo and bookmark image file cleanup errors are logged in release builds, and add orphaned-file cleanup on app launch.

## Current State

**File:** `OrbitAudioBooks/ViewModels/PlayerModel.swift` lines 2477-2490

```swift
do {
    try FileManager.default.removeItem(at: url)
} catch {
#if DEBUG
    print("Failed to remove voice memo at \(url.path): \(error)")
#endif
}
```

The cleanup is now attempted (previously `try?`), but failures in release builds are silently swallowed. Over time, orphaned voice memo and bookmark image files accumulate in the user's Documents directory with no visibility.

## Proposed Fix

1. Replace `#if DEBUG print(...)` with `os_log` using `.error` level so failures are visible in Console.app in release builds. Redact the file path with `.private` for privacy:

```swift
import os.log
// ...
} catch {
    os_log(.error, "Failed to remove voice memo: %{private}@", error.localizedDescription)
}
```

2. Add a startup cleanup pass in `PlayerModel.init()` (or on first folder load) that scans the bookmark sidecar directory for orphaned `.m4a` and `.png` files — files not referenced by any current bookmark — and removes them. Gate this on `#if DEBUG` or make it a one-time migration so it doesn't run on every launch.

## Files to Modify

| File | Change |
|------|--------|
| `OrbitAudioBooks/ViewModels/PlayerModel.swift` | Replace `#if DEBUG print` with `os_log`; add orphan cleanup method |

## Dependencies

- **Depends on:** Nothing
- **Blocked by:** Nothing
- **Conflicts with:** Plan A1 (PlayerModel decomposition) — minor coordination. If A1 extracts a `BookmarkStore` or `FileManager` utility, the logging and orphan cleanup should live there. Do B16 first or fold it into A1's bookmark extraction step.

## Complexity

**Small.** ~20 lines changed for logging, ~30 lines for orphan cleanup.
