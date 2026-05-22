import SwiftUI

struct NowPlayingTab: View {
    @Environment(PlayerModel.self) private var model
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    VStack(alignment: .leading, spacing: 16) {
                        AlbumArtHeroView(
                            artwork: model.currentDisplayArtwork ?? model.thumbnailImage,
                            artworkVersion: model.currentDisplayArtworkVersion,
                            caption: "",
                            mainText: model.chapters.count >= 2
                                ? (model.currentSubtitle.isEmpty
                                    ? String(localized: "Chapter \((model.currentChapterIndex ?? 0) + 1)")
                                    : model.currentSubtitle)
                                : model.currentTitle,
                            appFont: model.resolvedAppFont
                        )

                        Spacer()

                        if model.chapters.count >= 2 {
                            Text(chapterProgressText())
                                .customFont(.footnote, appFont: model.resolvedAppFont)
                                .foregroundStyle(.secondary)
                        } else if !model.tracks.isEmpty {
                            Text(trackProgressText())
                                .customFont(.footnote, appFont: model.resolvedAppFont)
                                .foregroundStyle(.secondary)
                        }

                        PlayerScrubberView()

                        TransportControlsView()
                    }
                    .grayscale(model.isPlayingVoiceMemo ? 1.0 : 0.0)
                    .opacity(model.isPlayingVoiceMemo ? 0.5 : 1.0)
                    .allowsHitTesting(!model.isPlayingVoiceMemo)

                    if model.isPlayingVoiceMemo {
                        VoiceMemoOverlayView()
                    }

                    if let card = model.activeInlineCard {
                        FlashcardOverlayView(
                            card: card,
                            onGrade: { grade in model.gradeInlineFlashcard(grade) },
                            onDismiss: { model.dismissInlineFlashcard() }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.isPlayingVoiceMemo)
                .animation(.easeInOut(duration: 0.2), value: model.isShowingInlineFlashcard)

                // Spacer ensures controls are not obscured by the floating toolbar.
                Spacer(minLength: 95)
            }
            .environment(\.font, model.resolvedAppFont == SettingsManager.systemFontName ? .body : .custom(model.resolvedAppFont, size: 17, relativeTo: .body))
            .padding(.horizontal)
            .padding(.top, 60)
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
    }

    private func formatHhMm(_ seconds: Double) -> String {
        let totalMinutes = Int((seconds / 60.0).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return String(format: "%dh%02dm", h, m)
        } else {
            return "\(m)m"
        }
    }

    private func chapterProgressText() -> String {
        let chapterIndex = (model.currentChapterIndex ?? 0) + 1
        let chapterCount = model.chapters.count
        
        let speed = model.speed > 0 ? Double(model.speed) : 1.0
        let currentSeconds = model.currentPlaybackTime
        let totalBookDuration = model.isMultiM4B ? model.totalBookDuration : (model.durationSeconds ?? 0)

        let elapsedSeconds: Double
        if model.isMultiM4B {
            let bookOffset = model.m4bBooks.indices.contains(model.currentIndex) ? model.m4bBooks[model.currentIndex].cumulativeStartOffset : 0
            elapsedSeconds = bookOffset + currentSeconds
        } else {
            elapsedSeconds = currentSeconds
        }

        let scaledElapsed = elapsedSeconds / speed
        let scaledDuration = totalBookDuration / speed
        let scaledRemaining = max(0, scaledDuration - scaledElapsed)

        let elapsedStr = formatHhMm(scaledElapsed)
        let remainingStr = formatHhMm(scaledRemaining)
        
        return String(localized: "Chapter \(chapterIndex) of \(chapterCount), \(elapsedStr) elapsed, \(remainingStr) remaining")
    }

    private func trackProgressText() -> String {
        let trackIndex = model.currentIndex + 1
        let trackCount = model.tracks.count
        
        let speed = model.speed > 0 ? Double(model.speed) : 1.0
        let currentSeconds = model.currentPlaybackTime
        let totalBookDuration = model.isMultiM4B ? model.totalBookDuration : (model.durationSeconds ?? 0)

        let elapsedSeconds: Double
        if model.isMultiM4B {
            let bookOffset = model.m4bBooks.indices.contains(model.currentIndex) ? model.m4bBooks[model.currentIndex].cumulativeStartOffset : 0
            elapsedSeconds = bookOffset + currentSeconds
        } else {
            elapsedSeconds = currentSeconds
        }

        let scaledElapsed = elapsedSeconds / speed
        let scaledDuration = totalBookDuration / speed
        let scaledRemaining = max(0, scaledDuration - scaledElapsed)

        let elapsedStr = formatHhMm(scaledElapsed)
        let remainingStr = formatHhMm(scaledRemaining)
        
        return String(localized: "Track \(trackIndex) of \(trackCount), \(elapsedStr) elapsed, \(remainingStr) remaining")
    }
}
