import SwiftUI

struct LibraryTab: View {
    @Environment(PlayerModel.self) private var model

    @State private var audiobooks: [AudiobookRecord] = []
    @State private var playbackStates: [String: PlaybackStateRecord] = [:]

    var body: some View {
        Group {
            if audiobooks.isEmpty {
                ContentUnavailableView(
                    "No Audiobooks",
                    systemImage: "books.vertical",
                    description: Text("Open a folder to add audiobooks to your library.")
                )
            } else {
                List {
                    if !inProgressBooks.isEmpty {
                        Section("Continue Listening") {
                            ForEach(inProgressBooks, id: \.id) { book in
                                LibraryRow(book: book, state: playbackStates[book.id])
                            }
                        }
                    }

                    Section("Library") {
                        ForEach(audiobooks, id: \.id) { book in
                            LibraryRow(book: book, state: playbackStates[book.id])
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .onAppear { loadLibrary() }
        .refreshable { loadLibrary() }
    }

    private var inProgressBooks: [AudiobookRecord] {
        audiobooks.filter { playbackStates[$0.id] != nil }
    }

    private func loadLibrary() {
        guard let db = model.databaseService else { return }
        do {
            let audiobookDAO = AudiobookDAO(db: db.writer)
            let stateDAO = PlaybackStateDAO(db: db.writer)
            audiobooks = try audiobookDAO.all()
            let states = try stateDAO.all()
            playbackStates = Dictionary(uniqueKeysWithValues: states.map { ($0.audiobookID, $0) })
        } catch {
            audiobooks = []
        }
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let book: AudiobookRecord
    let state: PlaybackStateRecord?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.15))
                .frame(width: 44, height: 56)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(formatDuration(book.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let state {
                        ProgressView(value: state.lastPosition, total: max(book.duration, 1))
                            .progressViewStyle(.linear)
                            .frame(width: 60)
                        Text(formatRelativeDate(state.lastPlayedAt))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatRelativeDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else { return "" }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
