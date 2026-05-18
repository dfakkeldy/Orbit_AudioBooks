# SQL Database Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace UserDefaults/JSON persistence with a unified SQL database (GRDB.swift) storing all five item types — tracks, chapters, bookmarks, flashcards, transcription segments — accessible from iOS, macOS, watchOS, and Widget targets via the App Group container.

**Architecture:** GRDB `DatabasePool` in WAL mode inside the App Group container. Lightweight DAOs (one per table) take `DatabaseWriter` protocol for testability. A `timeline` SQL VIEW unions all five item types for unified filtering and reordering.

**Tech Stack:** GRDB.swift (SPM), SQLite 3, WAL mode, FTS5 full-text search, Swift Observation

**Dependencies:** Completed A1 (PlayerModel decomposition) — DAOs replace `BookmarkStore` and `Persistence`.

---

### Phase 1: Foundation

### Task 1: Add GRDB SPM Dependency

**Files:**
- Modify: `Orbit Audiobooks.xcodeproj/project.pbxproj` (via Xcode SPM)

- [x] **Step 1: Add GRDB to Xcode project**

In Xcode: File → Add Package Dependencies → `https://github.com/groue/GRDB.swift.git`

Select version: `7.x` (latest 7.x)
Add to targets: Orbit Audiobooks (iOS), Orbit Audiobooks macOS, Orbit Audiobooks Watch App, Orbit Audiobooks WidgetExtension

- [x] **Step 2: Verify dependency resolves**

Run:
```bash
xcodebuild -resolvePackageDependencies -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks"
```
Expected: No errors about package resolution.

- [x] **Step 3: Verify import compiles on all targets**

Add a temporary `import GRDB` to a file in each target and build:

```bash
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks macOS" -destination 'platform=macOS' -quiet
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks Watch App" -destination 'generic/platform=watchOS Simulator' -quiet
```

Remove the temporary import after verification.

- [x] **Step 4: Commit**

```bash
git add "Orbit Audiobooks.xcodeproj/project.pbxproj" "Orbit Audiobooks.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
git commit -m "build: add GRDB.swift SPM dependency"
```

---

### Task 2: Create Schema Migration (V1)

**Files:**
- Create: `Shared/Database/Schema_V1.swift`

- [x] **Step 1: Create Shared/Database directory**

```bash
mkdir -p Shared/Database/DAOs
```

- [x] **Step 2: Write Schema_V1.swift**

```swift
import GRDB

/// V1 schema — creates all tables, views, and FTS5 indexes for the unified timeline.
enum Schema_V1 {
    static func migrate(_ db: Database) throws {
        // ── Foundation ──
        try db.create(table: "audiobook") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("author", .text)
            t.column("duration", .double).notNull()
            t.column("file_count", .integer)
            t.column("added_at", .text).notNull().defaults(to: sql: "datetime('now')")
        }

        // ── Item types ──
        try db.create(table: "track") { t in
            t.column("id", .text).primaryKey()
            t.column("audiobook_id", .text).notNull().references("audiobook", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("duration", .double).notNull()
            t.column("file_path", .text).notNull()
            t.column("is_enabled", .boolean).notNull().defaults(to: true)
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            t.column("playlist_position", .double)
        }

        try db.create(table: "chapter") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("audiobook_id", .text).notNull().references("audiobook", onDelete: .cascade)
            t.column("title", .text).notNull()
            t.column("start_seconds", .double).notNull()
            t.column("end_seconds", .double).notNull()
            t.column("is_enabled", .boolean).notNull().defaults(to: true)
            t.column("sort_order", .integer).notNull()
            t.column("playlist_position", .double)
        }

        try db.create(table: "bookmark") { t in
            t.column("id", .text).primaryKey()
            t.column("audiobook_id", .text).notNull().references("audiobook", onDelete: .cascade)
            t.column("track_id", .text).references("track")
            t.column("title", .text).notNull()
            t.column("media_timestamp", .double).notNull()
            t.column("note", .text)
            t.column("voice_memo_path", .text)
            t.column("image_path", .text)
            t.column("is_enabled", .boolean).notNull().defaults(to: true)
            t.column("playlist_position", .double)
            t.column("created_at", .text).notNull().defaults(to: sql: "datetime('now')")
            t.column("modified_at", .text).notNull().defaults(to: sql: "datetime('now')")
        }

        try db.create(table: "flashcard") { t in
            t.column("id", .text).primaryKey()
            t.column("audiobook_id", .text).notNull().references("audiobook", onDelete: .cascade)
            t.column("front_text", .text).notNull()
            t.column("back_text", .text).notNull()
            t.column("media_timestamp", .double).notNull()
            t.column("end_timestamp", .double)
            t.column("trigger_timing", .text).notNull().defaults(to: "beginning")
            // SM-2
            t.column("next_review_date", .text)
            t.column("interval_days", .integer).notNull().defaults(to: 0)
            t.column("ease_factor", .double).notNull().defaults(to: 2.5)
            t.column("repetitions", .integer).notNull().defaults(to: 0)
            t.column("last_reviewed_at", .text)
            t.column("last_grade", .integer)
            //
            t.column("is_enabled", .boolean).notNull().defaults(to: true)
            t.column("playlist_position", .double)
            t.column("created_at", .text).notNull().defaults(to: sql: "datetime('now')")
            t.column("modified_at", .text).notNull().defaults(to: sql: "datetime('now')")
        }

        try db.create(table: "transcription_segment") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("audiobook_id", .text).notNull().references("audiobook", onDelete: .cascade)
            t.column("start_time", .double).notNull()
            t.column("end_time", .double).notNull()
            t.column("text", .text).notNull()
        }

        try db.create(virtualTable: "transcription_fts", using: FTS5()) { t in
            t.synchronize(withTable: "transcription_segment")
            t.column("text")
        }

        try db.create(table: "transcription_word") { t in
            t.column("segment_id", .integer).notNull().references("transcription_segment", onDelete: .cascade)
            t.column("word", .text).notNull()
            t.column("start_time", .double).notNull()
            t.column("end_time", .double).notNull()
            t.column("position", .integer).notNull()
        }

        // ── Real-world time ──
        try db.create(table: "playback_event") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("audiobook_id", .text).notNull().references("audiobook", onDelete: .cascade)
            t.column("track_id", .text).references("track")
            t.column("started_at", .text).notNull()
            t.column("ended_at", .text)
            t.column("start_position", .double).notNull()
            t.column("end_position", .double)
            t.column("speed", .double).notNull().defaults(to: 1.0)
            t.column("event_type", .text).notNull().defaults(to: "play")
            t.column("source", .text)
        }

        // ── Supporting ──
        try db.create(table: "playback_state") { t in
            t.column("audiobook_id", .text).primaryKey().references("audiobook", onDelete: .cascade)
            t.column("last_position", .double).notNull().defaults(to: 0)
            t.column("speed", .double).notNull().defaults(to: 1.0)
            t.column("last_played_at", .text)
        }

        try db.create(table: "settings") { t in
            t.column("key", .text).primaryKey()
            t.column("value", .text).notNull()
        }

        // ── Unified timeline view ──
        try db.execute(sql: """
            CREATE VIEW timeline AS
            SELECT id, audiobook_id, 'track' AS item_type, title, NULL AS subtitle,
                   sort_order AS media_timestamp, is_enabled, playlist_position,
                   NULL AS created_at, NULL AS modified_at
            FROM track
            UNION ALL
            SELECT CAST(id AS TEXT), audiobook_id, 'chapter' AS item_type, title, NULL AS subtitle,
                   start_seconds AS media_timestamp, is_enabled, playlist_position,
                   NULL AS created_at, NULL AS modified_at
            FROM chapter
            UNION ALL
            SELECT id, audiobook_id, 'bookmark' AS item_type, title, note AS subtitle,
                   media_timestamp, is_enabled, playlist_position, created_at, modified_at
            FROM bookmark
            UNION ALL
            SELECT id, audiobook_id, 'flashcard' AS item_type, front_text AS title, back_text AS subtitle,
                   media_timestamp, is_enabled, playlist_position, created_at, modified_at
            FROM flashcard
            UNION ALL
            SELECT CAST(id AS TEXT), audiobook_id, 'transcription' AS item_type, text AS title, NULL AS subtitle,
                   start_time AS media_timestamp, 1 AS is_enabled, NULL AS playlist_position,
                   NULL AS created_at, NULL AS modified_at
            FROM transcription_segment
            """)

        // ── Indexes ──
        try db.create(index: "idx_bookmark_audiobook", on: "bookmark", columns: ["audiobook_id", "media_timestamp"])
        try db.create(index: "idx_flashcard_due", on: "flashcard", columns: ["next_review_date"])
        try db.create(index: "idx_transcription_segment_audiobook", on: "transcription_segment", columns: ["audiobook_id", "start_time"])
        try db.create(index: "idx_playback_event_audiobook", on: "playback_event", columns: ["audiobook_id", "started_at"])
    }
}
```

- [x] **Step 3: Commit**

```bash
git add Shared/Database/Schema_V1.swift
git commit -m "feat(db): add V1 schema migration with unified timeline view"
```

---

### Task 3: Create DatabaseService

**Files:**
- Create: `Shared/Database/DatabaseService.swift`

- [x] **Step 1: Write DatabaseService.swift**

```swift
import Foundation
import GRDB
import os.log

/// Owns the GRDB DatabasePool in WAL mode. Lives in the App Group container
/// so iOS, watchOS, macOS, and Widget targets all share the same database.
@Observable
final class DatabaseService {
    private let pool: DatabasePool
    let dbPath: String
    private let logger = Logger(subsystem: "com.orbitaudiobooks", category: "DatabaseService")

    /// Whether the UserDefaults → SQL migration has run.
    @ObservationIgnored private let migrationFlag = "sql_migration_done"

    init(appGroupIdentifier: String = "group.com.orbitaudiobooks") throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("App Group container not found. Check entitlements.")
        }

        // Ensure the database directory exists.
        try FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )

        let path = containerURL.appendingPathComponent("orbit.sqlite").path
        self.dbPath = path

        pool = try DatabasePool(path: path, configuration: {
            var config = Configuration()
            config.prepareDatabase { db in
                // WAL mode for concurrent reads across processes.
                try db.execute(sql: "PRAGMA journal_mode=WAL")
                // Enable foreign keys.
                try db.execute(sql: "PRAGMA foreign_keys=ON")
            }
            return config
        }())

        try runMigrations()
        logger.info("Database opened at \(path)")
    }

    /// Initializer for testing — uses an in-memory database.
    init(inMemory: Void) throws {
        self.pool = try DatabasePool(configuration: {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys=ON")
            }
            return config
        }())
        self.dbPath = ":memory:"
        try runMigrations()
    }

    // MARK: - Accessors

    /// Synchronous read. Use for queries that return quickly.
    func read<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        try pool.read(block)
    }

    /// Asynchronous read. Use from @MainActor contexts that shouldn't block.
    func readAsync<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await pool.read(block)
    }

    /// Synchronous write. Use when the caller is already off the main thread,
    /// or for very fast writes.
    func write<T>(_ block: @escaping (Database) throws -> T) throws -> T {
        try pool.write(block)
    }

    /// Asynchronous write. Preferred for all writes from @MainActor.
    func writeAsync<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await pool.write(block)
    }

    /// Returns a DatabaseWriter for DAO injection in tests.
    var writer: DatabaseWriter { pool }

    // MARK: - Migrations

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_schema") { db in
            try Schema_V1.migrate(db)
        }
        try migrator.migrate(pool)
    }

    // MARK: - UserDefaults migration flag

    var isMigrationDone: Bool {
        get { UserDefaults.standard.bool(forKey: migrationFlag) }
        set { UserDefaults.standard.set(newValue, forKey: migrationFlag) }
    }
}
```

- [x] **Step 2: Add DatabaseService as environment object in iOS app entry point**

In `OrbitAudioBooks/Orbit_AudioBooksApp.swift`, add:

```swift
@State private var databaseService: DatabaseService?

// In body, before the ContentView:
.environment(databaseService)
// Wrap in a task that initializes the DB:
.task {
    databaseService = try? DatabaseService()
}
```

- [x] **Step 3: Build to verify**

```bash
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: Build succeeds. No errors.

- [x] **Step 4: Commit**

```bash
git add Shared/Database/DatabaseService.swift OrbitAudioBooks/Orbit_AudioBooksApp.swift
git commit -m "feat(db): add DatabaseService with WAL-mode DatabasePool"
```

---

### Phase 2: Data Access Objects

### Task 4: Create TimelineItem Model + TimelineDAO

**Files:**
- Create: `Shared/Database/TimelineItem.swift`
- Create: `Shared/Database/DAOs/TimelineDAO.swift`

- [x] **Step 1: Write TimelineItem.swift**

```swift
import Foundation

enum TimelineItemType: String, Codable {
    case track, chapter, bookmark, flashcard, transcription
}

/// A unified row from the timeline VIEW. Represents any of the five item types
/// sorted by playlist_position (user order) or media_timestamp (book position).
struct TimelineItem: Identifiable, Equatable {
    let id: String
    let audiobookID: String
    let itemType: TimelineItemType
    let title: String
    let subtitle: String?
    let mediaTimestamp: TimeInterval
    let isEnabled: Bool
    let playlistPosition: TimeInterval?
    let createdAt: String?
    let modifiedAt: String?

    /// The effective sort key: user's custom order first, media position as fallback.
    var effectivePosition: TimeInterval {
        playlistPosition ?? mediaTimestamp
    }
}

extension TimelineItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, audiobookID = "audiobook_id", itemType = "item_type"
        case title, subtitle, mediaTimestamp = "media_timestamp"
        case isEnabled = "is_enabled", playlistPosition = "playlist_position"
        case createdAt = "created_at", modifiedAt = "modified_at"
    }
}

extension TimelineItem: FetchableRecord, TableRecord {
    static let databaseTableName = "timeline"
}
```

- [x] **Step 2: Write TimelineDAO.swift**

```swift
import Foundation
import GRDB

/// Queries the unified timeline VIEW. Filtering happens in SQL, not Swift.
struct TimelineDAO {
    let db: DatabaseWriter

    /// All items for an audiobook, sorted by user order (playlist_position)
    /// falling back to media position.
    func items(for audiobookID: String) throws -> [TimelineItem] {
        try db.read { db in
            try TimelineItem
                .filter(Column("audiobook_id") == audiobookID)
                .order(
                    Column("playlist_position") ?? Column("media_timestamp"),
                    Column("media_timestamp")
                )
                .fetchAll(db)
        }
    }

    /// Filtered by one or more item types.
    func items(
        for audiobookID: String,
        types: Set<TimelineItemType>
    ) throws -> [TimelineItem] {
        try db.read { db in
            try TimelineItem
                .filter(Column("audiobook_id") == audiobookID)
                .filter(types.contains(.track))      // … handled by IN clause below
                .filter(types.map(\.rawValue).contains(Column("item_type")))
                .order(
                    Column("playlist_position") ?? Column("media_timestamp")
                )
                .fetchAll(db)
        }
    }

    /// Items within a time range.
    func items(
        for audiobookID: String,
        from startTime: TimeInterval,
        to endTime: TimeInterval
    ) throws -> [TimelineItem] {
        try db.read { db in
            try TimelineItem
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("media_timestamp") >= startTime)
                .filter(Column("media_timestamp") <= endTime)
                .order(Column("media_timestamp"))
                .fetchAll(db)
        }
    }

    /// Full filter: types, time range, enabled only, and optional text search.
    func filtered(
        audiobookID: String,
        types: Set<TimelineItemType>? = nil,
        from startTime: TimeInterval? = nil,
        to endTime: TimeInterval? = nil,
        enabledOnly: Bool = false,
        searchText: String? = nil
    ) throws -> [TimelineItem] {
        try db.read { db in
            var query = TimelineItem
                .filter(Column("audiobook_id") == audiobookID)

            if let types, !types.isEmpty {
                query = query.filter(types.map(\.rawValue).contains(Column("item_type")))
            }
            if let startTime {
                query = query.filter(Column("media_timestamp") >= startTime)
            }
            if let endTime {
                query = query.filter(Column("media_timestamp") <= endTime)
            }
            if enabledOnly {
                query = query.filter(Column("is_enabled") == true)
            }
            if let searchText, !searchText.isEmpty {
                query = query.filter(
                    Column("title").like("%\(searchText)%") ||
                    Column("subtitle").like("%\(searchText)%")
                )
            }

            return try query
                .order(
                    Column("playlist_position") ?? Column("media_timestamp"),
                    Column("media_timestamp")
                )
                .fetchAll(db)
        }
    }

    /// Move an item to a new playlist position. Reorders surrounding items
    /// within a single write transaction.
    func moveItem(
        id: String,
        itemType: TimelineItemType,
        audiobookID: String,
        to newPosition: TimeInterval
    ) throws {
        try db.write { db in
            guard let table = tableName(for: itemType) else { return }
            try db.execute(
                sql: """
                    UPDATE \(table)
                    SET playlist_position = :position
                    WHERE id = :id AND audiobook_id = :audiobookID
                    """,
                arguments: [
                    "position": newPosition,
                    "id": id,
                    "audiobookID": audiobookID
                ]
            )
        }
    }

    func removeFromPlaylist(id: String, itemType: TimelineItemType, audiobookID: String) throws {
        try db.write { db in
            guard let table = tableName(for: itemType) else { return }
            try db.execute(
                sql: "UPDATE \(table) SET playlist_position = NULL WHERE id = :id AND audiobook_id = :audiobookID",
                arguments: ["id": id, "audiobookID": audiobookID]
            )
        }
    }

    private func tableName(for type: TimelineItemType) -> String? {
        switch type {
        case .track: return "track"
        case .chapter: return "chapter"
        case .bookmark: return "bookmark"
        case .flashcard: return "flashcard"
        case .transcription: return nil // not reorderable
        }
    }
}
```

- [x] **Step 3: Build to verify**

```bash
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: Build succeeds.

- [x] **Step 4: Commit**

```bash
git add Shared/Database/TimelineItem.swift Shared/Database/DAOs/TimelineDAO.swift
git commit -m "feat(db): add TimelineItem model and TimelineDAO with filtering"
```

---

### Task 5: Create BookmarkDAO, ChapterDAO, TrackDAO

**Files:**
- Create: `Shared/Database/DAOs/BookmarkDAO.swift`
- Create: `Shared/Database/DAOs/ChapterDAO.swift`
- Create: `Shared/Database/DAOs/TrackDAO.swift`

- [x] **Step 1: Write BookmarkDAO.swift**

```swift
import Foundation
import GRDB

struct BookmarkDAO {
    let db: DatabaseWriter

    func bookmarks(for audiobookID: String) throws -> [Bookmark] {
        try db.read { db in
            try Bookmark
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("media_timestamp"))
                .fetchAll(db)
        }
    }

    func bookmark(id: String) throws -> Bookmark? {
        try db.read { db in try Bookmark.fetchOne(db, key: id) }
    }

    func insert(_ bookmark: Bookmark) throws {
        try db.write { db in try bookmark.insert(db) }
    }

    func update(_ bookmark: Bookmark) throws {
        try db.write { db in
            var bm = bookmark
            try bm.update(db)
        }
    }

    func delete(id: String) throws {
        try db.write { db in
            try Bookmark.deleteOne(db, key: id)
        }
    }

    func deleteAll(for audiobookID: String) throws {
        try db.write { db in
            try Bookmark
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }

    func count(for audiobookID: String) throws -> Int {
        try db.read { db in
            try Bookmark
                .filter(Column("audiobook_id") == audiobookID)
                .fetchCount(db)
        }
    }
}
```

- [x] **Step 2: Make Bookmark conform to GRDB protocols**

Add this extension in `OrbitAudioBooks/Views/Bookmarks.swift` (where `Bookmark` is defined):

```swift
import GRDB

extension Bookmark: TableRecord, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "bookmark"

    // Map Swift properties to SQL columns.
    enum Columns: String, ColumnExpression {
        case id, audiobook_id = "audiobookID", trackId, title,
             mediaTimestamp = "media_timestamp", note,
             voiceMemoPath = "voice_memo_path", imagePath = "image_path",
             isEnabled = "is_enabled", playlistPosition = "playlist_position",
             createdAt = "created_at", modifiedAt = "modified_at"
    }

    // Encodable: override to exclude non-SQL fields.
    // GRDB auto-maps Codable properties to columns by name.
}
```

Note: `Bookmark` already conforms to `Codable`. GRDB can use this automatically if the coding keys match column names. If they differ, add a custom `encode(to:)` or use `Column` mappings as shown.

- [x] **Step 3: Write ChapterDAO.swift**

```swift
import Foundation
import GRDB

struct ChapterDAO {
    let db: DatabaseWriter

    func chapters(for audiobookID: String) throws -> [Chapter] {
        try db.read { db in
            try Chapter
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("sort_order"))
                .fetchAll(db)
        }
    }

    func insertAll(_ chapters: [Chapter], audiobookID: String) throws {
        try db.write { db in
            for chapter in chapters {
                try chapter.insert(db)
            }
        }
    }

    func deleteAll(for audiobookID: String) throws {
        try db.write { db in
            try Chapter
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }
}
```

- [x] **Step 4: Write TrackDAO.swift**

```swift
import Foundation
import GRDB

struct TrackDAO {
    let db: DatabaseWriter

    func tracks(for audiobookID: String) throws -> [Track] {
        try db.read { db in
            try Track
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("sort_order"))
                .fetchAll(db)
        }
    }

    func insertAll(_ tracks: [Track], audiobookID: String) throws {
        try db.write { db in
            for track in tracks {
                try track.insert(db)
            }
        }
    }

    func updateEnabled(id: String, isEnabled: Bool) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE track SET is_enabled = ? WHERE id = ?",
                arguments: [isEnabled, id]
            )
        }
    }

    func deleteAll(for audiobookID: String) throws {
        try db.write { db in
            try Track
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }
}
```

- [x] **Step 5: Build to verify**

```bash
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: Build succeeds.

- [x] **Step 6: Commit**

```bash
git add Shared/Database/DAOs/BookmarkDAO.swift Shared/Database/DAOs/ChapterDAO.swift Shared/Database/DAOs/TrackDAO.swift OrbitAudioBooks/Views/Bookmarks.swift
git commit -m "feat(db): add BookmarkDAO, ChapterDAO, TrackDAO"
```

---

### Task 6: Create FlashcardDAO + TranscriptionDAO + Remaining DAOs

**Files:**
- Create: `Shared/Database/DAOs/FlashcardDAO.swift`
- Create: `Shared/Database/DAOs/TranscriptionDAO.swift`
- Create: `Shared/Database/DAOs/PlaybackEventDAO.swift`
- Create: `Shared/Database/DAOs/SettingsDAO.swift`
- Create: `Shared/Database/DAOs/AudiobookDAO.swift`

- [x] **Step 1: Write FlashcardDAO.swift**

```swift
import Foundation
import GRDB

struct FlashcardDAO {
    let db: DatabaseWriter

    func flashcards(for audiobookID: String) throws -> [Flashcard] {
        try db.read { db in
            try Flashcard
                .filter(Column("audiobook_id") == audiobookID)
                .fetchAll(db)
        }
    }

    /// Cards due for review (next_review_date <= now).
    func dueCards(for audiobookID: String) throws -> [Flashcard] {
        try db.read { db in
            try Flashcard
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("next_review_date") <= Date().ISO8601Format())
                .order(Column("next_review_date"))
                .fetchAll(db)
        }
    }

    /// All due cards across all audiobooks.
    func allDueCards() throws -> [Flashcard] {
        try db.read { db in
            try Flashcard
                .filter(Column("next_review_date") <= Date().ISO8601Format())
                .order(Column("next_review_date"))
                .fetchAll(db)
        }
    }

    func insert(_ card: Flashcard) throws {
        try db.write { db in try card.insert(db) }
    }

    func update(_ card: Flashcard) throws {
        try db.write { db in
            var c = card
            try c.update(db)
        }
    }

    /// Apply SM-2 grade and update scheduling.
    func grade(cardID: String, grade: Int, now: Date = Date()) throws {
        try db.write { db in
            guard var card = try Flashcard.fetchOne(db, key: cardID) else { return }
            let result = SpacedRepetitionService.apply(grade: grade, to: card)
            try result.update(db)
        }
    }
}
```

- [x] **Step 2: Write TranscriptionDAO.swift**

```swift
import Foundation
import GRDB

struct TranscriptionDAO {
    let db: DatabaseWriter

    func segments(for audiobookID: String) throws -> [TranscriptionSegment] {
        try db.read { db in
            try TranscriptionSegment
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("start_time"))
                .fetchAll(db)
        }
    }

    func insertAll(_ segments: [TranscriptionSegment], audiobookID: String) throws {
        try db.write { db in
            for segment in segments {
                try segment.insert(db)
            }
        }
    }

    /// FTS5 full-text search across transcription segments.
    func search(_ query: String, audiobookID: String) throws -> [TranscriptionSegment] {
        try db.read { db in
            let pattern = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
            let sql = """
                SELECT ts.* FROM transcription_segment ts
                JOIN transcription_fts fts ON ts.id = fts.rowid
                WHERE transcription_fts MATCH :query
                AND ts.audiobook_id = :audiobookID
                ORDER BY rank
                """
            return try TranscriptionSegment.fetchAll(
                db, sql: sql,
                arguments: ["query": pattern, "audiobookID": audiobookID]
            )
        }
    }

    func insertWords(_ words: [TranscriptionWord], segmentID: Int64) throws {
        try db.write { db in
            for word in words {
                try db.execute(
                    sql: """
                        INSERT INTO transcription_word (segment_id, word, start_time, end_time, position)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [segmentID, word.word, word.startTime, word.endTime, word.position]
                )
            }
        }
    }

    func deleteAll(for audiobookID: String) throws {
        try db.write { db in
            try TranscriptionSegment
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }
}
```

- [x] **Step 3: Write PlaybackEventDAO.swift**

```swift
import Foundation
import GRDB

struct PlaybackEventDAO {
    let db: DatabaseWriter

    func log(
        audiobookID: String,
        trackID: String?,
        startedAt: Date,
        endedAt: Date?,
        startPosition: TimeInterval,
        endPosition: TimeInterval?,
        speed: Float,
        eventType: String,
        source: String?
    ) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO playback_event
                    (audiobook_id, track_id, started_at, ended_at, start_position, end_position, speed, event_type, source)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    audiobookID, trackID,
                    startedAt.ISO8601Format(), endedAt?.ISO8601Format(),
                    startPosition, endPosition, speed,
                    eventType, source
                ]
            )
        }
    }

    func events(for audiobookID: String, limit: Int = 100) throws -> [PlaybackEvent] {
        try db.read { db in
            try PlaybackEvent
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
```

- [x] **Step 4: Write SettingsDAO.swift**

```swift
import Foundation
import GRDB

struct SettingsDAO {
    let db: DatabaseWriter

    func get(_ key: String) throws -> String? {
        try db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    func set(_ key: String, value: String) throws {
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }

    func getAll() throws -> [String: String] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM settings")
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["key"], $0["value"]) })
        }
    }
}
```

- [x] **Step 5: Write AudiobookDAO.swift**

```swift
import Foundation
import GRDB

struct AudiobookDAO {
    let db: DatabaseWriter

    func insert(_ audiobook: AudiobookRecord) throws {
        try db.write { db in try audiobook.insert(db) }
    }

    func get(_ id: String) throws -> AudiobookRecord? {
        try db.read { db in try AudiobookRecord.fetchOne(db, key: id) }
    }

    func all() throws -> [AudiobookRecord] {
        try db.read { db in
            try AudiobookRecord
                .order(Column("added_at").desc)
                .fetchAll(db)
        }
    }

    func delete(_ id: String) throws {
        try db.write { db in
            try AudiobookRecord.deleteOne(db, key: id)
        }
    }
}

struct AudiobookRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var title: String
    var author: String?
    var duration: TimeInterval
    var fileCount: Int?
    var addedAt: String

    static let databaseTableName = "audiobook"

    enum CodingKeys: String, CodingKey {
        case id, title, author, duration
        case fileCount = "file_count"
        case addedAt = "added_at"
    }
}
```

- [x] **Step 6: Build to verify**

```bash
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: Build succeeds.

- [x] **Step 7: Commit**

```bash
git add Shared/Database/DAOs/FlashcardDAO.swift Shared/Database/DAOs/TranscriptionDAO.swift Shared/Database/DAOs/PlaybackEventDAO.swift Shared/Database/DAOs/SettingsDAO.swift Shared/Database/DAOs/AudiobookDAO.swift
git commit -m "feat(db): add FlashcardDAO, TranscriptionDAO, PlaybackEventDAO, SettingsDAO, AudiobookDAO"
```

---

### Phase 3: Wire Into Existing Code

### Task 7: Route BookmarkStore Through SQL

**Files:**
- Modify: `OrbitAudioBooks/Services/BookmarkStore.swift` — add SQL-backed persistence path
- Modify: `OrbitAudioBooks/ViewModels/PlayerModel.swift` — inject DatabaseService

- [x] **Step 1: Add SQL-backed load/save to BookmarkStore**

Add a new method to `BookmarkStore`:

```swift
extension BookmarkStore {
    /// Load bookmarks from SQL for the given audiobook ID.
    func loadFromSQL(database: DatabaseService, audiobookID: String) {
        let dao = BookmarkDAO(db: database.writer)
        if let bookmarks = try? dao.bookmarks(for: audiobookID) {
            self.bookmarks = bookmarks
        }
    }

    /// Persist all bookmarks through SQL, keyed by the current storage key.
    func configureSQLPersistence(database: DatabaseService) {
        onPersist = { [weak self] bookmarks in
            guard let self, let key = self.storageKeyProvider?() else { return }
            let dao = BookmarkDAO(db: database.writer)
            try? dao.deleteAll(for: key)
            for bm in bookmarks {
                try? dao.insert(bm)
            }
        }
    }
}
```

- [x] **Step 2: Update PlayerModel to use SQL**

In `PlayerModel.loadFolder(_:)`, after loading audiobook content:

```swift
if let db = databaseService {
    // Insert/update audiobook record
    let record = AudiobookRecord(
        id: folderKey,
        title: albumTitle,
        author: nil,
        duration: totalDuration,
        fileCount: tracks.count,
        addedAt: Date().ISO8601Format()
    )
    try? AudiobookDAO(db: db.writer).insert(record)

    // Insert tracks
    let trackDAO = TrackDAO(db: db.writer)
    try? trackDAO.deleteAll(for: folderKey)
    try? trackDAO.insertAll(tracks, audiobookID: folderKey)

    // Insert chapters
    let chapterDAO = ChapterDAO(db: db.writer)
    try? chapterDAO.deleteAll(for: folderKey)
    try? chapterDAO.insertAll(chapters, audiobookID: folderKey)
}
```

- [x] **Step 3: Build and test**

```bash
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
xcodebuild test -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: Build succeeds. Existing tests pass.

- [x] **Step 4: Commit**

```bash
git add OrbitAudioBooks/Services/BookmarkStore.swift OrbitAudioBooks/ViewModels/PlayerModel.swift
git commit -m "feat(db): route BookmarkStore persistence through SQL DAOs"
```

---

### Task 8: Migrate Existing UserDefaults Data to SQL

**Files:**
- Create: `Shared/Database/MigrationService.swift`

- [x] **Step 1: Write MigrationService.swift**

```swift
import Foundation
import GRDB
import os.log

/// One-shot migrator that reads existing UserDefaults/JSON-sidecar data
/// and writes it into the SQL database.
enum MigrationService {
    private static let logger = Logger(subsystem: "com.orbitaudiobooks", category: "Migration")

    /// Run the migration if needed. Safe to call on every launch.
    static func migrateIfNeeded(database: DatabaseService, persistence: Persistence) {
        guard !database.isMigrationDone else { return }

        logger.info("Starting UserDefaults → SQL migration…")

        do {
            let defaults = UserDefaults.standard

            // 1. Migrate bookmarks — iterate over all known bookmark keys.
            let bookmarkKeys = defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("bookmarks_") }
            for key in bookmarkKeys {
                let audiobookKey = String(key.dropFirst("bookmarks_".count))
                guard let data = defaults.data(forKey: key),
                      let bookmarks = try? JSONDecoder().decode([Bookmark].self, from: data)
                else { continue }

                let dao = BookmarkDAO(db: database.writer)
                for bm in bookmarks {
                    try? dao.insert(bm)
                }
                logger.debug("Migrated \(bookmarks.count) bookmarks for \(audiobookKey)")
            }

            // 2. Migrate playback progress.
            let progressKey = "OrbitAudiobooks.progress.dictionary"
            if let progress = defaults.dictionary(forKey: progressKey) as? [String: [String: Any]] {
                for (audiobookID, item) in progress {
                    guard let trackId = item["trackId"] as? String,
                          let time = item["time"] as? Double
                    else { continue }
                    try? database.write { db in
                        try db.execute(
                            sql: """
                                INSERT OR REPLACE INTO playback_state (audiobook_id, last_position, speed)
                                VALUES (?, ?, 1.0)
                                """,
                            arguments: [audiobookID, time]
                        )
                    }
                }
            }

            // 3. Migrate per-book speed.
            let speedKey = "OrbitAudiobooks.playback.speed.dictionary"
            if let speeds = defaults.dictionary(forKey: speedKey) as? [String: Double] {
                for (audiobookID, speed) in speeds {
                    try? database.write { db in
                        try db.execute(
                            sql: "UPDATE playback_state SET speed = ? WHERE audiobook_id = ?",
                            arguments: [speed, audiobookID]
                        )
                    }
                }
            }

            // 4. Migrate settings.
            let settingsKeys = [
                "appFont", "isDarkMode", "playBookmarksInline",
                "chapterCueEnabled", "bookmarkCueEnabled",
                "selectedChapterCue", "selectedBookmarkCue"
            ]
            let settingsDAO = SettingsDAO(db: database.writer)
            for key in settingsKeys {
                if let value = defaults.string(forKey: key) {
                    try? settingsDAO.set(key, value: value)
                }
            }

            database.isMigrationDone = true
            logger.info("Migration complete.")

        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
            // Leave isMigrationDone false so it retries next launch.
        }
    }
}
```

- [x] **Step 2: Call migration from app entry point**

In `Orbit_AudioBooksApp.swift`:

```swift
.task {
    let db = try? DatabaseService()
    if let db, let persistence = playerModel.persistence {
        MigrationService.migrateIfNeeded(database: db, persistence: persistence)
    }
    databaseService = db
}
```

- [x] **Step 3: Build to verify**

```bash
xcodebuild build -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
```

Expected: Build succeeds.

- [x] **Step 4: Commit**

```bash
git add Shared/Database/MigrationService.swift OrbitAudioBooks/Orbit_AudioBooksApp.swift
git commit -m "feat(db): add UserDefaults → SQL migration service"
```

---

### Phase 4: Tests

### Task 9: DAO Tests

**Files:**
- Modify: `Orbit AudiobooksTests/OrbitAudioBooksTests.swift`

- [x] **Step 1: Write DAO tests**

```swift
import Testing
import GRDB
@testable import Orbit_AudioBooks

struct DatabaseServiceTests {
    @Test func v1SchemaCreatesAllTables() throws {
        let db = try DatabaseService(inMemory: ())
        let tables = try db.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table' OR type='view'
                ORDER BY name
                """)
        }
        #expect(tables.contains("audiobook"))
        #expect(tables.contains("track"))
        #expect(tables.contains("chapter"))
        #expect(tables.contains("bookmark"))
        #expect(tables.contains("flashcard"))
        #expect(tables.contains("transcription_segment"))
        #expect(tables.contains("transcription_word"))
        #expect(tables.contains("playback_event"))
        #expect(tables.contains("playback_state"))
        #expect(tables.contains("settings"))
        #expect(tables.contains("timeline")) // view
    }

    @Test func bookmarkDAOInsertAndRead() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = BookmarkDAO(db: db.writer)
        let bm = Bookmark(
            id: UUID(),
            title: "Test",
            audiobookID: "book-1",
            trackID: nil,
            mediaTimestamp: 30.0
        )
        try dao.insert(bm)
        let results = try dao.bookmarks(for: "book-1")
        #expect(results.count == 1)
        #expect(results.first?.title == "Test")
        #expect(results.first?.mediaTimestamp == 30.0)
    }

    @Test func bookmarkDAODelete() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = BookmarkDAO(db: db.writer)
        let bm = Bookmark(
            id: UUID(),
            title: "Delete Me",
            audiobookID: "book-1",
            trackID: nil,
            mediaTimestamp: 0
        )
        try dao.insert(bm)
        try dao.delete(id: bm.id.uuidString)
        let results = try dao.bookmarks(for: "book-1")
        #expect(results.isEmpty)
    }

    @Test func timelineViewUnionsAllTypes() throws {
        let db = try DatabaseService(inMemory: ())
        let timelineDAO = TimelineDAO(db: db.writer)

        // Insert one of each type.
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO audiobook (id, title, duration) VALUES ('book-1', 'Test', 3600)
                """)
            try db.execute(sql: """
                INSERT INTO track (id, audiobook_id, title, duration, file_path, sort_order)
                VALUES ('t1', 'book-1', 'Track 1', 3600, '/tmp/t1.mp3', 0)
                """)
            try db.execute(sql: """
                INSERT INTO chapter (audiobook_id, title, start_seconds, end_seconds, sort_order)
                VALUES ('book-1', 'Chapter 1', 0, 1800, 0)
                """)
            try db.execute(sql: """
                INSERT INTO bookmark (id, audiobook_id, title, media_timestamp)
                VALUES ('bm1', 'book-1', 'Bookmark 1', 120.0)
                """)
            try db.execute(sql: """
                INSERT INTO flashcard (id, audiobook_id, front_text, back_text, media_timestamp)
                VALUES ('fc1', 'book-1', 'Question?', 'Answer.', 300.0)
                """)
            try db.execute(sql: """
                INSERT INTO transcription_segment (audiobook_id, start_time, end_time, text)
                VALUES ('book-1', 0, 5, 'Hello world')
                """)
        }

        let items = try timelineDAO.items(for: "book-1")
        #expect(items.count == 5)
        #expect(items.contains(where: { $0.itemType == .track }))
        #expect(items.contains(where: { $0.itemType == .chapter }))
        #expect(items.contains(where: { $0.itemType == .bookmark }))
        #expect(items.contains(where: { $0.itemType == .flashcard }))
        #expect(items.contains(where: { $0.itemType == .transcription }))
    }

    @Test func timelineFilterByType() throws {
        let db = try DatabaseService(inMemory: ())
        let timelineDAO = TimelineDAO(db: db.writer)

        try db.write { db in
            try db.execute(sql: """
                INSERT INTO audiobook (id, title, duration) VALUES ('book-1', 'Test', 3600)
                """)
            try db.execute(sql: """
                INSERT INTO bookmark (id, audiobook_id, title, media_timestamp)
                VALUES ('bm1', 'book-1', 'BM', 10.0)
                """)
            try db.execute(sql: """
                INSERT INTO flashcard (id, audiobook_id, front_text, back_text, media_timestamp)
                VALUES ('fc1', 'book-1', 'Q', 'A', 20.0)
                """)
        }

        let bookmarks = try timelineDAO.filtered(audiobookID: "book-1", types: [.bookmark])
        #expect(bookmarks.count == 1)
        #expect(bookmarks.first?.itemType == .bookmark)

        let cards = try timelineDAO.filtered(audiobookID: "book-1", types: [.flashcard])
        #expect(cards.count == 1)
        #expect(cards.first?.itemType == .flashcard)
    }

    @Test func timelineFilterByTimeRange() throws {
        let db = try DatabaseService(inMemory: ())
        let timelineDAO = TimelineDAO(db: db.writer)

        try db.write { db in
            try db.execute(sql: """
                INSERT INTO audiobook (id, title, duration) VALUES ('book-1', 'Test', 3600)
                """)
            try db.execute(sql: """
                INSERT INTO bookmark (id, audiobook_id, title, media_timestamp)
                VALUES ('bm1', 'book-1', 'Early', 10.0)
                """)
            try db.execute(sql: """
                INSERT INTO bookmark (id, audiobook_id, title, media_timestamp)
                VALUES ('bm2', 'book-1', 'Mid', 100.0)
                """)
            try db.execute(sql: """
                INSERT INTO bookmark (id, audiobook_id, title, media_timestamp)
                VALUES ('bm3', 'book-1', 'Late', 200.0)
                """)
        }

        let mid = try timelineDAO.filtered(audiobookID: "book-1", from: 50, to: 150)
        #expect(mid.count == 1)
        #expect(mid.first?.title == "Mid")
    }

    @Test func flashcardDueQuery() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = FlashcardDAO(db: db.writer)

        let past = Date().addingTimeInterval(-86400).ISO8601Format()
        let future = Date().addingTimeInterval(86400).ISO8601Format()

        try db.write { db in
            try db.execute(sql: """
                INSERT INTO audiobook (id, title, duration) VALUES ('book-1', 'Test', 3600)
                """)
            try db.execute(sql: """
                INSERT INTO flashcard (id, audiobook_id, front_text, back_text, media_timestamp, next_review_date)
                VALUES ('fc-due', 'book-1', 'Due', 'Answer', 10.0, ?)
                """, arguments: [past])
            try db.execute(sql: """
                INSERT INTO flashcard (id, audiobook_id, front_text, back_text, media_timestamp, next_review_date)
                VALUES ('fc-future', 'book-1', 'Future', 'Answer', 20.0, ?)
                """, arguments: [future])
        }

        let due = try dao.dueCards(for: "book-1")
        #expect(due.count == 1)
        #expect(due.first?.id == "fc-due")
    }

    @Test func transcriptionFTSSearch() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = TranscriptionDAO(db: db.writer)

        try db.write { db in
            try db.execute(sql: """
                INSERT INTO audiobook (id, title, duration) VALUES ('book-1', 'Test', 3600)
                """)
            try db.execute(sql: """
                INSERT INTO transcription_segment (audiobook_id, start_time, end_time, text)
                VALUES ('book-1', 0, 5, 'The quick brown fox')
                """)
            try db.execute(sql: """
                INSERT INTO transcription_segment (audiobook_id, start_time, end_time, text)
                VALUES ('book-1', 5, 10, 'jumps over the lazy dog')
                """)
        }

        let results = try dao.search("fox", audiobookID: "book-1")
        #expect(results.count == 1)
        #expect(results.first?.text == "The quick brown fox")
    }

    @Test func reorderMovesItemToNewPlaylistPosition() throws {
        let db = try DatabaseService(inMemory: ())
        let timelineDAO = TimelineDAO(db: db.writer)

        try db.write { db in
            try db.execute(sql: """
                INSERT INTO audiobook (id, title, duration) VALUES ('book-1', 'Test', 3600)
                """)
            try db.execute(sql: """
                INSERT INTO bookmark (id, audiobook_id, title, media_timestamp)
                VALUES ('bm1', 'book-1', 'First', 10.0)
                """)
            try db.execute(sql: """
                INSERT INTO bookmark (id, audiobook_id, title, media_timestamp)
                VALUES ('bm2', 'book-1', 'Second', 20.0)
                """)
        }

        try timelineDAO.moveItem(
            id: "bm1", itemType: .bookmark,
            audiobookID: "book-1", to: 30.0
        )

        let items = try timelineDAO.items(for: "book-1")
        let bookmarkItems = items.filter { $0.itemType == .bookmark }
        #expect(bookmarkItems.first(where: { $0.id == "bm1" })?.effectivePosition == 30.0)
    }
}
```

- [x] **Step 2: Run tests**

```bash
xcodebuild test -project "Orbit Audiobooks.xcodeproj" -scheme "Orbit Audiobooks" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep "passed\|failed"
```

Expected: All new tests pass.

- [x] **Step 3: Commit**

```bash
git add Orbit AudiobooksTests/OrbitAudioBooksTests.swift
git commit -m "test(db): add DAO and timeline integration tests"
```

---

### Task 10: Update ARCHITECTURE.md and Cross-Reference

**Files:**
- Modify: `ARCHITECTURE.md`
- Modify: `plan-cross-reference.md`

- [x] **Step 1: Update cross-reference completion table**

In `plan-cross-reference.md`, change the SQL row to in-progress:

```
| SQL — SQL Database Integration | ⏳ In Progress | 2026-05-17 |
```

- [x] **Step 2: Add SQL section to ARCHITECTURE.md**

```
## Shared/Database
- `DatabaseService.swift` — GRDB DatabasePool in WAL mode, App Group container
- `Schema_V1.swift` — V1 schema migration (10 tables, 1 view, FTS5)
- `DAOs/` — Type-safe query objects: AudiobookDAO, BookmarkDAO, ChapterDAO, FlashcardDAO, TimelineDAO, TrackDAO, TranscriptionDAO, PlaybackEventDAO, SettingsDAO
- `TimelineItem.swift` — Unified view model for all five item types
- `MigrationService.swift` — UserDefaults → SQL one-shot migration
```

- [x] **Step 3: Commit**

```bash
git add ARCHITECTURE.md plan-cross-reference.md
git commit -m "docs: update architecture for SQL database layer"
```

---

## Implementation Order

| Task | Dependency | Estimated Time |
|------|-----------|---------------|
| 1. Add GRDB SPM | None | 10 min |
| 2. Schema V1 | Task 1 | 15 min |
| 3. DatabaseService | Task 2 | 15 min |
| 4. TimelineItem + TimelineDAO | Task 3 | 15 min |
| 5. BookmarkDAO, ChapterDAO, TrackDAO | Task 3 | 20 min |
| 6. FlashcardDAO + remaining DAOs | Task 3 | 20 min |
| 7. Wire BookmarkStore → SQL | Tasks 4-6 | 15 min |
| 8. Migration service | Task 7 | 15 min |
| 9. DAO tests | Tasks 4-6 | 20 min |
| 10. Documentation update | All | 5 min |

**Total:** ~2.5 hours

Tasks 4, 5, 6 can be parallelized (different files, same dependency).
