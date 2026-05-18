# Plan: Localization & Settings Cleanup ✅ DONE (2026-05-17)

## Summary

Implement Apple-standard String Catalogs across the entire project with English and Dutch support, and refactor SettingsView to use native Form/Section for full HIG compliance.

## Current State

- **Zero localization:** No `String(localized:)` calls, no `.xcstrings` files in the project
- All user-facing strings are hardcoded English strings
- `SettingsView.swift` (160 lines) uses some custom styling
- Dutch is the requested second language

## 1. String Catalog Implementation

### Approach

- Create `Localizable.xcstrings` at the project root
- Add English (en) as the development language, Dutch (nl) as a translation
- Wrap ALL user-facing strings across all four targets in `String(localized:)` or `Text("key")` with LocalizedStringKey

### Categories of Strings to Localize

| Category | Example Strings |
|----------|----------------|
| Transport controls | "Play", "Pause", "Skip Forward", "Skip Back" |
| Speed picker | "Speed", "1.0x", "1.5x", "2.0x" |
| Sleep timer | "Sleep Timer", "5 min", "10 min", "End of Chapter" |
| Bookmarks | "Bookmark", "Add Bookmark", "Delete Bookmark", "Edit Note" |
| Settings | "Settings", "Font", "Smart Rewind", "Watch Layout" |
| Alerts/Errors | "Microphone access denied", "Failed to load audiobook" |
| Watch commands | "Play/Pause", "Skip 30s", "Volume" |
| macOS | "Transcript", "Word Cloud", "Bookmarks" |
| Widget | "Toggle Playback", "Create Bookmark" |
| Accessibility labels | All labels added in A4 |

### Implementation Pattern

```swift
// Before
Text("Play")
Button("Sleep Timer") { ... }

// After
Text("Play", comment: "Play button label — transport control")
Button("Sleep Timer", comment: "Button to open sleep timer options") { ... }

// In code
String(localized: "Microphone access is required to record a voice bookmark.", 
       comment: "Alert shown when mic permission is denied")
```

## 2. SettingsView HIG Refactoring

Replace any custom backgrounds, non-standard dividers, or manual layouts with native `Form` + `Section`:

```swift
NavigationStack {
    Form {
        Section("Typography") {
            Picker("Font", selection: $settings.font) {
                ForEach(AppFont.allCases) { font in
                    Text(font.displayName).tag(font)
                }
            }
        }
        
        Section("Playback") {
            Toggle("Smart Rewind", isOn: $settings.smartRewindEnabled)
            NavigationLink("Smart Rewind Duration") {
                SmartRewindSettingsView()
            }
        }
        
        Section("Watch Layout") {
            NavigationLink("Configure Watch Buttons") {
                WatchAppSettingsView()
            }
        }
        
        Section("Store") {
            // Purchase/restore UI (Task 6)
        }
    }
    .navigationTitle("Settings")
}
```

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/Localizable.xcstrings` |
| Create | `Orbit Audiobooks macOS/Localizable.xcstrings` (or shared) |
| Modify | EVERY SwiftUI view with user-facing text (all targets) |
| Modify | `OrbitAudioBooks/Views/SettingsView.swift` |
| Modify | `OrbitAudioBooks/Views/SmartRewindSettingsView.swift` |
| Modify | `OrbitAudioBooks/Views/WatchAppSettingsView.swift` |
| Modify | `Orbit Audiobooks macOS/Views/MacContentView.swift` |
| Modify | `Orbit Audiobooks macOS/Views/TranscriptPane.swift` |
| Modify | `Orbit Audiobooks Watch App/Views/ContentView.swift` |
| Modify | `Orbit Audiobooks Widget/Views/Orbit_Audiobooks_Widget.swift` |

## Dependencies

- **Blocked by:** Nothing fundamental, but should be done BEFORE A4 (accessibility) so accessibility labels are localized from the start
- **Conflicts with:** 
  - EVERY plan that touches UI — localization wraps every string. Recommend doing this FIRST, then all subsequent plans write localized strings from the start. If done later, every plan needs a second pass for localization.
  - A4 (accessibility) — must go after localization
  - Phase 3 (Dashboard UI) — must use localized strings

## Complexity

**Large (by surface area, not depth).** Touches nearly every SwiftUI file, but each change is mechanical string wrapping. The Dutch translation is the largest one-time effort. SettingsView refactoring is straightforward Form/Section work.
