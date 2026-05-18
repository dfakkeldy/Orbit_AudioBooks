# Help Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add an in-app help screen with 11 sections of user-facing documentation, accessible from both a "?" button on the main player and a "Help" row in Settings.

**Architecture:** A data-driven `HelpView` renders a `ScrollView` of sections defined in a static `HelpContent.sections` array. Two entry points (ContentView toolbar button, SettingsView NavigationLink) both open the same view — as a sheet from ContentView, and pushed onto the Settings navigation stack.

**Tech Stack:** SwiftUI, iOS 17+, `fileSystemSynchronizedGroups` (no Xcode project changes needed)

---

## File Structure

| File | Responsibility |
|------|---------------|
| `OrbitAudioBooks/Views/HelpContent.swift` (new) | `HelpSection` model + static content array |
| `OrbitAudioBooks/Views/HelpView.swift` (new) | `ScrollView` rendering the sections |
| `OrbitAudioBooks/Views/ContentView.swift` (edit) | Add `showingHelp` state, "?" button, `.sheet` modifier |
| `OrbitAudioBooks/Views/SettingsView.swift` (edit) | Add "Help" `NavigationLink` row |

---

### Task 1: Create HelpContent.swift — data model and static content

**Files:**
- Create: `OrbitAudioBooks/Views/HelpContent.swift`

- [x] **Step 1: Write the model and content file**

```swift
import Foundation

struct HelpSection: Identifiable {
    let id: String
    let title: String
    let body: String
}

enum HelpContent {
    static let sections: [HelpSection] = [
        HelpSection(
            id: "loading",
            title: "Loading Books",
            body: """
            Tap the folder icon in the top-left corner to open the file picker. You can select a single audio file or an entire folder.

            Supported formats: MP3, M4A, and M4B.

            When you select a folder, all supported audio files inside are added to your playlist in alphabetical order. Chapter markers embedded in M4B and M4A files are automatically detected and used for chapter navigation.

            Artwork is discovered automatically — the app looks for embedded cover art, then for an image file named "cover" (any image format) in the same folder. If nothing is found, the app icon is used as a fallback.

            If a .transcript.json file with the same name as your audio file is in the same folder, it is loaded automatically and available as a scrolling transcript overlay.

            Your last opened book is restored automatically when you relaunch the app.
            """
        ),
        HelpSection(
            id: "playback",
            title: "Playback Controls",
            body: """
            The transport bar has five buttons:

            • Previous — Jump to the previous chapter or track.
            • Skip Back 30s — Rewind 30 seconds.
            • Play / Pause — Start or pause playback.
            • Skip Forward 30s — Jump ahead 30 seconds.
            • Next — Jump to the next chapter or track.

            Playback also works from the Lock Screen and Control Center. Use the system Now Playing controls to pause, play, or skip without opening the app.
            """
        ),
        HelpSection(
            id: "speed",
            title: "Playback Speed",
            body: """
            Tap the speed button in the bottom toolbar to cycle through playback speeds: 1.0×, 1.25×, 1.5×, 2.0×, and 3.0×.

            Your chosen speed is saved per book. When you come back to a book, it resumes at the speed you last used for it.

            The default speed for new books is 1.25×.
            """
        ),
        HelpSection(
            id: "volume-boost",
            title: "Volume Boost",
            body: """
            The volume boost toggle applies a +9 dB gain to the audio. This is useful for quiet recordings or listening in noisy environments.

            Tap the speaker icon in the bottom toolbar to toggle it on or off. When active, the icon shows filled sound waves.
            """
        ),
        HelpSection(
            id: "loop",
            title: "Loop Modes",
            body: """
            The loop button cycles through three modes:

            • Off — The playlist plays straight through from start to finish.
            • Chapter — The current chapter repeats. When it ends, it starts again from the beginning of the same chapter.
            • Bookmark — Loops between consecutive bookmarks. Playback jumps back to the previous bookmark when it reaches the next one. This mode is hidden when no bookmarks exist.

            Tap the infinity (∞) icon in the bottom toolbar to cycle modes. A filled icon means a loop mode is active.
            """
        ),
        HelpSection(
            id: "bookmarks",
            title: "Bookmarks",
            body: """
            Bookmarks let you save and annotate specific moments in your audiobook.

            Creating a bookmark: Tap the bookmark icon in the bottom toolbar while playing. This captures the current timestamp and opens the bookmark editor.

            Editing a bookmark: You can give it a title, adjust the timestamp with +/- 1 second buttons, add a text note, attach a photo from your library (picture bookmark), or record a voice memo.

            Picture bookmarks: When playback passes a bookmark with an attached image, that image temporarily replaces the album artwork on the player screen.

            Voice memos: Record audio notes attached to bookmarks. When "Play Bookmarks Inline" is enabled in Settings, voice memos play automatically as the audiobook reaches each bookmark's timestamp. During voice memo playback, the main player dims and a "Playing Voice Memo" badge appears.

            Bookmarks are stored as a portable .json file alongside your audiobook files. You can export bookmarks to Markdown — the exported file includes clickable links that open the audiobook at the exact timestamp.

            Manage bookmarks from the Playlist screen: reorder, edit, toggle on/off, or delete them.
            """
        ),
        HelpSection(
            id: "sleep-timer",
            title: "Sleep Timer",
            body: """
            The sleep timer stops playback after a set duration. Tap the moon icon in the bottom toolbar to choose a preset:

            • 15 minutes
            • 30 minutes
            • 45 minutes
            • 1 hour
            • End of Chapter — Stops when the current chapter finishes.

            When a timer is active, the remaining time appears next to the moon icon as a compact countdown. To cancel, open the menu again and tap "Off".
            """
        ),
        HelpSection(
            id: "smart-rewind",
            title: "Smart Rewind",
            body: """
            Smart Rewind automatically rewinds a few seconds when you resume playback after a pause. This helps you pick up where you left off without losing context.

            You can configure three tiers based on pause duration:

            • Short pauses (seconds) — A small rewind for brief interruptions.
            • Medium pauses (minutes) — A larger rewind when you've been away longer.
            • Long pauses (hours) — The largest rewind, or optionally jump to the start of the current chapter.

            Configure Smart Rewind in Settings > Smart Rewind. The feature is off by default. All rewind amounts respect chapter boundaries — you will never rewind past the start of the current chapter.
            """
        ),
        HelpSection(
            id: "playlist",
            title: "Playlist",
            body: """
            Tap the list icon in the bottom toolbar to open the Playlist. It has two tabs:

            Chapters/Tracks — Shows the contents of your current book. If the file has chapter markers, you see chapter titles. Drag the handles to reorder, or toggle individual items on/off to skip them during playback. Tap "Reset" to restore the original order and enable all items.

            Bookmarks — Shows all bookmarks for the current book. Tap a bookmark to jump to its timestamp. Swipe left on a bookmark to edit or delete it. Use the toggle to enable or disable a bookmark without deleting it.
            """
        ),
        HelpSection(
            id: "watch",
            title: "Watch App",
            body: """
            The Apple Watch app works as a remote control for the iPhone player. Key features:

            • Two customizable Player Pages — Each page holds up to 5 action slots that you can configure from the iPhone Settings > Watch App screen. Drag and drop actions to reorder them.
            • Digital Crown — Configurable to control volume or scrub through the current track.
            • Quick Bookmarks — Hold the bookmark button to auto-create a bookmark after a configurable countdown (1–15 seconds). Great for hands-free bookmarking.
            • Progress Display — Choose between a circular progress ring and a linear progress bar. Each can show either chapter progress or total book progress.
            • Artwork — Two layouts: Full Face (immersive artwork) and Classic (small artwork with background). Backgrounds can be blurred artwork or solid black.
            • Word Cloud — A watch page showing the most frequent words from the current chapter.
            • Haptic feedback on button taps can be toggled in Settings.

            Configure all watch options from the iPhone app under Settings > Watch App.
            """
        ),
        HelpSection(
            id: "appearance",
            title: "Appearance & Settings",
            body: """
            Access Settings by tapping the gear icon in the top-right corner of the player.

            • Appearance — Toggle between dark and light mode. Choose from three fonts: Lexend (default, designed for readability), OpenDyslexic (optimized for readers with dyslexia), and the system font.

            • Pro Transcripts — An in-app purchase that unlocks the scrolling transcript overlay and word cloud. Requires a .transcript.json sidecar file next to your audiobook.

            • Play Bookmarks Inline — When enabled, voice memos attached to bookmarks play automatically when the audiobook reaches that timestamp.
            """
        )
    ]
}
```

- [x] **Step 2: Commit**

```bash
git add OrbitAudioBooks/Views/HelpContent.swift
git commit -m "feat: add HelpContent model and static help sections"
```

---

### Task 2: Create HelpView.swift — the scrollable help view

**Files:**
- Create: `OrbitAudioBooks/Views/HelpView.swift`

- [x] **Step 1: Write the view**

```swift
import SwiftUI

struct HelpView: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(HelpContent.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                }
            }
            .padding()
        }
        .environment(\.font, settings.appFont == SettingsManager.systemFontName ? .body : .custom(settings.appFont, size: 17, relativeTo: .body))
    }
}
```

- [x] **Step 2: Commit**

```bash
git add OrbitAudioBooks/Views/HelpView.swift
git commit -m "feat: add HelpView with scrollable help sections"
```

---

### Task 3: Add "?" button and sheet to ContentView

**Files:**
- Modify: `OrbitAudioBooks/Views/ContentView.swift`

- [x] **Step 1: Add the `showingHelp` state variable**

Add after line 12 (`@State private var showingSettings = false`):

```swift
@State private var showingHelp = false
```

- [x] **Step 2: Add the "?" toolbar button**

Add a new `ToolbarItem` after the folder button block (after line 89 `}`):

```swift

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel(Text("Help"))
            }
```

- [x] **Step 3: Add the `.sheet` modifier for HelpView**

Add after the `.sheet(isPresented: $showingSettings)` block (after line 112):

```swift
        .sheet(isPresented: $showingHelp) {
            NavigationStack {
                HelpView()
                    .navigationTitle("Help")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingHelp = false }
                        }
                    }
            }
        }
```

- [x] **Step 4: Commit**

```bash
git add OrbitAudioBooks/Views/ContentView.swift
git commit -m "feat: add help button and sheet to ContentView"
```

---

### Task 4: Add "Help" row to SettingsView

**Files:**
- Modify: `OrbitAudioBooks/Views/SettingsView.swift`

- [x] **Step 1: Add the Help section**

Add a new `Section` before the closing `}` of the `Form` (after line 62):

```swift

                Section {
                    NavigationLink("Help") {
                        HelpView()
                            .navigationTitle("Help")
                    }
                }
```

- [x] **Step 2: Commit**

```bash
git add OrbitAudioBooks/Views/SettingsView.swift
git commit -m "feat: add Help row to Settings"
```

---

### Task 5: Build verification

- [x] **Step 1: Build the project**

Run: `xcodebuild -project OrbitAudioBooks.xcodeproj -scheme "Orbit AudioBooks" -destination "platform=iOS Simulator,name=iPhone 16" build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [x] **Step 2: Verify all files are committed**

Run: `git status`
Expected: `nothing to commit, working tree clean`

- [x] **Step 3: Verify final commit log**

Run: `git log --oneline -4`
Expected: 4 commits (HelpContent, HelpView, ContentView edit, SettingsView edit)
