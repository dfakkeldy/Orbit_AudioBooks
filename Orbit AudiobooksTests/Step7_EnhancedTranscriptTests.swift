import Testing
import Foundation
@testable import Orbit_Audiobooks

struct EnhancedTranscriptTests {

    @Test("EnhancedTranscriptionSegment decodes from enhanced.json format")
    func decodeEnhancedTranscript() throws {
        let json = """
        [
            {
                "sequenceIndex": 0,
                "text": "Chapter 1",
                "startTime": 0.0,
                "endTime": 5.0,
                "markers": [{"type": "chapterStart", "payload": "Chapter 1", "epubCharOffset": 0}]
            },
            {
                "sequenceIndex": 1,
                "text": "It was a dark and stormy night.",
                "startTime": 5.0,
                "endTime": 10.0
            }
        ]
        """.data(using: .utf8)!

        let segments = try JSONDecoder().decode([EnhancedTranscriptionSegment].self, from: json)
        #expect(segments.count == 2)
        #expect(segments[0].markers?.count == 1)
        #expect(segments[1].markers == nil)
    }

    @Test("EnhancedTranscriptionSegment handles un-timestamped EPUB-only blocks")
    func untimestampedBlocks() throws {
        let json = """
        [
            {
                "sequenceIndex": 0,
                "text": "An image appears here",
                "startTime": null,
                "endTime": null,
                "markers": [{"type": "image", "payload": "cover.jpg", "epubCharOffset": 50}]
            }
        ]
        """.data(using: .utf8)!

        let segments = try JSONDecoder().decode([EnhancedTranscriptionSegment].self, from: json)
        #expect(segments.count == 1)
        #expect(segments[0].startTime == nil)
        #expect(segments[0].isTimestamped == false)
    }

    @Test("TranscriptService discovers enhanced.json sidecar alongside audio file")
    func enhancedSidecarDiscovery() throws {
        // Create a temp directory with an audio file and its enhanced.json sidecar
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrbitTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let audioURL = tmpDir.appendingPathComponent("testbook.m4b")
        try "fake audio".data(using: .utf8)!.write(to: audioURL)

        let enhancedURL = tmpDir.appendingPathComponent("testbook.enhanced.json")
        let enhancedJSON = """
        [{"sequenceIndex": 0, "text": "Test", "startTime": 0, "endTime": 5}]
        """
        try enhancedJSON.data(using: .utf8)!.write(to: enhancedURL)

        let enhanced = TranscriptService.loadEnhancedTranscript(for: audioURL)
        #expect(enhanced != nil)
        #expect(enhanced?.count == 1)
    }
}
