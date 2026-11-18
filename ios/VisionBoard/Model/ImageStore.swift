import CryptoKit
import ImageIO
import UIKit

// Board images live in four places: photos added on this device ("local:"),
// cloud images shared with the web app ("/api/sync/images/…", cached on disk
// once fetched, and immutable), Unsplash photos hotlinked from
// images.unsplash.com (cached the same way), and the occasional "data:" URL.
actor ImageStore {
    static let shared = ImageStore()

    static let localPrefix = "local:"
    // Long edge and size budget match the web app's upload limits
    private static let maxEdge: CGFloat = 2560
    static let maxUploadBytes = 3 * 1024 * 1024

    // Decoded images at the size they were asked for, weighed by their bytes
    private let memory = NSCache<NSString, UIImage>()
    // Pixel size of each image (upright), so a cached size can be found without opening the file
    private var pixelSizes: [String: CGSize] = [:]
    // Which long edges of each image are cached, so they move with it when it's uploaded
    private var variants: [String: Set<Int>] = [:]
    // The largest a photo is drawn: four times zoomed in on a big clipping
    private static let maxDisplayEdge: CGFloat = 4096
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
        memory.countLimit = 300
        memory.totalCostLimit = 96 * 1024 * 1024
    }

    static func isLocal(_ content: String?) -> Bool { content?.hasPrefix(localPrefix) ?? false }
    static func isCloud(_ content: String?) -> Bool { content?.hasPrefix("/api/sync/images/") ?? false }
    // Create with AI photos stay on Unsplash's own servers: their guidelines
    // ask apps to hotlink, never to copy the photo to a server of their own.
    // They are cached on this device like cloud images and never uploaded.
    static let unsplashPrefix = "https://images.unsplash.com/"
    static func isUnsplash(_ content: String?) -> Bool { content?.hasPrefix(unsplashPrefix) ?? false }

    // Width over height of a remote or stored image, fetching it into the
    // cache first if needed
    func aspect(for content: String) async -> Double? {
        guard let url = await fileURL(for: content),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let size = Self.pixelSize(of: source)
        else { return nil }
        pixelSizes[content] = size
        return size.width / size.height
    }

    // Shrinks a picked photo to board size and keeps it on this device until sync uploads it
    func importPhoto(_ data: Data) throws -> (content: String, aspect: Double) {
        // Decode straight to board size so a 48 MP photo never sits in memory at full size
        guard let image = Self.downsample(data, maxPixels: Self.maxEdge) ?? UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let jpeg = Self.encode(image)
        let name = UUID().uuidString.lowercased() + ".jpg"
        try jpeg.write(to: localDir.appending(path: name), options: .atomic)
        let size = image.size
        return (Self.localPrefix + name, size.height > 0 ? size.width / size.height : 1)
    }

    // The whole image, at most maxEdge on the long side. For sharing and
    // renders; views on screen use image(for:fitting:fill:).
    func image(for content: String) async -> UIImage? {
        await load(content, cached: true) { size in min(max(size.width, size.height), Self.maxEdge) }
    }

    // A one-off copy at most maxPixels on the long side, not kept in memory
    func image(for content: String, maxPixels: CGFloat) async -> UIImage? {
        await load(content, cached: false) { size in min(max(size.width, size.height), maxPixels) }
    }

    // For display: decoded just big enough to fill (or fit) a box of this
    // many pixels, so a 12 MP photo shown as a thumbnail costs a thumbnail's memory
    func image(for content: String, fitting box: CGSize, fill: Bool) async -> UIImage? {
        guard box.width >= 1, box.height >= 1 else { return await image(for: content) }
        return await load(content, cached: true) { size in
            let scale = fill
                ? max(box.width / max(size.width, 1), box.height / max(size.height, 1))
                : min(box.width / max(size.width, 1), box.height / max(size.height, 1))
            return min(max(size.width, size.height) * scale, Self.maxDisplayEdge)
        }
    }

    // Decodes with ImageIO at the long edge `edge` picks for the image's pixel
    // size. Edges round up to steps of 128 px so nearby sizes share one copy.
    private func load(_ content: String, cached: Bool, edge: (CGSize) -> CGFloat) async -> UIImage? {
        if let size = pixelSizes[content] {
            let key = Self.cacheKey(content, Self.step(edge(size), size: size))
            if let hit = memory.object(forKey: key) { return hit }
        }
        guard let url = await fileURL(for: content) else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions), let size = Self.pixelSize(of: source) else {
            return nil
        }
        pixelSizes[content] = size
        let target = Self.step(edge(size), size: size)
        let key = Self.cacheKey(content, target)
        if let hit = memory.object(forKey: key) { return hit }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        if cached {
            memory.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
            variants[content, default: []].insert(target)
        }
        return image
    }

    private static func step(_ edge: CGFloat, size: CGSize) -> Int {
        let full = Int(max(size.width, size.height).rounded(.up))
        let stepped = Int((max(edge, 1) / 128).rounded(.up)) * 128
        return max(1, min(stepped, full))
    }

    private static func cacheKey(_ content: String, _ edge: Int) -> NSString {
        "\(content)#\(edge)" as NSString
    }

    // Pixel size the right way up (EXIF orientations 5 to 8 turn it a quarter)
    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    // A file on disk for this image, downloading cloud images on first use
    func fileURL(for content: String) async -> URL? {
        if content.hasPrefix(Self.localPrefix) {
            let url = localDir.appending(path: String(content.dropFirst(Self.localPrefix.count)))
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
        if content.hasPrefix("data:") {
            guard let comma = content.firstIndex(of: ","), let data = Data(base64Encoded: String(content[content.index(after: comma)...])) else {
                return nil
            }
            let url = cacheDir.appending(path: Self.hash(content))
            if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { try? data.write(to: url) }
            return url
        }
        let cached = cacheDir.appending(path: Self.hash(content))
        if FileManager.default.fileExists(atPath: cached.path(percentEncoded: false)) { return cached }
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
        if let size = pixelSizes.removeValue(forKey: local) { pixelSizes[cloudPath] = size }
        for edge in variants.removeValue(forKey: local) ?? [] {
            guard let image = memory.object(forKey: Self.cacheKey(local, edge)), let cg = image.cgImage else { continue }
            memory.setObject(image, forKey: Self.cacheKey(cloudPath, edge), cost: cg.bytesPerRow * cg.height)
            variants[cloudPath, default: []].insert(edge)
        }
    }

    private func localDirURL(_ content: String) -> URL? {
        guard content.hasPrefix(Self.localPrefix) else { return nil }
        return localDir.appending(path: String(content.dropFirst(Self.localPrefix.count)))
    }

    func deleteLocal(_ content: String) {
        if let url = localDirURL(content) { try? FileManager.default.removeItem(at: url) }
    }

    // ImageIO thumbnail at most maxPixels on the long edge, upright
    private static func downsample(_ data: Data, maxPixels: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
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
