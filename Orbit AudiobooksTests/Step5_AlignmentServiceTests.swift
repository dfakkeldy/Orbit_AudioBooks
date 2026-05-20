import Testing
import Foundation
@testable import Orbit_Audiobooks

// MARK: - AlignmentService Tests

struct AlignmentServiceTests {

    @Test("moveBlockToCurrentTime creates or updates a point anchor")
    func moveBlockToCurrentTime() throws {
        let db = try DatabaseService(inMemory: ())
        let epubDAO = EpubBlockDAO(db: db.writer)
        let block = EpubBlockRecord(
            id: "block-1", audiobookID: "test", spineHref: "ch1.xhtml",
            spineIndex: 0, blockIndex: 0, sequenceIndex: 0,
            blockKind: "paragraph", text: "Test text", imagePath: nil,
            chapterIndex: 0, isHidden: false, hiddenReason: nil,
            createdAt: nil, modifiedAt: nil
        )
        try epubDAO.insert(block)

        let service = AlignmentService(database: db)
        try service.moveBlockToCurrentTime(blockID: "block-1", time: 42.5)

        let anchorDAO = AlignmentAnchorDAO(db: db.writer)
        let anchors = try anchorDAO.fetchAll(for: "test")
        #expect(anchors.count == 1)
        #expect(anchors[0].audioTime == 42.5)
        #expect(anchors[0].anchorKind == "point")
        #expect(anchors[0].source == "moveToNow")
    }

    @Test("anchorChapterStart creates a chapterStart anchor")
    func anchorChapterStart() throws {
        let db = try DatabaseService(inMemory: ())
        let epubDAO = EpubBlockDAO(db: db.writer)
        let block = EpubBlockRecord(
            id: "block-ch1", audiobookID: "test", spineHref: "ch1.xhtml",
            spineIndex: 0, blockIndex: 0, sequenceIndex: 0,
            blockKind: "heading", text: "Chapter 1", imagePath: nil,
            chapterIndex: 0, isHidden: false, hiddenReason: nil,
            createdAt: nil, modifiedAt: nil
        )
        try epubDAO.insert(block)

        let service = AlignmentService(database: db)
        try service.anchorChapterStart(blockID: "block-ch1", chapterIndex: 0, time: 0)

        let anchorDAO = AlignmentAnchorDAO(db: db.writer)
        let anchors = try anchorDAO.fetchAll(for: "test")
        #expect(anchors.count == 1)
        #expect(anchors[0].anchorKind == "chapterStart")
        #expect(anchors[0].source == "chapterBoundary")
    }

    @Test("hideBlock marks block as hidden")
    func hideBlock() throws {
        let db = try DatabaseService(inMemory: ())
        let epubDAO = EpubBlockDAO(db: db.writer)
        let block = EpubBlockRecord(
            id: "block-hide", audiobookID: "test", spineHref: "ch1.xhtml",
            spineIndex: 0, blockIndex: 5, sequenceIndex: 5,
            blockKind: "paragraph", text: "Hidden content", imagePath: nil,
            chapterIndex: 1, isHidden: false, hiddenReason: nil,
            createdAt: nil, modifiedAt: nil
        )
        try epubDAO.insert(block)

        let service = AlignmentService(database: db)
        try service.hideBlock("block-hide", reason: "omitted from audiobook")

        let fetched = try epubDAO.fetchAll(for: "test")
        #expect(fetched.first?.isHidden == true)
        #expect(fetched.first?.hiddenReason == "omitted from audiobook")
    }

    @Test("unhideBlock restores block visibility")
    func unhideBlock() throws {
        let db = try DatabaseService(inMemory: ())
        let epubDAO = EpubBlockDAO(db: db.writer)
        let block = EpubBlockRecord(
            id: "block-unhide", audiobookID: "test", spineHref: "ch1.xhtml",
            spineIndex: 0, blockIndex: 0, sequenceIndex: 0,
            blockKind: "paragraph", text: "Restored", imagePath: nil,
            chapterIndex: 0, isHidden: true, hiddenReason: "was omitted",
            createdAt: nil, modifiedAt: nil
        )
        try epubDAO.insert(block)

        let service = AlignmentService(database: db)
        try service.unhideBlock("block-unhide")

        let fetched = try epubDAO.fetchAll(for: "test")
        #expect(fetched.first?.isHidden == false)
        #expect(fetched.first?.hiddenReason == nil)
    }

    @Test("recalculateTimeline interpolates between two locked anchors")
    func interpolateBetweenAnchors() throws {
        let db = try DatabaseService(inMemory: ())
        let epubDAO = EpubBlockDAO(db: db.writer)

        // Create 5 blocks, anchor endpoints, verify middle 3 interpolate
        for i in 0..<5 {
            let block = EpubBlockRecord(
                id: "b-\(i)", audiobookID: "test", spineHref: "ch1.xhtml",
                spineIndex: 0, blockIndex: i, sequenceIndex: i,
                blockKind: "paragraph", text: "Block \(i)", imagePath: nil,
                chapterIndex: 0, isHidden: false, hiddenReason: nil,
                createdAt: nil, modifiedAt: nil
            )
            try epubDAO.insert(block)
        }

        let anchorDAO = AlignmentAnchorDAO(db: db.writer)
        try anchorDAO.insert(AlignmentAnchorRecord(
            id: "a-0", audiobookID: "test", epubBlockID: "b-0",
            audioTime: 0, audioEndTime: nil, anchorKind: "point",
            source: "moveToNow", note: nil, createdAt: nil, modifiedAt: nil
        ))
        try anchorDAO.insert(AlignmentAnchorRecord(
            id: "a-4", audiobookID: "test", epubBlockID: "b-4",
            audioTime: 100, audioEndTime: nil, anchorKind: "point",
            source: "moveToNow", note: nil, createdAt: nil, modifiedAt: nil
        ))

        let service = AlignmentService(database: db)
        try service.recalculateTimeline(audiobookID: "test")

        let timelineDAO = TimelineDAO(db: db.writer)
        let items = try timelineDAO.items(for: "test")
        let epubItems = items.filter { $0.sourceTable == "epub_block" }.sorted { ($0.epubSequenceIndex ?? 0) < ($1.epubSequenceIndex ?? 0) }

        #expect(epubItems.count == 5)
        #expect(epubItems[0].audioStartTime == 0)   // locked anchor
        #expect(epubItems[4].audioStartTime == 100)  // locked anchor
        // Middle items interpolate: b-1 at ~25, b-2 at ~50, b-3 at ~75
        #expect(epubItems[1].audioStartTime > 0 && epubItems[1].audioStartTime < 100)
        #expect(epubItems[2].audioStartTime > 0 && epubItems[2].audioStartTime < 100)
        #expect(epubItems[3].audioStartTime > 0 && epubItems[3].audioStartTime < 100)
    }

    @Test("recalculateTimeline: blocks before first anchor remain unaligned")
    func blocksBeforeFirstAnchor() throws {
        let db = try DatabaseService(inMemory: ())
        let epubDAO = EpubBlockDAO(db: db.writer)

        for i in 0..<3 {
            try epubDAO.insert(EpubBlockRecord(
                id: "b-\(i)", audiobookID: "test", spineHref: "ch1.xhtml",
                spineIndex: 0, blockIndex: i, sequenceIndex: i,
                blockKind: "paragraph", text: "Block \(i)", imagePath: nil,
                chapterIndex: 0, isHidden: false, hiddenReason: nil,
                createdAt: nil, modifiedAt: nil
            ))
        }

        // Only anchor the last block
        let anchorDAO = AlignmentAnchorDAO(db: db.writer)
        try anchorDAO.insert(AlignmentAnchorRecord(
            id: "a-2", audiobookID: "test", epubBlockID: "b-2",
            audioTime: 50, audioEndTime: nil, anchorKind: "point",
            source: "moveToNow", note: nil, createdAt: nil, modifiedAt: nil
        ))

        let service = AlignmentService(database: db)
        try service.recalculateTimeline(audiobookID: "test")

        let timelineDAO = TimelineDAO(db: db.writer)
        let items = try timelineDAO.items(for: "test")
        let epubItems = items.filter { $0.sourceTable == "epub_block" }.sorted { ($0.epubSequenceIndex ?? 0) < ($1.epubSequenceIndex ?? 0) }

        // Blocks before the only anchor should be estimated (not locked)
        #expect(epubItems[0].alignmentStatus == "estimated")
        #expect(epubItems[2].alignmentStatus == "lockedAnchor")
    }

    @Test("recalculateTimeline: hidden blocks are marked omitted")
    func hiddenBlocksOmitted() throws {
        let db = try DatabaseService(inMemory: ())
        let epubDAO = EpubBlockDAO(db: db.writer)

        try epubDAO.insert(EpubBlockRecord(
            id: "b-ok", audiobookID: "test", spineHref: "ch1.xhtml",
            spineIndex: 0, blockIndex: 0, sequenceIndex: 0,
            blockKind: "paragraph", text: "Visible", imagePath: nil,
            chapterIndex: 0, isHidden: false, hiddenReason: nil,
            createdAt: nil, modifiedAt: nil
        ))
        try epubDAO.insert(EpubBlockRecord(
            id: "b-hid", audiobookID: "test", spineHref: "ch1.xhtml",
            spineIndex: 0, blockIndex: 1, sequenceIndex: 1,
            blockKind: "paragraph", text: "Hidden", imagePath: nil,
            chapterIndex: 0, isHidden: true, hiddenReason: "skipped",
            createdAt: nil, modifiedAt: nil
        ))

        let service = AlignmentService(database: db)
        try service.recalculateTimeline(audiobookID: "test")

        let timelineDAO = TimelineDAO(db: db.writer)
        let items = try timelineDAO.items(for: "test")
        let hidden = items.first { $0.epubBlockID == "b-hid" }
        #expect(hidden?.alignmentStatus == "omitted")
        #expect(hidden?.isEnabled == false)
    }
}
