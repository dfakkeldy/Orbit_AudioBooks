# EPUB-Audio Alignment CLI Design

**Status:** Accepted
**Branch:** `feature/epub-audio-alignment`
**Context:** Building an offline Swift CLI tool to align Whisper JSON transcripts with EPUB text to generate an Enhanced Sync Map.

---

## 1. Package Structure & Dependencies

The existing `Tools/OrbitTranscriptionCLI/` gains a new library target `OrbitEPUBAligner` and a new dependency on ZIPFoundation.

```
Tools/OrbitTranscriptionCLI/
├── Package.swift                          # Updated: new target + ZIPFoundation dep
├── Sources/
│   ├── OrbitTranscriptionCLI/             # Existing executable (unchanged)
│   │   ├── OrbitTranscriptionCLI.swift    #   Existing: transcribe subcommand
│   │   ├── AlignCommand.swift             #   NEW: align subcommand (thin, wires args)
│   │   └── TranscriptionCLIEvent.swift    #   Existing (may add align-specific events)
│   └── OrbitEPUBAligner/                  # NEW library target
│       ├── EPUBParsing/
│       │   ├── EPUBUnpacker.swift         #   Unzips .epub to temp dir
│       │   ├── OPFParser.swift            #   Reads content.opf -> spine order
│       │   └── XHTMLParser.swift          #   Strips tags, extracts markers + text
│       ├── Alignment/
│       │   ├── TextAlignmentService.swift #   Protocol: aligns two text sequences
│       │   ├── SlidingWindowAligner.swift #   Hybrid sentence/word alignment
│       │   └── NLPProcessor.swift         #   NLTokenizer wrapper for sentence/word split
│       ├── Markers/
│       │   ├── MarkerInjector.swift       #   Injects EPUB markers into transcript
│       │   └── SyncMarker.swift           #   Marker model (image, heading, chapter, etc.)
│       ├── Models/
│       │   ├── EnhancedTranscriptionSegment.swift  # Extended TranscriptionSegment
│       │   └── EPUBStructure.swift        #   Parsed EPUB spine + content model
│       └── Utils/
│           └── String+Levenshtein.swift   #   Levenshtein distance extension
└── Tests/
    └── OrbitEPUBAlignerTests/             # NEW test target
        ├── Resources/
        │   ├── minimal.epub               #   2-page EPUB with 1 heading, 1 image, 1 paragraph
        │   ├── multi-chapter.epub         #   3 chapters with images and blockquotes
        │   └── fixtures/
        │       ├── whisper_transcript.json
        │       └── expected_enhanced.json
        ├── EPUBUnpackerTests.swift
        ├── XHTMLParserTests.swift
        ├── SlidingWindowAlignerTests.swift
        └── MarkerInjectorTests.swift
```

**New dependency:** `ZIPFoundation` — pure Swift ZIP library. Chosen because `.epub` is a ZIP archive with a required uncompressed `mimetype` first entry, which ZIPFoundation handles correctly.

---

## 2. Data Models

### EnhancedTranscriptionSegment

Extends the existing `Shared/TranscriptionSegment.swift` with optional fields. Existing consumers continue to work with plain segments; EPUB-aligned transcripts carry the optional extras.

```swift
public struct EnhancedTranscriptionSegment: Codable, Identifiable {
    public var id: String { "\(startTime)-\(endTime)" }
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    // nil when no EPUB was provided
    public let markers: [SyncMarker]?
    public let formatting: [TextFormat]?
}
```

### SyncMarker

Structural elements extracted from EPUB XHTML, attached to the transcript segment they temporally align with.

```swift
public struct SyncMarker: Codable, Equatable {
    public let type: MarkerType
    public let payload: String             // e.g. "cover.jpg" for image, "Chapter 1" for heading
    public let epubCharOffset: Int         // Position in the raw EPUB text stream
}

public enum MarkerType: String, Codable {
    case chapterStart
    case image
    case hyperlink
    case blockquote
    case list
    case table
    case footnote
    case horizontalRule
    case emphasis
}
```

### TextFormat

Carries inline formatting that spans a character range within the segment's text.

```swift
public struct TextFormat: Codable, Equatable {
    public let type: FormatType
    public let range: ClosedRange<Int>
}

public enum FormatType: String, Codable {
    case bold
    case italic
    case underline
    case strikethrough
    case superscript
    case smallCaps
}
```

### EPUBStructure (internal, not exported)

```swift
struct EPUBStructure {
    let title: String
    let author: String?
    let spine: [SpineItem]
}

struct SpineItem {
    let id: String
    let href: String                       // Relative path to .xhtml file
    let mediaType: String
    let rawText: String                    // Tag-stripped text
    let markers: [SyncMarker]             // Extracted markers with char offsets
}
```

---

## 3. Alignment Engine

### Strategy: Hybrid sentence-level + word-level fallback

**Pass 1 — Sentence-level (fast path):**
1. Split both EPUB text and Whisper transcript into sentences via `NLTokenizer(unit: .sentence)`
2. Slide a window of 10 Whisper sentences across the EPUB sentences
3. At each position, compute normalized Levenshtein similarity
4. When similarity > 80%, lock the match — emit `AlignmentResult`
5. Continue sliding forward monotonically

**Pass 2 — Word-level fallback (ambiguous regions):**
- Triggered when Pass 1 similarity is < 60% or multiple near-ties exist
- Drops to word-level Levenshtein within a narrow band around the expected position
- More expensive but catches cases like "palace" vs "place" that sentence-level misses

### Protocol interface

```swift
protocol TextAlignmentService {
    func align(
        epubText: String,
        transcript: [TranscriptionSegment]
    ) async throws -> [AlignmentResult]
}

struct AlignmentResult {
    let epubCharRange: ClosedRange<Int>
    let transcriptTimeRange: ClosedRange<TimeInterval>
    let confidence: Double
    let containedMarkers: [SyncMarker]
}
```

### Key constraint

Monotonic alignment — Whisper never scrambles sentence order. The transcript timeline always moves forward, which lets us slide a window in one direction, turning an O(n²) problem into O(n).

---

## 4. EPUB Parsing Pipeline

```
book.epub
    |
    v
EPUBUnpacker.unzip(to: tempDir)
    |  Validates mimetype file is first entry (EPUB spec)
    v
OPFParser.parse()
    |  Reads META-INF/container.xml -> finds content.opf path
    |  Parses <metadata>, <manifest>, <spine>
    v
XHTMLParser.parse(spineItems)    <- parallel per spine item
    |  Strips <script>, <style>, <head>
    |  Walks DOM, emits text + markers + formatting
    v
Concatenated text + marker array -> feeds into SlidingWindowAligner
```

Temp directory cleaned up on process exit via `defer` block.

---

## 5. CLI Subcommand Interface

```bash
orbit-transcription align \
    --epub book.epub \
    --transcript book.transcript.json \
    --output book.enhanced.json

orbit-transcription align \
    --epub book.epub \
    --transcript book.transcript.json \
    --confidence 0.85 \
    --max-window 15 \
    --verbose
```

```swift
struct AlignCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "align",
        abstract: "Align a Whisper transcript with an EPUB to produce an Enhanced Sync Map."
    )

    @Option var epub: String
    @Option var transcript: String
    @Option var output: String?
    @Option var confidence: Double = 0.80
    @Option var maxWindow: Int = 10
    @Flag var verbose: Bool = false
}
```

---

## 6. Error Handling

| Scenario | Behavior |
|---|---|
| EPUB has images but no alt text | Marker uses filename as payload |
| XHTML references missing image | Skip marker, log warning, continue |
| Whisper confidence < 30% globally | Fail with `alignmentFailed` |
| One spine item unparseable | Skip it, log warning, continue |
| EPUB contains DRM | Fail immediately with clear error |

```swift
enum AlignmentError: LocalizedError, Equatable {
    case notAnEPUB(path: String)
    case missingOPF
    case spineEmpty
    case transcriptEmpty(path: String)
    case alignmentFailed(confidence: Double)
    case unsupportedEPUBVersion(String)
    case corruptXHTML(item: String, reason: String)
}
```

---

## 7. Testing Strategy

Tests use real `.epub` fixtures committed to the repo. No mocking of ZIPFoundation or XMLParser — these are fast enough to run directly.

### EPUBUnpackerTests
- `testUnzipValidEPUB` — mimetype, OPF, XHTML extracted
- `testRejectsNonEPUBZip` — plain .zip without mimetype fails
- `testTempDirCleanup` — temp directory removed after parse

### XHTMLParserTests
- `testExtractsImageMarkers` — `<img>` -> SyncMarker(type: .image)
- `testExtractsHeadingMarkers` — `<h1>/<h2>` -> SyncMarker(type: .chapterStart)
- `testPreservesFormatting` — `<em>/<strong>` -> TextFormat spans
- `testStripsScriptTags` — `<script>` content absent from rawText
- `testInlineMarkerPositions` — epubCharOffset correct after tag stripping

### SlidingWindowAlignerTests
- `testPerfectMatch` — identical texts produce 1.0 confidence
- `testSlightDeviation` — Whisper hallucination doesn't break alignment
- `testChapterBoundaryDetection` — chapter markers appear at correct segments
- `testMonotonicOutput` — alignment indices never go backward
- `testEmptyTranscript` — throws transcriptEmpty

### MarkerInjectorTests
- `testMarkerAtExactWord` — marker lands on correct segment
- `testMarkerBetweenSegments` — marker assigned to nearest segment
- `testMultipleMarkersInSegment` — both image + heading in same segment
