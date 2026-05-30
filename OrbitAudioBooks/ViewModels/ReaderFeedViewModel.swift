import Foundation
import Observation
import GRDB
import os.log

/// View model for the EPUB reader feed. Loads blocks, builds the card array,
/// tracks the active block for playback sync, and handles search.
@MainActor
@Observable
final class ReaderFeedViewModel {
    private let logger = Logger(subsystem: "com.orbitaudiobooks", category: "ReaderFeed")

    let audiobookID: String
    private let blockDAO: EPubBlockDAO
    private let chapterDAO: ChapterDAO

    /// All cards in the feed (blocks + chapter dividers).
    private(set) var cards: [ReaderCardItem] = []
    /// Index of each card by block ID for fast lookup.
    private var cardIndexByBlockID: [String: Int] = [:]

    /// ID of the currently active block (based on playback position).
    var activeBlockID: String?

    /// Current search query. nil = show all blocks.
    var searchQuery: String? {
        didSet { reload() }
    }

    init(audiobookID: String, db: DatabaseWriter) {
        self.audiobookID = audiobookID
        self.blockDAO = EPubBlockDAO(db: db)
        self.chapterDAO = ChapterDAO(db: db)
    }

    /// Load blocks from the database and build the card array.
    func reload() {
        do {
            let blocks: [EPubBlockRecord]
            if let query = searchQuery, !query.isEmpty {
                blocks = try blockDAO.searchBlocks(for: audiobookID, query: query)
                cards = blocks.map { .block($0) }
            } else {
                let grouped = try blockDAO.blocksByChapter(for: audiobookID)
                var items: [ReaderCardItem] = []
                // Sort chapter indices for ordered output; -1 (no chapter) goes first.
                let sortedKeys = grouped.keys.sorted()
                for key in sortedKeys {
                    guard let chapterBlocks = grouped[key], !chapterBlocks.isEmpty else { continue }
                    let title: String
                    if key >= 0 {
                        let chapters = try? chapterDAO.chapters(for: audiobookID)
                        title = chapters?[safe: key]?.title ?? "Chapter \(key + 1)"
                    } else {
                        title = "Front Matter"
                    }
                    items.append(.chapterHeader(title: title, chapterIndex: key))
                    items.append(contentsOf: chapterBlocks.map { .block($0) })
                }
                cards = items
            }

            // Rebuild block ID index.
            cardIndexByBlockID = [:]
            for (idx, card) in cards.enumerated() {
                if case .block(let block) = card {
                    cardIndexByBlockID[block.id] = idx
                }
            }
        } catch {
            logger.error("Failed to load reader blocks: \(error.localizedDescription)")
        }
    }

    /// Update the active block based on current playback position.
    func updateActiveBlock(time: TimeInterval) {
        do {
            activeBlockID = try blockDAO.blockID(at: time, audiobookID: audiobookID)
        } catch {
            // Best-effort; if query fails, just keep the previous active block.
        }
    }

    /// Index path for a given block ID, if present in the current cards.
    func indexForBlockID(_ blockID: String) -> Int? {
        cardIndexByBlockID[blockID]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
