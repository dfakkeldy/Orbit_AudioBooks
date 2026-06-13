import Foundation

struct PlayerDeepLink: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case play(time: TimeInterval?)
        case focus
        case read
        case study
    }

    let action: Action

    init?(url: URL) {
        guard url.scheme == "echoaudio" else {
            return nil
        }

        switch url.host {
        case "play":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let time = components?.queryItems?
                .first(where: { $0.name == "time" })
                .flatMap { $0.value }
                .flatMap(TimeInterval.init)
            self.action = .play(time: time)
        case "focus":
            self.action = .focus
        case "read":
            self.action = .read
        case "study":
            self.action = .study
        default:
            return nil
        }
    }
}
