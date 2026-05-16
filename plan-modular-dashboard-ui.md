# Plan: Modular Dashboard UI & Transcript Optimization

## Summary

Redesign the main application into a modular, configurable dashboard where display sections (Thumbnail, Bookmarks, Wordcloud, Search, Playlist) are independent, toggleable widget-like components arranged in a `LazyVGrid`. Add layout persistence and tie transcript processing to UI visibility.

## Current State

**iOS views:**
- `ContentView.swift` (141 lines) — Top-level container
- `BottomToolbarView.swift` (194 lines) — Transport + speed
- `Bookmarks.swift` (793 lines) — Bookmark list with voice memo playback
- `PlaylistView.swift` — Chapter/playlist view
- `PlayerScrubberView.swift` — Scrubber
- `TranscriptView.swift` (not found in file listing, may be part of overlay)
- Various overlay and component views

The current UI is a scrollable single-column layout. Sections are hardcoded and always present.

## Proposed Design

### 1. Modular Components

Extract each display section into a standalone SwiftUI component conforming to a shared protocol:

```swift
protocol DashboardModule: View {
    static var moduleId: String { get }
    static var moduleName: String { get }
    static var moduleIcon: String { get }
    static var defaultSize: ModuleSize { get }
}

enum ModuleSize: Codable {
    case small   // 1x1 grid unit
    case medium  // 2x1
    case large   // 2x2
    case full    // full width
}
```

Modules:
- `ThumbnailModule` — Album art, track/chapter title, progress ring
- `BookmarkModule` — Current position bookmark, recent bookmarks
- `WordCloudModule` — Word frequency visualization (if transcript is unlocked)
- `SearchModule` — Transcript search with tap-to-seek
- `PlaylistModule` — Chapter list / book hierarchy
- `SleepTimerModule` — Timer countdown widget
- `SpeedModule` — Speed picker as a grid tile

### 2. Dashboard Grid Layout

```swift
struct DashboardView: View {
    @State private var modules: [DashboardModuleConfig] = loadLayout()
    @State private var isEditing = false
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))]) {
                ForEach(modules.filter(\.isVisible)) { config in
                    moduleView(for: config)
                        .frame(height: cellHeight(for: config.size))
                }
            }
            .padding()
        }
    }
}
```

### 3. Layout Persistence

Store module configuration in UserDefaults (App Group) as JSON:

```swift
struct DashboardModuleConfig: Codable, Identifiable {
    let id: String  // module type identifier
    var isVisible: Bool
    var size: ModuleSize
    var gridPosition: Int  // sort order
}
```

User can toggle modules on/off in settings, reorder via drag handle in edit mode, and resize (small/medium/large).

### 4. Transcript Visibility Optimization

Tie `TranscriptionManager`'s active processing to whether ANY transcript-dependent module is visible:

- `SearchModule` visible → transcription active
- `WordCloudModule` visible → transcription active
- Neither visible → `TranscriptionManager` suspends, no CPU/battery drain

Implement via a shared `@Published` flag or notification:

```swift
// In TranscriptionManager
@Published var isProcessingEnabled = false

// In DashboardView
.onChange(of: transcriptModulesVisible) { _, visible in
    transcriptionManager.isProcessingEnabled = visible
}
```

On macOS: same pattern — `TranscriptPane` visibility controls `TranscriptionManager` processing state.

### 5. Collapsible Transcript

On iOS, the transcript is currently an overlay. On macOS, it's a pane. The plan makes it a full-width module that can be toggled via:
- A toolbar button
- `DisclosureGroup` animation

When collapsed, the full transcript text view is removed from the hierarchy (not just hidden).

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/Views/Components/DashboardView.swift` |
| Create | `OrbitAudioBooks/Views/Components/DashboardModule.swift` (protocol) |
| Create | `OrbitAudioBooks/Views/Components/ThumbnailModule.swift` |
| Create | `OrbitAudioBooks/Views/Components/BookmarkModule.swift` |
| Create | `OrbitAudioBooks/Views/Components/WordCloudModule.swift` |
| Create | `OrbitAudioBooks/Views/Components/SearchModule.swift` |
| Create | `OrbitAudioBooks/Views/Components/PlaylistModule.swift` |
| Create | `OrbitAudioBooks/Views/Components/SleepTimerModule.swift` |
| Create | `OrbitAudioBooks/Views/Components/SpeedModule.swift` |
| Create | `OrbitAudioBooks/Models/DashboardModuleConfig.swift` |
| Modify | `OrbitAudioBooks/Views/ContentView.swift` — use `DashboardView` |
| Modify | `OrbitAudioBooks/Views/SettingsView.swift` — add module configuration section |
| Modify | `OrbitAudioBooks/ViewModels/PlayerModel.swift` — expose module-relevant state |
| Modify | `Orbit Audiobooks macOS/Views/TranscriptionManager.swift` — `isProcessingEnabled` flag |
| Modify | `Orbit Audiobooks macOS/Views/TranscriptPane.swift` — tie visibility to processing |

## Dependencies

- **Blocked by:**
  - Plan A1 (PlayerModel decomposition) — modules should bind to extracted components, not the god class
  - Plan A5 (protocol extraction) — modules should reference `PlayerModelProtocol`, not concrete `PlayerModel`
  - Plan Phase 1 (localization) — all module labels must be localized
- **Conflicts with:**
  - Plan Phase 4 (CarPlay) — CarPlay has its own UI templates; dashboard modules don't apply there. No conflict.
  - Plan SQL Database — bookmark and wordcloud modules would use SQL-backed queries

## Complexity

**Large.** Touches almost every iOS view. The modularization itself is a refactor, then the grid layout is new UI, then the transcript optimization is a separate concern across two platforms. Do after A1/A5 so the module boundaries align with the extracted services.
