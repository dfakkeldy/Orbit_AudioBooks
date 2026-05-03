import WidgetKit
import SwiftUI
import AppIntents

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), title: "Book Title", isPlaying: false, progressFraction: 0.3, thumbnailData: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let defaults = UserDefaults(suiteName: "group.com.bookloop")
        let title = defaults?.string(forKey: "title") ?? "No track"
        let isPlaying = defaults?.bool(forKey: "isPlaying") ?? false
        let progressFraction = defaults?.double(forKey: "progressFraction") ?? 0.0
        let thumbnailData = defaults?.data(forKey: "thumbnailData")
        
        let entry = SimpleEntry(date: Date(), title: title, isPlaying: isPlaying, progressFraction: progressFraction, thumbnailData: thumbnailData)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let defaults = UserDefaults(suiteName: "group.com.bookloop")
        let title = defaults?.string(forKey: "title") ?? "No track"
        let isPlaying = defaults?.bool(forKey: "isPlaying") ?? false
        let progressFraction = defaults?.double(forKey: "progressFraction") ?? 0.0
        let thumbnailData = defaults?.data(forKey: "thumbnailData")

        let entry = SimpleEntry(date: Date(), title: title, isPlaying: isPlaying, progressFraction: progressFraction, thumbnailData: thumbnailData)
        
        // Refresh periodically, but mostly we rely on reloadAllTimelines() when data changes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let title: String
    let isPlaying: Bool
    let progressFraction: Double
    let thumbnailData: Data?
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: isPlaying ? 100.0 : 0.0)
    }
}

struct BookLoop_WidgetEntryView : View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                if let data = entry.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 20))
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    Button(intent: TogglePlaybackIntent()) {
                        HStack(spacing: 4) {
                            Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                            ProgressView(value: entry.progressFraction)
                                .progressViewStyle(.linear)
                                .tint(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)

        case .accessoryCircular:
            Gauge(value: entry.progressFraction) {
                EmptyView()
            } currentValueLabel: {
                if let data = entry.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Image(systemName: "music.note")
                }
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Color.accentColor)
            .containerBackground(.fill.tertiary, for: .widget)
            // Wrapping it in a Button allows us to trigger the intent
            .overlay(
                Button(intent: TogglePlaybackIntent()) {
                    Color.clear
                }.buttonStyle(.plain)
            )

        default:
            Text(entry.title)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct BookLoop_Widget: Widget {
    let kind: String = "BookLoop_Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BookLoop_WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("BookLoop")
        .description("Quick access to your current audiobook.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}
