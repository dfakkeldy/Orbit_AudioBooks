import Foundation

// MARK: - BookmarkStoreProtocol

protocol BookmarkStoreProtocol {
    var bookmarks: [Bookmark] { get }
    var currentTrackBookmarks: [Bookmark] { get }
    func addBookmark(at time: TimeInterval, note: String?) -> Bookmark
    func deleteBookmark(id: UUID)
    func updateBookmark(id: UUID, note: String)
    func exportBookmarksAsMarkdown() -> String
}

// MARK: - PlaybackControllerProtocol

protocol PlaybackControllerProtocol {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval? { get }
    var speed: Float { get set }
    func play()
    func pause()
    func togglePlayPause()
    func skipForward()
    func skipBackward()
    func seek(to: TimeInterval)
    func skipToNextChapter()
    func skipToPreviousChapter()
}

// MARK: - SleepTimerManagerProtocol

protocol SleepTimerManagerProtocol {
    var mode: SleepTimerMode { get }
    var secondsRemaining: TimeInterval { get }
    var countdownText: String { get }
    func setTimer(minutes: Int)
    func setEndOfChapter()
    func cancel()
}
