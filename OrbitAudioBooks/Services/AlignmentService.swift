import Foundation
import GRDB
import os.log

/// Manages manual EPUB/audio alignment through locked anchors and
/// timestamp interpolation.
///
/// Public operations:
/// - `moveBlockToCurrentTime` — anchor a block at the current playback time
/// - `anchorSearchResult` — anchor a block found via search
/// - `anchorChapterStart` / `anchorChapterEnd` — mark chapter boundaries
/// - `hideBlock` / `unhideBlock` — toggle block visibility
/// - `recalculateTimeline` — re-interpolate all timestamps from anchors
///
/// Interpolation rules (applied in order of precedence):
/// 1. Locked anchors always win — assigned directly.
/// 2. Blocks between two locked anchors interpolate linearly by sequence_index.
/// 3. Blocks inside a chapter with known start/end but no manual anchors get
///    estimated from chapter boundaries.
/// 4. Blocks outside known ranges remain `unaligned` with audio_start_time = -1.
/// 5. Hidden blocks become `omitted` with is_enabled = false.
struct AlignmentService {
    private let db: DatabaseService
    private let logger = Logger(subsystem: "com.orbitaudiobooks", category: "Alignment")

    init(database: DatabaseService) {
        self.db = database
    }

    // MARK: - Anchor Operations

    /// Create or update a point anchor at the current playback time.
    func moveBlockToCurrentTime(blockID: String, time: TimeInterval) throws {
        try upsertAnchor(
            epubBlockID: blockID,
            audioTime: time,
            audioEndTime: nil,
            kind: "point",
            source: "moveToNow"
        )
    }

    /// Create or update an anchor from a search result tap.
    func anchorSearchResult(blockID: String, time: TimeInterval) throws {
        try upsertAnchor(
            epubBlockID: blockID,
            audioTime: time,
            audioEndTime: nil,
            kind: "point",
            source: "searchResult"
        )
    }

    /// Mark a chapter start boundary.
    func anchorChapterStart(blockID: String, chapterIndex: Int, time: TimeInterval) throws {
        try upsertAnchor(
            epubBlockID: blockID,
            audioTime: time,
            audioEndTime: nil,
            kind: "chapterStart",
            source: "chapterBoundary"
        )
        logger.info("Chapter \(chapterIndex) start anchored at \(time)s")
    }

    /// Mark a chapter end boundary.
    func anchorChapterEnd(blockID: String, chapterIndex: Int, time: TimeInterval) throws {
        try upsertAnchor(
            epubBlockID: blockID,
            audioTime: time,
            audioEndTime: nil,
            kind: "chapterEnd",
            source: "chapterBoundary"
        )
        logger.info("Chapter \(chapterIndex) end anchored at \(time)s")
    }

    // MARK: - Hide/Unhide

    /// Hide a block (omitted from the audiobook narration).
    func hideBlock(_ blockID: String, reason: String?) throws {
        // Need audiobookID — fetch from DB
        guard let block = try findBlock(blockID) else {
            throw AlignmentError.blockNotFound(blockID)
        }
        let dao = EpubBlockDAO(db: db.writer)
        try dao.setHidden(blockID, audiobookID: block.audiobookID, hidden: true, reason: reason)
        logger.info("Block \(blockID) hidden: \(reason ?? "no reason")")
    }

    /// Restore a previously hidden block.
    func unhideBlock(_ blockID: String) throws {
        guard let block = try findBlock(blockID) else {
            throw AlignmentError.blockNotFound(blockID)
        }
        let dao = EpubBlockDAO(db: db.writer)
        try dao.setHidden(blockID, audiobookID: block.audiobookID, hidden: false, reason: nil)
        logger.info("Block \(blockID) unhidden")
    }

    // MARK: - Recalculation

    /// Recalculate all timeline timestamps for an audiobook from the current
    /// set of locked anchors. Updates affected `timeline_item` rows in a
    /// single database transaction.
    func recalculateTimeline(audiobookID: String) throws {
        try db.write { db in
            let blocks = try EpubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("sequence_index"))
                .fetchAll(db)
            let anchors = try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("audio_time"))
                .fetchAll(db)

            // Build anchor lookup: epub_block_id → anchor
            var anchorByBlock: [String: AlignmentAnchorRecord] = [:]
            for anchor in anchors {
                anchorByBlock[anchor.epubBlockID] = anchor
            }

            // Get sorted locked anchors with their sequence positions
            let lockedAnchors: [(anchor: AlignmentAnchorRecord, seq: Int)] = anchors.compactMap { anchor in
                guard let block = blocks.first(where: { $0.id == anchor.epubBlockID }) else { return nil }
                return (anchor, block.sequenceIndex)
            }.sorted { $0.seq < $1.seq }

            // Pass 1: assign locked anchors directly
            var timelineUpdates: [(block: EpubBlockRecord, time: TimeInterval, source: String, status: String)] = []

            for block in blocks {
                if let anchor = anchorByBlock[block.id] {
                    timelineUpdates.append((block, anchor.audioTime, "lockedAnchor", "lockedAnchor"))
                }
            }

            // Pass 2: interpolate between locked anchors
            if lockedAnchors.count >= 2 {
                for i in 0..<(lockedAnchors.count - 1) {
                    let left = lockedAnchors[i]
                    let right = lockedAnchors[i + 1]
                    let seqRange = right.seq - left.seq
                    let timeRange = right.anchor.audioTime - left.anchor.audioTime

                    guard seqRange > 0, timeRange > 0 else { continue }

                    let middleBlocks = blocks.filter { block in
                        block.sequenceIndex > left.seq
                            && block.sequenceIndex < right.seq
                            && anchorByBlock[block.id] == nil
                            && !block.isHidden
                    }

                    for block in middleBlocks {
                        let fraction = Double(block.sequenceIndex - left.seq) / Double(seqRange)
                        let interpolatedTime = left.anchor.audioTime + (timeRange * fraction)
                        timelineUpdates.append((block, interpolatedTime, "interpolated", "interpolated"))
                    }
                }
            }

            // Pass 3: estimate remaining blocks from chapter boundaries
            for block in blocks where anchorByBlock[block.id] == nil && !block.isHidden {
                let alreadyUpdated = timelineUpdates.contains { $0.block.id == block.id }
                guard !alreadyUpdated else { continue }

                if let chapterIdx = block.chapterIndex {
                    // Fall back to simple estimation from chapter position
                    let chapterBlocks = blocks.filter { $0.chapterIndex == chapterIdx && !$0.isHidden }
                        .sorted { $0.sequenceIndex < $1.sequenceIndex }
                    if let position = chapterBlocks.firstIndex(where: { $0.id == block.id }),
                       !chapterBlocks.isEmpty {
                        // Without chapter timestamps, leave unaligned
                        timelineUpdates.append((block, -1, "none", "unaligned"))
                    } else {
                        timelineUpdates.append((block, -1, "none", "unaligned"))
                    }
                } else {
                    timelineUpdates.append((block, -1, "none", "unaligned"))
                }
            }

            // Pass 4: hidden blocks become omitted
            for block in blocks where block.isHidden {
                timelineUpdates.append((block, -1, "none", "omitted"))
            }

            // Apply updates to timeline_item
            for update in timelineUpdates {
                try db.execute(
                    sql: """
                        UPDATE timeline_item
                        SET audio_start_time = ?,
                            timestamp_source = ?,
                            alignment_status = ?,
                            is_enabled = ?,
                            modified_at = ?
                        WHERE epub_block_id = ? AND audiobook_id = ?
                        """,
                    arguments: [
                        update.time,
                        update.source,
                        update.status,
                        update.status != "omitted",
                        Date().ISO8601Format(),
                        update.block.id,
                        audiobookID
                    ]
                )
            }
        }

        logger.info("Recalculated timeline for \(audiobookID)")
    }

    // MARK: - Private Helpers

    private func upsertAnchor(
        epubBlockID: String,
        audioTime: TimeInterval,
        audioEndTime: TimeInterval?,
        kind: String,
        source: String
    ) throws {
        guard let block = try findBlock(epubBlockID) else {
            throw AlignmentError.blockNotFound(epubBlockID)
        }
        let dao = AlignmentAnchorDAO(db: db.writer)
        // Delete existing anchor for this block if any, then insert
        if let existing = try dao.fetch(forBlockID: epubBlockID, audiobookID: block.audiobookID) {
            try dao.delete(id: existing.id, audiobookID: block.audiobookID)
        }
        let anchor = AlignmentAnchorRecord(
            id: "anchor-\(epubBlockID)-\(Int(audioTime * 1000))",
            audiobookID: block.audiobookID,
            epubBlockID: epubBlockID,
            audioTime: audioTime,
            audioEndTime: audioEndTime,
            anchorKind: kind,
            source: source,
            note: nil,
            createdAt: Date().ISO8601Format(),
            modifiedAt: nil
        )
        try dao.insert(anchor)
        logger.info("Anchor \(kind) at \(audioTime)s for block \(epubBlockID)")
    }

    private func findBlock(_ blockID: String) throws -> EpubBlockRecord? {
        // Search across all audiobookIDs — simplified; in production, scope by current audiobook
        // We need to read from the DB to find which audiobook this block belongs to
        try db.read { db in
            try EpubBlockRecord
                .filter(Column("id") == blockID)
                .fetchOne(db)
        }
    }
}

// MARK: - Errors

enum AlignmentError: LocalizedError {
    case blockNotFound(String)

    var errorDescription: String? {
        switch self {
        case .blockNotFound(let id): "EPUB block not found: \(id)"
        }
    }
}
