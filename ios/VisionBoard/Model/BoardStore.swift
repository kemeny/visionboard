import Foundation
import Observation

// The board on screen. Saved as JSON in Application Support after every
// change; SyncService mirrors it to the cloud when that board has a sync key.
@MainActor
@Observable
final class BoardStore {
    private(set) var items: [BoardItem] = []
    private(set) var maxZIndex: Double = 1

    // Called after every change the user makes (not after remote pulls)
    @ObservationIgnored var onEdit: (@MainActor () -> Void)?

    // Undo history for this board. A burst of changes (a slider drag) counts as one step.
    private struct Snapshot { var items: [BoardItem]; var maxZIndex: Double }
    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var lastSnapshotAt: Date = .distantPast
    private(set) var canUndo = false
    private(set) var canRedo = false
    private static let historyLimit = 50

    // The board being shown; BoardLibrary keeps the list of boards
    private(set) var boardID: String
    @ObservationIgnored private var fileURL: URL

    init(boardID: String = BoardLibrary.mainID) {
        self.boardID = boardID
        fileURL = BoardLibrary.fileURL(for: boardID)
        loadFile()
    }

    // Show another board. The current one is already saved after every change.
    func open(boardID id: String) {
        boardID = id
        fileURL = BoardLibrary.fileURL(for: id)
        items = []
        maxZIndex = 1
        loadFile()
        clearHistory()
    }

    private func loadFile() {
        if let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(BoardFile.self, from: data) {
            items = file.items
            maxZIndex = file.maxZIndex ?? Double(file.items.count + 1)
        }
    }

    var sortedItems: [BoardItem] { items.sorted { $0.zIndex < $1.zIndex } }

    func item(_ id: String?) -> BoardItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    // MARK: Editing

    @discardableResult
    func addText(at center: CGPoint, content: String = "New goal") -> BoardItem {
        remember()
        let item = BoardItem(
            id: BoardItem.newID(), type: .text,
            x: center.x - 110, y: center.y - 50, width: 220, height: 100,
            content: content, zIndex: nextZ(),
            fontStyle: TextStyle.clean.rawValue, fontSize: 24, color: "#1a1a1a", bgColor: "transparent", rotation: 0
        )
        items.append(item)
        commit()
        return item
    }

    @discardableResult
    func addImage(content: String, aspect: Double, at center: CGPoint) -> BoardItem {
        remember()
        let width = 300.0
        let height = (width / max(aspect, 0.1)).rounded()
        let item = BoardItem(
            id: BoardItem.newID(), type: .image,
            x: center.x - width / 2, y: center.y - height / 2, width: width, height: height,
            content: content, zIndex: nextZ(), rotation: 0
        )
        items.append(item)
        commit()
        return item
    }

    func update(_ id: String, _ change: (inout BoardItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        remember()
        change(&items[index])
        commit()
    }

    func delete(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        remember()
        // The photo file stays so Undo can bring the clipping back
        items.removeAll { $0.id == id }
        commit()
    }

    @discardableResult
    func duplicate(_ id: String) -> BoardItem? {
        guard var copy = item(id) else { return nil }
        remember()
        copy.id = BoardItem.newID()
        copy.x += 24
        copy.y += 24
        copy.zIndex = nextZ()
        copy.locked = nil
        items.append(copy)
        commit()
        return copy
    }

    func bringToFront(_ id: String) {
        let z = nextZ()
        update(id) { $0.zIndex = z }
    }

    func sendToBack(_ id: String) {
        let lowest = (items.map(\.zIndex).min() ?? 1) - 1
        update(id) { $0.zIndex = lowest }
    }

    func toggleLike(_ id: String) {
        update(id) { $0.liked = !$0.isLiked ? true : nil }
    }

    func replaceBoard(with file: BoardFile) {
        remember()
        items = file.items
        maxZIndex = file.maxZIndex ?? Double(file.items.count + 1)
        commit()
    }

    // MARK: Sync

    // A newer board from the cloud. Not an edit, so it doesn't push back.
    func applyRemote(items remote: [BoardItem], maxZIndex z: Double) {
        items = remote
        maxZIndex = z
        clearHistory()
        save()
    }

    // Swap uploaded local images for their cloud paths. Not an edit either.
    func replaceContents(_ map: [String: String]) {
        guard !map.isEmpty else { return }
        for index in items.indices {
            if let cloud = map[items[index].content] { items[index].content = cloud }
            if let original = items[index].originalContent, let cloud = map[original] { items[index].originalContent = cloud }
        }
        save()
    }

    var boardFile: BoardFile { BoardFile(version: 1, items: items, maxZIndex: maxZIndex) }

    // MARK: Private

    private func nextZ() -> Double {
        maxZIndex = max(maxZIndex, (items.map(\.zIndex).max() ?? 0) + 1)
        defer { maxZIndex += 1 }
        return maxZIndex
    }

    private func commit() {
        save()
        onEdit?()
    }

    // MARK: Undo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(items: items, maxZIndex: maxZIndex))
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(items: items, maxZIndex: maxZIndex))
        restore(next)
    }

    private func restore(_ snapshot: Snapshot) {
        items = snapshot.items
        maxZIndex = snapshot.maxZIndex
        lastSnapshotAt = .distantPast
        updateFlags()
        commit()
    }

    // Called before each user change
    private func remember() {
        let now = Date()
        defer { lastSnapshotAt = now }
        guard now.timeIntervalSince(lastSnapshotAt) > 0.6 else { return }
        undoStack.append(Snapshot(items: items, maxZIndex: maxZIndex))
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        updateFlags()
    }

    private func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        lastSnapshotAt = .distantPast
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(boardFile) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

struct BoardTemplate: Identifiable {
    let id: String
    let name: String
    let symbol: String

    static let all = [
        BoardTemplate(id: "demo-goals-2026", name: String(localized: "Goals 2026"), symbol: "target"),
        BoardTemplate(id: "demo-morning-routine", name: String(localized: "Morning Routine"), symbol: "sunrise"),
        BoardTemplate(id: "demo-travel-bucket", name: String(localized: "Travel Bucket List"), symbol: "airplane"),
        BoardTemplate(id: "demo-creative-studio", name: String(localized: "Creative Studio"), symbol: "paintpalette"),
    ]

    func load() -> BoardFile? {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json"), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(BoardFile.self, from: data)
    }
}
