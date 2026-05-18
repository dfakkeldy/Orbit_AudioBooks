# Plan: SQL Database Integration — SUPERSEDED by 2026-05-17-sql-database-integration.md

## Summary

Introduce a local SQL database (GRDB.swift) to replace UserDefaults as the persistence layer for bookmarks, transcription segments, word frequencies, and playback state — enabling efficient querying, full-text search, and data integrity.

## Why SQL?

The current UserDefaults-based persistence has several limitations:

1. **Bookmarks** are stored as a JSON blob — no way to query "all bookmarks for track X within time range Y"
2. **Transcription segments** are stored in-memory and re-generated — no persistent search index
3. **Word frequencies** are computed fresh each time — no cached aggregation
4. **Playback state** (per-book speed, last position) is scattered across multiple UserDefaults keys
5. **No foreign key integrity** — deleting a track doesn't cascade to its bookmarks
6. **No full-text search** — transcript search is O(n) scan

## Technology Choice

**GRDB.swift** (recommended over CoreData/SwiftData):

| Criteria | GRDB | CoreData | SwiftData |
|----------|------|----------|-----------|
| SQL access | Direct, full SQL | Limited, NSPredicate | Limited |
| FTS5 (full-text search) | Built-in | Manual | Manual |
| Cross-target | SPM, works on all | iOS/macOS only | iOS 17+ only |
| Migration support | Explicit, reliable | Complex | Immature |
| Performance | Excellent | Good | Good |
| Watch compatibility | Yes (SPM) | No | No |

GRDB works on iOS, macOS, watchOS, and in Widget extensions via SPM.

## Schema Design

```sql
-- Core tables
CREATE TABLE audiobook (
    id TEXT PRIMARY KEY,        -- folderKey or file URL hash
    title TEXT NOT NULL,
    author TEXT,
    duration REAL NOT NULL,
    file_count INTEGER,
    added_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE chapter (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    audiobook_id TEXT NOT NULL REFERENCES audiobook(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    start_seconds REAL NOT NULL,
    end_seconds REAL NOT NULL,
    sort_order INTEGER NOT NULL
);

CREATE TABLE bookmark (
    id TEXT PRIMARY KEY,
    audiobook_id TEXT NOT NULL REFERENCES audiobook(id) ON DELETE CASCADE,
    chapter_id INTEGER REFERENCES chapter(id),
    title TEXT NOT NULL,
    timestamp REAL NOT NULL,
    note TEXT,
    voice_memo_path TEXT,
    image_path TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    modified_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Transcription
CREATE TABLE transcription_segment (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    audiobook_id TEXT NOT NULL REFERENCES audiobook(id) ON DELETE CASCADE,
    start_time REAL NOT NULL,
    end_time REAL NOT NULL,
    text TEXT NOT NULL
);

CREATE VIRTUAL TABLE transcription_fts USING fts5(
    text,
    content=transcription_segment,
    content_rowid=id
);

-- Word frequencies (materialized view for word cloud)
CREATE TABLE word_frequency (
    audiobook_id TEXT NOT NULL REFERENCES audiobook(id) ON DELETE CASCADE,
    word TEXT NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (audiobook_id, word)
);

-- Playback state (replaces per-book speed in UserDefaults)
CREATE TABLE playback_state (
    audiobook_id TEXT PRIMARY KEY REFERENCES audiobook(id) ON DELETE CASCADE,
    last_position REAL NOT NULL DEFAULT 0,
    speed REAL NOT NULL DEFAULT 1.0,
    last_played_at TEXT
);

-- Settings (replaces scattered UserDefaults)
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

## Migration Strategy

1. Add GRDB as an SPM dependency
2. Create `DatabaseService.swift` with schema creation and migrations
3. Create type-safe query interfaces for each table (DAO pattern)
4. Migrate existing UserDefaults data to SQL on first launch
5. Update `BookmarkStore` (from A1) to use the database instead of UserDefaults
6. Update `TranscriptionManager` to persist segments to SQL
7. Add FTS5 search for transcript
8. Remove old UserDefaults keys after migration confirmed

## Watch & Widget Access

The SQL database file lives in the App Group container (`group.com.orbitaudiobooks`), so all targets can read:
- Watch reads: current bookmark, playback state, settings
- Widget reads: current track info, isPlaying
- iOS writes: everything
- macOS writes: settings, transcript segments

Use GRDB's `DatabasePool` with WAL mode for concurrent read access across processes.

## Files to Create/Modify

| Action | File |
|--------|------|
| Create | `OrbitAudioBooks/Services/DatabaseService.swift` |
| Create | `OrbitAudioBooks/Services/DAOs/AudiobookDAO.swift` |
| Create | `OrbitAudioBooks/Services/DAOs/BookmarkDAO.swift` |
| Create | `OrbitAudioBooks/Services/DAOs/TranscriptionDAO.swift` |
| Create | `OrbitAudioBooks/Services/DAOs/PlaybackStateDAO.swift` |
| Create | `OrbitAudioBooks/Services/DAOs/SettingsDAO.swift` |
| Create | `OrbitAudioBooks/Services/Migrations/V1_CreateSchema.swift` |
| Modify | `OrbitAudioBooks/Services/BookmarkStore.swift` (from A1) — use SQL |
| Modify | `OrbitAudioBooks/Services/ChapterService.swift` (from A1) — use SQL |
| Modify | `Orbit Audiobooks macOS/Views/TranscriptionManager.swift` — persist to SQL |
| Modify | All targets using `AppGroupDefaults` — route settings reads through SQL |

## Dependencies

- **Blocked by:** Plan A1 (PlayerModel decomposition) — the DAOs replace what `BookmarkStore`, `Persistence`, and parts of `SettingsManager` do. Extract those components FIRST (using UserDefaults), then swap their storage backend to SQL.
- **Conflicts with:**
  - Plan A3 (deduplication) — `AppGroupDefaults` is being deduplicated; SQL replaces it entirely for most use cases
  - Plan Phase 3 (Dashboard) — FTS5 search replaces the in-memory transcript search

## Complexity

**Large.** New dependency, new schema, data migration, and every persistence call site changes. But the incremental approach (extract components first with UserDefaults, swap to SQL after) makes it manageable. The biggest risk is the UserDefaults → SQL migration corrupting user data — must be thoroughly tested with existing bookmark data.
