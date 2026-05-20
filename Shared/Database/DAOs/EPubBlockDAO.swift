import Foundation
import GRDB

struct EPubBlockDAO {
    let db: DatabaseWriter

    // MARK: - Insert / Delete

    func insertAll(_ blocks: [EPubBlockRecord], audiobookID: String) throws {
        guard !blocks.isEmpty else { return }
        try db.write { db in
            for var block in blocks {
                try block.insert(db)
            }
        }
    }

    func deleteAll(for audiobookID: String) throws {
        _ = try db.write { db in
            try EPubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .deleteAll(db)
        }
    }

    // MARK: - Queries

    func all(for audiobookID: String) throws -> [EPubBlockRecord] {
        try db.read { db in
            try EPubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .order(Column("sequence_index"))
                .fetchAll(db)
        }
    }

    func visible(for audiobookID: String) throws -> [EPubBlockRecord] {
        try db.read { db in
            try EPubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("is_hidden") == false)
                .order(Column("sequence_index"))
                .fetchAll(db)
        }
    }

    func blocks(inChapter chapterIndex: Int, audiobookID: String) throws -> [EPubBlockRecord] {
        try db.read { db in
            try EPubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("chapter_index") == chapterIndex)
                .order(Column("sequence_index"))
                .fetchAll(db)
        }
    }

    func block(id: String) throws -> EPubBlockRecord? {
        try db.read { db in
            try EPubBlockRecord.fetchOne(db, key: id)
        }
    }

    // MARK: - Hide / Unhide

    func hideBlock(id: String, reason: String?) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE epub_block
                    SET is_hidden = 1, hidden_reason = :reason, modified_at = :now
                    WHERE id = :id
                    """,
                arguments: ["id": id, "reason": reason, "now": Date().ISO8601Format()]
            )
        }
    }

    func unhideBlock(id: String) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE epub_block
                    SET is_hidden = 0, hidden_reason = NULL, modified_at = :now
                    WHERE id = :id
                    """,
                arguments: ["now": Date().ISO8601Format()]
            )
        }
    }

    // MARK: - Search

    func search(query: String, audiobookID: String, limit: Int = 20) throws -> [EPubBlockRecord] {
        try db.read { db in
            try EPubBlockRecord
                .filter(Column("audiobook_id") == audiobookID)
                .filter(Column("text") != nil)
                .filter(Column("text").like("%\(query)%"))
                .order(Column("sequence_index"))
                .limit(limit)
                .fetchAll(db)
        }
    }
}
