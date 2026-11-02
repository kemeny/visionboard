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

    // The board's "day" turns at midnight UTC, the same rotation as the web
    // app, the Today tab and the reminders
    static func dayStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 86_400) * 86_400)
    }
}
