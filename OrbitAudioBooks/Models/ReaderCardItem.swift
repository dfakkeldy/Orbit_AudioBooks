import Foundation

/// Items displayed in the EPUB reader feed.
enum ReaderCardItem: Hashable {
    /// A divider between chapters showing the chapter title.
    case chapterHeader(title: String, chapterIndex: Int)
    /// An EPUB block (heading, paragraph, or image).
    case block(EPubBlockRecord)
    // Future: case flashcard(Flashcard, associatedBlockIDs: [String], placement: FlashcardPlacement)
}
