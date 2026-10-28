import Foundation
import Observation

// Keeps this device's board in step with the cloud copy the web app uses.
// Last write wins, like the web: pull when the app comes to the foreground,
// push shortly after each local edit.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case unavailable, off, syncing, synced, error
    }

    private(set) var key: String? = KeyStore.read()
    private(set) var status: Status = .off
    private(set) var errorMessage: String?

    private let store: BoardStore
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    private var syncedAt: Double {
        get { UserDefaults.standard.double(forKey: "synced-at") }
        set { UserDefaults.standard.set(newValue, forKey: "synced-at") }
    }
    private static let pushDelay: Duration = .milliseconds(1500)

    init(store: BoardStore) {
        self.store = store
        status = !SyncAPI.isConfigured ? .unavailable : key == nil ? .off : .synced
    }

    var isOn: Bool { key != nil }

    func localEdit() {
        guard let key else { return }
        dirty = true
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled else { return }
            await push(key: key)
        }
    }

    func pull() async {
        guard let key, status != .unavailable else { return }
        status = .syncing
        do {
            if let remote = try await SyncAPI.fetchBoard(key: key), remote.updatedAt > syncedAt, !dirty {
                store.applyRemote(items: remote.board.items, maxZIndex: remote.board.maxZIndex ?? Double(remote.board.items.count + 1))
                syncedAt = remote.updatedAt
            }
            status = .synced
            errorMessage = nil
        } catch {
            fail(error)
        }
    }

    func syncNow() async {
        guard let key else { return }
        dirty = true
        await push(key: key)
    }

    // Start syncing this board under a brand-new key
    func enable() async {
        let newKey = SyncAPI.generateKey()
        KeyStore.write(newKey)
        key = newKey
        syncedAt = 0
        dirty = true
        await push(key: newKey)
    }

    // Join an existing board: the cloud copy replaces what's on this device
    func connect(_ input: String) async throws {
        let newKey = SyncAPI.normalizeKey(input)
        guard newKey.count >= 20 else {
            throw SyncAPI.Failure(message: "That doesn't look like a sync key. It's the code shown under Sync on your other device.", status: 0)
        }
        guard let remote = try await SyncAPI.fetchBoard(key: newKey) else {
            throw SyncAPI.Failure(message: "No board found for that key. Check it and try again.", status: 404)
        }
        KeyStore.write(newKey)
        key = newKey
        dirty = false
        store.applyRemote(items: remote.board.items, maxZIndex: remote.board.maxZIndex ?? Double(remote.board.items.count + 1))
        syncedAt = remote.updatedAt
        status = .synced
        errorMessage = nil
    }

    // Stop syncing here; the board stays on this device and in the cloud
    func disconnect() {
        pushTask?.cancel()
        KeyStore.write(nil)
        key = nil
        syncedAt = 0
        status = .off
        errorMessage = nil
    }

    // Remove the board and its images from the cloud for every device
    func deleteCloudCopy() async throws {
        guard let key else { return }
        try await SyncAPI.deleteBoard(key: key)
        disconnect()
    }

    private func push(key: String) async {
        status = .syncing
        do {
            // Upload photos added on this device first, then swap in their cloud paths
            var uploaded: [String: String] = [:]
            var imageError: String?
            let pending = Set(store.items.flatMap { [$0.content, $0.originalContent ?? ""] }.filter { ImageStore.isLocal($0) })
            for local in pending {
                guard let upload = await ImageStore.shared.uploadData(for: local) else { continue }
                do {
                    let path = try await SyncAPI.uploadImage(key: key, data: upload.0, contentType: upload.1)
                    await ImageStore.shared.adopt(local: local, as: path)
                    uploaded[local] = path
                } catch {
                    imageError = imageError ?? error.localizedDescription
                }
            }
            store.replaceContents(uploaded)

            // Anything still local (failed, or added mid-upload) stays off the cloud copy until the next push
            var file = store.boardFile
            file.items = file.items
                .filter { !ImageStore.isLocal($0.content) }
                .map { item in
                    var item = item
                    if ImageStore.isLocal(item.originalContent) { item.originalContent = nil }
                    return item
                }
            syncedAt = try await SyncAPI.pushBoard(key: key, board: file)
            dirty = store.items.contains { ImageStore.isLocal($0.content) }
            if let imageError {
                status = .error
                errorMessage = "Some photos couldn't be saved to the cloud: \(imageError)"
            } else {
                status = .synced
                errorMessage = nil
            }
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        status = .error
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
