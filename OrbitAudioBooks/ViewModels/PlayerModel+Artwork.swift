import UIKit

// MARK: - Artwork & Thumbnail Management

extension PlayerModel {

    // MARK: - Thumbnail Generation

    func generateThumbnail(for url: URL) async {
        let sourceImage: UIImage?
        if let embedded = await ArtworkCache.embeddedArtworkImage(for: url) {
            sourceImage = embedded
        } else if let folderImage = await ArtworkCache.folderArtworkImage(near: url) {
            sourceImage = folderImage
        } else {
            sourceImage = loadAppIconImage()
        }

        guard let sourceImage else {
            await MainActor.run {
                state.thumbnailImage = nil
                state.currentDisplayArtwork = nil
                state.watchThumbnailData = nil
                baseWatchThumbnailData = nil
                currentDisplayArtworkKey = nil
                updateNowPlayingInfo(isPaused: !isPlaying)
                syncToWatch()
            }
            return
        }

        let scale = displayScale
        let result = ArtworkCache.generateThumbnails(from: sourceImage, displayScale: scale)

        await MainActor.run {
            state.thumbnailImage = result.0
            baseWatchThumbnailData = result.1
            updateCurrentDisplayArtwork(at: currentPlaybackTime, force: true)
        }
    }

    // MARK: - Display Artwork

    static func activeArtworkBookmark(from bookmarks: [Bookmark], at currentTime: TimeInterval, trackId: String?) -> Bookmark? {
        bookmarks
            .filter { bookmark in
                guard bookmark.isEnabled,
                      bookmark.bookmarkImageFileName?.isEmpty == false,
                      bookmark.timestamp.isFinite,
                      bookmark.timestamp <= currentTime
                else { return false }

                if let bookmarkTrackId = bookmark.trackId, let trackId {
                    return bookmarkTrackId == trackId
                }
                return bookmark.trackId == nil || trackId == nil
            }
            .max { $0.timestamp < $1.timestamp }
    }

    func updateCurrentDisplayArtwork(at currentTime: TimeInterval, force: Bool = false) {
        let trackId = tracks.indices.contains(currentIndex) ? tracks[currentIndex].id : nil
        let activeBookmark = Self.activeArtworkBookmark(from: bookmarks, at: currentTime, trackId: trackId)
        let nextKey = activeBookmark.flatMap { bookmark -> String? in
            guard let fileName = bookmark.bookmarkImageFileName else { return nil }
            return "bookmark:\(bookmark.id.uuidString):\(fileName)"
        } ?? "base"

        guard force || nextKey != currentDisplayArtworkKey else { return }
        currentDisplayArtworkKey = nextKey

        if let activeBookmark,
           let fileName = activeBookmark.bookmarkImageFileName,
           let imageURL = activeBookmark.bookmarkImageURL(in: folderURL) {
            let cacheKey = imageURL.path
            if let cached = bookmarkArtworkCache[cacheKey] {
                state.currentDisplayArtwork = cached.image
                state.watchThumbnailData = cached.watchData
            } else if let image = UIImage(contentsOfFile: imageURL.path) {
                let watchData = makeWatchThumbnailData(from: image)
                bookmarkArtworkCache[cacheKey] = (image, watchData)
                state.currentDisplayArtwork = image
                state.watchThumbnailData = watchData
            } else {
                print("Failed to load bookmark artwork: \(fileName)")
                state.currentDisplayArtwork = thumbnailImage
                state.watchThumbnailData = baseWatchThumbnailData
            }
        } else {
            state.currentDisplayArtwork = thumbnailImage
            state.watchThumbnailData = baseWatchThumbnailData
        }

        updateNowPlayingInfo(isPaused: !isPlaying)
        syncToWatch()
        state.currentDisplayArtworkVersion += 1
    }

    func makeWatchThumbnailData(from image: UIImage) -> Data? {
        ArtworkCache.makeWatchThumbnailData(from: image)
    }
}
