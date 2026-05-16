import Foundation
@testable import Orbit_Audiobooks

/// Configurable SleepTimerManager for unit testing.
final class MockSleepTimerManager: SleepTimerManagerProtocol {
    var mode: SleepTimerMode = .off
    var secondsRemaining: TimeInterval = 0
    var countdownText: String = ""

    var setTimerCallCount = 0
    var setTimerMinutes: [Int] = []
    var setEndOfChapterCallCount = 0
    var cancelCallCount = 0

    func setTimer(minutes: Int) {
        setTimerCallCount += 1
        setTimerMinutes.append(minutes)
        mode = .minutes(minutes)
    }

    func setEndOfChapter() {
        setEndOfChapterCallCount += 1
        mode = .endOfChapter
    }

    func cancel() {
        cancelCallCount += 1
        mode = .off
    }
}
