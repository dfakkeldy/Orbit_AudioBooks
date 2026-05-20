import Foundation
import GRDB

struct AlignmentAnchorDAO {
    let db: DatabaseWriter

    // MARK: - Insert / Delete

    func insert(_ anchor: AlignmentAnchorRecord) throws {
        var mutable = anchor
        try db.write { db in
            try mutable.insert(db)
        }
    }

    func deleteAll(for audiobookID: String) throws {
        _ = try db.write { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }

    func delete(id: String) throws {
        _ = try db.write { db in
            try AlignmentAnchorRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Queries

    func all(for audiobookID: String) throws -> [AlignmentAnchorRecord] {
        try db.read { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("audio_time"))
                .fetchAll(db)
        }
    }

    func anchor(for epubBlockID: String, audiobookID: String) throws -> AlignmentAnchorRecord? {
        try db.read { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("epub_block_id") == epubBlockID)
                .fetchOne(db)
        }
    }

    /// Anchors on or after the given time, ordered ascending.
    func anchors(from time: TimeInterval, audiobookID: String) throws -> [AlignmentAnchorRecord] {
        try db.read { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("audio_time") >= time)
                .order(Column("audio_time"))
                .fetchAll(db)
        }
    }

    /// Anchors on or before the given time, ordered descending.
    func anchors(before time: TimeInterval, audiobookID: String) throws -> [AlignmentAnchorRecord] {
        try db.read { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("audio_time") <= time)
                .order(Column("audio_time").desc)
                .fetchAll(db)
        }
    }
}
