import Foundation
import GRDB

/// GRDB record for the `session_location` table (V14).
struct SessionLocationRecord: Codable, FetchableRecord, PersistableRecord {
    var playbackEventID: Int64
    var latitude: Double
    var longitude: Double
    var placeName: String?
    var createdAt: String

    static let databaseTableName = "session_location"

    enum CodingKeys: String, CodingKey {
        case playbackEventID = "playback_event_id"
        case latitude
        case longitude
        case placeName = "place_name"
        case createdAt = "created_at"
    }
}
