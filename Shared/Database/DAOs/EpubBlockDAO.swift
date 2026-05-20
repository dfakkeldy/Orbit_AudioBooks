import Foundation
import GRDB

struct EpubBlockDAO {
    let db: DatabaseWriter

    func insert(_ block: EpubBlockRecord) throws {
        var mutable = block
        try db.write { db in
            try mutable.insert(db)
        }
    }

    func insertAll(_ blocks: [EpubBlockRecord], audiobookID: String) throws {
        guard !blocks.isEmpty else { return }
        try db.write { db in
            for var block in blocks {
                try block.insert(db)
            }
        }
    }

    func fetchAll(for audiobookID: String) throws -> [EpubBlockRecord] {
        try db.read { db in
            try EpubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("sequence_index"))
                .fetchAll(db)
        }
    }

    func fetchVisible(for audiobookID: String) throws -> [EpubBlockRecord] {
        try db.read { db in
            try EpubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("is_hidden") == false)
                .order(Column("sequence_index"))
                .fetchAll(db)
        }
    }

    func fetch(forID id: String, audiobookID: String) throws -> EpubBlockRecord? {
        try db.read { db in
            try EpubBlockRecord
                .filter(Column("id") == id)
                .filter(Column("audiobook_id") == audiobookID)
                .fetchOne(db)
        }
    }

    func fetchByChapter(for audiobookID: String, chapterIndex: Int) throws -> [EpubBlockRecord] {
        try db.read { db in
            try EpubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("chapter_index") == chapterIndex)
                .filter(Column("is_hidden") == false)
                .order(Column("sequence_index"))
                .fetchAll(db)
        }
    }

    func setHidden(_ id: String, audiobookID: String, hidden: Bool, reason: String?) throws {
        try db.write { db in
            let now = Date().ISO8601Format()
            try db.execute(
                sql: """
                    UPDATE epub_block
                    SET is_hidden = ?, hidden_reason = ?, modified_at = ?
                    WHERE id = ? AND audiobook_id = ?
                    """,
                arguments: [hidden, reason, now, id, audiobookID]
            )
        }
    }

    func deleteAll(for audiobookID: String) throws {
        _ = try db.write { db in
            try EpubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }
}
