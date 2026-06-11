import Testing
import Foundation
import GRDB
@testable import Echo

/// THROWAWAY validation harness — runs the full import pipeline against the
/// real unzipped Pragmatic Programmer EPUB on this machine and dumps the
/// resulting TOC tree. Self-skips when the local path is absent.
/// NOT FOR COMMIT: machine-specific fixture path.
@MainActor
struct RealBookTOCValidationTests {

    private let epubPath = "/Users/dfakkeldy/Developer/The Pragmatic Programmer_epub"

    @Test func realPragmaticProgrammerHierarchy() async throws {
        guard FileManager.default.fileExists(atPath: epubPath) else { return }

        let db = try DatabaseService(inMemory: ())
        try db.write { db in
            try db.execute(sql: "INSERT INTO audiobook (id, title, duration) VALUES ('pp', 'PP', 3600)")
        }
        let service = EPUBImportService(assetStorage: EPUBAssetStorage(databaseService: db))
        let blocks = try await service.import(
            audiobookID: "pp",
            epubURL: URL(fileURLWithPath: epubPath),
            chapters: [],
            bookDuration: nil
        )
        let entries = try EPubTOCEntryDAO(db: db.writer).entries(for: "pp")

        // ---- Diagnostics ----
        let roots = entries.filter { $0.parentID == nil }
        print("PPVALIDATE ROOTS(\(roots.count)): \(roots.map(\.title))")
        let tree = TOCTreeBuilder.build(from: blocks, tocEntries: entries)
        func dump(_ nodes: [TOCNode], indent: String) {
            for n in nodes {
                print("PPVALIDATE \(indent)\(n.title)")
                dump(n.children, indent: indent + "· ")
            }
        }
        dump(tree, indent: "")

        // ---- Root list matches the publisher's NCX ----
        #expect(roots.map(\.title) == [
            "Foreword",
            "Preface to the Second Edition",
            "From the Preface to the First Edition",
            "1. A Pragmatic Philosophy",
            "2. A Pragmatic Approach",
            "3. The Basic Tools",
            "4. Pragmatic Paranoia",
            "5. Bend, or Break",
            "6. Concurrency",
            "7. While You Are Coding",
            "8. Before the Project",
            "9. Pragmatic Projects",
            "10. Postface",
            "A1. Bibliography",
            "A2. Possible Answers to the Exercises",
        ])

        // ---- Chapter 1 contains Topics 1–7 with NCX titles ----
        let ch1 = try #require(entries.first { $0.title == "1. A Pragmatic Philosophy" })
        let topics = entries.filter { $0.parentID == ch1.id }
        #expect(topics.count == 7)
        #expect(topics.first?.title == "Topic 1. It's Your Life")
        print("PPVALIDATE CH1 topics: \(topics.map(\.title))")

        // ---- Topic title blocks: fragment-resolved, promoted, de-glued ----
        let topic3 = try #require(entries.first { $0.title == "Topic 3. Software Entropy" })
        let topic3Block = try #require(blocks.first { $0.id == topic3.blockID })
        print("PPVALIDATE topic3 block kind=\(topic3Block.blockKind) text=\(topic3Block.text ?? "nil")")
        #expect(topic3Block.blockKind == EPubBlockRecord.Kind.heading.rawValue)
        #expect(topic3Block.text == "Topic 3 Software Entropy")

        // ---- Chapter opener heading no longer glued ----
        let ch1Block = try #require(blocks.first { $0.id == ch1.blockID })
        #expect(ch1Block.text == "Chapter 1 A Pragmatic Philosophy")

        // ---- Fragment precision: Topic 53 and Postface share f_0079.xhtml ----
        let topic53 = entries.first { $0.title == "Topic 53. Pride and Prejudice" }
        let postface = try #require(entries.first { $0.title == "10. Postface" })
        #expect(postface.blockID != nil)
        #expect(postface.blockID != topic53?.blockID)

        // ---- A1/A2 share f_0082.xhtml but resolve to different blocks ----
        let a1 = try #require(entries.first { $0.title == "A1. Bibliography" })
        let a2 = try #require(entries.first { $0.title == "A2. Possible Answers to the Exercises" })
        #expect(a1.blockID != a2.blockID)
    }
}
