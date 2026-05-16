import Foundation
@testable import Orbit_Audiobooks

/// In-memory SettingsManager for unit testing.
final class MockSettingsManager: SettingsManagerProtocol {
    var isDarkMode: Bool = true
    var appFont: String = "Lexend"

    var isRewindEnabled: Bool = false
    var rewindPauseSecondsThreshold: Int = 30
    var rewindAmountAfterSeconds: Int = 10
    var rewindPauseMinutesThreshold: Int = 5
    var rewindAmountAfterMinutes: Int = 30
    var rewindPauseHoursThreshold: Int = 1
    var rewindAmountAfterHours: Int = 90
    var rewindHoursToChapterStart: Bool = false

    var playBookmarksInline: Bool = true

    var crownAction: String = "volume"
    var crownVolumeSensitivity: Double = 0.05
    var crownScrubSensitivity: Double = 0.5
    var watchPage1: String = "empty,empty,skipBackward,playPause,skipForward"
    var watchPage2: String = "loopMode,empty,speed,sleepTimer,bookmark"
    var linearBarMode: String = "total"
    var linearBarHidden: Bool = false
    var circularRingMode: String = "chapter"
    var circularRingHidden: Bool = false
    var watchArtworkLayout: String = "immersive"
    var watchBackgroundStyle: String = "artwork"
    var isHapticFeedbackEnabled: Bool = true
    var watchQuickBookmarkTimeoutSeconds: Int = 5

    static var systemFontName: String { "System" }
}
