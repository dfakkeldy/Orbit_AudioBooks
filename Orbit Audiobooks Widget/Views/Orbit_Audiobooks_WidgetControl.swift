import AppIntents
import SwiftUI
import WidgetKit

struct Orbit_Audiobooks_WidgetControl: ControlWidget {
    static let kind: String = "Dan.OrbitAudiobooks.watchkitapp.Orbit_Audiobooks_Widget"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TogglePlaybackIntent()) {
                let defaults = AppGroupDefaults.shared
                let isPlaying = defaults.bool(forKey: "isPlaying")
                Label(isPlaying ? String(localized: "Pause") : String(localized: "Play"), systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .displayName("Orbit Audiobooks Playback")
        .description("Toggle audiobook playback.")
    }
}
