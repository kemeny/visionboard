import SwiftUI
import UserNotifications

@main
struct VisionBoardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var store: BoardStore
    @State private var sync: SyncService
    @State private var reminders = Reminders()
    @State private var router = AppRouter.shared

    init() {
        let store = BoardStore()
        let sync = SyncService(store: store)
        store.onEdit = { sync.localEdit() }
        _store = State(initialValue: store)
        _sync = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
                .environment(reminders)
                .environment(router)
                .onOpenURL { url in router.open(url) }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await sync.pull()
                    await reminders.reschedule(items: store.items)
                }
                // Board edits change which goal shows on which day
                .task(id: store.items) {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await reminders.reschedule(items: store.items)
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
        [.banner, .sound]
    }

    // Tapping a reminder opens that day's goal and photo full screen
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let text = info["text"] as? String ?? ""
        let image = (info["image"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        await MainActor.run {
            AppRouter.shared.todayCard = DailyCard(text: text, image: image)
        }
    }
}
