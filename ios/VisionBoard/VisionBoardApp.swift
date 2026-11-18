import SwiftUI
import UserNotifications

@main
struct VisionBoardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: BoardStore
    @State private var sync: SyncService
    @State private var library: BoardLibrary
    @State private var account: AccountService
    @State private var reminders = Reminders()
    @State private var router = AppRouter.shared
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        Analytics.start()
        let store = BoardStore(boardID: BoardLibrary.savedCurrentID)
        let sync = SyncService(store: store)
        store.onEdit = { sync.localEdit() }
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
        let library = BoardLibrary(store: store, sync: sync)
        let account = AccountService(library: library, sync: sync, store: store)
        // The account backup follows every board and key change
        library.onListChange = { account.scheduleBackup() }
        sync.onKeyChange = { account.scheduleBackup() }
        _library = State(initialValue: library)
        _account = State(initialValue: account)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
                .environment(library)
                .environment(account)
                .environment(reminders)
                .environment(router)
                .environment(ProAccess.shared)
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in router.open(url) }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: AppLifecycleAnalytics.didBecomeActive()
                    case .background: AppLifecycleAnalytics.didEnterBackground()
                    default: break
                    }
                }
                // Sign out here if this Apple Account stopped using the app
                .task { await account.checkCredentialState() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await sync.pull()
                    // Things shared from other apps land on the board after the pull,
                    // so a newer cloud board can't replace them
                    if ShareInbox.hasPending {
                        router.tab = .board
                        router.sharedArrivals += 1
                    }
                    await reminders.reschedule(items: store.items)
                    await WidgetPublisher.publish(items: store.items)
                }
                // A new local day, a time zone change or daylight saving time
                // moves the reminder times, so lay the two weeks out again
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task {
                        await reminders.reschedule(items: store.items)
                        await WidgetPublisher.publish(items: store.items)
                    }
                }
                // Board edits change which goal shows on which day
                .task(id: store.items) {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await reminders.reschedule(items: store.items)
                    await WidgetPublisher.publish(items: store.items)
                }
        }
    }
}

// App-wide navigation state: the selected tab, the full-screen "today" card
// opened from a reminder, and a sync key arriving from a link
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Tab: Hashable {
        case board, feed, today, settings
    }

    var tab: Tab = .board
    var todayCard: DailyCard?
    var incomingSyncKey: String?
    // Bumped when the share sheet left something in the inbox
    var sharedArrivals = 0

    func open(_ url: URL) {
        let text = url.absoluteString
        if text.contains("#sync=") || url.host() == "sync" {
            incomingSyncKey = SyncAPI.normalizeKey(text)
            tab = .settings
        } else if url.host() == "today" {
            tab = .today
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // Tapping a reminder opens that day's goal and photo full screen
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let info = request.content.userInfo
        if request.identifier.hasPrefix("daily-") || request.identifier.hasPrefix("test-") {
            Analytics.capture("reminder_opened", ["kind": request.identifier.hasPrefix("test-") ? "test" : "daily"])
        }
        let text = info["text"] as? String ?? ""
        let image = (info["image"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        await MainActor.run {
            AppRouter.shared.todayCard = DailyCard(text: text, image: image)
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { String(localized: String.LocalizationValue(rawValue.capitalized)) }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
