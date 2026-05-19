import Foundation
import Observation
import os.log

/// Manages the "Twitter Feed" timeline with time-windowed pagination,
/// playback tracking, and dual-path (dense/sparse) support.
///
/// ## Playback Tracking State Machine
/// ```
/// [following] ──user scrolls──▶ [paused] ──5s idle──▶ [following]
///      ▲                           │                      │
///      │     goToRightNow()        │      goToRightNow()   │
///      └───────────────────────────┴──────────────────────┘
///              [jumping] ──animation done──▶ [following]
/// ```
///
/// ## Memory Safety
/// Holds a rolling window of ~200 items (±5 minutes around playback position).
/// For sparse feeds, chapter markers and summary items are always retained.
@Observable
final class TimelineFeedViewModel {
    private let logger = Logger(subsystem: "com.orbitaudiobooks", category: "TimelineFeedVM")

    // MARK: - Published State

    private(set) var visibleSections: [TimelineFeedSection] = []
    private(set) var followState: FollowState = .following
    private(set) var currentItemID: String?
    private(set) var totalDuration: TimeInterval = 0

    var isFollowingPlayback: Bool { followState == .following }

    /// Flattened view of all items across sections, for scroll target lookups.
    var allVisibleItems: [TimelineFeedItem] {
        visibleSections.flatMap { section in
            let chapterItems: [TimelineFeedItem] = section.chapter.map { [.item($0)] } ?? []
            return chapterItems + section.items
        }
    }

    /// Public read access for the view's empty-state logic.
    private(set) var currentAudiobookID: String?

    /// Items that should always be visible regardless of the time window
    /// (chapter markers, bookmarks, ankiCards, image assets).
    private var summaryItems: [TimelineItem] = []

    /// Text segments within the current time window.
    private var windowedTextSegments: [TimelineItem] = []

    // MARK: - Configuration

    /// Minimum gap (seconds) between consecutive items to insert a visual spacer.
    let sparseGapThreshold: TimeInterval = 60

    /// Time window radius around current playback position.
    var windowRadius: TimeInterval = 300

    /// Maximum number of items to hold in the rolling window.
    var maxWindowSize = 200

    /// How many items to load per page.
    var pageSize = 50

    // MARK: - Dependencies

    private var db: DatabaseService?
    private var audiobookID: String?

    /// Seconds of idle scrolling before auto-follow resumes.
    private let pauseResumeDelay: TimeInterval = 5.0
    private var pauseTimeoutTask: Task<Void, Never>?

    /// Incremented each time items are rebuilt, used to debounce rapid calls.
    private var generation: Int = 0

    // MARK: - Follow State

    enum FollowState: Equatable {
        case following
        case paused
        case jumping(to: String) // item ID to scroll to

        var isJumping: Bool { if case .jumping = self { return true }; return false }
    }

    // MARK: - Public API

    func configure(db: DatabaseService, audiobookID: String, duration: TimeInterval) {
        self.db = db
        self.audiobookID = audiobookID
        self.currentAudiobookID = audiobookID
        self.totalDuration = duration
        loadInitialWindow()
    }

    func setAudiobookID(_ id: String?) {
        guard id != audiobookID else { return }
        audiobookID = id
        currentAudiobookID = id
        summaryItems = []
        windowedTextSegments = []
        visibleSections = []
        reload()
    }

    /// Called by the playback engine each time the playhead moves.
    func updatePlaybackTime(_ time: TimeInterval) {
        guard followState == .following || followState.isJumping else { return }
        rebuildVisibleItems(at: time)
    }

    /// User manually scrolled the feed — pause auto-follow.
    func userDidScroll() {
        guard followState == .following else { return }
        followState = .paused
        scheduleAutoFollowResume()
    }

    /// "Go to Right Now" — jump to the item closest to current playback time.
    func goToRightNow(currentPlaybackTime: TimeInterval) -> String? {
        let targetID = findClosestItem(to: currentPlaybackTime)?.id
        if let id = targetID {
            followState = .jumping(to: id)
            rebuildVisibleItems(at: currentPlaybackTime)
            // Transition to following after the scroll animation completes.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                if case .jumping = followState {
                    followState = .following
                }
            }
        }
        return targetID
    }

    func reload() {
        guard let db, let audiobookID else { return }
        Task {
            do {
                // Load all summary items (chapter markers, bookmarks, etc.) — they're few.
                let summaryTypes: Set<TimelineItemType> = [
                    .chapterMarker, .bookmark, .ankiCard, .imageAsset
                ]
                let allSummary = try TimelineDAO(db: db.writer)
                    .filtered(audiobookID: audiobookID, types: summaryTypes)

                await MainActor.run {
                    self.summaryItems = allSummary
                    // Trigger initial window build.
                    if !allSummary.isEmpty {
                        rebuildVisibleItems(at: 0)
                    }
                }
            } catch {
                logger.error("Failed to load summary items: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private: Window Management

    private func loadInitialWindow() {
        reload()
    }

    private func rebuildVisibleItems(at time: TimeInterval) {
        guard let db, let audiobookID else { return }
        let gen = generation + 1
        generation = gen

        Task {
            do {
                let windowStart = max(0, time - windowRadius)
                let windowEnd = time + windowRadius

                // Load text segments in the current time window.
                let textTypes: Set<TimelineItemType> = [.textSegment]
                let segments = try TimelineDAO(db: db.writer)
                    .filtered(audiobookID: audiobookID, types: textTypes,
                              from: windowStart, to: windowEnd)

                guard generation == gen else { return } // Debounce: newer call superseded.

                await MainActor.run {
                    guard generation == gen else { return }
                    self.windowedTextSegments = segments
                    self.buildSections(currentTime: time)
                }
            } catch {
                logger.error("Failed to load window: \(error.localizedDescription)")
            }
        }
    }

    /// Merges summary items + windowed text segments, groups by chapter boundaries,
    /// inserts gap markers, and produces `visibleSections`.
    private func buildSections(currentTime: TimeInterval) {
        // Merge and sort all items by timestamp, then by sequence index.
        let allItems = (summaryItems + windowedTextSegments)
            .sorted { a, b in
                if a.audioStartTime != b.audioStartTime {
                    return a.audioStartTime < b.audioStartTime
                }
                return (a.epubSequenceIndex ?? 0) < (b.epubSequenceIndex ?? 0)
            }

        // Extract chapter markers in order.
        let chapterMarkers = allItems.filter { $0.itemType == .chapterMarker }
            .sorted { $0.audioStartTime < $1.audioStartTime }

        guard !chapterMarkers.isEmpty else {
            // No chapters: wrap everything in a single section.
            let items = buildFlatItems(from: allItems, currentTime: currentTime)
            visibleSections = [TimelineFeedSection(
                chapter: nil,
                items: items,
                chapterStartTime: 0,
                chapterEndTime: items.last?.timelineItem?.audioEndTime ?? totalDuration
            )]
            currentItemID = allItems.last { $0.audioStartTime <= currentTime }?.id
            return
        }

        // Group items by chapter time boundaries.
        let chapterRanges: [(TimelineItem, TimeInterval, TimeInterval)] = chapterMarkers.enumerated().map { index, ch in
            let end = index + 1 < chapterMarkers.count
                ? chapterMarkers[index + 1].audioStartTime
                : (allItems.map { $0.audioEndTime ?? $0.audioStartTime }.max() ?? totalDuration)
            return (ch, ch.audioStartTime, end)
        }

        var sections: [TimelineFeedSection] = []
        var processedIDs = Set<String>()

        for (chapter, rangeStart, rangeEnd) in chapterRanges {
            let chapterItems = allItems.filter { item in
                guard !processedIDs.contains(item.id) else { return false }
                return item.audioStartTime >= rangeStart && item.audioStartTime < rangeEnd
            }
            processedIDs.formUnion(chapterItems.map(\.id))

            let feedItems = buildFlatItems(from: chapterItems, currentTime: currentTime)
            sections.append(TimelineFeedSection(
                chapter: chapter,
                items: feedItems,
                chapterStartTime: rangeStart,
                chapterEndTime: rangeEnd
            ))
        }

        // Any remaining items after the last chapter.
        let remaining = allItems.filter { !processedIDs.contains($0.id) }
        if !remaining.isEmpty {
            let feedItems = buildFlatItems(from: remaining, currentTime: currentTime)
            sections.append(TimelineFeedSection(
                chapter: nil,
                items: feedItems,
                chapterStartTime: sections.last?.chapterEndTime ?? 0,
                chapterEndTime: remaining.map { $0.audioEndTime ?? $0.audioStartTime }.max() ?? totalDuration
            ))
        }

        visibleSections = sections
        currentItemID = allItems.last { $0.audioStartTime <= currentTime }?.id
    }

    /// Builds a flat array of `TimelineFeedItem` from a sorted array of `TimelineItem`,
    /// inserting `TimeGapCell` markers where the gap exceeds the threshold.
    private func buildFlatItems(from items: [TimelineItem], currentTime: TimeInterval) -> [TimelineFeedItem] {
        var result: [TimelineFeedItem] = []

        for (index, item) in items.enumerated() {
            let previousEnd = index > 0
                ? (items[index - 1].audioEndTime ?? items[index - 1].audioStartTime)
                : nil
            let gap = previousEnd.map { item.audioStartTime - $0 }

            if let gap, gap > sparseGapThreshold {
                result.append(.timeGap(
                    id: "gap-\(items[index - 1].id)",
                    fromTime: previousEnd!,
                    toTime: item.audioStartTime,
                    duration: gap
                ))
            }

            result.append(.item(item))
        }

        return result
    }

    private func findClosestItem(to time: TimeInterval) -> TimelineItem? {
        let allItems = (summaryItems + windowedTextSegments)
            .sorted { $0.audioStartTime < $1.audioStartTime }
        return allItems.min { abs($0.audioStartTime - time) < abs($1.audioStartTime - time) }
    }

    private func scheduleAutoFollowResume() {
        pauseTimeoutTask?.cancel()
        pauseTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.pauseResumeDelay ?? 5))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                if self.followState == .paused {
                    self.followState = .following
                }
            }
        }
    }
}

// MARK: - Feed Item Enum

/// Represents a single row in the timeline feed.
/// Either a database-backed `TimelineItem` or a synthetic time gap spacer.
enum TimelineFeedItem: Identifiable, Equatable {
    case item(TimelineItem)
    case timeGap(id: String, fromTime: TimeInterval, toTime: TimeInterval, duration: TimeInterval)

    var id: String {
        switch self {
        case .item(let ti): return ti.id
        case .timeGap(let id, _, _, _): return id
        }
    }

    var timelineItem: TimelineItem? {
        if case .item(let ti) = self { return ti }
        return nil
    }

    var isGap: Bool {
        if case .timeGap = self { return true }
        return false
    }
}

// MARK: - Feed Section

/// Groups timeline items under a chapter header for sticky section rendering.
/// When `chapter` is nil, the section has no header (orphan items).
struct TimelineFeedSection: Identifiable {
    let chapter: TimelineItem?
    let items: [TimelineFeedItem]
    let chapterStartTime: TimeInterval
    let chapterEndTime: TimeInterval

    var id: String { chapter?.id ?? "section-\(chapterStartTime)" }

    var title: String {
        chapter?.title ?? "Other"
    }

    var duration: TimeInterval {
        chapterEndTime - chapterStartTime
    }
}
