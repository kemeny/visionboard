import Foundation

// What the widget shows, written by the app into the App Group container:
// the goal and photo for each of the next two weeks, so the widget can turn
// the page at each day boundary without the app running.
struct WidgetSnapshot: Codable {
    struct Day: Codable {
        var start: Date
        var text: String
        var image: String? // file name inside `folder`
    }

    var days: [Day]

    static let widgetKind = "TodayGoal"

    static var folder: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareInbox.appGroup)?
            .appending(path: "Widget", directoryHint: .isDirectory)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = folder?.appending(path: "snapshot.json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() throws {
        guard let folder = Self.folder else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appending(path: "snapshot.json"), options: .atomic)
    }

    func imageURL(for day: Day) -> URL? {
        guard let name = day.image else { return nil }
        return Self.folder?.appending(path: name)
    }

    // The board's "day" turns at local midnight on this iPhone, so today's
    // goal changes when the date on the Lock Screen does. Today, the widget
    // and the reminders all count days this way.
    static func dayStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    // The start of the local day `days` after the one holding `date`. Counted
    // in calendar days, so a daylight saving change never skips or repeats one.
    static func dayStart(_ date: Date, adding days: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: start).map { calendar.startOfDay(for: $0) } ?? start
    }

    // A running count of local days, used to rotate goals and photos. The
    // local date is counted as if it were a UTC date, so on a UTC clock the
    // count is the same as before and the rotation doesn't jump.
    static func dayNumber(_ date: Date) -> Int {
        let local = Calendar.current
        let parts = local.dateComponents([.era, .year, .month, .day], from: date)
        var utc = local
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? local.timeZone
        guard let midnight = utc.date(from: parts) else {
            return Int(floor(date.timeIntervalSince1970 / 86_400))
        }
        return Int(floor(midnight.timeIntervalSince1970 / 86_400))
    }
}
