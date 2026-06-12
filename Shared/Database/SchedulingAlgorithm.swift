import Foundation

/// Protocol seam for scheduling algorithms — v1.0 ships SM-2, FSRS for post-1.0.
protocol SchedulingAlgorithm: Sendable {
    /// Applies a review grade (0–5) to a card, returning the updated card with
    /// new interval, ease, due date, and review metadata.
    func review(card: Flashcard, grade: Int, now: Date) -> Flashcard
}

/// SM-2 spaced repetition algorithm with deterministic `now` injection.
struct SM2Scheduler: SchedulingAlgorithm {

    func review(card: Flashcard, grade: Int, now: Date) -> Flashcard {
        var updated = card

        if grade >= 3 {
            if updated.repetitions == 0 {
                updated.intervalDays = 1
            } else if updated.repetitions == 1 {
                updated.intervalDays = 6
            } else {
                updated.intervalDays = Int(Double(updated.intervalDays) * updated.easeFactor)
            }
            updated.repetitions += 1
        } else {
            updated.repetitions = 0
            updated.intervalDays = 1
        }

        updated.easeFactor = max(
            1.3,
            updated.easeFactor + (0.1 - Double(5 - grade) * (0.08 + Double(5 - grade) * 0.02))
        )
        updated.lastReviewedAt = now.ISO8601Format()
        updated.lastGrade = grade
        updated.modifiedAt = now.ISO8601Format()

        if let nextDate = Calendar.current.date(byAdding: .day, value: updated.intervalDays, to: now) {
            updated.nextReviewDate = nextDate.ISO8601Format()
        }

        return updated
    }
}
