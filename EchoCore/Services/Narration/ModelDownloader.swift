import Foundation

/// Handles one-time downloading of the Kokoro CoreML models.
actor ModelDownloader {
    enum DownloadState {
        case notDownloaded
        case downloading(progress: Double)
        case completed(url: URL)
        case failed(Error)
    }
    
    private(set) var state: DownloadState = .notDownloaded
    
    /// The local URL where the model should reside.
    var modelURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Kokoro-82M.mlpackage")
    }
    
    /// Starts the download process. In this spike, it simulates a download.
    func downloadModel() async throws {
        if FileManager.default.fileExists(atPath: modelURL.path) {
            state = .completed(url: modelURL)
            return
        }
        
        state = .downloading(progress: 0.0)
        
        // Simulate network latency for the spike
        for i in 1...10 {
            try await Task.sleep(for: .milliseconds(200))
            state = .downloading(progress: Double(i) / 10.0)
        }
        
        // In a real implementation, we would download the zip, extract the .mlpackage,
        // and move it to `modelURL`. For the benchmark spike, we'll pretend it exists.
        
        state = .completed(url: modelURL)
    }
}
