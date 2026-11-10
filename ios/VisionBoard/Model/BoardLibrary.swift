import Foundation
import Observation

// Every board on this device: a name and a JSON file each, plus which one is
// on screen. Each board syncs on its own key, so a travel board can be shared
// with a partner while a career board stays private.
@MainActor
@Observable
final class BoardLibrary {
    struct Board: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var created: Date
    }

    static let mainID = "main"

    private(set) var boards: [Board] = []
    private(set) var currentID: String

    @ObservationIgnored private let store: BoardStore
    @ObservationIgnored private let sync: SyncService

    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "VisionBoard")
        try? FileManager.default.createDirectory(at: dir.appending(path: "boards"), withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for boardID: String) -> URL {
        directory.appending(path: "boards/\(boardID).json")
    }

    private static var listURL: URL { directory.appending(path: "boards.json") }

    // The board to open at launch, read before the store exists
    static var savedCurrentID: String {
        migrateIfNeeded()
        let saved = UserDefaults.standard.string(forKey: "current-board") ?? mainID
        return FileManager.default.fileExists(atPath: fileURL(for: saved).path(percentEncoded: false)) || saved == mainID ? saved : mainID
    }

    init(store: BoardStore, sync: SyncService) {
        self.store = store
        self.sync = sync
        currentID = store.boardID
        boards = Self.loadList()
        if !boards.contains(where: { $0.id == currentID }) {
            boards.insert(Board(id: currentID, name: String(localized: "My Board"), created: .now), at: 0)
            saveList()
        }
        if let starter = Self.movedAside, !boards.contains(where: { $0.id == starter }) {
            boards.append(Board(id: starter, name: String(localized: "Starter Board"), created: .now))
            saveList()
        }
        if Self.movedAside != nil || Self.restored, currentID == Self.mainID {
            // The restored board is the newest version of this board, so the cloud copy takes it
            Task { await sync.syncNow() }
        }
        publishForShareSheet()
    }

    var current: Board? { boards.first { $0.id == currentID } }

    // MARK: Changing boards

    func open(_ id: String) async {
        guard id != currentID, boards.contains(where: { $0.id == id }) else { return }
        await sync.finishPending()
        store.open(boardID: id)
        sync.boardChanged()
        currentID = id
        UserDefaults.standard.set(id, forKey: "current-board")
        publishForShareSheet()
        await sync.pull()
    }

    @discardableResult
    func create(named name: String) async -> Board {
        let board = Board(id: BoardItem.newID(), name: Self.clean(name, fallback: String(localized: "New Board")), created: .now)
        let empty = BoardFile(version: 1, items: [], maxZIndex: 1)
        if let data = try? JSONEncoder().encode(empty) {
            try? data.write(to: Self.fileURL(for: board.id), options: .atomic)
        }
        boards.append(board)
        saveList()
        await open(board.id)
        return board
    }

    func rename(_ id: String, to name: String) {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return }
        boards[index].name = Self.clean(name, fallback: boards[index].name)
        saveList()
    }

    // Removes the board from this device. A cloud copy, if any, is left for
    // the other devices that use it.
    func delete(_ id: String) async {
        guard boards.count > 1, let index = boards.firstIndex(where: { $0.id == id }) else { return }
        if id == currentID {
            let next = boards[index == 0 ? 1 : index - 1]
            await open(next.id)
        }
        let file = Self.fileURL(for: id)
        if let data = try? Data(contentsOf: file), let board = try? JSONDecoder().decode(BoardFile.self, from: data) {
            for item in board.items where ImageStore.isLocal(item.content) {
                await ImageStore.shared.deleteLocal(item.content)
            }
        }
        try? FileManager.default.removeItem(at: file)
        SyncService.forget(board: id)
        boards.removeAll { $0.id == id }
        saveList()
    }

    // MARK: Storage

    private static func clean(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(40))
    }

    private static func loadList() -> [Board] {
        guard let data = try? Data(contentsOf: listURL), let list = try? JSONDecoder().decode([Board].self, from: data) else {
            return []
        }
        return list
    }

    private func saveList() {
        if let data = try? JSONEncoder().encode(boards) {
            try? data.write(to: Self.listURL, options: .atomic)
        }
        publishForShareSheet()
    }

    // The share sheet lists boards by name so you can pick where things go
    private func publishForShareSheet() {
        ShareInbox.saveBoards(boards.map { ShareInbox.BoardChoice(id: $0.id, name: $0.name) }, current: currentID)
    }

    // Before several boards, the one board lived at VisionBoard/board.json.
    // A build that couldn't find it may have started a fresh main board (from
    // onboarding or a template), so that one is kept as its own board.
    private static var movedAside: String?
    private static var restored = false

    private static func migrateIfNeeded() {
        let fm = FileManager.default
        let old = directory.appending(path: "board.json")
        let new = fileURL(for: mainID)
        guard fm.fileExists(atPath: old.path(percentEncoded: false)) else { return }
        if fm.fileExists(atPath: new.path(percentEncoded: false)) {
            let fresh = (try? Data(contentsOf: new)).flatMap { try? JSONDecoder().decode(BoardFile.self, from: $0) }
            if let fresh, !fresh.items.isEmpty {
                let id = BoardItem.newID()
                guard (try? fm.moveItem(at: new, to: fileURL(for: id))) != nil else { return }
                movedAside = id
            } else {
                try? fm.removeItem(at: new)
            }
            restored = true
            // Keep a pull from replacing the restored board with what that build pushed
            UserDefaults.standard.set(Date.now.timeIntervalSince1970 * 1000, forKey: "synced-at")
        }
        try? fm.moveItem(at: old, to: new)
    }
}
