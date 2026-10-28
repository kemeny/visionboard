import Foundation
import Security

// Client for the Cloudflare Worker in worker/, reached through the web app's
// /api/sync proxy. Auth is the board's sync key as a bearer token.
enum SyncAPI {
    struct Failure: LocalizedError {
        let message: String
        let status: Int
        var errorDescription: String? { message }
    }

    struct RemoteBoard: Decodable {
        let board: BoardFile
        let updatedAt: Double
    }

    // The web app's address, from VB_WEB_ORIGIN in the build settings
    static let webOrigin: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "VBWebOrigin") as? String, !raw.isEmpty else { return nil }
        return URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
    }()

    static var isConfigured: Bool { webOrigin != nil }

    static func absoluteURL(for path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        guard let origin = webOrigin, path.hasPrefix("/") else { return nil }
        return URL(string: origin.absoluteString + path)
    }

    // A link that opens this board on another device. The key rides in the
    // fragment, which browsers never send to the server.
    static func shareLink(for key: String) -> URL? {
        guard let origin = webOrigin else { return nil }
        let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? key
        return URL(string: "\(origin.absoluteString)/#sync=\(escaped)")
    }

    // 20 random characters from the web app's alphabet, grouped: "k3fa-9qzt-…"
    static func generateKey() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var bytes = [UInt8](repeating: 0, count: 20)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let chars = bytes.map { String(alphabet[Int($0) % alphabet.count]) }
        return stride(from: 0, to: chars.count, by: 4).map { chars[$0..<min($0 + 4, chars.count)].joined() }.joined(separator: "-")
    }

    // Accepts a bare key, a "…/#sync=KEY" link from the web app or its QR code,
    // or a visionboard://sync?key=KEY link
    static func normalizeKey(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "#sync=") {
            text = String(text[range.upperBound...].prefix { $0 != "&" })
        } else if let components = URLComponents(string: text), let key = components.queryItems?.first(where: { $0.name == "key" })?.value {
            text = key
        }
        return (text.removingPercentEncoding ?? text).lowercased().filter { !$0.isWhitespace }
    }

    // MARK: Requests

    static func health() async -> Bool {
        (try? await request("/health", key: nil) as [String: Bool]) != nil
    }

    static func fetchBoard(key: String) async throws -> RemoteBoard? {
        do {
            return try await request("/board", key: key)
        } catch let failure as Failure where failure.status == 404 {
            return nil
        }
    }

    static func pushBoard(key: String, board: BoardFile) async throws -> Double {
        struct Response: Decodable { let updatedAt: Double }
        let response: Response = try await request("/board", key: key, method: "PUT", body: try JSONEncoder().encode(board))
        return response.updatedAt
    }

    static func deleteBoard(key: String) async throws {
        let _: [String: Bool] = try await request("/board", key: key, method: "DELETE")
    }

    static func uploadImage(key: String, data: Data, contentType: String) async throws -> String {
        struct Response: Decodable { let path: String }
        let response: Response = try await request("/images", key: key, method: "PUT", body: data, contentType: contentType)
        return response.path
    }

    private static func request<T: Decodable>(
        _ path: String, key: String?, method: String = "GET", body: Data? = nil, contentType: String = "application/json"
    ) async throws -> T {
        guard let origin = webOrigin, let url = URL(string: origin.absoluteString + "/api/sync" + path) else {
            throw Failure(message: "Sync isn't set up in this build", status: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw Failure(message: message ?? "Request failed (\(status))", status: status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// The sync key is a secret, so it lives in the Keychain rather than UserDefaults
enum KeyStore {
    private static let account = "sync-key"

    static func read() -> String? {
        var result: AnyObject?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String?) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
        guard let key else { return }
        var add = query
        add[kSecValueData] = Data(key.utf8)
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
