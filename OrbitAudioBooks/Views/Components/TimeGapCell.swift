import SwiftUI

/// Visual spacer shown between timeline items when the gap exceeds the threshold.
///
/// In a sparse (audio-only) feed, chapters may be 45+ minutes apart.
/// This cell renders a dotted vertical line with a duration label so the user
/// understands the temporal distance between items, rather than seeing unexplained
/// whitespace.
struct TimeGapCell: View {
    let fromTime: TimeInterval
    let toTime: TimeInterval
    let duration: TimeInterval
    let isPlayheadWithin: Bool // Whether current playback time falls within this gap.

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // ── Timeline track ──
            VStack(spacing: 0) {
                Circle()
                    .fill(isPlayheadWithin ? Color.blue : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)

                DottedLine()
                    .stroke(isPlayheadWithin ? Color.blue : Color.secondary.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 1.5, height: gapHeight)

                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 12)

            // ── Gap label ──
            VStack(alignment: .leading, spacing: 2) {
                Text(formatGapDuration(duration))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isPlayheadWithin ? .blue : .secondary)

                Text("\(formatHMS(fromTime)) — \(formatHMS(toTime))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            if isPlayheadWithin {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.trailing, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isPlayheadWithin ? Color.blue.opacity(0.04) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formatGapDuration(duration)) gap from \(formatHMS(fromTime)) to \(formatHMS(toTime))")
    }

    // MARK: - Helpers

    private var gapHeight: CGFloat {
        // Cap at a reasonable visual size; the gap label conveys the actual time.
        min(CGFloat(duration), 120)
    }

    private func formatGapDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        if total < 60 { return "\(total)s gap" }
        let min = total / 60
        if min < 60 { return "\(min) min gap" }
        let hours = min / 60
        let remainingMin = min % 60
        return remainingMin > 0 ? "\(hours)h \(remainingMin)m gap" : "\(hours)h gap"
    }
}

// MARK: - Dotted Line Shape

private struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
