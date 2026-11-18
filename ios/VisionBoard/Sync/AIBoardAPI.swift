import Foundation

// "Create with AI": the Worker's /api/sync/ai/* routes (worker/src/ai.ts).
// Claude writes the goals and Unsplash finds a photo for each one. No sync
// key is needed; the Worker only answers requests marked as coming from iOS.
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
        let data = try await post("/ai/board", body: body, timeout: 60)
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

    // Unsplash asks apps to report each photo they actually use. Best effort.
    static func reportDownload(_ url: String) async {
        _ = try? await post("/ai/unsplash-download", body: ["url": url], timeout: 20)
    }

    private static func post(_ path: String, body: [String: Any], timeout: TimeInterval) async throws -> Data {
        guard let origin = SyncAPI.webOrigin, let url = URL(string: origin.absoluteString + "/api/sync" + path) else {
            throw Failure(reason: "not_configured")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios", forHTTPHeaderField: "X-VB-Client")
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
