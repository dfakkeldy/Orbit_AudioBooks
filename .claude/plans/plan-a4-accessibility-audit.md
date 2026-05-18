# Plan A4: Accessibility Audit & Fix

## Summary

Add missing accessibility labels, values, and Dynamic Type support to key UI elements across all targets, bringing the app in line with the A11y-first promises in the README.

## Current Gaps

| Element | Missing | Location |
|---------|---------|----------|
| Scrubber Slider | No `accessibilityLabel` or `accessibilityValue` | `PlayerScrubberView.swift` |
| Album artwork | No accessibility labels | `ContentView.swift`, `MacContentView.swift`, Watch `PlayerPage` |
| Transport controls | Fixed font sizes (no Dynamic Type) | `BottomToolbarView.swift` |
| Speed picker | No accessibility announcement of current speed | `BottomToolbarView.swift` |
| Bookmark rows | No accessibility hint for available actions | `Bookmarks.swift` (iOS), `Bookmarks.swift` (Watch) |
| Word cloud | Text may not scale with Dynamic Type | macOS TranscriptPane, Watch WordCloudPage |
| Settings toggles | Labels use system font instead of Lexend | `SettingsView.swift` |

## Proposed Changes

### Scrubber Slider
```swift
Slider(value: $scrubPosition, ...)
    .accessibilityLabel("Playback position")
    .accessibilityValue(formatHMS(currentTime))
```

### Album Artwork
```swift
artworkImage
    .accessibilityLabel(trackTitle ?? "Audiobook artwork")
    .accessibilityAddTraits(.isImage)
```

### Transport Controls (Dynamic Type)
Replace `.font(.system(size: 20))` with `.font(.custom("Lexend", size: 20, relativeTo: .body))` throughout transport controls, so they scale with the user's Dynamic Type setting.

### Speed Picker
Add `.accessibilityValue("\(speed, specifier: "%.1f")x speed")` and post `UIAccessibility.post(notification: .announcement, argument: "Speed \(speed)x")` on change.

### Settings
Ensure all `Picker`, `Toggle`, and `Stepper` controls use `.font(.custom("Lexend", ...))` consistently. Labels should not fall back to system font.

### macOS-Specific
- `TranscriptPane`: Ensure text views respect Dynamic Type
- `MacContentView`: Add accessibility labels to transport buttons and scrubber

## Files to Modify

| File | Change |
|------|--------|
| `OrbitAudioBooks/Views/PlayerScrubberView.swift` | Add slider accessibility |
| `OrbitAudioBooks/Views/ContentView.swift` | Add artwork accessibility |
| `OrbitAudioBooks/Views/BottomToolbarView.swift` | Dynamic Type on transport, speed accessibility |
| `OrbitAudioBooks/Views/Bookmarks.swift` | Row action hints |
| `OrbitAudioBooks/Views/SettingsView.swift` | Font consistency |
| `Orbit Audiobooks macOS/Views/MacContentView.swift` | Accessibility labels |
| `Orbit Audiobooks macOS/Views/TranscriptPane.swift` | Dynamic Type text |
| `Orbit Audiobooks Watch App/Views/ContentView.swift` | Artwork and button labels |

## Dependencies

- **Depends on:** Plan Phase 1 (localization) — accessibility labels MUST be localized via `String(localized:)`. Do A4 AFTER the localization infrastructure is in place so labels are wrapped correctly from the start.
- **Conflicts with:** Plan A2 (Watch decomposition) — coordinate so accessibility modifiers land in the right extracted files. Minor coordination: do A2 first, then A4 on the extracted structure.

## Complexity

**Medium.** Many files touched but each change is small (~5-10 lines per file). Requires manual testing with VoiceOver at different Dynamic Type sizes.
