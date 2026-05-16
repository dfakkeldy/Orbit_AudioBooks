import Foundation
@testable import Orbit_Audiobooks

/// In-memory BookmarkStore for unit testing.
final class MockBookmarkStore: BookmarkStoreProtocol {
    var bookmarks: [Bookmark] = []
    var bookmarkToAdd: Bookmark?
    var deletedBookmarkIDs: [UUID] = []
    var updatedBookmarkNotes: [(UUID, String)] = []

    var currentTrackBookmarks: [Bookmark] {
        bookmarks.filter { $0.isEnabled }
    }

    func addBookmark(at time: TimeInterval, note: String?) -> Bookmark {
        let bookmark = Bookmark(timestamp: time, note: note)
        bookmarks.append(bookmark)
        bookmarkToAdd = bookmark
        return bookmark
    }

    func deleteBookmark(id: UUID) {
        deletedBookmarkIDs.append(id)
        bookmarks.removeAll { $0.id == id }
    }

    func updateBookmark(id: UUID, note: String) {
        updatedBookmarkNotes.append((id, note))
        if let index = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[index] = Bookmark(
                id: bookmarks[index].id,
                title: bookmarks[index].title,
                folderKey: bookmarks[index].folderKey,
                trackId: bookmarks[index].trackId,
                timestamp: bookmarks[index].timestamp,
                note: note,
                voiceMemoFileName: bookmarks[index].voiceMemoFileName,
                bookmarkImageFileName: bookmarks[index].bookmarkImageFileName,
                isEnabled: bookmarks[index].isEnabled
            )
        }
    }

    func exportBookmarksAsMarkdown() -> String {
        bookmarks.map { "- \($0.title) (\(Int($0.timestamp))s)" }.joined(separator: "\n")
    }
}
