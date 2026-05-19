import Foundation

/// Generic protocol for timeline items that represent playable media segments.
///
/// Conforming types can appear in the unified "Twitter Feed" timeline regardless
/// of whether the underlying media is audio (current) or video (future).
/// The protocol exposes the minimum set of properties needed for feed rendering:
/// a temporal position, an optional duration span, and a display title.
protocol MediaPlayable: Identifiable {
    /// When this segment begins in the media timeline (seconds).
    var audioStartTime: TimeInterval { get }

    /// When this segment ends, if it has a duration.
    /// Point-in-time items (bookmarks, images) return nil.
    var audioEndTime: TimeInterval? { get }

    /// Short display label for the feed cell.
    var title: String { get }
}
