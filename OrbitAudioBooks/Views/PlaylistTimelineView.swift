import SwiftUI

struct PlaylistTimelineView: View {
    @Environment(PlayerModel.self) private var model
    let chapterSections: [ChapterSection]
    let timeScale: TimeScale
    let projectionContext: (position: TimeInterval, realTime: Date, speed: Double)

    private let projectionService = RealTimeProjectionService()

    var body: some View {
        if chapterSections.isEmpty {
            ContentUnavailableView(
                "No Content",
                systemImage: "music.note.list",
                description: Text("Open a folder or audiobook to see its chapters and content on the playlist timeline.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    bookHeader

                    ForEach(chapterSections) { section in
                        Section {
                            ChapterTimeBlockView(
                                title: section.title,
                                chapterIndex: section.index,
                                chapterCount: chapterSections.count,
                                startSeconds: section.startSeconds,
                                durationSeconds: section.duration,
                                totalBookDuration: section.totalBookDuration,
                                isCurrentChapter: model.currentChapterIndex == section.index,
                                isPlayed: section.endSeconds < model.currentPlaybackTime
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 4)

                            if timeScale.showsEntries {
                                let visibleCards = section.cards.filter { card in
                                    timeScale == .seconds || card.cardType.isSummaryItem
                                }
                                ForEach(visibleCards) { card in
                                    TimelineContentCard(
                                        card: card,
                                        isEditing: false,
                                        projectedTime: projectedTime(for: card),
                                        projectionSpeed: projectionContext.speed
                                    )
                                    .padding(.leading, 32)
                                    .padding(.horizontal)
                                }
                            }
                        } header: {
                            sectionHeader(for: section)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Timeless headers

    private var bookHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            Text(model.currentTitle)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sectionHeader(for section: ChapterSection) -> some View {
        HStack(spacing: 8) {
            Text(section.title)
                .font(.subheadline)
                .fontWeight(model.currentChapterIndex == section.index ? .bold : .semibold)
                .foregroundStyle(model.currentChapterIndex == section.index ? .blue : .primary)
            Spacer()
            if timeScale.showsEntries {
                Text("\(section.cards.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(formatHMS(section.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            if model.currentChapterIndex == section.index {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Projection

    private func projectedTime(for card: ContentCard) -> Date? {
        guard let mt = card.mediaTimestamp else { return nil }
        return projectionService.projectedWallClock(
            for: mt,
            currentPosition: projectionContext.position,
            currentRealTime: projectionContext.realTime,
            speed: projectionContext.speed
        )
    }
}
