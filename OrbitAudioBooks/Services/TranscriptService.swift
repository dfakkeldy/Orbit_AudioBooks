import Foundation

/// Loads transcript sidecar JSON files and computes word frequency data.
/// Uses direct injection of PlaybackState (same pattern as PlaylistManager).
struct TranscriptService {
    let state: PlaybackState

    /// Loads the transcript sidecar JSON for the given audio file.
    /// The transcript is expected at `<audio>.transcript.json` in the same directory.
    func loadTranscript(for url: URL) {
        let fileName = url.deletingPathExtension().lastPathComponent + ".transcript.json"
        let transcriptURL = url.deletingLastPathComponent().appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: transcriptURL.path) else {
            state.transcription = []
            return
        }

        do {
            let data = try Data(contentsOf: transcriptURL)
            state.transcription = try JSONDecoder().decode([TranscriptionSegment].self, from: data)
            computeWordClouds()
        } catch {
            print("Failed to load transcript: \(error)")
            state.transcription = []
        }
    }

    /// Computes word frequencies for the full track, per-chapter, and rolling windows.
    /// Called after both transcript and chapter data are available.
    func computeWordClouds() {
        guard !state.transcription.isEmpty else { return }

        // Full-track word frequencies.
        let fullFrequencies = WordFrequencyComputer.compute(from: state.transcription)

        // Per-chapter frequencies.
        if !state.chapters.isEmpty {
            state.chapterWordClouds = WordFrequencyComputer.computePerChapter(
                segments: state.transcription,
                chapters: state.chapters
            )
        } else {
            // No chapters: store full frequencies under index 0 as the only "chapter."
            state.chapterWordClouds = [0: fullFrequencies]
        }

        // Rolling 5-minute windows.
        state.rollingWordClouds = WordFrequencyComputer.computeRollingWindows(
            segments: state.transcription,
            windowDuration: 300,
            step: 60
        )
    }
}
