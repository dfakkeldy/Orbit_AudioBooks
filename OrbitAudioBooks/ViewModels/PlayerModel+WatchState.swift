import Foundation

// MARK: - Watch State Serialization

extension PlayerModel {

    var currentArtworkSyncKey: String? {
        guard tracks.indices.contains(currentIndex) else { return nil }
        let trackId = tracks[currentIndex].id
        return "\(trackId)#\(currentDisplayArtworkKey ?? "base")"
    }

    func watchStateContext() -> [String: Any] {
        var context: [String: Any] = [:]
        context["isPlaying"] = isPlaying
        context["progressFraction"] = progressFraction
        context["currentTime"] = currentPlaybackTime
        context["bookmarkStorageKey"] = bookmarksStorageKey
        context["folderKey"] = folderURL?.absoluteString
        if tracks.indices.contains(currentIndex) {
            context["trackId"] = tracks[currentIndex].id
        }

        let title = chapters.count >= 2
            ? (currentSubtitle.isEmpty
                ? String(localized: "Chapter \((currentChapterIndex ?? 0) + 1)")
                : currentSubtitle)
            : currentTitle
        context["title"] = title

        // Dual-progress: total book progress (time-based when possible)
        if let duration = durationSeconds, duration.isFinite, duration > 0 {
            let totalElapsed = currentPlaybackTime
            context["totalProgressFraction"] = min(1, max(0, totalElapsed / duration))
            context["totalBookDuration"] = duration
        } else {
            let totalCount = Double(tracks.count)
            context["totalProgressFraction"] = totalCount > 0
                ? (Double(currentIndex) + progressFraction) / totalCount : 0.0
        }

        let settings = settingsManager
        let crownAction = settings?.crownAction ?? SettingsManager.Defaults.crownAction
        context["crownAction"] = crownAction
        context["isHapticFeedbackEnabled"] = settings?.isHapticFeedbackEnabled ?? SettingsManager.Defaults.isHapticFeedbackEnabled
        context["watchQuickBookmarkTimeoutSeconds"] = settings?.watchQuickBookmarkTimeoutSeconds ?? SettingsManager.Defaults.watchQuickBookmarkTimeoutSeconds
        context["loopMode"] = loopMode.rawValue
        context["playbackSpeed"] = Double(speed)

        context["watchPage1"] = (try? JSONEncoder().encode(settings?.watchPage1 ?? SettingsManager.Defaults.watchPage1)) ?? Data()
        context["watchPage2"] = (try? JSONEncoder().encode(settings?.watchPage2 ?? SettingsManager.Defaults.watchPage2)) ?? Data()
        context["linearBarMode"] = settings?.linearBarMode ?? SettingsManager.Defaults.linearBarMode
        context["linearBarHidden"] = settings?.linearBarHidden ?? SettingsManager.Defaults.linearBarHidden
        context["circularRingMode"] = settings?.circularRingMode ?? SettingsManager.Defaults.circularRingMode
        context["circularRingHidden"] = settings?.circularRingHidden ?? SettingsManager.Defaults.circularRingHidden
        context["watchArtworkLayout"] = settings?.watchArtworkLayout ?? SettingsManager.Defaults.watchArtworkLayout
        context["watchBackgroundStyle"] = settings?.watchBackgroundStyle ?? SettingsManager.Defaults.watchBackgroundStyle
        context["hasThumbnail"] = watchThumbnailData != nil

        // Sleep timer state for watch UI.
        switch sleepTimerMode {
        case .off:
            context["sleepTimerMode"] = "off"
            context["sleepTimerRemainingSeconds"] = 0
        case .minutes(let mins):
            context["sleepTimerMode"] = "minutes"
            context["sleepTimerMinutes"] = mins
            context["sleepTimerRemainingSeconds"] = sleepTimerRemainingSeconds
        case .endOfChapter:
            context["sleepTimerMode"] = "endOfChapter"
            context["sleepTimerRemainingSeconds"] = 0
        }

        // Word cloud data: top 10 words for the current chapter.
        let cloud = currentChapterWordCloud.prefix(10)
        if !cloud.isEmpty, let jsonData = try? JSONEncoder().encode(Array(cloud)),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            context["wordCloudJSON"] = jsonString
            context["wordCloudChapterIndex"] = currentChapterIndex ?? 0
        }

        // Due flashcards for watch review.
        if let db = databaseService,
           let cards = try? FlashcardDAO(db: db.writer).allDueCards(),
           !cards.isEmpty {
            let watchCards = cards.map {
                WatchFlashcard(id: $0.id, frontText: $0.frontText, backText: $0.backText)
            }
            if let data = try? JSONEncoder().encode(watchCards),
               let json = String(data: data, encoding: .utf8) {
                context["dueCardsJSON"] = json
            }
        }

        return context
    }
}
