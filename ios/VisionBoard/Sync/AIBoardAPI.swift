import Foundation

// "Create with AI": the Worker's /api/sync/ai/* routes (worker/src/ai.ts).
// Claude writes the goals and Unsplash finds a photo for each one. No sync
// key is needed. Board generation sends the active plan's signed App Store
// transaction, and the Worker answers 402 "pro_required" without one.
enum AIBoardAPI {
    struct Failure: Error {
        // The Worker's error code ("rate_limited", "ai_unavailable", …) or
        // "network", "not_configured", "bad_response". Safe for analytics.
        let reason: String
    }

    struct Suggestion: Identifiable, Hashable {
        let id: Int
        let text: String
        let imageURL: URL?
        let photographer: String?
        let photographerURL: String?
        let downloadURL: String?

        var credit: BoardItem.Credit? {
            guard let photographer, !photographer.isEmpty else { return nil }
            return BoardItem.Credit(name: photographer, url: photographerURL, source: "unsplash")
        }
    }

    static let maxPromptLength = 600

    // The app's own language, so goals come back in the language of the UI
    static var language: String {
        let code = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return code.lowercased().hasPrefix("es") ? "es" : "en"
    }

    static func generate(prompt: String, count: Int = 8) async throws -> [Suggestion] {
        struct Wire: Decodable {
            let text: String
            let imageUrl: String?
            let photographer: String?
            let photographerUrl: String?
            let unsplashDownloadUrl: String?
        }
        struct Response: Decodable { let items: [Wire] }

        let body: [String: Any] = ["prompt": String(prompt.prefix(maxPromptLength)), "lang": language, "count": count]
        // The Worker checks this signed App Store transaction before it runs
        // anything, so Pro is enforced there too and not only in the app
        let proof = await ProAccess.shared.entitlementJWS()
        let data = try await post("/ai/board", body: body, timeout: 60, proof: proof)
        guard let response = try? JSONDecoder().decode(Response.self, from: data), !response.items.isEmpty else {
            throw Failure(reason: "bad_response")
        }
        return response.items.enumerated().map { index, wire in
            Suggestion(
                id: index,
                text: wire.text,
                imageURL: wire.imageUrl.flatMap { URL(string: $0) },
                photographer: wire.photographer,
                photographerURL: wire.photographerUrl,
                downloadURL: wire.unsplashDownloadUrl
            )
        }
    }

    // MARK: Photo search

    // One Unsplash result for Search Photos in the board's add menu
    struct Photo: Identifiable, Hashable, Decodable {
        let imageUrl: String
        let thumbUrl: String
        let width: Double
        let height: Double
        let alt: String?
        let photographer: String?
        let photographerUrl: String?
        let unsplashDownloadUrl: String?

        var id: String { imageUrl }
        var aspect: Double { width / max(height, 1) }

        var credit: BoardItem.Credit? {
            guard let photographer, !photographer.isEmpty else { return nil }
            return BoardItem.Credit(name: photographer, url: photographerUrl, source: "unsplash")
        }
    }

    static let maxSearchLength = 80

    // Free for everyone: no Pro proof. 24 photos a page, up to 10 pages.
    static func searchPhotos(_ query: String, page: Int = 1) async throws -> (photos: [Photo], hasMore: Bool) {
        struct Response: Decodable {
            let photos: [Photo]
            let hasMore: Bool?
        }
        let body: [String: Any] = ["query": String(query.prefix(maxSearchLength)), "page": page]
        let data = try await post("/ai/photos", body: body, timeout: 20)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw Failure(reason: "bad_response")
        }
        // Only hotlink Unsplash's own CDN
        let photos = response.photos.filter {
            ImageStore.isUnsplash($0.imageUrl) && ImageStore.isUnsplash($0.thumbUrl) && $0.width > 0 && $0.height > 0
        }
        return (photos, response.hasMore ?? false)
    }

    // Unsplash asks apps to report each photo they actually use. Best effort.
    static func reportDownload(_ url: String) async {
        _ = try? await post("/ai/unsplash-download", body: ["url": url], timeout: 20)
    }

    private static func post(_ path: String, body: [String: Any], timeout: TimeInterval, proof: String? = nil) async throws -> Data {
        guard let origin = SyncAPI.webOrigin, let url = URL(string: origin.absoluteString + "/api/sync" + path) else {
            throw Failure(reason: "not_configured")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios", forHTTPHeaderField: "X-VB-Client")
        if let proof { request.setValue(proof, forHTTPHeaderField: "X-VB-Pro") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(reason: "network")
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw Failure(reason: code ?? "http_\(status)")
        }
        return data
    }
}
