import Foundation
import GRDB

struct PlaybackStateDAO {
    let db: DatabaseWriter

    func all() throws -> [PlaybackStateRecord] {
        try db.read { db in
            try PlaybackStateRecord
                .order(Column("last_played_at").desc)
                .fetchAll(db)
        }
    }

    func get(_ audiobookID: String) throws -> PlaybackStateRecord? {
        try db.read { db in try PlaybackStateRecord.fetchOne(db, key: audiobookID) }
    }

    func upsert(_ record: PlaybackStateRecord) throws {
        var copy = record
        try db.write { db in try copy.save(db) }
    }
}

struct PlaybackStateRecord: Codable, FetchableRecord, MutablePersistableRecord {
    var audiobookID: String
    var lastPosition: Double
    var speed: Double
    var lastPlayedAt: String?

    static let databaseTableName = "playback_state"

    enum CodingKeys: String, CodingKey {
        case audiobookID = "audiobook_id"
        case lastPosition = "last_position"
        case speed
        case lastPlayedAt = "last_played_at"
    }
}
