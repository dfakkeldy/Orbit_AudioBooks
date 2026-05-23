import SwiftUI

// MARK: - PlaybackControllerDelegate

extension PlayerModel: PlaybackControllerDelegate {
    func playbackController(_ controller: PlaybackController, didUpdateTime currentTime: TimeInterval) {
        autoreleasepool {
            updateNowPlayingElapsedTime()
            updateCurrentChapterFromPlayerTime()
            updateProgressFromPlayer()
            updateCurrentDisplayArtwork(at: currentTime)
            playbackController.enforceEnabledState()
            playbackController.applyChapterLoopIfNeeded()
            playbackController.applyBookmarkLoopIfNeeded()
            if resolvedPlayBookmarksInline,
               currentTime.isFinite {
                checkVoiceMemoTrigger(at: currentTime, previousSeconds: lastBookmarkCheckSecond)
                checkInlineFlashcardTrigger(at: currentTime, previousSeconds: lastBookmarkCheckSecond)
                lastBookmarkCheckSecond = currentTime
            }
        }
    }

    func playbackControllerDidPlayToEnd(_ controller: PlaybackController) {
        playbackController.handleTrackEnded()
    }

    func playbackControllerInterruptionBegan(_ controller: PlaybackController) {
        pause()
    }

    func playbackControllerInterruptionEnded(_ controller: PlaybackController, shouldResume: Bool) {
        if shouldResume {
            play()
        }
    }
}
