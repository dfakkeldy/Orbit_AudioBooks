import Foundation
import GRDB

/// A single structural block extracted from an EPUB spine item.
/// Blocks are ordered by `sequence_index` across all spine items,
/// preserving the author's intended reading order.
struct EPubBlockRecord: Identifiable, Equatable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var audiobookID: String
    var spineHref: String
    var spineIndex: Int
    var blockIndex: Int
    var sequenceIndex: Int
    var blockKind: String
    var text: String?
    var imagePath: String?
    var chapterIndex: Int?
    var isHidden: Bool
    var hiddenReason: String?
    var createdAt: String?
    var modifiedAt: String?

    static let databaseTableName = "epub_block"

    enum CodingKeys: String, CodingKey {
        case id
        case audiobookID = "audiobook_id"
        case spineHref = "spine_href"
        case spineIndex = "spine_index"
        case blockIndex = "block_index"
        case sequenceIndex = "sequence_index"
        case blockKind = "block_kind"
        case text
        case imagePath = "image_path"
        case chapterIndex = "chapter_index"
        case isHidden = "is_hidden"
        case hiddenReason = "hidden_reason"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }
}

// MARK: - Block Kind Constants

extension EPubBlockRecord {
    enum BlockKind: String {
        case heading = "heading"
        case paragraph = "paragraph"
        case sentence = "sentence"
        case image = "image"
    }
}
