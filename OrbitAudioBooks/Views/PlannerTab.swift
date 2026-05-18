import SwiftUI

/// Daily Planner tab — real-time (calendar) timeline for scheduling listening sessions.
/// Currently a placeholder; will host the full TimelineContentView when scheduling is built out.
struct PlannerTab: View {
    @State private var timeScale: TimeScale = .minutes
    @State private var isViewingMode: Bool = true
    @State private var recenterTrigger = 0

    var body: some View {
        VStack(spacing: 0) {
            // Planner-specific header: scale + edit toggle + recenter
            HStack(spacing: 12) {
                scaleCycleButton

                Spacer()

                Button {
                    isViewingMode.toggle()
                } label: {
                    Image(systemName: isViewingMode ? "eye" : "pencil")
                }
                .accessibilityLabel(isViewingMode ? "Viewing mode" : "Editing mode")

                Button {
                    recenterTrigger += 1
                } label: {
                    Label("Now", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            SpeedSuggestionBanner()

            TimelineContentView(
                isEditing: $isViewingMode.negated(),
                timeScale: timeScale,
                recenterTrigger: recenterTrigger
            )
        }
    }

    // MARK: - Scale cycle button

    private var scaleCycleButton: some View {
        Button {
            cycleScale()
        } label: {
            Label(timeScale.label, systemImage: "clock.arrow.2.circlepath")
                .font(.caption)
                .fontWeight(.medium)
        }
        .buttonStyle(.bordered)
        .contextMenu {
            ForEach(TimeScale.allCases) { scale in
                Button {
                    timeScale = scale
                } label: {
                    Label(scale.menuLabel, systemImage: scale == timeScale ? "checkmark" : "")
                }
            }
        }
    }

    private func cycleScale() {
        let all = TimeScale.allCases
        guard let idx = all.firstIndex(of: timeScale) else { return }
        timeScale = all[(idx + 1) % all.count]
    }
}

private extension Binding where Value == Bool {
    func negated() -> Binding<Bool> {
        Binding<Bool>(
            get: { !wrappedValue },
            set: { wrappedValue = !$0 }
        )
    }
}
