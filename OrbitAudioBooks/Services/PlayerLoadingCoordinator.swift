import Foundation
import AVFoundation
import os.log

// MARK: - PlayerLoadingCoordinator

/// Orchestrates folder and track loading: playlist enumeration, multi-M4B
/// aggregation, non-M4B multi-file timeline ingestion, last-track restore,
/// manifest migration, EPUB auto-import kickoff, and per-track preparation.
/// Extracted from PlayerModel to keep it focused on playback orchestration.
final class PlayerLoadingCoordinator {

    // MARK: - Dependencies (set by PlayerModel)

    @ObservationIgnored var state: PlaybackState?
    @ObservationIgnored var audioEngine: AudioEngine?
    @ObservationIgnored var playbackController: PlaybackController?
    @ObservationIgnored var playlistManager: PlaylistManager?
    @ObservationIgnored var persistence: Persistence?
    @ObservationIgnored var timelinePersistence: PlayerTimelinePersistenceService?
    @ObservationIgnored var bookSettingsOverrideStore: BookSettingsOverrideStore?
    @ObservationIgnored var securityScope: SecurityScopeManager?
    @ObservationIgnored var artworkCoordinator: BookmarkArtworkCoordinator?
    @ObservationIgnored var flashcardTriggerController: InlineFlashcardTriggerController?
    @ObservationIgnored var bookmarkStore: BookmarkStore?
    @ObservationIgnored var progressPresenter: PlaybackProgressPresenter?
    @ObservationIgnored var chapterLoadingCoordinator: ChapterLoadingCoordinator?
    @ObservationIgnored var watchSyncManager: WatchSyncManager?
    @ObservationIgnored var transcriptService: TranscriptService?
    @ObservationIgnored var nowPlayingController: NowPlayingController?
    @ObservationIgnored var deepLinkHandler: DeepLinkHandler?

    /// Value providers for properties owned by PlayerModel.
    @ObservationIgnored var databaseServiceProvider: (() -> DatabaseService?)?
    @ObservationIgnored var resolvedVolumeBoostEnabledProvider: (() -> Bool)?
    @ObservationIgnored var defaultPlaybackSpeedProvider: (() -> Float)?

    /// Callbacks for PlayerModel-specific behavior.
    @ObservationIgnored var onConfigureRemoteCommands: (() -> Void)?
    @ObservationIgnored var onPersistSelection: ((URL) -> Void)?
    /// Resets the player-level bookmark-check timestamp, used to avoid
    /// stale state bleeding across track boundaries.
    @ObservationIgnored var onResetBookmarkCheckSecond: (() -> Void)?

    // MARK: - Folder loading

    /// Loads a folder or single audio file as the active playlist. If the URL is a
    /// directory, all supported audio files are enumerated and sorted; if a single
    /// file, it becomes the sole track. Stops any current playback first.
    /// - Parameters:
    ///   - url: The folder or file URL to load.
    ///   - autoplay: Whether to automatically begin playback after loading. Defaults to `true`.
    func loadFolder(_ url: URL, autoplay: Bool = true) {
        guard let state, let playbackController, let playlistManager, let persistence,
              let timelinePersistence, let bookSettingsOverrideStore, let bookmarkStore else { return }

        playbackController.stop()

        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            state.tracks = playlistManager.loadTracks(from: url)
        } else {
            state.tracks = [Track(url: url, title: url.deletingPathExtension().lastPathComponent)]
        }

        state.folderURL = url

        // Load per-book settings overrides
        bookSettingsOverrideStore.loadOverrides(for: url.absoluteString)
        playbackController.setVolumeBoost(enabled: resolvedVolumeBoostEnabledProvider?() ?? false)

        // Persist to SQL after tracks are loaded so the DB has accurate track data.
        timelinePersistence.persistAudiobookToSQL(folderURL: url, tracks: state.tracks, duration: state.durationSeconds)

        // Multi-M4B aggregation: when 2+ .m4b files are detected, parse all of them
        // asynchronously and build an aggregated chapter list with cumulative offsets.
        let m4bTrackCount = state.tracks.filter { $0.url.pathExtension.lowercased() == "m4b" }.count
        if m4bTrackCount >= 2 {
            let folderURL = url
            Task {
                let didStart = folderURL.startAccessingSecurityScopedResource()
                defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }
                if let parsed = await M4BParser.parseFolder(folderURL) {
                    state.m4bBooks = parsed.books
                    state.aggregatedChapters = parsed.aggregatedChapters
                    state.totalBookDuration = parsed.totalDuration

                    let chapters = parsed.aggregatedChapters.map { agg in
                        Chapter(
                            index: agg.chapterIndex,
                            title: agg.chapterTitle,
                            startSeconds: agg.startSeconds,
                            endSeconds: agg.endSeconds,
                            isEnabled: true
                        )
                    }
                    let audioURL = parsed.books.first?.url ?? folderURL
                    await timelinePersistence.ingestTimelineItems(
                        audiobookID: folderURL.absoluteString,
                        audioURL: audioURL,
                        chapters: chapters,
                        transcription: state.transcription,
                        enhancedTranscription: state.enhancedTranscription,
                        folderURL: folderURL
                    )
                }
            }
        } else if state.tracks.count > 1 {
            // Non-M4B multi-file folder: ingest chapters from every track so the
            // timeline feed shows all chapters, not just the current track's.
            let folderURL = url
            let tracks = state.tracks
            Task {
                let didStart = folderURL.startAccessingSecurityScopedResource()
                defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }
                var allChapters: [Chapter] = []
                for (_, track) in tracks.enumerated() {
                    let ext = track.url.pathExtension.lowercased()
                    let asset = AVURLAsset(url: track.url)
                    let parsed = await ChapterService.parseChapters(from: asset)
                    if parsed.count >= 2 {
                        for ch in parsed {
                            allChapters.append(Chapter(
                                index: allChapters.count,
                                title: ch.title,
                                startSeconds: ch.startSeconds,
                                endSeconds: ch.endSeconds,
                                isEnabled: ch.isEnabled
                            ))
                        }
                    } else {
                        let duration: TimeInterval
                        if ext == "m4b" || ext == "m4a" {
                            duration = (try? await asset.load(.duration))?.seconds ?? 0
                        } else {
                            duration = 0
                        }
                        allChapters.append(Chapter(
                            index: allChapters.count,
                            title: track.title,
                            startSeconds: 0,
                            endSeconds: duration.isFinite ? duration : 0,
                            isEnabled: true
                        ))
                    }
                }
                guard !allChapters.isEmpty else { return }
                await timelinePersistence.ingestTimelineItems(
                    audiobookID: folderURL.absoluteString,
                    audioURL: tracks[0].url,
                    chapters: allChapters,
                    transcription: state.transcription,
                    enhancedTranscription: state.enhancedTranscription,
                    folderURL: folderURL
                )
            }
        }

        if let folderKey = state.folderURL?.absoluteString,
           let savedTrackId = persistence.getLastTrack(for: folderKey),
           let idx = state.tracks.firstIndex(where: { $0.id == savedTrackId }) {
            state.currentIndex = idx
        } else {
            state.currentIndex = 0
        }

        if state.tracks.indices.contains(state.currentIndex) {
            state.currentTitle = state.tracks[state.currentIndex].title
            prepareToPlay(index: state.currentIndex, autoplay: autoplay)
            applyPendingDeepLinkSeekIfPossible()
        } else {
            state.currentTitle = String(localized: "No .mp3/.m4a/.m4b files found")
            progressPresenter?.updateNowPlayingInfo(isPaused: true)
        }

        // Migrate per-folder UserDefaults state into .orbitplaylist.json if needed.
        if isDir.boolValue, !state.tracks.isEmpty {
            let manifestURL = url.appendingPathComponent(PlaylistManifestService.fileName)
            if !FileManager.default.fileExists(atPath: manifestURL.path) {
                let manifest = PlaylistManifestService.migrate(
                    from: persistence,
                    folderURL: url,
                    tracks: state.tracks,
                    bookmarks: bookmarkStore.bookmarks,
                    defaultSpeed: defaultPlaybackSpeedProvider?() ?? 1.25
                )
                PlaylistManifestService.write(manifest, to: url)
            }
        }

        onPersistSelection?(url)

        // Route bookmark persistence through SQL when available.
        if let db = databaseServiceProvider?() {
            bookmarkStore.configureSQLPersistence(database: db)
        }

        // Auto-import EPUB companion files when present in the folder.
        if let db = databaseServiceProvider?() {
            let currentChapters = state.chapters
            let currentDuration = state.durationSeconds
            Task {
                await EPUBAutoImportScanner.scanAndImportIfNeeded(
                    folderURL: url,
                    databaseService: db,
                    chapters: currentChapters,
                    duration: currentDuration
                )
            }
        }
    }

    // MARK: - Track preparation

    func prepareToPlay(index: Int, autoplay: Bool) {
        guard let state, let audioEngine, let playbackController, let persistence,
              let artworkCoordinator, let flashcardTriggerController,
              let progressPresenter, let chapterLoadingCoordinator,
              let watchSyncManager, let transcriptService else { return }
        guard state.tracks.indices.contains(index) else { return }

        // Save progress before changing track
        if let folder = state.folderURL?.absoluteString,
           state.tracks.indices.contains(state.currentIndex) {
            persistence.saveBookProgress(
                for: folder,
                trackId: state.tracks[state.currentIndex].id,
                time: audioEngine.currentTime,
                folderURL: state.folderURL
            )
        }

        state.currentIndex = index
        state.currentTitle = state.tracks[index].title
        state.currentSubtitle = ""
        state.thumbnailImage = nil
        artworkCoordinator.invalidateCache()

        // Load transcript for the new track
        transcriptService.loadTranscript(for: state.tracks[index].url)
        if let audiobookID = state.folderURL?.absoluteString {
            timelinePersistence?.persistTranscriptToSQL(
                audiobookID: audiobookID,
                transcription: state.transcription
            )
        }

        if let folderURL = state.folderURL {
            persistence.saveLastTrack(
                for: folderURL.absoluteString,
                trackId: state.tracks[index].id,
                folderURL: folderURL
            )
        }

        // Load the specific speed for this book
        if let key = state.folderURL?.absoluteString {
            playbackController.speed = persistence.getSpeed(for: key, folderURL: state.folderURL) ?? defaultPlaybackSpeedProvider?() ?? 1.25
            if let raw = persistence.getLoopMode(for: key, folderURL: state.folderURL),
               let mode = LoopMode(rawValue: raw) {
                playbackController.loopMode = mode
            } else {
                playbackController.loopMode = .off
            }
        } else {
            playbackController.speed = defaultPlaybackSpeedProvider?() ?? 1.25
            playbackController.loopMode = .off
        }
        audioEngine.setSpeed(playbackController.speed)
        state.chapters = []
        state.currentChapterIndex = nil
        state.isSeekingForChapterBoundary = false
        state.isManualSeeking = false
        onResetBookmarkCheckSecond?()
        flashcardTriggerController.resetForNewTrack()

        // Multi-M4B: load the correct book's chapter list and duration.
        if state.isMultiM4B, state.m4bBooks.indices.contains(index) {
            let book = state.m4bBooks[index]
            state.chapters = book.chapters
            state.durationSeconds = book.duration
            state.totalBookDuration = state.m4bBooks.reduce(0) { $0 + $1.duration }
        }

        // For Files/iCloud-provider URLs:
        if let folderURL = state.folderURL {
            securityScope?.startSelection(url: folderURL)
        }
        securityScope?.stopFile()
        securityScope?.startFile(url: state.tracks[index].url)

        let trackURL = state.tracks[index].url
        Task {
            await ArtworkCache.ensureItemIsAvailable(url: trackURL)
        }

        // AudioEngine handles AVPlayerItem creation, observers, and duration loading.
        audioEngine.configureAudioSession()
        audioEngine.replaceCurrentItem(with: trackURL)

        playbackController.applySpeedToCurrentItem()
        onConfigureRemoteCommands?()

        // Prime Now Playing metadata even before play (helps show stable controls)
        progressPresenter.updateNowPlayingInfo(isPaused: true)
        progressPresenter.updateProgress()
        watchSyncManager.syncToWatch()

        Task { @MainActor [weak self] in
            guard let self else { return }
            await chapterLoadingCoordinator.loadChaptersForCurrentItem()
            await chapterLoadingCoordinator.loadDurationForNowPlaying()
            await artworkCoordinator.generateThumbnail(for: trackURL)

            // Handle pending aggregated chapter seek (cross-book navigation).
            if let pending = state.pendingAggregatedChapter {
                state.pendingAggregatedChapter = nil
                let bookOffset = state.m4bBooks.indices.contains(pending.bookIndex)
                    ? state.m4bBooks[pending.bookIndex].cumulativeStartOffset : 0
                let intraBookTime = max(0, pending.startSeconds - bookOffset) + 0.05
                audioEngine.seek(to: intraBookTime) { [weak self] _ in
                    self?.playbackController?.resumeAfterSeek()
                }
            } else if autoplay {
                playbackController.play()
            }
        }
    }

    // MARK: - Private helpers

    private func applyPendingDeepLinkSeekIfPossible() {
        guard var handler = deepLinkHandler, let audioEngine, let playbackController else { return }
        guard let action = handler.applyPendingSeekIfPossible(
            isItemLoaded: audioEngine.isItemLoaded
        ) else { return }
        deepLinkHandler = handler
        if case .seek(let time) = action {
            playbackController.seek(toSeconds: time)
        }
    }
}
