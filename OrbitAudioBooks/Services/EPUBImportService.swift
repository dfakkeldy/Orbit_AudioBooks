import Foundation
import os.log

/// Handles app-side EPUB import: writes parsed blocks to SQL,
/// copies images to app-controlled storage, and triggers timeline re-ingestion.
///
/// Does NOT perform ZIP extraction or XHTML parsing — those are handled by the
/// CLI pipeline (OrbitEPUBAligner) or a future in-app parser backed by ZIPFoundation.
struct EPUBImportService {
    private let db: DatabaseService
    private let logger = Logger(subsystem: "com.orbitaudiobooks", category: "EPUBImport")

    init(database: DatabaseService) {
        self.db = database
    }

    // MARK: - Block Import

    /// Writes parsed EPUB blocks into the `epub_block` table, replacing any
    /// existing blocks for the given audiobook.
    func importBlocks(_ blocks: [EpubBlockRecord], audiobookID: String) throws {
        let dao = EpubBlockDAO(db: db.writer)
        try dao.deleteAll(for: audiobookID)
        try dao.insertAll(blocks, audiobookID: audiobookID)
        logger.info("Imported \(blocks.count) EPUB blocks for \(audiobookID)")
    }

    // MARK: - Asset Storage

    /// Returns the directory where EPUB assets (images, etc.) are stored
    /// for a given audiobook. Creates the directory if it doesn't exist.
    static func epubAssetsDirectory(
        audiobookID: String,
        baseURL: URL? = nil
    ) -> URL {
        let root: URL
        if let baseURL {
            root = baseURL
        } else {
            // swiftlint:disable:next force_unwrapping
            root = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
        }
        let safeID = SafeFileName.fromAudiobookID(audiobookID)
        let dir = root
            .appendingPathComponent("EPUBAssets")
            .appendingPathComponent(safeID)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// Copies an image from a source path (within an extracted EPUB) into the
    /// app-controlled EPUBAssets directory. Returns the destination file path
    /// usable by `UIImage(contentsOfFile:)`.
    @discardableResult
    static func copyImageAsset(
        from sourcePath: String,
        audiobookID: String
    ) -> String? {
        let assetDir = epubAssetsDirectory(audiobookID: audiobookID)
        let sourceURL: URL
        if sourcePath.hasPrefix("/") {
            sourceURL = URL(fileURLWithPath: sourcePath)
        } else {
            // Relative path within extracted EPUB directory
            sourceURL = URL(fileURLWithPath: sourcePath)
        }

        let destURL = assetDir.appendingPathComponent(
            sourceURL.lastPathComponent
        )

        // Skip if already copied
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL.path
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL.path
        } catch {
            Logger(subsystem: "com.orbitaudiobooks", category: "EPUBImport")
                .warning("Failed to copy EPUB image: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Timeline Trigger

    /// Posts a notification that triggers timeline re-ingestion for the given
    /// audiobook. Call after importing or updating EPUB blocks.
    func notifyTimelineNeedsRefresh(audiobookID: String) {
        NotificationCenter.default.post(
            name: .epubBlocksDidChange,
            object: nil,
            userInfo: ["audiobookID": audiobookID]
        )
    }
}

extension Notification.Name {
    /// Posted when EPUB blocks are imported or updated for an audiobook.
    /// The timeline feed observes this to re-ingest items.
    static let epubBlocksDidChange = Notification.Name("EPUBBlocksDidChange")
}
