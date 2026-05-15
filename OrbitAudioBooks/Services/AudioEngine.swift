import AVFoundation
import Observation

// MARK: - AudioEngineDelegate

protocol AudioEngineDelegate: AnyObject {
    func audioEngineDidUpdateTime(_ engine: AudioEngine, currentTime: TimeInterval)
    func audioEngineDidPlayToEnd(_ engine: AudioEngine)
    func audioEngineInterruptionBegan(_ engine: AudioEngine)
    func audioEngineInterruptionEnded(_ engine: AudioEngine, shouldResume: Bool)
}

// MARK: - AudioEngine

/// Encapsulates AVPlayer, AVAudioSession, and time/end/interruption observers.
/// PlayerModel accesses `player` directly for domain-specific boundary observers
/// (chapter boundaries, bookmark boundaries) and receives time/end/interruption
/// events through the delegate protocol.
@Observable
final class AudioEngine {
    // MARK: - Observable State

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var speed: Float = 1.25

    // MARK: - AVPlayer Access (for boundary observers)

    private(set) var player: AVPlayer?

    // MARK: - Delegate

    weak var delegate: AudioEngineDelegate?

    // MARK: - Private State

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaServicesLostObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?
    private var audioSessionConfigured = false

    deinit {
        cleanup()
    }

    // MARK: - Audio Session

    func configureAudioSession() {
        guard !audioSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            audioSessionConfigured = true
        } catch {
            print("AudioSession error: \(error)")
        }
        setupInterruptionObserver()
        setupMediaServicesObservers()
    }

    // MARK: - Playback Controls

    func play() {
        guard let player, !isPlaying else { return }
        player.defaultRate = speed
        player.rate = speed
        isPlaying = true
    }

    func playImmediately(atRate rate: Float) {
        setSpeed(rate)
        player?.playImmediately(atRate: rate)
        isPlaying = player != nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to targetSeconds: Double, completion: ((Bool) -> Void)? = nil) {
        guard let player else { return }
        player.seek(
            to: CMTime(seconds: targetSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard let self else {
                completion?(finished)
                return
            }
            let current = player.currentTime().seconds
            if current.isFinite {
                self.currentTime = current
            } else if targetSeconds.isFinite {
                self.currentTime = targetSeconds
            }
            completion?(finished)
        }
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        if let player {
            player.defaultRate = speed
        }
        if isPlaying {
            player?.rate = speed
        }
    }

    // MARK: - Item Management

    /// Replaces the current playing item. Sets up time and end observers.
    func replaceCurrentItem(with url: URL, startTime: TimeInterval? = nil) {
        removeTimeObserver()
        removeEndObserver()
        currentTime = startTime ?? 0
        duration = nil

        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        item.preferredForwardBufferDuration = 10

        if player == nil {
            player = AVPlayer(playerItem: item)
            player?.automaticallyWaitsToMinimizeStalling = true
        } else {
            player?.replaceCurrentItem(with: item)
        }

        player?.defaultRate = speed
        if let startTime, startTime > 0 {
            player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }

        addTimeObserver()
        addEndObserver()

        Task { [weak self] in
            guard let self, let asset = self.player?.currentItem?.asset else { return }
            if let cmDuration = try? await asset.load(.duration) {
                await MainActor.run {
                    self.duration = cmDuration.seconds
                }
            }
        }
    }

    /// Stops playback and releases the AVPlayer.
    func stop() {
        player?.pause()
        isPlaying = false
        currentTime = 0
        duration = nil

        removeTimeObserver()
        removeEndObserver()
        removeInterruptionObserver()
        removeMediaServicesObservers()
        player = nil
        audioSessionConfigured = false
    }

    func cleanup() {
        stop()
    }

    // MARK: - Observers

    private func addTimeObserver() {
        removeTimeObserver()
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, time.seconds.isFinite else { return }
            self.currentTime = time.seconds
            self.delegate?.audioEngineDidUpdateTime(self, currentTime: time.seconds)
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let player {
            player.removeTimeObserver(obs)
        }
        timeObserver = nil
    }

    private func addEndObserver() {
        removeEndObserver()
        guard let item = player?.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.audioEngineDidPlayToEnd(self)
        }
    }

    private func removeEndObserver() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        endObserver = nil
    }

    private func setupInterruptionObserver() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            switch type {
            case .began:
                audioSessionConfigured = false
                self.isPlaying = false
                self.delegate?.audioEngineInterruptionBegan(self)
            case .ended:
                let optionsValue = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                self.delegate?.audioEngineInterruptionEnded(self, shouldResume: options.contains(.shouldResume))
            @unknown default:
                break
            }
        }
    }

    private func removeInterruptionObserver() {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        interruptionObserver = nil
    }

    private func setupMediaServicesObservers() {
        guard mediaServicesLostObserver == nil else { return }

        mediaServicesLostObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.delegate?.audioEngineInterruptionBegan(self)
        }

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.audioSessionConfigured = false
            self.configureAudioSession()
        }
    }

    private func removeMediaServicesObservers() {
        if let obs = mediaServicesLostObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        mediaServicesLostObserver = nil
        if let obs = mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        mediaServicesResetObserver = nil
    }
}
