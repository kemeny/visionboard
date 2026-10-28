import CryptoKit
import UIKit

// Board images live in three places: photos added on this device ("local:"),
// cloud images shared with the web app ("/api/sync/images/…", cached on disk
// once fetched, and immutable), and the occasional inline "data:" URL.
actor ImageStore {
    static let shared = ImageStore()

    static let localPrefix = "local:"
    // Long edge and size budget match the web app's upload limits
    private static let maxEdge: CGFloat = 2560
    static let maxUploadBytes = 3 * 1024 * 1024

    private let memory = NSCache<NSString, UIImage>()
    private let localDir: URL
    private let cacheDir: URL

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "VisionBoard/Images")
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "BoardImages")
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        try? fm.createDirectory(at: caches, withIntermediateDirectories: true)
        localDir = support
        cacheDir = caches
        memory.countLimit = 80
    }

    static func isLocal(_ content: String?) -> Bool { content?.hasPrefix(localPrefix) ?? false }
    static func isCloud(_ content: String?) -> Bool { content?.hasPrefix("/api/sync/images/") ?? false }

    // Shrinks a picked photo to board size and keeps it on this device until sync uploads it
    func importPhoto(_ data: Data) throws -> (content: String, aspect: Double) {
        guard let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        let jpeg = Self.encode(image)
        let name = UUID().uuidString.lowercased() + ".jpg"
        try jpeg.write(to: localDir.appending(path: name), options: .atomic)
        let size = image.size
        return (Self.localPrefix + name, size.height > 0 ? size.width / size.height : 1)
    }

    func image(for content: String) async -> UIImage? {
        if let hit = memory.object(forKey: content as NSString) { return hit }
        guard let url = await fileURL(for: content), let image = UIImage(contentsOfFile: url.path()) else { return nil }
        memory.setObject(image, forKey: content as NSString)
        return image
    }

    // A file on disk for this image, downloading cloud images on first use
    func fileURL(for content: String) async -> URL? {
        if content.hasPrefix(Self.localPrefix) {
            let url = localDir.appending(path: String(content.dropFirst(Self.localPrefix.count)))
            return FileManager.default.fileExists(atPath: url.path()) ? url : nil
        }
        if content.hasPrefix("data:") {
            guard let comma = content.firstIndex(of: ","), let data = Data(base64Encoded: String(content[content.index(after: comma)...])) else {
                return nil
            }
            let url = cacheDir.appending(path: Self.hash(content))
            if !FileManager.default.fileExists(atPath: url.path()) { try? data.write(to: url) }
            return url
        }
        let cached = cacheDir.appending(path: Self.hash(content))
        if FileManager.default.fileExists(atPath: cached.path()) { return cached }
        guard let remote = SyncAPI.absoluteURL(for: content) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try data.write(to: cached, options: .atomic)
            return cached
        } catch {
            return nil
        }
    }

    // Bytes and content type for uploading a local image to the cloud
    func uploadData(for content: String) -> (Data, String)? {
        guard content.hasPrefix(Self.localPrefix) else { return nil }
        let url = localDir.appending(path: String(content.dropFirst(Self.localPrefix.count)))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (data, "image/jpeg")
    }

    // After an upload the cloud path replaces the local one. Seed the cache so
    // the image never downloads back to the device that just sent it.
    func adopt(local: String, as cloudPath: String) {
        guard let source = localDirURL(local) else { return }
        let target = cacheDir.appending(path: Self.hash(cloudPath))
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: source, to: target)
        if let image = memory.object(forKey: local as NSString) {
            memory.setObject(image, forKey: cloudPath as NSString)
        }
    }

    private func localDirURL(_ content: String) -> URL? {
        guard content.hasPrefix(Self.localPrefix) else { return nil }
        return localDir.appending(path: String(content.dropFirst(Self.localPrefix.count)))
    }

    func deleteLocal(_ content: String) {
        if let url = localDirURL(content) { try? FileManager.default.removeItem(at: url) }
    }

    private static func encode(_ image: UIImage) -> Data {
        var edge = maxEdge
        var best = Data()
        for _ in 0..<4 {
            let scale = min(1, edge / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            best = resized.jpegData(compressionQuality: 0.85) ?? best
            if best.count <= maxUploadBytes { break }
            edge *= 0.7
        }
        return best
    }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
