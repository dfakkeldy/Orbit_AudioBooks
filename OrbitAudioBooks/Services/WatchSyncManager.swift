import WatchConnectivity
import Foundation

/// Manages bidirectional WatchConnectivity communication with the Apple Watch companion.
///
/// Uses closure-based callbacks rather than a delegate protocol so PlayerModel can wire
/// everything up in one `init()` block with weak-captured self.
///
/// The WatchSyncManager itself conforms to WCSessionDelegate and owns no domain knowledge
/// of audiobook playback, chapters, or bookmarks.
final class WatchSyncManager: NSObject, WCSessionDelegate {
    // MARK: - Callback Closures

    /// Called when a message is received from the Watch. Parameters: message dict, optional reply handler.
    var onMessage: (([String: Any], (([String: Any]) -> Void)?) -> Void)?

    /// Called when a file (voice memo) is received from the Watch.
    var onReceiveFile: ((WCSessionFile) -> Void)?

    /// Called when the Watch sends application context (e.g. on app launch).
    var onReceiveApplicationContext: (([String: Any]) -> Void)?

    /// Returns the current state dictionary to send to the Watch.
    var stateProvider: (() -> [String: Any])?

    /// Returns (trackId, thumbnailData) for thumbnail transfer. Thumbnails are
    /// sent only when the track changes (optimization: avoid sending heavy image
    /// data on every sync).
    var thumbnailProvider: (() -> (trackId: String?, data: Data?))?

    // MARK: - Private State

    private var lastSyncedThumbnailTrackId: String?

    // MARK: - Init

    override init() {
        super.init()
        setup()
    }

    private func setup() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Public API

    /// Pushes the current playback state to the Watch app. Called on every
    /// state change (play, pause, seek, track change, etc.).
    func syncToWatch() {
        let session = WCSession.default
        guard session.activationState == .activated, let context = stateProvider?() else { return }

        if session.isReachable {
            session.sendMessage(context, replyHandler: nil) { error in
                print("Immediate watch sync failed: \(error)")
                WCSession.default.transferUserInfo(context)
            }
        } else {
            session.transferUserInfo(context)
        }

        sendThumbnailIfNeeded()
    }

    private func sendThumbnailIfNeeded() {
        let session = WCSession.default
        guard session.activationState == .activated,
              let (trackId, data) = thumbnailProvider?(),
              let trackId, let data,
              trackId != lastSyncedThumbnailTrackId
        else { return }

        lastSyncedThumbnailTrackId = trackId
        let payload: [String: Any] = [
            "trackId": trackId,
            "thumbnailData": data
        ]
        session.transferUserInfo(payload)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else {
            if let error {
                print("WatchConnectivity activation failed: \(error)")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.syncToWatch()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(message, nil)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(message, replyHandler)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(userInfo, nil)
        }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        DispatchQueue.main.async { [weak self] in
            self?.onReceiveFile?(file)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.onReceiveApplicationContext?(applicationContext)
        }
    }
}
