import AuthenticationServices
import CryptoKit
import Foundation
import Observation

// An optional Sign in with Apple account, for backup only. Never required:
// every board works the same without one.
//
// Signing in turns on sync for every board and backs up the list of boards
// (name and sync key) to the account. On a new iPhone, signing in again
// brings those boards back by connecting to each key.
@MainActor
@Observable
final class AccountService {
    private(set) var session: AccountSession?
    private(set) var busy = false
    private(set) var errorMessage: String?
    private(set) var lastBackup: Date?
    // A short note after something finished, like "3 boards restored"
    private(set) var notice: String?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }
    var isAvailable: Bool { SyncAPI.isConfigured }

    @ObservationIgnored private let library: BoardLibrary
    @ObservationIgnored private let sync: SyncService
    @ObservationIgnored private let store: BoardStore
    @ObservationIgnored private var backupTask: Task<Void, Never>?
    @ObservationIgnored private var revokedObserver: NSObjectProtocol?

    // Hashes of the sync keys this device had at its last backup. A key that
    // was here and is gone was removed on purpose, so it leaves the backup; a
    // key this device never had came from another device and is kept.
    private static let knownKeysDefaultsKey = "account-known-key-hashes"
    private static let lastBackupDefaultsKey = "account-last-backup"
    private static let backupDelay: Duration = .seconds(2)

    init(library: BoardLibrary, sync: SyncService, store: BoardStore) {
        self.library = library
        self.sync = sync
        self.store = store
        session = AccountSession.load()
        let last = UserDefaults.standard.double(forKey: Self.lastBackupDefaultsKey)
        lastBackup = last > 0 ? Date(timeIntervalSince1970: last) : nil
        // Signing out of the app in iOS Settings > Apple Account ends the session here too
        revokedObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.signOut() }
        }
    }

    // A device with nothing on it yet: one empty board that isn't syncing
    var looksFresh: Bool {
        library.boards.count == 1 && store.items.isEmpty && !sync.isOn
    }

    // MARK: Sign in

    func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if let auth = error as? ASAuthorizationError, auth.code == .canceled { return }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = String(localized: "Sign in with Apple didn't finish. Try again.")
                return
            }
            await signIn(identityToken: identityToken, userID: credential.user, email: credential.email)
        }
    }

    private func signIn(identityToken: String, userID: String, email: String?) async {
        busy = true
        errorMessage = nil
        notice = nil
        defer { busy = false }
        do {
            let response = try await AccountAPI.signIn(identityToken: identityToken)
            let newSession = AccountSession(token: response.sessionToken, userID: userID, email: response.email ?? email)
            AccountSession.save(newSession)
            session = newSession
        } catch {
            errorMessage = Self.describe(error)
            return
        }
        // Boards backed up from another device come back first, so the
        // backup below holds both
        let restored = await restoreMissingBoards()
        await turnOnSyncForAllBoards()
        try? await uploadBackup()
        guard isSignedIn else { return }
        Analytics.capture("signin_completed", ["board_count": library.boards.count, "restored_board_count": restored])
    }

    // On launch: if this Apple Account stopped using the app, sign out here
    func checkCredentialState() async {
        guard let userID = session?.userID else { return }
        let answer: (state: ASAuthorizationAppleIDProvider.CredentialState, failed: Bool) = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                continuation.resume(returning: (state, error != nil))
            }
        }
        // A failed check (offline, say) is not a reason to sign out
        if answer.state == .revoked || (answer.state == .notFound && !answer.failed) {
            signOut()
        }
    }

    // MARK: Restore

    // Connects every backed-up board that isn't on this iPhone yet. Returns how many came back.
    @discardableResult
    func restoreMissingBoards() async -> Int {
        guard let token = session?.token else { return 0 }
        let remote: [AccountAPI.BackupBoard]
        do {
            remote = try await AccountAPI.fetchBackup(session: token).boards
        } catch {
            handleFailure(error)
            return 0
        }
        var localKeys = Set(library.boards.compactMap { KeyStore.read(board: $0.id) })
        let missing = remote.filter { !localKeys.contains($0.syncKey) }
        guard !missing.isEmpty else { return 0 }

        let startID = library.currentID
        var restored = 0
        var failed = 0
        for entry in missing where !localKeys.contains(entry.syncKey) {
            if looksFresh {
                // The empty board on a new iPhone becomes the first restored board
                do {
                    try await sync.connect(entry.syncKey)
                    library.rename(library.currentID, to: entry.name)
                    restored += 1
                    localKeys.insert(entry.syncKey)
                } catch {
                    failed += 1
                }
            } else {
                let created = await library.create(named: entry.name)
                do {
                    try await sync.connect(entry.syncKey)
                    restored += 1
                    localKeys.insert(entry.syncKey)
                } catch {
                    await library.delete(created.id)
                    failed += 1
                }
            }
        }
        // Back to the board that was on screen
        if library.currentID != startID, library.boards.contains(where: { $0.id == startID }) {
            await library.open(startID)
        }
        if restored > 0 {
            Analytics.capture("backup_restored", ["boards": restored])
            notice = restored == 1
                ? String(localized: "1 board restored.")
                : String(localized: "\(restored) boards restored.")
        }
        if failed > 0 {
            errorMessage = failed == 1
                ? String(localized: "1 board couldn't be restored. It may have been deleted from the cloud.")
                : String(localized: "\(failed) boards couldn't be restored. They may have been deleted from the cloud.")
        }
        return restored
    }

    // The Restore button for someone who is already signed in
    func restoreNow() async {
        busy = true
        errorMessage = nil
        notice = nil
        defer { busy = false }
        let restored = await restoreMissingBoards()
        if restored > 0 {
            try? await uploadBackup()
        } else if errorMessage == nil, isSignedIn {
            notice = String(localized: "All your backed-up boards are already here.")
        }
    }

    // MARK: Backup

    // Every board gets a sync key, so the backup can point to all of them
    private func turnOnSyncForAllBoards() async {
        for board in library.boards {
            if board.id == library.currentID {
                if !sync.isOn { await sync.enable() }
            } else if KeyStore.read(board: board.id) == nil {
                await SyncService.enableStored(board: board.id)
            }
        }
    }

    // Called when a board is created, renamed or deleted, or a sync key changes
    func scheduleBackup() {
        guard isSignedIn, !busy else { return }
        backupTask?.cancel()
        backupTask = Task {
            try? await Task.sleep(for: Self.backupDelay)
            guard !Task.isCancelled else { return }
            try? await uploadBackup()
        }
    }

    func backUpNow() async {
        busy = true
        errorMessage = nil
        notice = nil
        defer { busy = false }
        await turnOnSyncForAllBoards()
        do {
            try await uploadBackup()
            notice = String(localized: "Backed up.")
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    private func uploadBackup() async throws {
        guard let token = session?.token else { return }
        var list: [AccountAPI.BackupBoard] = library.boards.compactMap { board in
            KeyStore.read(board: board.id).map { AccountAPI.BackupBoard(name: board.name, syncKey: $0) }
        }
        let localHashes = Set(list.map { Self.hash($0.syncKey) })
        let known = Set(UserDefaults.standard.stringArray(forKey: Self.knownKeysDefaultsKey) ?? [])
        do {
            // Keep boards that other devices backed up and this one never had
            let remote = try await AccountAPI.fetchBackup(session: token).boards
            for entry in remote {
                let hashed = Self.hash(entry.syncKey)
                if !localHashes.contains(hashed), !known.contains(hashed), !list.contains(where: { $0.syncKey == entry.syncKey }) {
                    list.append(entry)
                }
            }
            try await AccountAPI.uploadBackup(list, session: token)
        } catch {
            handleFailure(error)
            throw error
        }
        UserDefaults.standard.set(Array(localHashes), forKey: Self.knownKeysDefaultsKey)
        let now = Date.now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastBackupDefaultsKey)
        lastBackup = now
    }

    // MARK: Sign out and delete

    // Ends the account on this iPhone only. Boards keep syncing.
    func signOut() {
        backupTask?.cancel()
        backupTask = nil
        AccountSession.save(nil)
        session = nil
        notice = nil
        UserDefaults.standard.removeObject(forKey: Self.knownKeysDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.lastBackupDefaultsKey)
        lastBackup = nil
    }

    // Deletes the account and its backup from the server. With
    // deleteCloudBoards, every board's cloud copy goes too; the boards
    // themselves stay on this iPhone.
    @discardableResult
    func deleteAccount(deleteCloudBoards: Bool) async -> Bool {
        guard let token = session?.token else { return false }
        busy = true
        errorMessage = nil
        notice = nil
        defer { busy = false }
        backupTask?.cancel()
        do {
            try await AccountAPI.deleteAccount(session: token)
        } catch {
            if let failure = error as? SyncAPI.Failure, failure.status == 401 {
                signOut()
                errorMessage = String(localized: "Your sign-in expired. Sign in again, then delete your account.")
            } else {
                errorMessage = Self.describe(error)
            }
            return false
        }
        var deleted = 0
        if deleteCloudBoards {
            for board in library.boards {
                if board.id == library.currentID {
                    guard sync.isOn else { continue }
                    if (try? await sync.deleteCloudCopy()) != nil { deleted += 1 }
                } else if let key = KeyStore.read(board: board.id) {
                    if (try? await SyncAPI.deleteBoard(key: key)) != nil {
                        SyncService.forget(board: board.id)
                        deleted += 1
                    }
                }
            }
        }
        Analytics.capture("account_deleted", ["cloud_boards_deleted": deleted])
        signOut()
        notice = String(localized: "Your account was deleted.")
        return true
    }

    // MARK: Helpers

    private func handleFailure(_ error: Error) {
        if let failure = error as? SyncAPI.Failure, failure.status == 401 {
            signOut()
            errorMessage = String(localized: "Your sign-in expired. Sign in again to keep your boards backed up.")
        } else {
            errorMessage = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func hash(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
