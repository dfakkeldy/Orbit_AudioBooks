import Foundation
import AVFoundation
import Observation

// MARK: - PlaybackControllerDelegate

protocol PlaybackControllerDelegate: AnyObject {
    func playbackController(_ controller: PlaybackController, didUpdateTime currentTime: TimeInterval)
    func playbackControllerDidPlayToEnd(_ controller: PlaybackController)
    func playbackControllerInterruptionBegan(_ controller: PlaybackController)
    func playbackControllerInterruptionEnded(_ controller: PlaybackController, shouldResume: Bool)
}

// MARK: - PlaybackController

@Observable
final class PlaybackController {
    let audioEngine = AudioEngine()
    weak var delegate: PlaybackControllerDelegate?

    var speed: Float = 1.25
    var loopMode: LoopMode = .off
    var isVolumeBoostEnabled: Bool = false

    var isPlaying: Bool { audioEngine.isPlaying }
    var currentTime: TimeInterval { audioEngine.currentTime }
    var duration: TimeInterval? { audioEngine.duration }

    // Coordinators — set by PlayerModel to handle cross-cutting concerns.
    @ObservationIgnored var coordinator_smartRewind: ((_ pausedDuration: TimeInterval) -> Double)?
    @ObservationIgnored var coordinator_jumpToChapterStartForHours: ((_ pausedDuration: TimeInterval) -> Bool)?
    @ObservationIgnored var coordinator_loadTrack: ((_ index: Int, _ autoplay: Bool) -> Void)?
    @ObservationIgnored var coordinator_persistAndSync: ((_ isPaused: Bool) -> Void)?
    @ObservationIgnored var coordinator_checkVoiceMemo: ((_ at: Double, _ previous: Double?) -> Void)?
    @ObservationIgnored var coordinator_seekCompleted: ((_ isManual: Bool) -> Void)?

    init() {
        audioEngine.delegate = self
    }

    // MARK: - Pure Helpers

    func findNextEnabledTrackIndex(in tracks: [Track], currentIndex: Int) -> Int? {
        guard !tracks.isEmpty else { return nil }
        for i in (currentIndex + 1)..<tracks.count {
            if tracks[i].isEnabled { return i }
        }
        return nil
    }

    func findPrevEnabledTrackIndex(in tracks: [Track], currentIndex: Int) -> Int? {
        guard !tracks.isEmpty else { return nil }
        for i in stride(from: currentIndex - 1, through: 0, by: -1) {
            if tracks[i].isEnabled { return i }
        }
        return nil
    }

    func applySpeedToCurrentItem() {
        audioEngine.setSpeed(speed)
        if isPlaying {
            audioEngine.playImmediately(atRate: speed)
        }
    }

    // MARK: - Playback Commands

    func play() {
        audioEngine.play()
        applySpeedToCurrentItem()
    }

    func pause() {
        audioEngine.pause()
    }

    func togglePlayPause() {
        if audioEngine.isPlaying {
            audioEngine.pause()
        } else {
            audioEngine.play()
            applySpeedToCurrentItem()
        }
    }

    func seek(to time: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        audioEngine.seek(to: time, completion: completion)
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        applySpeedToCurrentItem()
    }

    func setVolumeBoost(enabled: Bool) {
        isVolumeBoostEnabled = enabled
        audioEngine.setVolumeBoost(enabled: enabled)
    }

    func setLoopMode(_ mode: LoopMode) {
        loopMode = mode
    }

    func stop() {
        audioEngine.stop()
    }

    func replaceCurrentItem(with url: URL, startTime: TimeInterval? = nil) {
        audioEngine.replaceCurrentItem(with: url, startTime: startTime)
    }
}

// MARK: - AudioEngineDelegate

extension PlaybackController: AudioEngineDelegate {
    func audioEngineDidUpdateTime(_ engine: AudioEngine, currentTime: TimeInterval) {
        delegate?.playbackController(self, didUpdateTime: currentTime)
    }

    func audioEngineDidPlayToEnd(_ engine: AudioEngine) {
        delegate?.playbackControllerDidPlayToEnd(self)
    }

    func audioEngineInterruptionBegan(_ engine: AudioEngine) {
        delegate?.playbackControllerInterruptionBegan(self)
    }

    func audioEngineInterruptionEnded(_ engine: AudioEngine, shouldResume: Bool) {
        delegate?.playbackControllerInterruptionEnded(self, shouldResume: shouldResume)
    }
}
