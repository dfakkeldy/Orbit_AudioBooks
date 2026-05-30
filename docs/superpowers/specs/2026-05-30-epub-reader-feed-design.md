# EPUB Reader Feed — Design Spec

**Date:** 2026-05-30
**Status:** Design approved, awaiting implementation plan
**Phase:** 5.1 (Dedicated Reader Tab)
**Depends on:** Schema V5 (epub_block, alignment_anchor tables), EPUB import pipeline

---

## Overview

Add a 3rd "Read" tab to the iOS app that renders EPUB content as a vertically-scrolling card feed — each heading, paragraph, and image is its own card ("tweet"). This replaces the traditional book-reader paradigm with a feed-based reader that directly supports the Phase 6 manual alignment workflow.

### Key Design Principles

- **Every block is a card.** Headings, paragraphs, images — each is a discrete, tappable, alignable unit.
- **Every card has a timestamp.** On import, the first and last blocks are anchored to audio start/end. All blocks between are linearly interpolated. Every card is tappable from day one.
- **Manual alignment from the start.** Long-press any card to pin it to the current playback position, a chapter boundary, or 5 seconds ago. The Timeline recalculates around each new anchor.
- **SRS cards are future cards.** The `ReaderCardItem` enum is designed for flashcard cards to be inserted between EPUB blocks later.

---

## 1. Data Layer

### 1.1 Schema V6 Migration

New file: `Shared/Database/Schema_V6.swift`

```sql
ALTER TABLE epub_block ADD COLUMN html_content TEXT;
ALTER TABLE epub_block ADD COLUMN card_color TEXT;
```

- `html_content`: Inner HTML of the block element — inline formatting tags (`<b>`, `<i>`, `<em>`, `<strong>`, `<span>`) preserved, block-level tags stripped. NULL for blocks imported before this migration or blocks with no formatting (images, plain headings).
- `card_color`: Optional per-card background color as a hex string (e.g. `"#FFF8E7"`). NULL means "use the global reader card tint." Set via long-press → Change Color.

### 1.2 EPubBlockRecord Update

Add to `Shared/Database/EPubBlockRecord.swift`:

```swift
var htmlContent: String?
var cardColor: String?
```

With coding keys `"html_content"` and `"card_color"`. Both optional — nil for pre-V6 data.

### 1.3 XHTMLBlockDelegate — Inner HTML Preservation

Modify `EPUBImportService.XHTMLBlockDelegate` to collect inner HTML alongside plain text.

**Current behavior:** `foundCharacters` appends trimmed text to `currentText`. On block end, the plain text is flushed to a `TextBlockDescriptor`.

**New behavior:** A parallel `currentHTML` string collects raw XML content while inside a tracked block element. When the parser encounters `didStartElement` for inline formatting tags (`b`, `i`, `em`, `strong`, `span`, `small`, `sub`, `sup`, `a`), it appends the opening tag with attributes to `currentHTML`. `foundCharacters` appends its raw string (not trimmed) to `currentHTML`. `didEndElement` appends the closing tag. Block-level end tags flush both `currentText` and `currentHTML` into `TextBlockDescriptor`.

`TextBlockDescriptor` gains `var htmlContent: String?`.

The import service writes `htmlContent` to the new `EPubBlockRecord.htmlContent` field.

**Inline tags preserved:** `b`, `i`, `em`, `strong`, `span`, `small`, `sub`, `sup`, `a`, `br`
**Block tags (define card boundaries, excluded from inner HTML):** `p`, `div`, `h1`-`h6`, `blockquote`, `li`, `section`

### 1.4 EPubBlockDAO Additions

Add to `Shared/Database/DAOs/EPubBlockDAO.swift`:

```swift
/// Blocks grouped by chapter index. Blocks without a chapter index go in bucket -1.
func blocksByChapter(for audiobookID: String) throws -> [Int: [EPubBlockRecord]]

/// Find the EPUB block ID at a given audio time. Joins epub_block → timeline_item
/// on epub_block_id. Returns nil if no block covers this time.
func blockID(at time: TimeInterval, audiobookID: String) throws -> String?

/// Update a single block's card color.
func setCardColor(_ color: String?, blockID: String) throws
```

`blockID(at:)` queries:
```sql
SELECT epub_block.id FROM epub_block
JOIN timeline_item ON timeline_item.epub_block_id = epub_block.id
WHERE epub_block.audiobook_id = ?
  AND timeline_item.audio_start_time <= ?
  AND timeline_item.audio_end_time > ?
ORDER BY epub_block.sequence_index
LIMIT 1
```

### 1.5 Initial Anchors on Import

After `EPUBImportService.import(...)` completes, the caller (`EPUBAutoImportScanner` or `PlayerModel`) runs an initialization step:

1. Create anchor: first block → `audio_time = 0`
2. Create anchor: last block → `audio_time = totalDuration`
3. Call `AlignmentService.recalculateTimeline(audiobookID:)` to interpolate all blocks between

The two system anchors use `source: .imported` so the UI can distinguish them from user-created anchors if needed.

### 1.6 AlignmentService.recalculateTimeline

Implement the existing stub in `OrbitAudioBooks/Services/AlignmentService.swift`:

```
Algorithm:
  1. Collect all anchors for the audiobook, sorted by audio_time.
  2. Collect all epub_blocks, sorted by sequence_index.
  3. For each pair of consecutive anchors (A, B):
     a. Find all blocks whose sequence_index falls between A's block and B's block.
     b. Linearly interpolate timestamps: assign each block an audio_start_time
        proportional to its position between the two anchors.
     c. For the last block in each gap, audio_end_time = next anchor's audio_time.
     d. Upsert timeline_item rows for each block (INSERT if no row exists for the
        epub_block_id, UPDATE if one already exists). Every block gets a row.
  4. Blocks before the first anchor: extrapolate backward from first anchor.
  5. Blocks after the last anchor: extrapolate forward from last anchor.

After recalculateTimeline runs, every epub_block has a corresponding timeline_item
row with epub_block_id set. This is what makes every card tappable. Before the
initial import runs this step, blocks have no timeline rows — the reader handles
this brief window by hiding the active-block highlight and allowing scroll without
seek until interpolation completes.
```

---

## 2. Navigation

### 2.1 TabSelection Enum

New file: `Shared/TabSelection.swift`

```swift
enum TabSelection: String, CaseIterable {
    case nowPlaying
    case read
    case timeline
}
```

### 2.2 RootTabView Changes

Replace `@State var showingTimeline: Bool` with `@State var selectedTab: TabSelection = .nowPlaying`.

The body switches on `selectedTab`:

```swift
case .nowPlaying:
    NowPlayingTab()
case .read:
    if model.hasEPUB, let folderURL = model.folderURL {
        ReaderTab(folderURL: folderURL)
    } else {
        ReaderEmptyState()
    }
case .timeline:
    TimelineTab(...)
```

The bottom toolbar with tab selector uses three buttons (or a segmented picker). The Read tab button shows a book icon and is disabled (grayed, shows explanatory toast) when `!model.hasEPUB`.

The `PlayerControlBar` and `BottomToolbarView` remain in the `ZStack` overlay, visible across all three tabs when audio is loaded — same as current behavior.

### 2.3 PlayerModel Changes

- Replace `@Published var showingTimeline: Bool` with `@Published var selectedTab: TabSelection`
- Expose `var duration: TimeInterval` (computed from chapters last end time) — needed for initial anchor creation

---

## 3. Reader Tab View Hierarchy

### 3.1 File Tree (new files)

```
OrbitAudioBooks/
├── Views/
│   ├── ReaderTab.swift                    ← root view for the Read tab
│   ├── ReaderHeaderView.swift             ← search bar + chapter title + settings button
│   ├── ReaderFeedCollectionView.swift     ← UIViewRepresentable wrapping UICollectionView
│   ├── ReaderSettingsSheet.swift          ← font size/spacing/color settings
│   ├── ChapterPickerSheet.swift           ← chapter list for "Align to Chapter" action
│   └── Cells/
│       ├── HeadingCardCell.swift          ← heading card (larger font, prominent bg)
│       ├── ParagraphCardCell.swift        ← paragraph/sentence card (UITextView for HTML)
│       ├── ImageCardCell.swift            ← image card (async UIImageView)
│       └── ChapterDividerCell.swift       ← thin chapter separator
├── ViewModels/
│   └── ReaderFeedViewModel.swift          ← data source, search, position tracking
└── Services/
    └── (AlignmentService.swift modified)  ← recalculateTimeline implementation
```

### 3.2 ReaderTab

The root view for the Read tab. Responsibilities:
- Own the `ReaderFeedViewModel`
- Host the `ReaderHeaderView` + `ReaderFeedCollectionView`
- Present `ReaderSettingsSheet` and `ChapterPickerSheet`
- Observe `PlayerModel.currentPosition` for active block tracking
- Route alignment actions to `AlignmentService`

### 3.3 ReaderFeedViewModel

`@Observable` class. Responsibilities:
- Load blocks via `EPubBlockDAO` grouped by chapter
- Build `[ReaderCardItem]` array with chapter divider cards inserted between chapters
- Filter by search query (delegates to `EPubBlockDAO.searchBlocks`)
- Track `activeBlockID` (recomputed on position change, throttled to 1 Hz)
- Expose `performAlignment(blockID:to:source:)` for context menu actions

### 3.4 ReaderCardItem Enum

```swift
enum ReaderCardItem: Hashable {
    case chapterHeader(title: String, chapterIndex: Int)
    case block(EPubBlockRecord)
    // Future: case flashcard(Flashcard, associatedBlockIDs: [String], placement: FlashcardPlacement)
}
```

Chapter headers are synthetic dividers inserted when `chapterIndex` changes between consecutive blocks. The chapter title is resolved by looking up the `Chapter` record with matching `chapterIndex` (via `ChapterDAO`). If no match is found, a fallback label of "Chapter N" is shown where N is `chapterIndex + 1`. Chapter divider cards are not interactive.

### 3.5 ReaderFeedCollectionView

`UIViewRepresentable` wrapping `UICollectionView` with `UICollectionViewCompositionalLayout`.

**Layout:** Vertical scrolling. Each card is a full-width item with horizontal insets. Estimated item height with `.estimated` for self-sizing cells (paragraph cards with `UITextView` determine their own height).

**Data source:** `UICollectionViewDiffableDataSource<Section, ReaderCardItem>` with a single section.

**Cell registration:** 4 cell types registered by reuse identifier.

**Context menus:** `UICollectionViewDelegate.contextMenuConfigurationForItemAt` returns `UIContextMenuConfiguration` with alignment actions.

**Active block highlight:** `cellForItemAt` reads `viewModel.activeBlockID` and sets `isActiveBlock` on the cell.

**Scroll on position change:** `scrollToItem(at:at:animated:)` with `.centeredVertically` when `activeBlockID` changes and the user hasn't manually scrolled recently (same follow-state pattern as Timeline feed: auto-scroll disengages on user scroll, re-engages after a tripwire).

### 3.6 ReaderEmptyState

`ContentUnavailableView` with:
- Title: "No EPUB Available"
- System image: `"book.pages"`
- Description: "Import an EPUB file alongside your audiobook to enable reading."
- Optional action button: "Import EPUB" (if folder is loaded, triggers file picker)

---

## 4. Card Cells

### 4.1 HeadingCardCell

`UICollectionViewCell` subclass.

- Font: `.title3` weight `.semibold`, applied via `UIFont.custom(appFont, size: resolvedFontSize + 2)`
- Background: `cardTintColor.withAlphaComponent(0.15)`
- Active state: left border bar (3pt blue) + background alpha boost
- Padding: 14pt all sides
- Corner radius: 12pt

### 4.2 ParagraphCardCell

`UICollectionViewCell` subclass containing a `UITextView`.

- `UITextView` is non-editable, non-selectable (by default; selection can be enabled in a future "copy text" feature)
- Content: `NSAttributedString` from `htmlContent` (preferred) or plain `text` (fallback for pre-V6 data)
- Font: `.body` applied via `UIFont.custom(appFont, size: resolvedFontSize)`
- Background: `cardTintColor.withAlphaComponent(0.08)`
- Active state: left border bar (3pt blue) + background alpha boost to 0.12
- Line spacing: applied via `NSMutableParagraphStyle.lineSpacing`
- Padding: 14pt all sides
- Corner radius: 12pt

**HTML → NSAttributedString conversion:**
```swift
let html = block.htmlContent ?? block.text ?? ""
let data = Data(html.utf8)
let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
    .documentType: NSAttributedString.DocumentType.html,
    .characterEncoding: String.Encoding.utf8.rawValue
]
let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
```

The `UITextView` is sized intrinsically — `isScrollEnabled = false` so it reports its full content height to Auto Layout. The compositional layout uses `.estimated(200)` height and the cell self-sizes.

### 4.3 ImageCardCell

`UICollectionViewCell` subclass containing a `UIImageView`.

- Image loaded asynchronously from `EPUBAssetStorage` local path
- Max height: 300pt, aspect-fit scaling
- Below the image: optional caption (alt text from `epub_block.text`)
- Background: `cardTintColor.withAlphaComponent(0.05)`
- Corner radius: 12pt
- Tapping the image presents it fullscreen in a system image viewer (future enhancement)

### 4.4 ChapterDividerCell

Simple divider between chapter groups. Thin horizontal line or a pill-shaped "Chapter N" label. Not interactive. Not affected by the card tint (transparent background, always centered).

---

## 5. Reader Settings

### 5.1 New Storage

**Per-book overrides** (in `BookPreferencesService`, stored in `UserDefaults`):

| Key pattern | Type | Default | Description |
|---|---|---|---|
| `book_readerFontSize_{id}` | `Double` | nil (inherit global) | Font size in points |
| `book_readerLineSpacing_{id}` | `Double` | nil (inherit global) | Line height multiplier |
| `book_readerCardTint_{id}` | `String` | nil (inherit global) | Hex color string |

**Global defaults** (in `SettingsManager.Defaults`):

```swift
static let readerFontSize: Double = 17.0
static let readerLineSpacing: Double = 1.4
static let readerCardTint: String = "#F5F0E8"
```

### 5.2 ReaderSettings Observable

New file: `Shared/ReaderSettings.swift`

```swift
@Observable
final class ReaderSettings {
    var fontSize: Double
    var lineSpacing: Double
    var cardTintHex: String

    var cardTintColor: UIColor {
        UIColor(hex: cardTintHex) ?? UIColor.systemBackground
    }

    // Resolution: per-book override > global default
    static func resolved(fontSizeOverride: Double?, lineSpacingOverride: Double?,
                         cardTintOverride: String?, globalFontSize: Double,
                         globalLineSpacing: Double, globalCardTint: String) -> ReaderSettings
}
```

### 5.3 ReaderSettingsSheet

`NavigationStack` sheet with sections:

1. **Font Family** — 3-button picker (Lexend / OpenDyslexic / System). Reuses `SettingsManager.appFont`.
2. **Font Size** — `Stepper` 12–28pt, ±1. Live preview text below: "The quick brown fox jumps over the lazy dog."
3. **Line Spacing** — `Slider` 1.0–2.5, step 0.1. Same live preview.
4. **Card Tint** — Horizontal scroll of 8 color swatches, each a 44pt filled circle: Sepia (`#F5F0E8`), Cream (`#FFF8E7`), White (`#FFFFFF`), Light Gray (`#F0F0F0`), Dark (`#2C2C2C`), Black (`#000000`), Soft Green (`#E8F5E9`), Soft Blue (`#E3F2FD`). Selected swatch has a checkmark overlay. When Dark/Black is selected, text color inverts to white.
5. **Reset to Defaults** — restores all four settings to global defaults.

A `.toolbar` "Done" button dismisses.

### 5.4 Per-Card Color Override

When a user long-presses a card and selects "Change Color," a color picker (or the same swatch grid) appears. Selected color is written to `EPubBlockRecord.card_color` via `EPubBlockDAO.setCardColor`. The cell reloads showing the per-card override. A "Reset to Default" option clears `card_color` back to NULL.

---

## 6. Long-Press Context Menu

### 6.1 Menu Structure

**Chapter heading card (`blockKind == .heading`):**
```
Change Color       🎨
Align to Now       📍
Align to 5s Ago    ⏪
Align to Chapter   📖
```

**Paragraph / Image card:**
```
Change Color       🎨
Align to Now       📍
Align to 5s Ago    ⏪
```

### 6.2 Action Implementations

All alignment actions follow the same pattern:

```swift
func alignBlock(blockID: String, to time: TimeInterval, source: AlignmentAnchorRecord.Source) throws {
    let anchor = AlignmentAnchorRecord(
        id: UUID().uuidString,
        audiobookID: audiobookID,
        epubBlockID: blockID,
        audioTime: time,
        anchorKind: .point,
        source: source.rawValue
    )
    try anchorDAO.upsert(anchor)
    try alignmentService.recalculateTimeline(audiobookID: audiobookID)
    // Refresh timeline_items in the database
    // Feed view model reloads and cards reflect updated timestamps
}
```

- **Align to Now:** `time = model.currentPosition` (current playback position, works paused or playing)
- **Align to 5s Ago:** `time = max(0, model.currentPosition - 5.0)`
- **Align to Chapter:** Presents `ChapterPickerSheet`. On selection, `time = chapter.startSeconds`. Source: `.chapterBoundary`.

### 6.3 ChapterPickerSheet

A sheet showing the audiobook's chapter list (filtered from `PlaylistView`, showing only chapters — tracks with chapter markers). Each row shows:
- Chapter title
- Start time formatted as `MM:SS`
- The track/chapter artwork thumbnail

Tapping a row sets the anchor to `chapter.startSeconds` and dismisses the sheet. Uses the same data source as `PlaylistView` but simplified — no reordering, no toggles.

### 6.4 Change Color Action

Presents a compact color picker overlay (the same 8-swatch grid from `ReaderSettingsSheet`). On selection, writes to `EPubBlockRecord.cardColor`. The cell reloads with the per-card color. "Reset to Default" option at the bottom clears the override.

---

## 7. Tap-to-Seek

Tapping a card seeks audio to the block's timestamp. Flow:

1. `collectionView(_:didSelectItemAt:)` fires
2. Get `ReaderCardItem` for the index path
3. Extract `block.epubBlockID`
4. Query `TimelineDAO` for `timeline_item` with matching `epub_block_id`
5. If found → `PlaybackController.seek(to: timelineItem.audioStartTime)`
6. After `recalculateTimeline` runs, every block has a `timeline_item` row — tap always works

No special handling needed for ChapterDivider cells — they are not selectable.

---

## 8. Reading Position Sync

### 8.1 Active Block Computation

`ReaderFeedViewModel` exposes `@Published var activeBlockID: String?`. On each position change from `PlayerModel` (throttled to 1 Hz):

```swift
activeBlockID = try? blockDAO.blockID(at: currentPosition, audiobookID: audiobookID)
```

### 8.2 Highlight Application

`ReaderFeedCollectionView` observes `viewModel.$activeBlockID`. When it changes:

1. Find the index path of the old active block → reload that cell (removes highlight)
2. Find the index path of the new active block → reload that cell (adds highlight)
3. If the new active block is not visible → `scrollToItem(at:at:animated:)` with `.centeredVertically`

### 8.3 Follow State

Same pattern as `TimelineFeedCollectionView`:
- Default: follow mode ON (auto-scroll to active block)
- User manually scrolls → follow mode OFF, "Go to Current" floating button appears
- 5-second tripwire after scroll stops → follow mode re-engages

### 8.4 Offline Reading

When no audio is playing (`model.playbackState == .stopped` and no folder loaded), no highlight is shown. The feed is fully scrollable and all blocks render at normal opacity. Reading works without audio entirely.

---

## 9. Search

### 9.1 Search Bar

In `ReaderHeaderView`: a search field (`TextField` with magnifying glass icon, or a `UISearchBar` bridged via `UIViewRepresentable`).

### 9.2 Search Behavior

On submit, calls `EPubBlockDAO.searchBlocks(for:audiobookID:query:)`. Results replace the normal chapter-grouped feed with a flat filtered feed — same card styles, same interaction model. A "×" clear button restores the full feed.

### 9.3 Search + Alignment Workflow

1. User hears a distinctive phrase in the audio
2. Taps the Read tab, types the phrase in search
3. Matching cards appear as a filtered feed
4. User long-presses the correct card → "Align to Now" (or "Align to 5s Ago")
5. Anchor written, timeline recalculated
6. Clear search, continue reading with improved alignment

---

## 10. SRS Card Extensibility

The `ReaderCardItem` enum and card-based feed are designed to accommodate future inline SRS cards without layout changes:

- **Flashcard case:** `case flashcard(Flashcard, associatedBlockIDs: [String], placement: FlashcardPlacement)` — added to the enum when Phase 5.2 begins.
- **Sorting:** SRS cards use `sequenceIndex` of their nearest associated block, with a sub-offset (`-0.5` for `.beginning`, `+0.5` for `.end`) to position before/after the block range.
- **Cell type:** A new `FlashcardCardCell` registered in the collection view, rendered with a distinct tint and badge.
- **No feed layout changes needed.** The `[ReaderCardItem]` array is rebuilt when flashcards are added or removed.

---

## 11. File Manifest

### New Files (13)

| File | Location | Purpose |
|---|---|---|
| `TabSelection.swift` | `Shared/` | 3-tab navigation enum |
| `Schema_V6.swift` | `Shared/Database/` | Migration: html_content, card_color |
| `ReaderSettings.swift` | `Shared/` | Observable settings object |
| `ReaderCardItem.swift` | `OrbitAudioBooks/Models/` | Feed card enum |
| `ReaderTab.swift` | `OrbitAudioBooks/Views/` | Read tab root view |
| `ReaderHeaderView.swift` | `OrbitAudioBooks/Views/` | Search + navigation |
| `ReaderFeedCollectionView.swift` | `OrbitAudioBooks/Views/` | UICollectionView wrapper |
| `ReaderFeedViewModel.swift` | `OrbitAudioBooks/ViewModels/` | Data source + state |
| `ReaderSettingsSheet.swift` | `OrbitAudioBooks/Views/` | Settings modal |
| `ChapterPickerSheet.swift` | `OrbitAudioBooks/Views/` | Chapter picker modal |
| `HeadingCardCell.swift` | `OrbitAudioBooks/Views/Cells/` | Heading card cell |
| `ParagraphCardCell.swift` | `OrbitAudioBooks/Views/Cells/` | Paragraph card cell |
| `ImageCardCell.swift` | `OrbitAudioBooks/Views/Cells/` | Image card cell |

### Modified Files (9)

| File | Change |
|---|---|
| `EPubBlockRecord.swift` | Add `htmlContent`, `cardColor` |
| `EPubBlockDAO.swift` | Add `blocksByChapter`, `blockID(at:)`, `setCardColor` |
| `EPUBImportService.swift` | Preserve inner HTML in XHTMLBlockDelegate; add `htmlContent` to `TextBlockDescriptor` |
| `EPUBAutoImportScanner.swift` | Initial anchor creation + recalculateTimeline after import |
| `AlignmentService.swift` | Implement `recalculateTimeline` |
| `BookPreferencesService.swift` | Reader font/size/spacing/tint keys |
| `SettingsManager.swift` | Global reader defaults |
| `RootTabView.swift` | Boolean → TabSelection, 3rd tab, Read tab routing |
| `PlayerModel.swift` | TabSelection state, expose `duration` |

---

## 12. Implementation Order

| Step | What | Why First |
|---|---|---|
| 1 | Schema V6 + EPubBlockRecord + XHTMLBlockDelegate | Foundation — all rendering depends on data |
| 2 | AlignmentService.recalculateTimeline + initial anchors | Makes every block tappable from day one |
| 3 | TabSelection + RootTabView + PlayerModel changes | Navigation — users can reach the reader |
| 4 | ReaderCardItem + ReaderFeedViewModel | Data source for the feed |
| 5 | ReaderFeedCollectionView + Card Cells | Visual rendering |
| 6 | ReaderHeaderView + Search | Navigation within the reader |
| 7 | Long-press context menu + ChapterPickerSheet | Alignment interactions |
| 8 | Reading position sync + follow state | Highlight + auto-scroll |
| 9 | ReaderSettingsSheet + per-card color | User customization |
| 10 | ReaderEmptyState | Polish for non-EPUB users |

---

## 13. Out of Scope (Deferred)

- Auto-alignment from transcription pipeline (use manual alignment only)
- SRS flashcard cards in the reader feed (Phase 5.2+)
- Image fullscreen viewer on tap (use system share sheet or defer)
- Text selection / copy within paragraph cards (can be enabled later)
- Horizontal page-flipping (vertical scroll feed only)
- iPad multi-column reader layout (uses same card feed, scaled)
- watchOS or macOS reader (iOS only for Phase 5.1)
