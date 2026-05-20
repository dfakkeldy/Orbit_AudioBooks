import Foundation
import GRDB

struct AlignmentAnchorDAO {
    let db: DatabaseWriter

    func insert(_ anchor: AlignmentAnchorRecord) throws {
        var mutable = anchor
        try db.write { db in
            try mutable.insert(db)
        }
    }

    func insertAll(_ anchors: [AlignmentAnchorRecord], audiobookID: String) throws {
        guard !anchors.isEmpty else { return }
        try db.write { db in
            for var anchor in anchors {
                try anchor.insert(db)
            }
        }
    }

    func fetchAll(for audiobookID: String) throws -> [AlignmentAnchorRecord] {
        try db.read { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("audio_time"))
                .fetchAll(db)
        }
    }

    func fetch(forBlockID epubBlockID: String, audiobookID: String) throws -> AlignmentAnchorRecord? {
        try db.read { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("epub_block_id") == epubBlockID)
                .fetchOne(db)
        }
    }

    func delete(id: String, audiobookID: String) throws {
        _ = try db.write { db in
            try AlignmentAnchorRecord
                .filter(Column("id") == id)
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }

    func deleteAll(for audiobookID: String) throws {
        _ = try db.write { db in
            try AlignmentAnchorRecord
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }
}
