import CryptoKit
import UIKit
import WidgetKit

// Writes the next two weeks of daily goals and photos where the widget can
// read them, then asks WidgetKit to redraw. Photos are shrunk to widget size
// because a widget gets only a few megabytes of memory.
enum WidgetPublisher {
    private static let days = 14
    private static let maxEdge: CGFloat = 800

    @MainActor
    static func publish(items: [BoardItem]) async {
        guard let folder = WidgetSnapshot.folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let today = WidgetSnapshot.dayStart(.now)
        var entries: [WidgetSnapshot.Day] = []
        var written: Set<String> = []
        for offset in 0..<days {
            let start = today.addingTimeInterval(Double(offset) * 86_400)
            let card = DailyCard.pick(from: items, on: start)
            var file: String?
            if let content = card.image {
                let name = fileName(for: content)
                if written.contains(name) || FileManager.default.fileExists(atPath: folder.appending(path: name).path()) {
                    file = name
                } else if let image = await ImageStore.shared.image(for: content), let jpeg = shrink(image) {
                    try? jpeg.write(to: folder.appending(path: name), options: .atomic)
                    file = name
                }
                if let file { written.insert(file) }
            }
            entries.append(.init(start: start, text: card.text, image: file))
        }
        try? WidgetSnapshot(days: entries).save()

        // Drop photos no day uses any more
        let stale = (try? FileManager.default.contentsOfDirectory(atPath: folder.path())) ?? []
        for name in stale where name.hasSuffix(".jpg") && !written.contains(name) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
    }

    private static func fileName(for content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    private static func shrink(_ image: UIImage) -> Data? {
        let scale = min(1, maxEdge / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .jpegData(withCompressionQuality: 0.8) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
