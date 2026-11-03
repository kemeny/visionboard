import SwiftUI
import WidgetKit

@main
struct VisionBoardWidgets: WidgetBundle {
    var body: some Widget {
        TodayGoalWidget()
    }
}

struct TodayGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: TodayProvider()) { entry in
            TodayGoalView(entry: entry)
                .widgetURL(URL(string: "visionboard://today"))
        }
        .configurationDisplayName("Today's Goal")
        .description("One goal and one photo from your board, new each day.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let text: String
    let imageURL: URL?

    static let sample = TodayEntry(date: .now, text: "Run the Patagonia marathon", imageURL: nil)
    static let empty = TodayEntry(date: .now, text: String(localized: "Open VisionBoard to start your board."), imageURL: nil)
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? (entries().first ?? .sample) : (entries().first ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let list = entries()
        guard !list.isEmpty else {
            completion(Timeline(entries: [.empty], policy: .after(.now.addingTimeInterval(3600))))
            return
        }
        // After the last day the app has written, wait for it to write more
        completion(Timeline(entries: list, policy: .atEnd))
    }

    private func entries() -> [TodayEntry] {
        guard let snapshot = WidgetSnapshot.load() else { return [] }
        let today = WidgetSnapshot.dayStart(.now)
        return snapshot.days
            .filter { $0.start >= today }
            .map { day in
                // The first entry shows now, the rest at their day boundary
                TodayEntry(date: max(day.start, .now), text: day.text, imageURL: snapshot.imageURL(for: day))
            }
    }
}

struct TodayGoalView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.text)
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(entry.text)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.clear, for: .widget)
        default:
            card
        }
    }

    private var photo: UIImage? {
        entry.imageURL.flatMap { UIImage(contentsOfFile: $0.path()) }
    }

    @ViewBuilder
    private var card: some View {
        if let photo {
            Text(entry.text)
                .font(.system(size: family == .systemSmall ? 15 : 19, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(family == .systemLarge ? 4 : 3)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .containerBackground(for: .widget) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .overlay {
                            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        }
                }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.text)
                    .font(.custom("Georgia", size: family == .systemSmall ? 18 : 22, relativeTo: .title3))
                    .lineLimit(family == .systemLarge ? 6 : 4)
                    .minimumScaleFactor(0.7)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) {
                Color(uiColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.12, green: 0.11, blue: 0.09, alpha: 1)
                        : UIColor(red: 0.96, green: 0.94, blue: 0.91, alpha: 1)
                })
            }
        }
    }
}
