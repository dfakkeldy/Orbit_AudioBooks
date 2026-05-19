import SwiftUI

struct TimelineTab: View {
    @Environment(PlayerModel.self) private var model
    @State private var timeScale: TimeScale = .minutes
    @State private var dueCount: Int = 0
    var onReviewTap: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            TimelineHeaderView(
                timeScale: $timeScale,
                onRecenterNow: {}
            )

            Divider()

            DashboardShelf(onReviewTap: onReviewTap)

            if dueCount > 0 {
                Button {
                    onReviewTap?()
                } label: {
                    HStack {
                        Label("\(dueCount) cards due for review", systemImage: "rectangle.stack.fill")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            TimelineFeedView()
        }
        .onAppear {
            refreshDueCount()
        }
    }

    private func refreshDueCount() {
        guard let db = model.databaseService else { return }
        dueCount = (try? FlashcardDAO(db: db.writer).allDueCards().count) ?? 0
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
