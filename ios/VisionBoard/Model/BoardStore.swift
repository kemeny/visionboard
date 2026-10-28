import Foundation
import Observation

// The board on this device. Saved as JSON in Application Support after every
// change; SyncService mirrors it to the cloud when a sync key is set.
@MainActor
@Observable
final class BoardStore {
    private(set) var items: [BoardItem] = []
    private(set) var maxZIndex: Double = 1

    // Called after every change the user makes (not after remote pulls)
    @ObservationIgnored var onEdit: (@MainActor () -> Void)?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "VisionBoard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "board.json")
    }()

    init() {
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
        change(&items[index])
        commit()
    }

    func delete(_ id: String) {
        guard let removed = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        if ImageStore.isLocal(removed.content) {
            Task { await ImageStore.shared.deleteLocal(removed.content) }
        }
        commit()
    }

    @discardableResult
    func duplicate(_ id: String) -> BoardItem? {
        guard var copy = item(id) else { return nil }
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
        items = file.items
        maxZIndex = file.maxZIndex ?? Double(file.items.count + 1)
        commit()
    }

    // MARK: Sync

    // A newer board from the cloud. Not an edit, so it doesn't push back.
    func applyRemote(items remote: [BoardItem], maxZIndex z: Double) {
        items = remote
        maxZIndex = z
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
        BoardTemplate(id: "demo-goals-2026", name: "Goals 2026", symbol: "target"),
        BoardTemplate(id: "demo-morning-routine", name: "Morning Routine", symbol: "sunrise"),
        BoardTemplate(id: "demo-travel-bucket", name: "Travel Bucket List", symbol: "airplane"),
        BoardTemplate(id: "demo-creative-studio", name: "Creative Studio", symbol: "paintpalette"),
    ]

    func load() -> BoardFile? {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json"), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(BoardFile.self, from: data)
    }
}
