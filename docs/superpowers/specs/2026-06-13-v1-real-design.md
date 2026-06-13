# Echo v1.0 Design (Real)

**Date:** 2026-06-13
**Status:** Design approved, pending implementation plan

## Context

The original v1.0 roadmap (WS0–WS10, predicted ~14 weeks) was completed far faster than expected (shipped through PRs #39–#51 on main). This document defines the **real** v1.0 — pulling in the previously-cut post-1.0 features at a more ambitious scope.

Platform targets: iOS (full), watchOS (companion), macOS (full parity).

---

## Scope

v1.0 = [shipped: WS0–WS10] + five new capability clusters:

1. **SRS 2.0** — FSRS algorithm, true cloze cards, .apkg export, anki21b import, auto-draft chapter cards
2. **Sensory Suite** — Focus soundscapes (ambient loops + generative), fidget UI (doodle pad + tactile playground + visualizers including acidwarp), hyperfocus interval chimes
3. **Mac Study Desk** — Tri-pane reader (TOC + reader feed + transcript/notes), bulk folder alignment, AnkiConnect file bridge
4. **CarPlay Pro** — Capture buttons (bookmark, voice memo, mark passage) always available, library/chapter/bookmark browsing while parked
5. **Solo Transcription** — Progressive standalone audiobook transcription (no EPUB/PDF needed), first-chapter-immediate then background

Additions during design review: auto-draft chapter-heading flashcards for new users unfamiliar with Anki.

---

## Cluster 1: SRS 2.0

### FSRS Algorithm

Replace the static `SpacedRepetitionService.apply(grade:to:)` enum with a protocol-based scheduler.

**Protocol:**
```swift
protocol SchedulingAlgorithm: Sendable {
    func review(card: Flashcard, grade: Int, now: Date) -> Flashcard
}
```

**Implementations:**
- `SM2Scheduler` — wraps existing SM-2 math. Default for cards with <6 reviews (FSRS needs minimum history).
- `FSRSScheduler` — Swift port of open-source `fsrs-rs` algorithm (MIT-licensed). Takes over when a card has ≥6 reviews. Computes stability, difficulty, and optimal interval using the FSRS forgetting curve model.

**Schema migration (V15):**
```sql
ALTER TABLE flashcard ADD COLUMN stability REAL;       -- nullable, nil until FSRS active
ALTER TABLE flashcard ADD COLUMN difficulty REAL;       -- nullable, nil until FSRS active
ALTER TABLE flashcard ADD COLUMN card_type TEXT NOT NULL DEFAULT 'normal';  -- 'normal' | 'cloze'
ALTER TABLE flashcard ADD COLUMN cloze_index INTEGER;   -- nullable, 0-based index for cloze cards
ALTER TABLE deck ADD COLUMN anki_deck_id INTEGER;       -- nullable, for Anki round-tripping
```

**Data flow:**
```
FlashcardDAO.grade(card:grade:scheduler:)
  ├── scheduler.review(card:grade:now:) → updated Flashcard
  ├── UPDATE flashcard SET ... WHERE id = ?
  ├── INSERT real_time_event (flashcard_reviewed)
  └── CloudKitSyncService.pushIfNeeded()
```

**Injected clock:** `FSRSScheduler` takes a `now` parameter for test determinism (fixes the latent SM-2 bug where `Date()` was called internally).

### True Cloze Cards

**Import behavior change:**
- Current: `{{c1::answer}}` is flattened to `answer` (cloze deletion stripped).
- New: `{{c1::answer}}` produces a cloze card. Front = text with `{{c1::answer}}` replaced by `[...]`. Back = full text with answer highlighted. One card per cloze index (`c1`, `c2`, etc.).

**Field mapping:**
```
card_type = 'cloze'
cloze_index = 1 (or 2, 3, ...)
front_text = "The capital of France is [...]"
back_text = "The capital of France is Paris"
```

**Review UI:** Cloze cards render with the `[...]` placeholder. Tap to reveal. Grade buttons same as normal cards (Again/Hard/Good/Easy).

**Export:** `.apkg` export writes proper Anki cloze note type so Anki recognizes them natively.

### .apkg Export

`ApkgExportService` — async, progress-reporting:
1. Read deck + cards from database
2. Build `collection.anki21` SQLite database in a temp directory:
   - `col` table — collection metadata
   - `notes` table — one note per card (front/back/cloze fields)
   - `cards` table — scheduling state per card
   - `revlog` table — review history from `real_time_event`
3. Copy referenced media files from `App Group/FlashcardMedia/<deckID>/`
4. Zip via ZIPFoundation (reusing zip-slip-safe helper) → `.apkg` file
5. Export via ShareLink on iOS, `NSSavePanel` on Mac

**Entry points:** DeckListView (per-deck), DeckDetailView (per-deck), "Export All Decks" button.

### anki21b Import Support

Extend `ApkgImportService` with an anki21b code path:
- Detect `.anki21b` SQLite schema (different table names from `.anki21`)
- Map new note/card/review-log tables to our schema
- Remove the existing "reject with guidance" path — support it directly

**Mapping differences vs. anki21:**
- Table names differ (`notes` → `fields` structure)
- Scheduling columns have different names/scales
- Media references use a different JSON structure

### Auto-Draft Chapter Cards

`ChapterCardDrafter` — structural flashcard generation from book organization:

**Trigger:** On first EPUB open (after import completes), or manually from the book's context menu.

**Algorithm:**
1. Query all `epub_block` rows where `kind = 'heading'` AND `is_front_matter = false`
2. Skip headings classified as junk by `HeadingClassifier` (cover, praise, printed TOC, copyright)
3. For each remaining heading:
   - Front: heading text (e.g., "The Prison Door")
   - Back: chapter number + book title (e.g., "Chapter 1 — The Scarlet Letter")
   - Deck: auto-created deck named after the book title
   - Tags: `auto-drafted`, `chapter`
   - `source_block_id`: the heading's block ID
   - `card_type`: `normal`
4. Idempotency guard: check `(source_block_id, card_type)` before creating — re-running doesn't duplicate

**Settings:** `SettingsManager.autoDraftChapterCards` (default `true`). Toggle in Settings > Study.

**Rationale:** A new user unfamiliar with Anki imports a book and immediately has a deck of chapter-summary cards. This bridges "I want to study" → "I know how to write flashcards."

### SRS 2.0 Tests

| Test Suite | Coverage |
|---|---|
| `FSRSSchedulerTests` | Grades 1–4, stability/difficulty convergence, interval bounds, injected clock determinism |
| `SM2SchedulerTests` | Existing SM-2 edge cases (ease floor 1.3, interval progression, reset on lapse) with injected clock |
| `ClozeParsingTests` | `{{c1::single}}`, `{{c1::a}}{{c2::b}}`, nested braces, malformed (no `::`), empty cloze |
| `ApkgExportRoundTripTests` | Import anki21 fixture → export .apkg → reimport → card/due/interval equality |
| `Anki21bMappingTests` | .anki21b fixture import → verify card count, scheduling, media references |
| `ChapterCardDrafterTests` | Seeded DB with headings + front matter → verify auto-drafted cards (count, skips FM, idempotency) |

---

## Cluster 2: Sensory Suite

All four sensory features layer on top of the audio playback session. They share an upgraded AudioEngine mixing path and are protocol-seamed for testability.

### AudioEngine Upgrades

**SoundscapeMixer:**
- `AVAudioPlayerNode` for ambient looping playback (scheduled buffers for gapless looping)
- `AVAudioUnitEQ` for optional ducking (cut ~3 dB from ambient when book is speaking vs. silent)
- Independent volume: `soundscapeVolume` (0.0–1.0), separate from `bookVolume`
- Fades on play/pause/route change (0.3s fade to avoid clicks)
- Protocol: `protocol SoundscapePlaying: AnyObject { func play(preset: SoundscapePreset) async; func stop(); var volume: Float { get set } }`

**ChimePlayer:**
- Lightweight `AVAudioPlayerNode` for one-shot chime sounds
- Pre-loaded audio buffers (short, <2s each)
- Plays at `chimeVolume` relative to `bookVolume` (default 30%)
- Protocol: `protocol ChimeScheduling: AnyObject { func schedule(interval: TimeInterval, sound: ChimeSound); func cancel() }`

**VisualizerTap:**
- Read-only tap off the main mixer node output
- Delivers RMS + peak + 16-band frequency data at ~30 fps via `AsyncStream<VisualizerFrame>`
- No audio modification — observation only
- Protocol: `protocol VisualizerDataProviding { var frames: AsyncStream<VisualizerFrame> { get } }`

All three are `nonisolated(unsafe)` properties on `AudioEngine`, accessed only on `@MainActor`.

### Focus Soundscapes

**Ambient Loops:**
- Bundled CC0 audio files (30–60s seamless loops): rain, cafe murmur, white noise, brown noise, forest, ocean, fireplace, thunderstorm, library ambiance, cat purr
- Compressed as AAC ~128kbps, ~5 MB total bundle
- `SoundscapeLibrary` enum with preset metadata (name, SF Symbol, category: nature/urban/tonal)

**Generative Engine:**
- `AVAudioSourceNode` with per-sample render callback
- White/pink/brown noise (simple DSP)
- Binaural beats: carrier tone in left channel, carrier + offset in right. Configurable base frequency (100–400 Hz) and beat frequency (4–40 Hz)
- Isochronic tones: pulsed sine wave at configurable rate
- All parameters configurable via a `GenerativeSoundscapePreset` struct

**UI:**
- `SoundscapePickerView` — grid of presets. Tap to preview (plays alone for 5s), double-tap or checkmark to select. "Generative" tab for tone configuration.
- `SoundscapeVolumeSlider` — independent volume in the Now Playing overflow + DashboardShelf
- Persistence: `BookPreferencesService` stores last soundscape choice + volume per book

### Fidget Suite

Three modes accessible from the Now Playing overflow menu (`FidgetOverlayView`, presented as a sheet).

**Doodle Pad:**
- `PKCanvasView` (PencilKit) via `UIViewRepresentable`
- Tool picker: pen (6 colors), eraser, clear
- Auto-save to `App Group/doodles/<audiobookID>/<UUID>.png` on sheet dismiss
- Share button (optional, not pressured)
- Playback continues while drawing

**Tactile Playground:**
- **Bubble Pop:** `Canvas`-based grid of circles. Tap → pop animation + `UIImpactFeedbackGenerator(style: .light)`. Auto-regenerates after 2s. Counts pops silently.
- **Kinetic Sand:** `Canvas` with particle simulation. ~200 particles, drag applies force. `UIImpactFeedbackGenerator` on fast swipes. Continuous mode.
- **Infinity Scroll:** `SpriteKitView` with endless scrolling pattern. Horizontal auto-scroll at gentle speed. Drag to change direction.
- Mode switcher: horizontal swipe between playground types

**Audio Visualizers:**
- `MetalKit` `MTKView` via `UIViewRepresentable`, driven by `VisualizerTap.frames`
- Styles (swipe to cycle):
  - **AcidWarp:** LFO-modulated hue rotation + fractal recursion on a full-screen quad. Color palette cycles over time. Psychedelic, hypnotic.
  - **Waveform River:** Scrolling waveform of current audio, color-mapped to cover theme. Flows left to right.
  - **Particle Flow:** ~500 particles emit from center, velocity + color driven by amplitude. Calm when quiet, energetic during loud passages.
  - **Spectrum Bars:** Classic frequency-bar visualizer. 64 bars, bottom-aligned, colored from cover theme.
- `VisualizerStyle` enum with associated Metal shader
- Each style renders to a full-screen quad; shader receives RMS + spectrum as uniforms

### Hyperfocus Chimes

**ChimeScheduler:**
- Configurable interval: off / 15 min / 30 min / 60 min
- Fires `ChimePlayer.play(sound:)` via `Task.sleep` loop (cancelled on interval change)
- Interval resets on pause/stop — only counts active listening time

**ChimeLibrary:**
- Bundled sounds (~2s each, uncompressed WAV for zero-decode-latency): cuckoo clock, temple bell, singing bowl, soft chime, piano C5, harp gliss, "hey" whisper
- `ChimeSound` enum with display name + SF Symbol + audio file reference

**UI:**
- New "Focus" section in `PhonePlayerSettingsView`:
  - "Interval Chime" row → picker (Off / 15 min / 30 min / 60 min)
  - "Chime Sound" row → picker with preview button (plays when tapped)
  - "Chime Volume" slider (10%–100% of book volume, default 30%)
- `ChimeSettings` struct persisted in `SettingsManager`

---

## Cluster 3: Mac Study Desk

### Tri-Pane Reader

**Layout:**
```
NavigationSplitView
├── Sidebar (left):     TOC tree (collapsible) + compact playlist
├── Content (center):   Reader card feed (same Shared/ cells as iOS)
└── Detail (right):     Transcript pane + Book Notes pane
```

**Left Pane — TOC + Playlist:**
- Publisher TOC tree from `epub_toc_entry`, rendered with `DisclosureGroup`/`OutlineGroup`
- Click heading → seek playback to that block's timestamp
- Below TOC: compact playlist (current chapter ± 2, with play icons)
- Search field at top: filters TOC + headings

**Center Pane — Reader Feed:**
- `ScrollView` + `LazyVStack` of card views
- Reuses card types from `Shared/` (extracted from iOS `Views/Cells/`)
- Active block highlighting (blue leading bar)
- Auto-scroll following playback, disengages on manual scroll
- Right-click context menu: same actions as iOS long-press (Align to Now, Bookmark, Not in Audio, etc.)
- Scrolling is decoupled: uses `ScrollViewProxy.scrollTo(blockID, anchor: .center)` driven by `TimelineSynchronizer`

**Right Pane — Transcript + Notes:**
- `TranscriptPane` (existing): scrolling transcript segments, current segment highlighted
- `MacNotesPane` (new): per-book Brain Dump notes list. Inline editable. Shows recent bookmarks with timestamps.
- Panes are stacked vertically with a `VSplitView`-style divider

**TimelineSynchronizer:**
- Observes `PlaybackState.currentTime`
- Maps time → block (center pane), time → transcript segment (right pane), time → TOC entry (left pane)
- Each pane independently scrolls to its match position
- Manual scroll in any pane pauses auto-scroll for that pane; "scroll to active" button re-engages

**Keyboard Shortcuts:**
```
Space           → Play/Pause
← →            → Skip back/forward 15s
⌘← ⌘→          → Previous/next chapter
⌘B             → Bookmark
⌘M             → Mark passage (card inbox)
⌘N             → New Brain Dump note
⌘⇧A            → Align current block to now
⌘F             → Find in book
⌘T             → Toggle right pane
⌘1/2/3         → Focus left/center/right pane
```

**Mac-Native Controls:**
- Menu bar: File (Open Folder, Export Study Notes), Edit (Find), View (Toggle Panes), Playback (all transport), Study (Review Due Cards)
- `NSMenuItem` with keyboard shortcut equivalents
- Touch Bar support: scrubber, play/pause, chapter forward/back

### Bulk Folder Alignment

`MacBulkAlignmentService` — long-running background alignment for a folder tree:

**Workflow:**
1. User picks a directory via `NSOpenPanel` (canOpenDirectories)
2. Service recursively scans for `.m4b`/`.mp3`/`.m4a` files
3. For each audio file, checks sibling directory + parent for matching `.epub`/`.pdf`
4. Imports each pair into the database (reuses `EPUBImportCoordinator`, skips already-imported books)
5. Queues `AutoAlignmentService.align(book:)` for each book sequentially
6. Reports progress: `BulkAlignmentProgress` (book N of M, current chapter/total, estimated remaining)

**Progress UI:**
- `BulkAlignmentProgressView` — sheet showing progress bar per book, overall progress, ETA
- "Run in Background" button dismisses the sheet while alignment continues
- Menu bar shows progress indicator + book count
- "Sleep when done" checkbox: on completion, triggers `pmset sleepnow` (macOS-only)

**Design constraints:**
- WhisperKit is GPU-bound: one model instance, sequential alignment (not parallel)
- Uses existing `WhisperSession` (reference-counted shared model)
- Each book's auto-anchors are cleared before re-alignment (existing `AutoAlignmentService` behavior)
- Cancelable: stop button clears the queue, current chapter finishes its chunk then stops

### AnkiConnect File Bridge

**Export for Anki:**
- `MacAnkiExportView` — sheet in DeckListView
- Checkbox list of all decks, "Select All", "Export Selected"
- Writes `.apkg` files + `review-log.json` to user-chosen directory (via `NSSavePanel`)
- `review-log.json` format:
  ```json
  {
    "formatVersion": 1,
    "exportedAt": "2026-06-13T...",
    "decks": [{
      "name": "Book Title",
      "ankiDeckID": null,
      "cards": [{ "front": "...", "back": "...", "stability": 2.5, ... }],
      "reviewLog": [{ "cardID": "...", "grade": 4, "reviewedAt": "..." }]
    }]
  }
  ```

**Bonus — Direct to Anki:**
- "Send to Anki" button makes `POST http://localhost:8765` with AnkiConnect API payload
- Detects AnkiConnect availability (quick health-check GET)
- If reachable: one-click push. If not: fall back to file export.
- This is a bonus convenience, not a new integration model — the file export is the canonical path.

---

## Cluster 4: CarPlay Pro

### Architecture

`CarPlayManager` (`@MainActor` class), owned by `CarPlaySceneDelegate`:

```
CPTabBarTemplate
├── Tab 0: CPNowPlayingTemplate (enhanced)
├── Tab 1: CPListTemplate (Library)
├── Tab 2: CPListTemplate (Chapters)
└── Tab 3: CPListTemplate (Bookmarks)
```

### Now Playing — Capture Buttons

CarPlay `CPNowPlayingTemplate` supports `up to 3` custom buttons (`CPNowPlayingImageButton`):

| Button | SF Symbol | Action |
|---|---|---|
| Bookmark | `bookmark` | `BookmarkStore.append(at:)` — creates bookmark, confirmation beep |
| Voice Memo | `mic` | Starts recording via CarPlay mic. Confirmation tone. Tap again to stop (60s cap). Saves as global Book Note on current book. |
| Mark Passage | `rectangle.and.pencil.and.ellipsis` | `MarkedPassageService.mark(around:)` — marks [now−15s, now+5s] for Card Inbox |

All three are fire-and-forget. Confirmation via a subtle beep mixed into car audio. No popups, no text — fully eyes-free.

### Safe Browsing

CarPlay enforces limited interaction while moving. We design for this:

**While moving:** Only Now Playing tab is available (default CarPlay behavior for `CPTabBarTemplate` with a `CPNowPlayingTemplate`). Capture buttons always work.

**While parked:** All four tabs available.
- **Library:** `CPListTemplate` with `CPListItem` rows (cover thumbnail + book title + author). Tap → load and play. Empty state: "Add audiobooks in the Echo app on your iPhone."
- **Chapters:** Current book's chapter list from `PlaybackState.chapters`. Tap → seek. Shows current chapter with play icon.
- **Bookmarks:** Recent 20 bookmarks for current book. Tap → seek. Swipe to delete (CPListTemplate supports swipe actions).

Transition is automatic — CarPlay enables/disables tabs based on `CPNavigationAlert` state.

### Watch Coexistence

Both watch and CarPlay can be connected simultaneously. No conflict:
- CarPlay takes audio output priority (car speakers)
- Watch remains companion for review + pomodoro
- Commands from either route through `WatchCommandRouter` (same pattern)
- CarPlay gets its own `CarPlayManager` that calls `PlayerModel` facade methods directly

---

## Cluster 5: Solo Transcription

### Progressive Standalone Pipeline

**Service:** `StandaloneTranscriptionService` (`@MainActor`)

**Trigger:** On audiobook import when no EPUB/PDF detected, auto-starts. Can also be manually triggered from the book context menu.

**Pipeline:**
```
StandaloneTranscriptionService.start(book:)
  ├── Chapter 1: transcribe immediately
  │     ├── SilenceDetectionService → chunk boundaries
  │     ├── AudioSegmentReader → read audio windows
  │     ├── WhisperSession → transcribe with word timestamps
  │     └── TranscriptAssembler → write to standalone_transcript table
  ├── Report progress: "Chapter 1/24 complete"
  └── Queue remaining chapters → background Task.detached
        └── for each chapter: chunk → transcribe → write
            └── Cancelable, resumable, checkpoints per chapter
```

**Schema (V15):**
```sql
CREATE TABLE standalone_transcript (
    id TEXT PRIMARY KEY,
    audiobook_id TEXT NOT NULL REFERENCES audiobook(id),
    chapter_index INTEGER NOT NULL,
    segment_index INTEGER NOT NULL,
    text TEXT NOT NULL,
    start_time REAL NOT NULL,
    end_time REAL NOT NULL,
    words_json TEXT,  -- JSON array of {word, start, end, confidence}
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_standalone_transcript_book_time
    ON standalone_transcript(audiobook_id, start_time);
```

**Background execution:**
- `beginBackgroundTask(expirationHandler:)` for app-backgrounded scenarios
- Chapter checkpoints: each chapter write commits to DB → safe to cancel mid-book
- `StandaloneProgressState` — `@Observable` struct: `chaptersTotal`, `chaptersComplete`, `currentChapterIndex`, `isRunning`, `isCancelled`

### UI Integration

**Now Playing:**
- When transcript exists for current position: show a transcript snippet below the chapter title
- Tap → expand to `StandaloneTranscriptOverlayView` (scrolling transcript that follows playback)

**Reader Tab fallback:**
- When no EPUB/PDF but standalone transcript exists: show `StandaloneTranscriptView`
- Chapter markers from M4B track metadata
- Searchable text segments
- Simplified layout (not card-based, but functional for reading along)

**Search:**
- `TranscriptAssembler.search(bookID:query:)` — SQL `LIKE` or FTS across `standalone_transcript.text`
- Integrated into the existing search bar pattern

### Smart Chapter Titling

When M4B chapter titles are generic ("Chapter 1", "Track 01"):
- Extract first transcribed sentence of each chapter
- Use as descriptive subtitle: `"Chapter 1 — 'It was the best of times...'"`
- Stored in `chapter` table's existing `title` column if generic
- Falls back to generic title if no transcript yet (chapter not yet transcribed)

### User Controls

"Transcription" row in book settings sheet:
- Status: "Not started" / "Chapter N of M" / "Complete"
- "Start" / "Pause" / "Resume" button
- "Reset Transcription" (destructive, with confirmation)
- "Export Transcript" → plain text / SRT / JSON via ShareLink

### Budget

- 10-hour audiobook ≈ 9,000 transcript segments ≈ 1.8 MB text
- WhisperKit model: already loaded (~40 MB), shared via `WhisperSession`
- Transcription time: ~3–5× realtime on iPhone (30–50 min for 10-hour book)

---

## Cross-Cutting Concerns

### Schema V15

Combined migration for SRS 2.0 + Solo Transcription:
```sql
-- SRS 2.0
ALTER TABLE flashcard ADD COLUMN stability REAL;
ALTER TABLE flashcard ADD COLUMN difficulty REAL;
ALTER TABLE flashcard ADD COLUMN card_type TEXT NOT NULL DEFAULT 'normal';
ALTER TABLE flashcard ADD COLUMN cloze_index INTEGER;
ALTER TABLE deck ADD COLUMN anki_deck_id INTEGER;

-- Solo Transcription
CREATE TABLE standalone_transcript (
    id TEXT PRIMARY KEY,
    audiobook_id TEXT NOT NULL REFERENCES audiobook(id),
    chapter_index INTEGER NOT NULL,
    segment_index INTEGER NOT NULL,
    text TEXT NOT NULL,
    start_time REAL NOT NULL,
    end_time REAL NOT NULL,
    words_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_standalone_transcript_book_time
    ON standalone_transcript(audiobook_id, start_time);
```

### Shared vs. Platform-Specific

| Component | Shared/ | iOS (EchoCore) | macOS | Notes |
|---|---|---|---|---|
| FSRS/SM-2 schedulers | ✓ | | | Pure math, no platform deps |
| Cloze parsing | ✓ | | | String transforms |
| .apkg export/import | ✓ | | | ZIPFoundation + GRDB |
| Auto-draft chapter cards | | ✓ | ✓ | Needs EPUB block DAO |
| Soundscape mixer | | ✓ | (✓) | `AVAudioEngine` available on both; Mac gets basic support |
| Chime player | | ✓ | (✓) | Same |
| Visualizer tap | | ✓ | | Metal shaders are iOS-primary |
| Fidget UI (PencilKit/Metal) | | ✓ | | iOS-only |
| CarPlay manager | | ✓ | | iOS-only |
| Mac tri-pane layout | | | ✓ | Mac-only |
| Bulk alignment | | | ✓ | Mac-only (`NSOpenPanel` + overnight) |
| AnkiConnect bridge | | | ✓ | Mac-only (localhost HTTP) |
| Standalone transcription | ✓ | | | WhisperSession + AudioSegmentReader are already cross-platform |

### New Protocols & Seams

| Protocol | Purpose | Conforms |
|---|---|---|
| `SchedulingAlgorithm` | Card scheduling abstraction | `SM2Scheduler`, `FSRSScheduler` |
| `SoundscapePlaying` | Ambient audio playback | `SoundscapeMixer` (AudioEngine) |
| `ChimeScheduling` | Interval chime firing | `ChimePlayer` (AudioEngine) |
| `VisualizerDataProviding` | Audio spectrum data feed | `VisualizerTap` (AudioEngine) |
| `VisualizerStyle` | Visualizer shader rendering | `AcidWarpStyle`, `WaveformRiverStyle`, etc. |

### Test Strategy

All new logic follows TDD (as established in CLAUDE.md):
- Pure functions first (FSRS math, cloze parsing, transcript assembly, chime interval math)
- Integration tests on in-memory GRDB (apkg import/export, auto-draft cards, standalone transcript read/write)
- UI snapshot tests for visualizer styles (reference images)
- Manual QA gates for CarPlay (requires CarPlay simulator or device) and bulk alignment (long-running)

### Documentation Sync

After implementation:
- `ARCHITECTURE.md` — add SRS 2.0, Sensory Suite services, Mac tri-pane, CarPlay manager, standalone transcription pipeline
- `README.md` — update feature list with all new capabilities
- `MARKETING.md` — move FSRS, cloze, .apkg export, soundscapes, standalone transcription from "planned" to "shipped"
- `ROADMAP.md` — mark v1.0 complete, create v1.1/post-1.0 section for remaining cut features

---

## Cut Lines (Post-1.0)

Features explicitly excluded from this v1.0:

- AnkiConnect **live** sync (file bridge only)
- AI tutor / quiz generator / auto-drafted **content** cards (structural chapter cards only)
- Notion/Evernote API integrations (Markdown export covers Obsidian)
- Gamification beyond streaks (badges, growing tree)
- iPad split-view
- Siri Shortcuts / App Intents
- Widget families beyond current
- Social/sharing features
- EQ settings
- Semantic alignment Phases 1–2
- Location **map** view (place-name list exists)
- Watch stats UI (phone stats exist)
- CarPlay Siri integration beyond existing
- Focus soundscape **upload** (user-provided loops)
- Fidget **sharing** (doodles/generative art export)
