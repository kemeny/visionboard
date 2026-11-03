import AVFoundation
import ImageIO
import LinkPresentation
import UIKit
import UniformTypeIdentifiers

// Turns whatever another app shares into things a board can hold: photos stay
// photos, a video becomes its first good frame, a link becomes its preview
// image (or its title), and text becomes a goal.
@MainActor
@Observable
final class ShareModel {
    enum Phase { case loading, ready, saving, failed(String) }

    struct Thing: Identifiable {
        let id = UUID()
        var image: UIImage?
        var jpeg: Data?
        var text: String?
        var isVideo = false
    }

    var phase: Phase = .loading
    var things: [Thing] = []
    var caption = ""
    var boards: [ShareInbox.BoardChoice] = []
    var board: String?

    private let context: NSExtensionContext?
    private static let maxItems = 10
    private static let maxPixels: CGFloat = 2048

    init(context: NSExtensionContext?) {
        self.context = context
    }

    var canAdd: Bool {
        if case .ready = phase {
            return !things.isEmpty || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    func load() async {
        guard ShareInbox.isAvailable else {
            phase = .failed("VisionBoard can't reach its board from here. Open the app once, then try again.")
            return
        }
        let saved = ShareInbox.loadBoards()
        boards = saved.boards
        board = saved.current ?? saved.boards.first?.id
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers.prefix(Self.maxItems) {
            if let thing = await Self.thing(from: provider) {
                things.append(thing)
            }
        }
        // A link shared with its page title as text arrives twice. Keep the picture.
        if things.contains(where: { $0.image != nil }) {
            things.removeAll { $0.image == nil && ($0.text.map(Self.looksLikeURL) ?? false) }
        }
        phase = things.isEmpty ? .failed("There's nothing here VisionBoard can add. Try a photo, a video, a link or some text.") : .ready
    }

    func add() {
        phase = .saving
        var items: [ShareInbox.Item] = []
        for thing in things {
            if let jpeg = thing.jpeg {
                items.append(.image(jpeg))
            } else if let text = thing.text {
                items.append(.text(text))
            }
        }
        let words = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty { items.append(.text(words)) }
        do {
            try ShareInbox.write(items, board: board)
            context?.completeRequest(returningItems: nil)
        } catch {
            phase = .failed("Couldn't save to your board: \(error.localizedDescription)")
        }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    // MARK: Reading what was shared

    private static func thing(from provider: NSItemProvider) async -> Thing? {
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return await videoFrame(from: provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            guard let data = try? await loadData(provider, type: .image) else { return nil }
            return photo(from: data)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider), !url.isFileURL {
            return await linkPreview(url)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadText(provider) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), looksLikeURL(trimmed) {
                return await linkPreview(url)
            }
            return trimmed.isEmpty ? nil : Thing(text: String(trimmed.prefix(280)))
        }
        return nil
    }

    private static func photo(from data: Data) -> Thing? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return still(UIImage(cgImage: cg))
    }

    private static func still(_ image: UIImage, isVideo: Bool = false) -> Thing? {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        return Thing(image: image, jpeg: jpeg, isVideo: isVideo)
    }

    private static func videoFrame(from provider: NSItemProvider) async -> Thing? {
        guard let file = await copyFile(provider, type: .movie) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        // Skip the first instant, which is often black
        for seconds in [1.0, 0.0] {
            if let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                return still(UIImage(cgImage: frame.image), isVideo: true)
            }
        }
        return nil
    }

    private static func linkPreview(_ url: URL) async -> Thing? {
        let fetcher = LPMetadataProvider()
        fetcher.timeout = 10
        let metadata = try? await fetcher.startFetchingMetadata(for: url)
        if let imageProvider = metadata?.imageProvider,
           let data = try? await loadData(imageProvider, type: .image),
           let thing = photo(from: data) {
            return thing
        }
        let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Thing(text: (title?.isEmpty == false ? title : nil) ?? url.absoluteString)
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        (text.hasPrefix("http://") || text.hasPrefix("https://")) && !text.contains(" ")
    }

    // MARK: NSItemProvider helpers

    private static func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    // The provider deletes its file when the handler returns, so keep a copy
    private static func copyFile(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let copy = FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: (object as? NSURL) as URL?)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString) as String?)
            }
        }
    }
}
