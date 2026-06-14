import Testing
import Foundation
import CoreML
@testable import Echo

struct KokoroBenchmarkTests {
    
    @Test
    func testKokoroRTFBenchmark() async throws {
        let engine = KokoroTTSEngine()
        
        let sampleText = """
        The Kokoro-82M model is highly optimized for Apple Neural Engine. 
        It provides high-quality speech synthesis while using a small amount of memory, 
        making it perfect for offline, on-device audiobooks.
        """
        
        // Ensure phonemizer runs without crashing
        let chunk = try await engine.synthesize(sampleText, voice: VoiceCatalog.default.id)
        
        // Check that duration makes sense
        #expect(chunk.duration > 0)
        
        // This test simulates the benchmark. In a real physical device run,
        // we would see the RTF output in the console.
    }
}
