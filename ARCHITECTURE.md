# Architecture Overview

<!-- ⚠️  AUTO-GENERATED — do not edit directly. -->
<!-- Regenerate with: `make architecture`                        -->

**Last generated:** 2026-05-21 07:20:49

This document maps the source-tree layout of the Xcode targets and Shared/
module in the Orbit Audiobooks project. Folders are shown in the order
returned by the filesystem; only source, configuration, and metadata files
are included (build artifacts, asset catalogs, and media files are filtered
out).

---

## OrbitAudioBooks (iOS)

```
CarPlay/CarPlaySceneDelegate.swift
DailyPlanner/PlannedSession.swift
DailyPlanner/RealTimeProjectionService.swift
DailyPlanner/SchedulingSheet.swift
Development Assets/.gitkeep
Info.plist
Localizable.xcstrings
Models/AggregatedChapter.swift
Models/Chapter.swift
Models/ChapterSection.swift
Models/ContentCard.swift
Models/FlashcardDeckImport.swift
Models/M4BBook.swift
Models/Note.swift
Models/OrbitPlaylistManifest.swift
Models/PlayerDeepLink.swift
Models/RealTimeEvent.swift
Models/SpeedSuggestion.swift
Models/TimelineDisplayItem.swift
Models/TimelineGroup.swift
Models/TimelineScope.swift
Models/Track.swift
OrbitAudioBooks.entitlements
Orbit_AudioBooksApp.swift
Protocols/PlayerModelComponentProtocols.swift
Protocols/SettingsManagerProtocol.swift
Protocols/StoreManagerProtocol.swift
Services/AlignmentService.swift
Services/ArtworkCache.swift
Services/AudioEngine.swift
Services/BookmarkStore.swift
Services/ChapterService.swift
Services/DeckImportService.swift
Services/DeepLinkHandler.swift
Services/EPUBAssetStorage.swift
Services/EPUBImportService.swift
Services/M4BParser.swift
Services/MockMediaProvider.swift
Services/NowPlayingController.swift
Services/Persistence.swift
Services/PlaybackController.swift
Services/PlaybackTimelineService.swift
Services/PlaylistManager.swift
Services/PlaylistManifestService.swift
Services/SecurityScopeManager.swift
Services/SettingsManager.swift
Services/SleepTimerManager.swift
Services/SnippetPlayer.swift
Services/StoreManager.swift
Services/TimelineIngestionFactory.swift
Services/TimelineService.swift
Services/TranscriptService.swift
Services/WatchCommandRouter.swift
Services/WatchSyncManager.swift
State/PlaybackState.swift
Utilities/FolderPicker.swift
Utilities/ViewModifiers.swift
Utilities/WordFrequencyComputer.swift
ViewModels/DailyReviewViewModel.swift
ViewModels/PlayerModel.swift
ViewModels/TimelineFeedViewModel.swift
Views/BookmarkCardView.swift
Views/Bookmarks.swift
Views/BottomToolbarView.swift
Views/ChapterTimeBlockView.swift
Views/Components/AlbumArtHeroView.swift
Views/Components/FlashcardCreationSheet.swift
Views/Components/FlashcardOverlayView.swift
Views/Components/TranscriptOverlayView.swift
Views/Components/TranscriptRowView.swift
Views/Components/WordCloudView.swift
Views/ContentCardEditor.swift
Views/DashboardShelf.swift
Views/FlashcardReviewCard.swift
Views/FlashcardReviewSession.swift
Views/HelpContent.swift
Views/HelpView.swift
Views/ListeningProgressModuleView.swift
Views/NoteEditorView.swift
Views/NowLineView.swift
Views/NowPlayingTab.swift
Views/PlayerScrubberView.swift
Views/PlayheadLineView.swift
Views/PlaylistTimelineView.swift
Views/PlaylistView.swift
Views/RootTabView.swift
Views/SettingsView.swift
Views/SleepTimerCardView.swift
Views/SmartRewindSettingsView.swift
Views/SpeedCardView.swift
Views/SpeedSuggestionBanner.swift
Views/StatsModuleView.swift
Views/TimelineContentCard.swift
Views/TimelineContentView.swift
Views/TimelineFeedCollectionView.swift
Views/TimelineHeaderView.swift
Views/TimelineTab.swift
Views/TransportControlsView.swift
Views/UpcomingReviewsModuleView.swift
Views/VoiceMemoOverlayView.swift
Views/WatchAppSettingsView.swift
```

## Orbit Audiobooks macOS

```
Info.plist
Orbit_Audiobooks_macOS.entitlements
Orbit_Audiobooks_macOSApp.swift
Views/MacContentView.swift
Views/MacPlayerModel.swift
Views/TranscriptPane.swift
Views/TranscriptStore.swift
Views/TranscriptionManager.swift
```

## Orbit Audiobooks Watch App

```
Info.plist
Models/WatchBookmark.swift
OrbitAudioBooksWatchApp.swift
Services/WatchViewModel.swift
Services/WatchVoiceMemoRecorder.swift
Views/Bookmarks.swift
Views/Components/ToggleTraitModifier.swift
Views/ContentView.swift
Views/PlayerPage.swift
Views/WatchControlBackground.swift
Views/WatchReviewView.swift
Views/WordCloudPage.swift
```

## Shared (cross-target)

```
AppGroupDefaults.swift
Database/AlignmentAnchorRecord.swift
Database/BookmarkRecord.swift
Database/ChapterRecord.swift
Database/DAOs/AlignmentAnchorDAO.swift
Database/DAOs/AudiobookDAO.swift
Database/DAOs/BookmarkDAO.swift
Database/DAOs/ChapterDAO.swift
Database/DAOs/EPubBlockDAO.swift
Database/DAOs/FlashcardDAO.swift
Database/DAOs/NoteDAO.swift
Database/DAOs/PlannedSessionDAO.swift
Database/DAOs/PlaybackEventDAO.swift
Database/DAOs/PlaybackStateDAO.swift
Database/DAOs/RealTimeEventDAO.swift
Database/DAOs/SettingsDAO.swift
Database/DAOs/TimelineDAO.swift
Database/DAOs/TrackDAO.swift
Database/DAOs/TranscriptionDAO.swift
Database/DatabaseService.swift
Database/EPubBlockRecord.swift
Database/Flashcard.swift
Database/MigrationService.swift
Database/NoteRecord.swift
Database/PlannedSessionRecord.swift
Database/RealTimeEventRecord.swift
Database/Schema_V1.swift
Database/Schema_V2.swift
Database/Schema_V3.swift
Database/Schema_V4.swift
Database/Schema_V5.swift
Database/TimelineItem.swift
Database/TrackRecord.swift
Database/TranscriptionRecord.swift
Database/TranscriptionWord.swift
EnhancedTranscriptionSegment.swift
MediaPlayable.swift
SafeFileName.swift
SyncMarker.swift
TimeFormatting.swift
TranscriptionSegment.swift
WatchAction.swift
WatchFlashcard.swift
WordFrequency.swift
```

## Widget Extension

```
Info.plist
Models/AppIntent.swift
Views/Orbit_Audiobooks_Widget.swift
Views/Orbit_Audiobooks_WidgetBundle.swift
Views/Orbit_Audiobooks_WidgetControl.swift
```

