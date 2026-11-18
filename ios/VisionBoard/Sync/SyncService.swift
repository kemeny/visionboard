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

    private(set) var key: String?
    private(set) var status: Status = .off
    private(set) var errorMessage: String?

    private let store: BoardStore
    // Called when this board's key appears or goes away, so the account
    // backup can follow
    @ObservationIgnored var onKeyChange: (@MainActor () -> Void)?
    // The delayed push after an edit. Cancelling it only stops the wait;
    // a push that already started runs to the end in `inFlight`.
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var pushTaskToken = 0
    // The push talking to the server right now. Pushes run one at a time.
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var inFlightToken = 0
    // Bumped on every local edit, so a push only marks the board clean when
    // nothing changed while it was uploading
    @ObservationIgnored private var editGeneration = 0
    // Saved per board, so an edit made just before the app is killed is
    // still pushed on the next launch instead of being pulled over
    private static func dirtyDefaultsKey(board boardID: String) -> String { "sync-dirty-\(boardID)" }
    private static func isDirty(board boardID: String) -> Bool {
        UserDefaults.standard.bool(forKey: dirtyDefaultsKey(board: boardID))
    }
    private static func setDirty(_ value: Bool, board boardID: String) {
        UserDefaults.standard.set(value, forKey: dirtyDefaultsKey(board: boardID))
    }
    private var dirty: Bool {
        get { Self.isDirty(board: store.boardID) }
        set { Self.setDirty(newValue, board: store.boardID) }
    }
    private static func syncedAtKey(board boardID: String) -> String {
        boardID == BoardLibrary.mainID ? "synced-at" : "synced-at-\(boardID)"
    }
    private static func syncedAt(board boardID: String) -> Double {
        UserDefaults.standard.double(forKey: syncedAtKey(board: boardID))
    }
    private static func setSyncedAt(_ value: Double, board boardID: String) {
        UserDefaults.standard.set(value, forKey: syncedAtKey(board: boardID))
    }
    private static let pushDelay: Duration = .milliseconds(1500)

    init(store: BoardStore) {
        self.store = store
        key = KeyStore.read(board: store.boardID)
        status = !SyncAPI.isConfigured ? .unavailable : key == nil ? .off : .synced
    }

    // Before the store switches boards: send any edit still waiting and let a
    // push already under way finish, so nothing is left for the next board
    func finishPending() async {
        let hadPending = pushTask != nil
        pushTask?.cancel()
        pushTask = nil
        if let inFlight { await inFlight.value }
        if hadPending, dirty, let key {
            await runPush(key: key, board: store.boardID)
        }
    }

    // After the store switched boards: pick up that board's own key
    func boardChanged() {
        pushTask?.cancel()
        pushTask = nil
        // `dirty` now reads the new board's own saved flag
        errorMessage = nil
        key = KeyStore.read(board: store.boardID)
        status = !SyncAPI.isConfigured ? .unavailable : key == nil ? .off : .synced
    }

    // A board deleted from this device takes its key with it
    static func forget(board boardID: String) {
        KeyStore.write(nil, board: boardID)
        UserDefaults.standard.removeObject(forKey: "synced-at-\(boardID)")
        UserDefaults.standard.removeObject(forKey: dirtyDefaultsKey(board: boardID))
    }

    var isOn: Bool { key != nil }

    func localEdit() {
        guard let key else { return }
        let boardID = store.boardID
        dirty = true
        editGeneration += 1
        pushTask?.cancel()
        pushTaskToken += 1
        let token = pushTaskToken
        pushTask = Task {
            try? await Task.sleep(for: Self.pushDelay)
            guard !Task.isCancelled else { return }
            await runPush(key: key, board: boardID)
            // A newer edit may have scheduled its own push meanwhile
            if pushTaskToken == token { pushTask = nil }
        }
    }

    func pull() async {
        guard let key, status != .unavailable else { return }
        let boardID = store.boardID
        // An edit that never got out (the app was killed first) goes up
        // before anything comes down. A push already waiting will send it.
        if dirty && pushTask == nil {
            await runPush(key: key, board: boardID)
        }
        guard isCurrent(key: key, board: boardID) else { return }
        status = .syncing
        do {
            let remote = try await SyncAPI.fetchBoard(key: key)
            // The board on screen changed while this was downloading:
            // never put one board's cloud copy into another
            guard isCurrent(key: key, board: boardID) else { return }
            if let remote, remote.updatedAt > Self.syncedAt(board: boardID), !dirty {
                store.applyRemote(items: remote.board.items, maxZIndex: remote.board.maxZIndex ?? Double(remote.board.items.count + 1))
                Self.setSyncedAt(remote.updatedAt, board: boardID)
            }
            status = .synced
            errorMessage = nil
        } catch {
            if isCurrent(key: key, board: boardID) { fail(error) }
        }
    }

    func syncNow() async {
        guard let key else { return }
        dirty = true
        await runPush(key: key, board: store.boardID)
    }

    // Start syncing this board under a brand-new key
    func enable() async {
        let newKey = SyncAPI.generateKey()
        let boardID = store.boardID
        KeyStore.write(newKey, board: boardID)
        key = newKey
        Self.setSyncedAt(0, board: boardID)
        dirty = true
        Analytics.capture("sync_enabled", ["board_item_count": store.items.count])
        onKeyChange?()
        await runPush(key: newKey, board: boardID)
    }

    // Join an existing board: the cloud copy replaces what's on this device
    func connect(_ input: String) async throws {
        let newKey = SyncAPI.normalizeKey(input)
        guard newKey.count >= 20 else {
            throw SyncAPI.Failure(message: String(localized: "That doesn't look like a sync key. It's the code shown under Sync on your other device."), status: 0)
        }
        let boardID = store.boardID
        guard let remote = try await SyncAPI.fetchBoard(key: newKey) else {
            throw SyncAPI.Failure(message: String(localized: "No board found for that key. Check it and try again."), status: 404)
        }
        // Another board was opened while this was loading; join nothing
        guard store.boardID == boardID else { return }
        KeyStore.write(newKey, board: boardID)
        key = newKey
        dirty = false
        store.applyRemote(items: remote.board.items, maxZIndex: remote.board.maxZIndex ?? Double(remote.board.items.count + 1))
        Self.setSyncedAt(remote.updatedAt, board: boardID)
        status = .synced
        errorMessage = nil
        Analytics.capture("board_joined", ["board_item_count": store.items.count])
        onKeyChange?()
    }

    // Stop syncing here; the board stays on this device and in the cloud
    func disconnect() {
        pushTask?.cancel()
        pushTask = nil
        KeyStore.write(nil, board: store.boardID)
        dirty = false
        key = nil
        Self.setSyncedAt(0, board: store.boardID)
        status = .off
        errorMessage = nil
        onKeyChange?()
    }

    // Remove the board and its images from the cloud for every device
    func deleteCloudCopy() async throws {
        guard let key else { return }
        try await SyncAPI.deleteBoard(key: key)
        disconnect()
    }

    // Turns on sync for a board that isn't on screen: a new key, its photos
    // uploaded and the board pushed, straight from its file. If the upload
    // fails the board stays marked as changed, so it goes up when opened.
    @discardableResult
    static func enableStored(board boardID: String) async -> String {
        if let existing = KeyStore.read(board: boardID) { return existing }
        let key = SyncAPI.generateKey()
        KeyStore.write(key, board: boardID)
        setSyncedAt(0, board: boardID)
        setDirty(true, board: boardID)

        let url = BoardLibrary.fileURL(for: boardID)
        guard let data = try? Data(contentsOf: url), var file = try? JSONDecoder().decode(BoardFile.self, from: data) else {
            return key
        }
        var pending = Set<String>()
        for item in file.items {
            for content in [item.content, item.originalContent] {
                if let content, ImageStore.isLocal(content) { pending.insert(content) }
            }
        }
        var uploaded: [String: String] = [:]
        for local in pending {
            guard let upload = await ImageStore.shared.uploadData(for: local) else { continue }
            if let path = try? await SyncAPI.uploadImage(key: key, data: upload.0, contentType: upload.1) {
                await ImageStore.shared.adopt(local: local, as: path)
                uploaded[local] = path
            }
        }
        if !uploaded.isEmpty {
            for index in file.items.indices {
                if let cloud = uploaded[file.items[index].content] { file.items[index].content = cloud }
                if let original = file.items[index].originalContent, let cloud = uploaded[original] { file.items[index].originalContent = cloud }
            }
            if let encoded = try? JSONEncoder().encode(file) { try? encoded.write(to: url, options: .atomic) }
        }
        var remote = file
        remote.items = remote.items
            .filter { !ImageStore.isLocal($0.content) }
            .map { item in
                var item = item
                if ImageStore.isLocal(item.originalContent) { item.originalContent = nil }
                return item
            }
        if let updatedAt = try? await SyncAPI.pushBoard(key: key, board: remote) {
            setSyncedAt(updatedAt, board: boardID)
            let stillLocal = file.items.contains { ImageStore.isLocal($0.content) }
            setDirty(stillLocal, board: boardID)
        }
        return key
    }

    // True while `board` is on screen and still syncs under `key`
    private func isCurrent(key: String, board boardID: String) -> Bool {
        store.boardID == boardID && self.key == key
    }

    // Runs a push after any push already in flight, in a task of its own so
    // cancelling the delayed push never cuts an upload off halfway
    private func runPush(key: String, board boardID: String) async {
        let previous = inFlight
        inFlightToken += 1
        let token = inFlightToken
        let task = Task { [weak self] in
            await previous?.value
            await self?.push(key: key, board: boardID)
        }
        inFlight = task
        await task.value
        if inFlightToken == token { inFlight = nil }
    }

    // Sends `board` under `key`. Everything it sends is read while that board
    // is on screen; if another board opens part way, it stops and leaves the
    // first board marked dirty so its next push (or pull) sends it.
    private func push(key: String, board boardID: String) async {
        guard isCurrent(key: key, board: boardID) else {
            // Its board is no longer on screen. Keep the edit for next time.
            if KeyStore.read(board: boardID) == key { Self.setDirty(true, board: boardID) }
            return
        }
        let generation = editGeneration
        let snapshot = store.items
        status = .syncing
        do {
            // Upload photos added on this device first, then swap in their cloud paths
            var uploaded: [String: String] = [:]
            var imageError: String?
            var pending = Set<String>()
            for item in snapshot {
                for content in [item.content, item.originalContent] {
                    if let content, ImageStore.isLocal(content) { pending.insert(content) }
                }
            }
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
            guard isCurrent(key: key, board: boardID) else {
                abandon(board: boardID, key: key, uploaded: uploaded)
                return
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
            // `file` is this board's, so it is safe to send even if another board opens during the request
            let pushedAt = try await SyncAPI.pushBoard(key: key, board: file)
            Self.setSyncedAt(pushedAt, board: boardID)
            guard isCurrent(key: key, board: boardID) else {
                // Edits after `file` was built can't be told apart from here, so push again next time
                Self.setDirty(true, board: boardID)
                return
            }
            // An edit made during the upload keeps the board dirty for its own push
            if editGeneration == generation {
                dirty = store.items.contains { ImageStore.isLocal($0.content) }
            }
            if let imageError {
                status = .error
                errorMessage = String(localized: "Some photos couldn't be saved to the cloud: \(imageError)")
            } else {
                status = .synced
                errorMessage = nil
            }
        } catch {
            if isCurrent(key: key, board: boardID) {
                fail(error)
            } else {
                Self.setDirty(true, board: boardID)
            }
        }
    }

    // Another board opened during the uploads. The photos that made it up are
    // written into the first board's saved file so they don't upload twice,
    // and that board stays dirty so it is pushed the next time it is open.
    private func abandon(board boardID: String, key: String, uploaded: [String: String]) {
        Self.setDirty(true, board: boardID)
        guard !uploaded.isEmpty else { return }
        let url = BoardLibrary.fileURL(for: boardID)
        guard let data = try? Data(contentsOf: url), var file = try? JSONDecoder().decode(BoardFile.self, from: data) else { return }
        for index in file.items.indices {
            if let cloud = uploaded[file.items[index].content] { file.items[index].content = cloud }
            if let original = file.items[index].originalContent, let cloud = uploaded[original] { file.items[index].originalContent = cloud }
        }
        if let encoded = try? JSONEncoder().encode(file) {
            try? encoded.write(to: url, options: .atomic)
        }
    }

    private func fail(_ error: Error) {
        status = .error
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
