import Foundation
import AVFoundation
import UIKit

/// Stateless helper that fetches and processes audiobook artwork.
/// Does not own mutable state — PlayerModel remains the single source of truth.
struct ArtworkCache {

    /// Extracts embedded artwork from an audio file's AVAsset metadata.
    /// - Parameter url: The audio file URL.
    /// - Returns: A downsampled UIImage, or nil if no artwork is embedded.
    static func embeddedArtworkImage(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []

        let maxPixelSize = 600
        for item in metadata where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue) else { continue }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage)
            }
        }

        return nil
    }

    /// Lists non-hidden regular files in a directory, with a security-scoped
    /// fallback for sandboxed folders.
    /// - Parameter folderURL: The directory to enumerate.
    /// - Returns: An array of file URLs, or an empty array on failure.
    static func listFilesInFolder(_ folderURL: URL) -> [URL] {
        if let files = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            return files
        }

        let didStart = folderURL.startAccessingSecurityScopedResource()
        defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

        return (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// Creates a 60×60 JPEG thumbnail suitable for Watch transfer.
    /// - Parameter image: The source image to downscale.
    /// - Returns: JPEG data, or nil on failure.
    static func makeWatchThumbnailData(from image: UIImage) -> Data? {
        let watchSize = CGSize(width: 60, height: 60)
        let watchFormat = UIGraphicsImageRendererFormat()
        watchFormat.scale = 1.0
        let watchRenderer = UIGraphicsImageRenderer(size: watchSize, format: watchFormat)
        let watchImage = watchRenderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: watchSize))
        }
        return watchImage.jpegData(compressionQuality: 0.6)
    }
}
