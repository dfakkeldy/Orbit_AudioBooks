import Foundation

struct TranscriptionSegment: Codable, Identifiable {
    var id: String { "\(startTime)-\(endTime)" }
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
