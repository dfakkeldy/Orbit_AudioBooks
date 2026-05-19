import SwiftUI

/// Compact "tweet-style" cell for text segments in the timeline feed.
/// Shows a short text preview, timestamp, and playback progress indicator.
struct TimelineTweetCell: View {
    let item: TimelineItem
    let isCurrentItem: Bool
    let isPlayed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // ── Playback indicator ──
            VStack(spacing: 2) {
                Circle()
                    .fill(isCurrentItem ? Color.blue : Color.clear)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(isCurrentItem ? .blue : .secondary.opacity(0.3), lineWidth: 1.5)
                    )
                if item.audioEndTime != nil {
                    Rectangle()
                        .fill(isPlayed ? .blue.opacity(0.3) : .secondary.opacity(0.1))
                        .frame(width: 1.5)
                }
            }
            .frame(width: 12)

            // ── Content ──
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(isPlayed ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let duration = item.audioEndTime.map({ $0 - item.audioStartTime }) {
                        Text(formatSegmentDuration(duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text(formatHMS(item.audioStartTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.quaternary)

                    if item.epubReference != nil {
                        Image(systemName: "book.pages")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(isCurrentItem ? Color.blue.opacity(0.06) : Color.clear)
        .opacity(isPlayed ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let time = formatHMS(item.audioStartTime)
        let played = isPlayed ? "Played" : ""
        return "\(played) \(time): \(item.title)".trimmingCharacters(in: .whitespaces)
    }

    private func formatSegmentDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        if total < 60 { return "\(total)s" }
        let min = total / 60
        let sec = total % 60
        return "\(min):\(String(format: "%02d", sec))"
    }
}
