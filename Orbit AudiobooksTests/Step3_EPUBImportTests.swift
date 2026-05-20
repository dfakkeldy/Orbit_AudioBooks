import Testing
import Foundation
@testable import Orbit_Audiobooks

// MARK: - EPUBImportService Tests

struct EPUBImportServiceTests {

    @Test("EPUBImportService writes blocks to DB via EpubBlockDAO")
    func writesBlocksToDatabase() throws {
        let db = try DatabaseService(inMemory: ())
        let service = EPUBImportService(database: db)

        let blocks: [EpubBlockRecord] = [
            EpubBlockRecord(
                id: "block-0", audiobookID: "test-book",
                spineHref: "ch1.xhtml", spineIndex: 0, blockIndex: 0,
                sequenceIndex: 0, blockKind: "heading",
                text: "Chapter 1", imagePath: nil,
                chapterIndex: 0, isHidden: false, hiddenReason: nil,
                createdAt: nil, modifiedAt: nil
            ),
            EpubBlockRecord(
                id: "block-1", audiobookID: "test-book",
                spineHref: "ch1.xhtml", spineIndex: 0, blockIndex: 1,
                sequenceIndex: 1, blockKind: "paragraph",
                text: "It was a dark and stormy night.", imagePath: nil,
                chapterIndex: 0, isHidden: false, hiddenReason: nil,
                createdAt: nil, modifiedAt: nil
            ),
        ]

        try service.importBlocks(blocks, audiobookID: "test-book")

        let dao = EpubBlockDAO(db: db.writer)
        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched.count == 2)
        #expect(fetched[0].blockKind == "heading")
        #expect(fetched[1].blockKind == "paragraph")
    }

    @Test("EPUBImportService assigns consecutive sequence indices across spine items")
    func consecutiveSequenceIndices() throws {
        let db = try DatabaseService(inMemory: ())
        let service = EPUBImportService(database: db)

        let spine1 = EpubBlockRecord(
            id: "s1-b0", audiobookID: "test-book",
            spineHref: "ch1.xhtml", spineIndex: 0, blockIndex: 0,
            sequenceIndex: 0, blockKind: "paragraph",
            text: "First block chapter 1.", imagePath: nil,
            chapterIndex: 0, isHidden: false, hiddenReason: nil,
            createdAt: nil, modifiedAt: nil
        )
        let spine2 = EpubBlockRecord(
            id: "s2-b0", audiobookID: "test-book",
            spineHref: "ch2.xhtml", spineIndex: 1, blockIndex: 0,
            sequenceIndex: 1, blockKind: "paragraph",
            text: "First block chapter 2.", imagePath: nil,
            chapterIndex: 1, isHidden: false, hiddenReason: nil,
            createdAt: nil, modifiedAt: nil
        )

        try service.importBlocks([spine1, spine2], audiobookID: "test-book")

        let dao = EpubBlockDAO(db: db.writer)
        let fetched = try dao.fetchAll(for: "test-book")
        #expect(fetched[0].sequenceIndex == 0)
        #expect(fetched[1].sequenceIndex == 1)
    }

    @Test("EPUBImportService import triggers no crash with empty blocks")
    func emptyImportIsSafe() throws {
        let db = try DatabaseService(inMemory: ())
        let service = EPUBImportService(database: db)
        try service.importBlocks([], audiobookID: "test-book")
    }
}

// MARK: - EPUB Asset Storage Tests

struct EPUBAssetStorageTests {

    @Test("EPUB asset directory is created under app support")
    func assetDirectoryCreation() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let assetDir = EPUBImportService.epubAssetsDirectory(
            audiobookID: "test-book", baseURL: baseURL
        )
        #expect(assetDir.lastPathComponent.contains("test-book"))
        #expect(assetDir.path.contains("EPUBAssets"))
    }
}
