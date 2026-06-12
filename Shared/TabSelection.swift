import Foundation

enum TabSelection: String, CaseIterable {
    case nowPlaying
    case read
    case timeline
    case stats

    var icon: String {
        switch self {
        case .nowPlaying: return "headphones"
        case .read: return "book.pages"
        case .timeline: return "list.bullet.rectangle"
        case .stats: return "chart.bar.fill"
        }
    }

    var label: String {
        switch self {
        case .nowPlaying: return "Listen"
        case .read: return "Read"
        case .timeline: return "Study"
        case .stats: return "Stats"
        }
    }
}
