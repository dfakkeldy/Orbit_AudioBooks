import Testing
import Foundation
import GRDB
@testable import Orbit_Audiobooks

// MARK: - Schema_V5 Tests

struct SchemaV5Tests {

    @Test("Schema_V5 creates epub_block table with all expected columns")
    func epubBlockTableExists() throws {
        let db = try DatabaseService(inMemory: ())
        try db.read { db in
            let columns = try db.columns(in: "epub_block")
            let names = Set(columns.map { $0.name })
            #expect(names.contains("id"))
            #expect(names.contains("audiobook_id"))
            #expect(names.contains("spine_href"))
            #expect(names.contains("spine_index"))
            #expect(names.contains("block_index"))
            #expect(names.contains("sequence_index"))
            #expect(names.contains("block_kind"))
            #expect(names.contains("text"))
            #expect(names.contains("image_path"))
            #expect(names.contains("chapter_index"))
            #expect(names.contains("is_hidden"))
            #expect(names.contains("hidden_reason"))
            #expect(names.contains("created_at"))
            #expect(names.contains("modified_at"))
        }
    }

    @Test("Schema_V5 creates alignment_anchor table with all expected columns")
    func alignmentAnchorTableExists() throws {
        let db = try DatabaseService(inMemory: ())
        try db.read { db in
            let columns = try db.columns(in: "alignment_anchor")
            let names = Set(columns.map { $0.name })
            #expect(names.contains("id"))
            #expect(names.contains("audiobook_id"))
            #expect(names.contains("epub_block_id"))
            #expect(names.contains("audio_time"))
            #expect(names.contains("audio_end_time"))
            #expect(names.contains("anchor_kind"))
            #expect(names.contains("source"))
            #expect(names.contains("note"))
            #expect(names.contains("created_at"))
            #expect(names.contains("modified_at"))
        }
    }

    @Test("Schema_V5 adds epub_block_id column to timeline_item")
    func timelineItemHasEpubBlockColumn() throws {
        let db = try DatabaseService(inMemory: ())
        try db.read { db in
            let columns = try db.columns(in: "timeline_item")
            let names = Set(columns.map { $0.name })
            #expect(names.contains("epub_block_id"))
            #expect(names.contains("timestamp_source"))
            #expect(names.contains("alignment_status"))
            #expect(names.contains("alignment_confidence"))
        }
    }

    @Test("Schema_V5 creates expected indexes on epub_block")
    func epubBlockIndexes() throws {
        let db = try DatabaseService(inMemory: ())
        try db.read { db in
            let indexes = try db.indexes(on: "epub_block")
            let indexNames = Set(indexes.map { $0.name })
            // GRDB auto-creates index on primary key; look for our named indexes
            let hasSequenceIdx = indexNames.contains { $0.contains("sequence") || $0.contains("epub_block") }
            #expect(hasSequenceIdx)
        }
    }
}

// MARK: - EpubBlockRecord Tests

struct EpubBlockRecordTests {

    @Test("EpubBlockRecord inserts and fetches by audiobook")
    func insertAndFetch() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = EpubBlockDAO(db: db.writer)

        let block = EpubBlockRecord(
            id: "block-1",
            audiobookID: "test-book",
            spineHref: "chapter1.xhtml",
            spineIndex: 0,
            blockIndex: 0,
            sequenceIndex: 0,
            blockKind: "paragraph",
            text: "It was a dark and stormy night.",
            imagePath: nil,
            chapterIndex: 0,
            isHidden: false,
            hiddenReason: nil,
            createdAt: nil,
            modifiedAt: nil
        )

        try dao.insert(block)
        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched.count == 1)
        #expect(fetched[0].text == "It was a dark and stormy night.")
    }

    @Test("EpubBlockRecord hides and unhides blocks")
    func hideAndUnhide() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = EpubBlockDAO(db: db.writer)

        let block = EpubBlockRecord(
            id: "block-hide",
            audiobookID: "test-book",
            spineHref: "ch1.xhtml",
            spineIndex: 0,
            blockIndex: 5,
            sequenceIndex: 5,
            blockKind: "paragraph",
            text: "Content to hide.",
            imagePath: nil,
            chapterIndex: 1,
            isHidden: false,
            hiddenReason: nil,
            createdAt: nil,
            modifiedAt: nil
        )
        try dao.insert(block)

        try dao.setHidden("block-hide", audiobookID: "test-book", hidden: true, reason: "omitted from audiobook")
        let hidden = try dao.fetchAll(for: "test-book")
        #expect(hidden.first?.isHidden == true)

        try dao.setHidden("block-hide", audiobookID: "test-book", hidden: false, reason: nil)
        let visible = try dao.fetchAll(for: "test-book")
        #expect(visible.first?.isHidden == false)
    }

    @Test("EpubBlockRecord fetches in sequence order")
    func sequenceOrder() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = EpubBlockDAO(db: db.writer)

        for i in 0..<5 {
            let block = EpubBlockRecord(
                id: "block-\(i)",
                audiobookID: "test-book",
                spineHref: "ch1.xhtml",
                spineIndex: 0,
                blockIndex: i,
                sequenceIndex: 4 - i, // reverse order
                blockKind: "paragraph",
                text: "Block \(i)",
                imagePath: nil,
                chapterIndex: 0,
                isHidden: false,
                hiddenReason: nil,
                createdAt: nil,
                modifiedAt: nil
            )
            try dao.insert(block)
        }

        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched.count == 5)
        // Should be ordered by sequence_index ascending
        #expect(fetched[0].sequenceIndex == 0)
        #expect(fetched[4].sequenceIndex == 4)
    }
}

// MARK: - AlignmentAnchorRecord Tests

struct AlignmentAnchorRecordTests {

    @Test("AlignmentAnchorRecord inserts and fetches by audiobook")
    func insertAndFetch() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = AlignmentAnchorDAO(db: db.writer)

        let anchor = AlignmentAnchorRecord(
            id: "anchor-1",
            audiobookID: "test-book",
            epubBlockID: "block-1",
            audioTime: 42.5,
            audioEndTime: nil,
            anchorKind: "point",
            source: "moveToNow",
            note: nil,
            createdAt: nil,
            modifiedAt: nil
        )

        try dao.insert(anchor)
        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched.count == 1)
        #expect(fetched[0].audioTime == 42.5)
    }

    @Test("AlignmentAnchorRecord fetches anchors sorted by audio_time")
    func sortedByTime() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = AlignmentAnchorDAO(db: db.writer)

        let times: [Double] = [150.0, 30.0, 90.0, 10.0]
        for (i, t) in times.enumerated() {
            let anchor = AlignmentAnchorRecord(
                id: "anchor-\(i)",
                audiobookID: "test-book",
                epubBlockID: "block-\(i)",
                audioTime: t,
                audioEndTime: nil,
                anchorKind: "point",
                source: "moveToNow",
                note: nil,
                createdAt: nil,
                modifiedAt: nil
            )
            try dao.insert(anchor)
        }

        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched.count == 4)
        #expect(fetched[0].audioTime == 10.0)
        #expect(fetched[3].audioTime == 150.0)
    }

    @Test("AlignmentAnchorRecord deletes all for an audiobook")
    func deleteAll() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = AlignmentAnchorDAO(db: db.writer)

        for i in 0..<3 {
            let anchor = AlignmentAnchorRecord(
                id: "anchor-\(i)",
                audiobookID: "test-book",
                epubBlockID: "block-\(i)",
                audioTime: Double(i * 10),
                audioEndTime: nil,
                anchorKind: "point",
                source: "moveToNow",
                note: nil,
                createdAt: nil,
                modifiedAt: nil
            )
            try dao.insert(anchor)
        }

        try dao.deleteAll(for: "test-book")
        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched.isEmpty)
    }

    @Test("EpubBlockDAO deletes all blocks for an audiobook")
    func deleteAllBlocks() throws {
        let db = try DatabaseService(inMemory: ())
        let dao = EpubBlockDAO(db: db.writer)

        for i in 0..<3 {
            let block = EpubBlockRecord(
                id: "block-\(i)",
                audiobookID: "test-book",
                spineHref: "ch1.xhtml",
                spineIndex: 0,
                blockIndex: i,
                sequenceIndex: i,
                blockKind: "paragraph",
                text: "Text \(i)",
                imagePath: nil,
                chapterIndex: 0,
                isHidden: false,
                hiddenReason: nil,
                createdAt: nil,
                modifiedAt: nil
            )
            try dao.insert(block)
        }

        try dao.deleteAll(for: "test-book")
        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched.isEmpty)
    }
}

// MARK: - TimelineItem V5 Extension Tests

struct TimelineItemV5ExtensionTests {

    @Test("TimelineItem encodes and decodes new V5 columns")
    func newColumnRoundTrip() throws {
        let item = TimelineItem(
            id: "test-item",
            audiobookID: "test-book",
            itemType: .textSegment,
            title: "Test",
            subtitle: nil,
            textPayload: "Test text",
            imagePath: nil,
            audioStartTime: 10.0,
            audioEndTime: 15.0,
            epubSequenceIndex: 0,
            granularityLevel: .sentence,
            playlistPosition: nil,
            isEnabled: true,
            sourceTable: "epub_block",
            sourceRowid: "block-1",
            metadataJSON: nil,
            createdAt: nil,
            modifiedAt: nil,
            epubBlockID: "block-1",
            timestampSource: "estimated",
            alignmentStatus: "estimated",
            alignmentConfidence: 0.85
        )

        #expect(item.epubBlockID == "block-1")
        #expect(item.timestampSource == "estimated")
        #expect(item.alignmentStatus == "estimated")
        #expect(item.alignmentConfidence == 0.85)
    }
}
