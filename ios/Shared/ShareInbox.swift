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
        var boardID: String?
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

    // MARK: Boards to choose from

    struct BoardChoice: Codable, Identifiable, Hashable {
        var id: String
        var name: String
    }

    private struct BoardList: Codable {
        var boards: [BoardChoice]
        var current: String
    }

    private static var boardsURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "boards.json")
    }

    // Written by the app whenever boards change
    static func saveBoards(_ boards: [BoardChoice], current: String) {
        guard let url = boardsURL, let data = try? JSONEncoder().encode(BoardList(boards: boards, current: current)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // Read by the share sheet: every board and the one open in the app
    static func loadBoards() -> (boards: [BoardChoice], current: String?) {
        guard let url = boardsURL, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(BoardList.self, from: data)
        else { return ([], nil) }
        return (list.boards, list.current)
    }

    // MARK: Writing a share

    private struct Manifest: Codable {
        var board: String?
        var entries: [Entry]
    }

    static func write(_ items: [Item], board: String? = nil) throws {
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
        let manifest = try JSONEncoder().encode(Manifest(board: board, entries: entries))
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
                  let manifest = (try? JSONDecoder().decode(Manifest.self, from: data))
                    ?? (try? JSONDecoder().decode([Entry].self, from: data)).map({ Manifest(board: nil, entries: $0) })
            else { continue }
            for entry in manifest.entries {
                switch entry.kind {
                case .image:
                    guard let file = entry.file,
                          let image = try? Data(contentsOf: folder.appending(path: file))
                    else { continue }
                    result.append(Pending(boardID: manifest.board, kind: .image, imageData: image))
                case .text:
                    guard let text = entry.text, !text.isEmpty else { continue }
                    result.append(Pending(boardID: manifest.board, kind: .text, text: text))
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
            if FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path(percentEncoded: false)) {
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
