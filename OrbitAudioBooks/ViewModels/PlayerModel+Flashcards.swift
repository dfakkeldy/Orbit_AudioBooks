import Foundation

// MARK: - Inline Flashcard Triggers

extension PlayerModel {

    /// Polls flashcard timestamps on each time tick and fires an inline overlay when
    /// playback crosses a card's trigger point. Follows the same tolerance/deduplication
    /// pattern as voice memo triggers.
    func checkInlineFlashcardTrigger(at currentSeconds: Double, previousSeconds: Double?) {
        guard activeInlineCard == nil, isPlaying, !isManualSeeking,
              loopMode != .bookmark else { return }

        let toleranceAfter: Double = 0.75

        let trackKey = tracks.indices.contains(currentIndex)
            ? tracks[currentIndex].url.lastPathComponent : ""
        if cachedTrackFlashcardKey != trackKey, let db = databaseService {
            cachedTrackFlashcards = (try? FlashcardDAO(db: db.writer).flashcards(for: trackKey)) ?? []
            cachedTrackFlashcardKey = trackKey
        }
        let cards = cachedTrackFlashcards

        for card in cards {
            guard card.triggerTiming != "manualOnly" else { continue }
            guard !triggeredFlashcardIDs.contains(card.id) else { continue }

            let triggerTime = card.mediaTimestamp

            // Check if playback just crossed the trigger point.
            let crossed: Bool
            if let prev = previousSeconds, prev.isFinite {
                crossed = prev <= triggerTime && currentSeconds > triggerTime
            } else {
                crossed = abs(currentSeconds - triggerTime) <= toleranceAfter
            }
            guard crossed else { continue }

            // Deduplicate: don't fire within 5s of last trigger.
            if abs(currentSeconds - lastFlashcardTriggerSecond) < 5 { continue }

            lastFlashcardTriggerSecond = currentSeconds
            triggeredFlashcardIDs.insert(card.id)
            wasPlayingBeforeFlashcard = true
            audioEngine.pause()
            activeInlineCard = card
            return
        }
    }

    /// Grades the currently shown inline flashcard and resumes playback.
    func gradeInlineFlashcard(_ grade: Int) {
        guard let card = activeInlineCard else { return }
        if let db = databaseService {
            try? FlashcardDAO(db: db.writer).grade(cardID: card.id, grade: grade)
        }
        activeInlineCard = nil
        if wasPlayingBeforeFlashcard {
            wasPlayingBeforeFlashcard = false
            audioEngine.playImmediately(atRate: speed)
            playbackController.applySpeedToCurrentItem()
        }
    }

    /// Dismisses the inline flashcard overlay without grading, resuming playback.
    func dismissInlineFlashcard() {
        activeInlineCard = nil
        if wasPlayingBeforeFlashcard {
            wasPlayingBeforeFlashcard = false
            audioEngine.playImmediately(atRate: speed)
            playbackController.applySpeedToCurrentItem()
        }
    }
}
