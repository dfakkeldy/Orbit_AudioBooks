import Foundation
@testable import Orbit_Audiobooks

/// Configurable PlaybackController for unit testing.
final class MockPlaybackController: PlaybackControllerProtocol {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval? = 300
    var speed: Float = 1.0

    var playCallCount = 0
    var pauseCallCount = 0
    var togglePlayPauseCallCount = 0
    var skipForwardCallCount = 0
    var skipBackwardCallCount = 0
    var seekCalls: [TimeInterval] = []
    var skipToNextChapterCallCount = 0
    var skipToPreviousChapterCallCount = 0

    func play() {
        isPlaying = true
        playCallCount += 1
    }

    func pause() {
        isPlaying = false
        pauseCallCount += 1
    }

    func togglePlayPause() {
        isPlaying.toggle()
        togglePlayPauseCallCount += 1
    }

    func skipForward() {
        currentTime += 30
        skipForwardCallCount += 1
    }

    func skipBackward() {
        currentTime = max(0, currentTime - 30)
        skipBackwardCallCount += 1
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        seekCalls.append(time)
    }

    func skipToNextChapter() {
        skipToNextChapterCallCount += 1
    }

    func skipToPreviousChapter() {
        skipToPreviousChapterCallCount += 1
    }
}
