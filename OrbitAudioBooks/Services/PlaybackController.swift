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

    init() {
        audioEngine.delegate = self
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

    // MARK: - Internal

    func applySpeedToCurrentItem() {
        guard audioEngine.isItemLoaded else { return }
        audioEngine.setSpeed(speed)
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
