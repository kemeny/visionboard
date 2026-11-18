import Foundation
import Security

// The Worker's optional account routes (/api/sync/account/*). An account only
// keeps a backup of this person's board list: each board's name and sync key.
enum AccountAPI {
    struct BackupBoard: Codable, Equatable {
        var name: String
        var syncKey: String
    }

    struct SignInResponse: Decodable {
        let sessionToken: String
        let email: String?
        let hasBackup: Bool?
    }

    struct BackupResponse: Decodable {
        let boards: [BackupBoard]
        let email: String?
    }

    static func signIn(identityToken: String, nonce: String, authorizationCode: String?) async throws -> SignInResponse {
        var fields = ["identityToken": identityToken, "nonce": nonce]
        if let authorizationCode { fields["authorizationCode"] = authorizationCode }
        let body = try JSONEncoder().encode(fields)
        return try await request("/account/signin", session: nil, method: "POST", body: body)
    }

    static func fetchBackup(session: String) async throws -> BackupResponse {
        try await request("/account/backup", session: session)
    }

    static func uploadBackup(_ boards: [BackupBoard], session: String) async throws {
        struct Body: Encodable { let boards: [BackupBoard] }
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request("/account/backup", session: session, method: "PUT", body: try JSONEncoder().encode(Body(boards: boards)))
    }

    static func deleteAccount(session: String) async throws {
        struct Response: Decodable { let ok: Bool }
        let _: Response = try await request("/account", session: session, method: "DELETE")
    }

    private static func request<T: Decodable>(_ path: String, session: String?, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let origin = SyncAPI.webOrigin, let url = URL(string: origin.absoluteString + "/api/sync" + path) else {
            throw SyncAPI.Failure(message: String(localized: "Accounts aren't set up in this build."), status: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let session { request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw SyncAPI.Failure(message: message ?? "Request failed (\(status))", status: status)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// The signed-in account, kept in the Keychain: the session token is a secret
struct AccountSession: Codable, Equatable {
    var token: String
    var userID: String
    var email: String?

    private static let account = "account-session"

    static func load() -> AccountSession? {
        var result: AnyObject?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }

    static func save(_ session: AccountSession?) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var add = query
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
