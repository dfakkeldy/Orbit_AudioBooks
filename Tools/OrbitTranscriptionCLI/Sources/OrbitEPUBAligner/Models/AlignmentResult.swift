import Foundation

struct AlignmentResult {
    let epubCharRange: ClosedRange<Int>
    let transcriptTimeRange: ClosedRange<TimeInterval>
    let confidence: Double
    let containedMarkers: [SyncMarker]
}
