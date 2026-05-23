import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TimelineTab: View {
    @Environment(PlayerModel.self) private var model
    @State private var timelineScope: TimelineScope = .chapter
    @State private var dueCount: Int = 0
    @State private var feedViewModel: TimelineFeedViewModel?
    @State private var isFollowingPlayback = true
    @State private var feedItems: [TimelineDisplayItem] = []
    @State private var currentPosition: TimeInterval = 0
    @State private var scrollTargetPosition: TimeInterval?
    @State private var isZoomedIn: Bool = false
    @State private var hasEPUB = false
    @State private var hasTranscript = false
    @State private var isColumnMode = false

    var onReviewTap: (() -> Void)?
    /// Callback to present the bookmark editor sheet in the parent view.
    var onEditBookmark: ((UUID) -> Void)?
    /// Callback to create a new bookmark draft.
    var onCreateBookmark: ((BookmarkDraft) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if hasEPUB || hasTranscript {
                if isZoomedIn {
                    TimelineHeaderView(
                        scope: $timelineScope,
                        isColumnMode: $isColumnMode,
                        onZoomOut: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isZoomedIn = false
                            }
                        },
                        onRecenterNow: {
                            feedViewModel?.goToNow()
                        }
                    )

                    Divider()

                    DashboardShelf(onReviewTap: onReviewTap)

                    SpeedSuggestionBanner()

                    if dueCount > 0 {
                        dueReviewBanner
                    }

                    if let viewModel = feedViewModel {
                        if isColumnMode {
                            columnLayout(viewModel: viewModel)
                        } else {
                            ZStack {
                                TimelineFeedCollectionView(
                                    items: $feedItems,
                                    currentPosition: $currentPosition,
                                    scrollTargetPosition: $scrollTargetPosition,
                                    isFollowingPlayback: isFollowingPlayback,
                                    onUserScrolled: {
                                        viewModel.userDidScroll()
                                    },
                                    onItemTapped: { displayItem in
                                        handleItemTap(displayItem)
                                    },
                                    onContextMenuAction: { displayItem in
                                        handleContextMenu(displayItem)
                                    },
                                    onDeleteBookmark: { timelineItem in
                                        handleDeleteBookmark(timelineItem)
                                    },
                                    onEPUBBlockAction: { item, action in
                                        handleEPUBBlockAction(item, action)
                                    }
                                )

                                // "Go to Now" floating button (visible when not following)
                                if !isFollowingPlayback {
                                    VStack {
                                        Spacer()
                                        Button {
                                            viewModel.goToNow()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.down.to.line")
                                                Text("Go to Now")
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                            .shadow(radius: 4)
                                        }
                                        .padding(.bottom, 12)
                                    }
                                }
                            }
                        }
                    } else {
                        ProgressView()
                            .padding(.top, 40)
                    }
                } else {
                    PlaylistView(
                        isEmbedded: true,
                        onRowTapped: { timestamp in
                            model.seek(toSeconds: timestamp)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isZoomedIn = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                feedViewModel?.goToNow()
                            }
                        },
                        onZoomIn: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isZoomedIn = true
                            }
                        }
                    )
                }
            } else {
                PlaylistView(isEmbedded: true)
            }
        }
        .onAppear {
            hasEPUB = model.hasEPUB
            hasTranscript = model.hasTranscript
            refreshDueCount()
            setupFeed()
        }
        .onChange(of: model.folderURL) { _, _ in
            hasEPUB = model.hasEPUB
            hasTranscript = model.hasTranscript
            setupFeed()
        }
        .onChange(of: isZoomedIn) { _, newZoom in
            if newZoom {
                feedViewModel?.goToNow()
            }
        }
        .onChange(of: model.currentPlaybackTime) { _, newPosition in
            currentPosition = newPosition
            feedViewModel?.updatePosition(newPosition)
        }
        .onChange(of: timelineScope) { _, newScope in
            feedViewModel?.scope = newScope
        }
        .onChange(of: model.isTimelineFrozen) { _, isFrozen in
            if isFrozen {
                feedViewModel?.freezeTimeline()
            } else {
                feedViewModel?.goToNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            feedViewModel?.isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
        }
        .onReceive(NotificationCenter.default.publisher(for: .timelineItemsIngested)) { notification in
            guard let ingestedID = notification.userInfo?["audiobookID"] as? String,
                  let audiobookID = model.folderURL?.absoluteString,
                  ingestedID == audiobookID
            else { return }
            hasEPUB = model.hasEPUB
            hasTranscript = model.hasTranscript
            if let viewModel = feedViewModel {
                Task {
                    await viewModel.loadInitialWindow(around: model.currentPlaybackTime)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksDidChange)) { _ in
            guard let viewModel = feedViewModel else { return }
            Task {
                await viewModel.loadInitialWindow(around: model.currentPlaybackTime)
            }
        }
        .overlay(alignment: .top) {
            if feedViewModel?.feedMode == .searchingToAnchor {
                searchOverlay
            }
        }
    }

    // MARK: - Search Overlay

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search EPUB text...", text: Binding(
                    get: { feedViewModel?.searchQuery ?? "" },
                    set: { feedViewModel?.search($0) }
                ))
                .textFieldStyle(.plain)

                Button("Cancel") {
                    feedViewModel?.cancelSearch()
                }
                .font(.caption)
            }
            .padding(12)
            .background(.ultraThinMaterial)

            if let results = feedViewModel?.searchResults, !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            Button {
                                feedViewModel?.anchorSearchResult(
                                    result, at: model.currentPlaybackTime
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.text)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .foregroundStyle(.primary)
                                    Text("Seq: \(result.sequenceIndex)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Item Tap Handling

    private func handleItemTap(_ displayItem: TimelineDisplayItem) {
        switch displayItem {
        case .audiobookCard(let info):
            // Switch to the selected audiobook
            guard info.id != model.folderURL?.absoluteString else { return }
            let url = URL(fileURLWithPath: info.id)
            let gotAccess = url.startAccessingSecurityScopedResource()
            if gotAccess {
                model.loadFolder(url)
                // Switch to chapter scope to show the book's content
                timelineScope = .chapter
            } else {
                // Fallback: try to restore security-scoped bookmark
                model.loadFolder(url)
                timelineScope = .chapter
            }

        case .timelineItem(let item):
            switch item.itemType {
            case .textSegment, .chapterMarker, .bookmark:
                guard item.isTimestamped else { return }
                model.seek(toSeconds: item.audioStartTime)
            case .imageAsset:
                if let path = item.imagePath, let url = URL(string: "file://\(path)") {
                    UIApplication.shared.open(url)
                }
            case .ankiCard:
                onReviewTap?()
            }

        case .nowLine, .scrubberGap:
            break
        }
    }

    /// Long-press context menu → edit or delete the item.
    private func handleContextMenu(_ displayItem: TimelineDisplayItem) {
        switch displayItem {
        case .timelineItem(let item):
            if item.itemType == .bookmark,
               let sourceRowid = item.sourceRowid,
               let uuid = UUID(uuidString: sourceRowid) {
                onEditBookmark?(uuid)
            } else {
                model.seek(toSeconds: item.audioStartTime)
            }
        case .audiobookCard:
            // Context menu on book card: no extra action needed beyond tap-to-play
            break
        case .nowLine, .scrubberGap:
            break
        }
    }

    /// Handle EPUB block context menu actions.
    private func handleEPUBBlockAction(_ item: TimelineItem, _ action: TimelineFeedCollectionView.EPUBBlockAction) {
        guard let viewModel = feedViewModel else { return }
        switch action {
        case .playFromHere:
            model.seek(toSeconds: item.audioStartTime)
        case .moveToNow:
            guard let blockID = item.epubBlockID else { return }
            viewModel.moveBlockToNow(blockID: blockID, time: model.currentPlaybackTime)
        case .searchSimilar:
            guard let text = item.textPayload else { return }
            viewModel.beginSearch()
            viewModel.search(text)
        case .hide:
            guard let blockID = item.epubBlockID else { return }
            viewModel.hideBlock(blockID: blockID, reason: "user_hidden")
        case .unhide:
            guard let blockID = item.epubBlockID else { return }
            viewModel.unhideBlock(blockID: blockID)
        }
    }

    /// Delete a bookmark from the timeline context menu.
    private func handleDeleteBookmark(_ item: TimelineItem) {
        guard let sourceRowid = item.sourceRowid,
              let uuid = UUID(uuidString: sourceRowid) else { return }
        model.deleteBookmark(id: uuid)
        // Feed will refresh via .bookmarksDidChange notification
    }

    // MARK: - Column Layout

    /// Timestamps + Chapters columns, reused in both frozen and synchronized modes.
    @ViewBuilder
    private func sharedColumns(viewModel: TimelineFeedViewModel) -> some View {
        if viewModel.columnVisibility.showTimestamps {
            TimestampColumn(viewModel: viewModel)
                .frame(width: 72)
        }
        if viewModel.columnVisibility.showChapters {
            if viewModel.columnVisibility.showTimestamps {
                Divider()
            }
            ChapterColumn(viewModel: viewModel)
        }
    }

    private func columnLayout(viewModel: TimelineFeedViewModel) -> some View {
        let isFrozen = viewModel.isTimelineFrozen

        return VStack(spacing: 0) {
            columnVisibilityPicker(viewModel: viewModel)
            Divider()

            if isFrozen {
                frozenScrollLayout(viewModel: viewModel)
            } else {
                synchronizedScrollLayout(viewModel: viewModel)
            }
        }
    }

    /// All columns share one ScrollView — synchronized vertical scrolling.
    @ViewBuilder
    private func synchronizedScrollLayout(viewModel: TimelineFeedViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                sharedColumns(viewModel: viewModel)
                if viewModel.columnVisibility.showEPUB, hasEPUB {
                    Divider()
                    EPUBColumn(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// EPUB column has its own ScrollView so the user can browse it independently
    /// while the Timestamps + Chapters columns remain frozen at the current position.
    @ViewBuilder
    private func frozenScrollLayout(viewModel: TimelineFeedViewModel) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    sharedColumns(viewModel: viewModel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.columnVisibility.showEPUB, hasEPUB {
                Divider()
                ScrollView(.vertical, showsIndicators: true) {
                    EPUBColumn(viewModel: viewModel)
                }
            }
        }
    }

    private func columnVisibilityPicker(viewModel: TimelineFeedViewModel) -> some View {
        HStack(spacing: 8) {
            ForEach(TimelineColumn.allCases) { column in
                if column == .epub, !hasEPUB { EmptyView() }
                else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            var updated = viewModel.columnVisibility
                            updated[column].toggle()
                            viewModel.columnVisibility = updated
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.columnVisibility[column]
                                  ? "checkmark.square.fill"
                                  : "square")
                                .font(.caption)
                            Text(column.label)
                                .customFont(.caption2, appFont: model.resolvedAppFont)
                        }
                        .foregroundStyle(viewModel.columnVisibility[column] ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Column Subviews

    struct TimestampColumn: View {
        let viewModel: TimelineFeedViewModel

        var body: some View {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.timestampColumnItems) { item in
                    timestampCell(for: item)
                }
            }
            .padding(.vertical, 8)
        }

        @ViewBuilder
        private func timestampCell(for item: TimelineDisplayItem) -> some View {
            switch item {
            case .nowLine:
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(.red)
                        .frame(width: 8, height: 2)
                    Text("NOW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.red)
                    Rectangle()
                        .fill(.red)
                        .frame(height: 1)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)

            case .scrubberGap(let duration, _):
                Text(formatGap(duration))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)

            case .timelineItem(let ti):
                Text(formatHMS(ti.audioStartTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)

            case .audiobookCard:
                EmptyView()
            }
        }

        private func formatGap(_ duration: TimeInterval) -> String {
            let m = Int(duration / 60)
            if m >= 60 { return "\(m / 60)h \(m % 60)m" }
            return "\(m)m gap"
        }

        private func formatHMS(_ interval: TimeInterval) -> String {
            let total = max(0, Int(interval.rounded(.down)))
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
            return String(format: "%d:%02d", m, s)
        }
    }

    struct ChapterColumn: View {
        let viewModel: TimelineFeedViewModel

        var body: some View {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.chapterColumnItems) { item in
                    chapterCell(for: item)
                }
            }
            .padding(.vertical, 8)
        }

        @ViewBuilder
        private func chapterCell(for item: TimelineDisplayItem) -> some View {
            switch item {
            case .timelineItem(let ti) where ti.itemType == .chapterMarker:
                let isGreyed = viewModel.greyedChapterIDs.contains(ti.id)
                Button {
                    viewModel.toggleChapterGreyed(ti.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "number.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ti.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(isGreyed ? .tertiary : .primary)
                                .multilineTextAlignment(.leading)
                            if let subtitle = ti.subtitle {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(isGreyed ? 0.4 : 1.0)
                }
                .buttonStyle(.plain)

            case .audiobookCard(let info):
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let author = info.author {
                        Text(author)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)

            default:
                EmptyView()
            }
        }
    }

    struct EPUBColumn: View {
        let viewModel: TimelineFeedViewModel

        var body: some View {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.epubColumnItems) { item in
                    epubCell(for: item)
                }
            }
            .padding(.vertical, 8)
        }

        @ViewBuilder
        private func epubCell(for item: TimelineDisplayItem) -> some View {
            if case .timelineItem(let ti) = item {
                switch ti.itemType {
            case .textSegment:
                VStack(alignment: .leading, spacing: 4) {
                    Text(ti.textPayload ?? ti.title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(8)
                    Text(formatHMS(ti.audioStartTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .contextMenu {
                    if ti.isTimestamped {
                        Button { } label: {
                            Label("Play From Here", systemImage: "play.fill")
                        }
                    }
                }

            case .imageAsset:
                VStack(alignment: .leading, spacing: 4) {
                    if let path = ti.imagePath,
                       let image = platformImage(from: path) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text(ti.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding(.vertical, 2)
                .padding(.horizontal, 4)

            default:
                EmptyView()
                } // switch
            } else {
                EmptyView()
            }
        } // epubCell

        private func platformImage(from path: String) -> UIImage? {
            UIImage(contentsOfFile: path)
        }

        private func formatHMS(_ interval: TimeInterval) -> String {
            let total = max(0, Int(interval.rounded(.down)))
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
            return String(format: "%d:%02d", m, s)
        }
    }

    // MARK: - Private

    private var dueReviewBanner: some View {
        Button {
            onReviewTap?()
        } label: {
            HStack {
                Label("\(dueCount) cards due for review", systemImage: "rectangle.stack.fill")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func setupFeed() {
        guard let db = model.databaseService else { return }

        let audiobookID = model.folderURL?.absoluteString
        let timelineDAO = TimelineDAO(db: db.writer)
        let audiobookDAO = AudiobookDAO(db: db.writer)
        let viewModel = TimelineFeedViewModel(
            timelineDAO: timelineDAO,
            audiobookDAO: audiobookDAO,
            audiobookID: audiobookID
        )
        viewModel.scope = timelineScope
        viewModel.isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
        viewModel.playbackSpeed = Double(model.speed)

        // Wire scroll callback: view model pushes position → state triggers updateUIView.
        viewModel.onScrollToPosition = { [weak viewModel] position in
            guard viewModel?.isFollowingPlayback == true else { return }
            scrollTargetPosition = position
        }

        viewModel.onResumePlayback = { [weak model] in
            model?.play()
        }
        viewModel.onUnfrozen = { [weak model] in
            model?.isTimelineFrozen = false
        }

        // Wire item change callback
        viewModel.onItemsChanged = {
            feedItems = viewModel.items
            isFollowingPlayback = viewModel.isFollowingPlayback
        }

        self.feedViewModel = viewModel
        feedItems = viewModel.items

        Task {
            await viewModel.loadInitialWindow(around: model.currentPlaybackTime)
        }
    }

    private func refreshDueCount() {
        guard let db = model.databaseService else { return }
        dueCount = (try? FlashcardDAO(db: db.writer).allDueCards().count) ?? 0
    }
}

// MARK: - Bookmark Change Notification

extension Notification.Name {
    /// Posted when the bookmark store persists changes (add, update, delete).
    /// The Timeline feed observes this to refresh inline bookmark items.
    static let bookmarksDidChange = Notification.Name("BookmarksDidChange")
}
