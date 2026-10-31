import Foundation

// Hand-off between the share sheet extension and the app. The extension can't
// open the app, so it drops what was shared into the App Group container and
// the app puts it on the board the next time it comes to the front.
//
// Each share is one folder: the image files first, then manifest.json written
// last, so a folder without a manifest is a share still being written.
enum ShareInbox {
    static let appGroup = "group.com.kemenystudio.visionboard"

    struct Entry: Codable {
        enum Kind: String, Codable { case image, text }
        var kind: Kind
        var file: String?
        var text: String?
    }

    struct Pending {
        var kind: Entry.Kind
        var imageData: Data?
        var text: String?
    }

    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Inbox", directoryHint: .isDirectory)
    }

    static var isAvailable: Bool { directory != nil }

    // MARK: Extension side

    enum Item {
        case image(Data)
        case text(String)
    }

    static func write(_ items: [Item]) throws {
        guard let inbox = directory else { throw CocoaError(.fileNoSuchFile) }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let folder = inbox.appending(path: "\(stamp)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var entries: [Entry] = []
        for (index, item) in items.enumerated() {
            switch item {
            case .image(let data):
                let name = "\(index).jpg"
                try data.write(to: folder.appending(path: name), options: .atomic)
                entries.append(Entry(kind: .image, file: name))
            case .text(let text):
                entries.append(Entry(kind: .text, text: text))
            }
        }
        let manifest = try JSONEncoder().encode(entries)
        try manifest.write(to: folder.appending(path: "manifest.json"), options: .atomic)
    }

    // MARK: App side

    static var hasPending: Bool {
        !finishedFolders().isEmpty
    }

    // Reads every finished share, oldest first, and removes it from the inbox
    static func take() -> [Pending] {
        var result: [Pending] = []
        for folder in finishedFolders() {
            defer { try? FileManager.default.removeItem(at: folder) }
            guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
                  let entries = try? JSONDecoder().decode([Entry].self, from: data)
            else { continue }
            for entry in entries {
                switch entry.kind {
                case .image:
                    guard let file = entry.file,
                          let image = try? Data(contentsOf: folder.appending(path: file))
                    else { continue }
                    result.append(Pending(kind: .image, imageData: image))
                case .text:
                    guard let text = entry.text, !text.isEmpty else { continue }
                    result.append(Pending(kind: .text, text: text))
                }
            }
        }
        return result
    }

    private static func finishedFolders() -> [URL] {
        guard let inbox = directory,
              let folders = try? FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
        else { return [] }

        var finished: [URL] = []
        for folder in folders {
            if FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path()) {
                finished.append(folder)
            } else if let created = try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      created < Date().addingTimeInterval(-3600) {
                // An extension that was killed mid-write leaves a folder behind
                try? FileManager.default.removeItem(at: folder)
            }
        }
        return finished.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
