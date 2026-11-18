import Foundation
import UIKit

// Product analytics and feature flags, sent to PostHog without a third-party
// package. Anonymous: the only id is a random UUID made on this device. Never
// put board content (goal text, photos, names) in properties; counts and
// enums only.
//
// Every call is safe from any thread and returns at once. Work happens on a
// private serial queue; events wait in memory and in a small file in
// Application Support, so nothing is lost if the app is killed.
enum Analytics {
    // Reads the token, loads saved events, starts the 30 second timer and
    // fetches feature flags. Safe to call more than once.
    static func start() {
        AnalyticsEngine.shared.start()
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        AnalyticsEngine.shared.capture(event, properties)
    }

    // The flag's variant, "true" for a plain flag that is on, or nil when the
    // flag is off or unknown. Answers from the cached flags, so it works offline.
    static func flag(_ key: String) -> String? {
        AnalyticsEngine.shared.flag(key)
    }

    static func isEnabled(_ key: String) -> Bool {
        guard let value = flag(key) else { return false }
        return value != "false"
    }

    // When true nothing is captured or sent, and saved events are dropped
    static var optedOut: Bool {
        get { UserDefaults.standard.bool(forKey: AnalyticsEngine.optedOutKey) }
        set { AnalyticsEngine.shared.setOptedOut(newValue) }
    }

    // Sends what's waiting now, asking iOS for a little background time
    static func flush() {
        AnalyticsEngine.shared.flush()
    }
}

final class AnalyticsEngine: @unchecked Sendable {
    static let shared = AnalyticsEngine()

    static let optedOutKey = "analytics-opted-out"
    private static let distinctIDKey = "analytics-distinct-id"
    private static let flagsKey = "analytics-flags"
    private static let flushInterval: TimeInterval = 30
    private static let flushAt = 20
    private static let maxQueued = 500
    private static let maxBatch = 100
    private static let flagsInterval: TimeInterval = 600

    // Fixed at launch, read from any thread
    private let token: String
    private let host: String
    let distinctID: String
    private let superProperties: [String: Any]

    // Owned by `queue`
    private let queue = DispatchQueue(label: "com.kemenystudio.visionboard.analytics", qos: .utility)
    private var events: [Data] = []
    private var started = false
    private var sending = false
    private var timer: DispatchSourceTimer?
    private var lastFlagsFetch: Date?
    private var fetchingFlags = false

    // Read synchronously by flag(), so guarded by a lock
    private let lock = NSLock()
    private var flags: [String: String]
    private var calledFlags: Set<String> = []

    private init() {
        let info = Bundle.main
        token = (info.object(forInfoDictionaryKey: "VBPostHogKey") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var host = (info.object(forInfoDictionaryKey: "VBPostHogHost") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty { host = "https://us.i.posthog.com" }
        while host.hasSuffix("/") { host.removeLast() }
        self.host = host

        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Self.distinctIDKey), !saved.isEmpty {
            distinctID = saved
        } else {
            let made = UUID().uuidString.lowercased()
            defaults.set(made, forKey: Self.distinctIDKey)
            distinctID = made
        }
        flags = defaults.dictionary(forKey: Self.flagsKey) as? [String: String] ?? [:]

        let version = ProcessInfo.processInfo.operatingSystemVersion
        superProperties = [
            "product": "visionboard",
            "platform": "ios",
            "app_version": info.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "app_build": info.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "os_version": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "locale": Locale.current.identifier,
            "$lib": "visionboard-ios",
            "$os": "iOS",
            // Anonymous events: no person profiles, like the web's identified_only
            "$process_person_profile": false,
        ]
    }

    private var isConfigured: Bool { !token.isEmpty }
    private var isActive: Bool { isConfigured && !UserDefaults.standard.bool(forKey: Self.optedOutKey) }

    // MARK: Lifecycle

    func start() {
        queue.async {
            guard !self.started else { return }
            self.started = true
            guard self.isConfigured else { return }
            self.events = self.loadQueue()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
            timer.setEventHandler { [weak self] in self?.send(completion: nil) }
            timer.resume()
            self.timer = timer
            self.fetchFlagsIfStale()
        }
    }

    // Called when the app comes to the front; at most every 10 minutes
    func refreshFlags() {
        queue.async { self.fetchFlagsIfStale() }
    }

    func setOptedOut(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.optedOutKey)
        guard value else { return }
        queue.async {
            self.events.removeAll()
            self.saveQueue()
        }
    }

    func flush() {
        guard isActive else { return }
        Task { @MainActor in
            let task = BackgroundTask()
            task.begin()
            self.queue.async {
                self.send {
                    Task { @MainActor in task.end() }
                }
            }
        }
    }

    // MARK: Events

    func capture(_ event: String, _ properties: [String: Any]) {
        guard isActive, !event.isEmpty else { return }
        var props: [String: Any] = superProperties
        for (key, value) in properties {
            props[key] = Self.jsonSafe(value)
        }
        props["distinct_id"] = distinctID
        let body: [String: Any] = [
            "event": event,
            "distinct_id": distinctID,
            "properties": props,
            "timestamp": Date().ISO8601Format(),
            "uuid": UUID().uuidString.lowercased(),
        ]
        guard JSONSerialization.isValidJSONObject(body), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        queue.async {
            self.events.append(data)
            self.trim()
            self.saveQueue()
            if self.events.count >= Self.flushAt { self.send(completion: nil) }
        }
    }

    // On the queue. Sends up to 100 events; on success the rest follow.
    private func send(completion: (@Sendable () -> Void)?) {
        guard isActive, !sending, !events.isEmpty, let url = URL(string: host + "/batch/") else {
            completion?()
            return
        }
        let batch = Array(events.prefix(Self.maxBatch))
        guard let tokenJSON = try? JSONEncoder().encode(token) else {
            completion?()
            return
        }
        var body = Data("{\"api_key\":".utf8)
        body.append(tokenJSON)
        body.append(Data(",\"batch\":[".utf8))
        for (index, event) in batch.enumerated() {
            if index > 0 { body.append(Data(",".utf8)) }
            body.append(event)
        }
        body.append(Data("]}".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 20
        sending = true
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            self.queue.async {
                self.sending = false
                let delivered = error == nil && (200..<300).contains(status)
                // A batch the server rejects as malformed would fail forever
                let rejected = error == nil && (status == 400 || status == 413)
                if delivered || rejected {
                    self.events.removeFirst(min(batch.count, self.events.count))
                    self.saveQueue()
                    if delivered && !self.events.isEmpty {
                        self.send(completion: completion)
                        return
                    }
                }
                completion?()
            }
        }.resume()
    }

    // Keep the newest 500 when sending keeps failing
    private func trim() {
        if events.count > Self.maxQueued {
            events.removeFirst(events.count - Self.maxQueued)
        }
    }

    // MARK: Persistence (one JSON event per line)

    private var queueURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "VisionBoard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "analytics-queue.jsonl")
    }

    private func loadQueue() -> [Data] {
        guard let data = try? Data(contentsOf: queueURL), !data.isEmpty else { return [] }
        let lines = data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
        return Array(lines.suffix(Self.maxQueued))
    }

    private func saveQueue() {
        var data = Data()
        for (index, event) in events.enumerated() {
            if index > 0 { data.append(UInt8(ascii: "\n")) }
            data.append(event)
        }
        try? data.write(to: queueURL, options: .atomic)
    }

    // MARK: Feature flags

    func flag(_ key: String) -> String? {
        lock.lock()
        let value = flags[key]
        let firstRead = calledFlags.insert(key).inserted
        lock.unlock()
        if firstRead {
            let response: Any = value.map { $0 == "true" ? true as Any : $0 as Any } ?? false
            capture("$feature_flag_called", ["$feature_flag": key, "$feature_flag_response": response])
        }
        return value
    }

    // On the queue
    private func fetchFlagsIfStale() {
        guard isActive, !fetchingFlags, let url = URL(string: host + "/flags?v=2") else { return }
        if let last = lastFlagsFetch, Date().timeIntervalSince(last) < Self.flagsInterval { return }
        let payload: [String: Any] = ["api_key": token, "distinct_id": distinctID]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15
        fetchingFlags = true
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let parsed: [String: String]? = (error == nil && (200..<300).contains(status)) ? data.flatMap { AnalyticsEngine.parseFlags($0) } : nil
            self.queue.async {
                self.fetchingFlags = false
                guard let parsed else { return }
                self.lastFlagsFetch = Date()
                self.lock.lock()
                self.flags = parsed
                self.lock.unlock()
                UserDefaults.standard.set(parsed, forKey: Self.flagsKey)
            }
        }.resume()
    }

    // Reads /flags?v=2 ({"flags": {key: {enabled, variant}}}) and the older
    // {"featureFlags": {key: true | "variant"}} shape. Only flags that are on are kept.
    private static func parseFlags(_ data: Data) -> [String: String]? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        if let flags = json["flags"] as? [String: Any] {
            for (key, raw) in flags {
                guard let flag = raw as? [String: Any], flag["enabled"] as? Bool == true else { continue }
                if let variant = flag["variant"] as? String, !variant.isEmpty {
                    result[key] = variant
                } else {
                    result[key] = "true"
                }
            }
            return result
        }
        if let flags = json["featureFlags"] as? [String: Any] {
            for (key, raw) in flags {
                if let variant = raw as? String, !variant.isEmpty {
                    result[key] = variant
                } else if let on = raw as? Bool, on {
                    result[key] = "true"
                }
            }
            return result
        }
        return nil
    }

    // MARK: Helpers

    private static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let text as String: return text
        case let flag as Bool: return flag
        case let number as Int: return number
        case let number as Double: return number.isFinite ? number : 0
        case let number as Float: return number.isFinite ? Double(number) : 0
        case let number as CGFloat: return number.isFinite ? Double(number) : 0
        case let list as [Any]: return list.map { jsonSafe($0) }
        case let map as [String: Any]: return map.mapValues { jsonSafe($0) }
        default: return String(describing: value)
        }
    }
}

// Keeps the app awake for a few seconds after it goes to the background, so
// the last events get out
@MainActor
private final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        id = UIApplication.shared.beginBackgroundTask(withName: "Analytics") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
