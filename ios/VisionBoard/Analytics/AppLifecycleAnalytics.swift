import Foundation
import WidgetKit

// App-level events: app_opened each time the app comes back from the
// background, widget_installed the first time each widget size shows up
// after the first run (widgets already there on that run are not counted),
// and a flush when the app leaves the screen.
enum AppLifecycleAnalytics {
    private static let lastOpenKey = "analytics-last-open"
    private static let widgetFamiliesKey = "analytics-widget-families"
    @MainActor private static var wasInBackground = true

    @MainActor
    static func didBecomeActive() {
        guard wasInBackground else { return }
        wasInBackground = false

        let defaults = UserDefaults.standard
        let now = Date()
        var properties: [String: Any] = [:]
        if let last = defaults.object(forKey: lastOpenKey) as? Date {
            // Calendar days, so 11 PM then 7 AM the next morning counts as 1
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
            properties["days_since_last_open"] = max(0, days)
        } else {
            properties["first_open"] = true
        }
        defaults.set(now, forKey: lastOpenKey)
        Analytics.capture("app_opened", properties)
        AnalyticsEngine.shared.refreshFlags()
        checkWidgets()
    }

    @MainActor
    static func didEnterBackground() {
        wasInBackground = true
        Analytics.flush()
    }

    // Not on the main actor: WidgetKit calls back on a background queue
    private static func checkWidgets() {
        let key = widgetFamiliesKey
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case .success(let widgets) = result else { return }
            let families = Set(widgets.map { AppLifecycleAnalytics.familyName($0.family) })
            let defaults = UserDefaults.standard
            // The first run of this build only records the widgets already
            // on screen, so an update doesn't count old widgets as new ones
            guard let stored = defaults.stringArray(forKey: key) else {
                defaults.set(Array(families).sorted(), forKey: key)
                return
            }
            let seen = Set(stored)
            let new = families.subtracting(seen)
            guard !new.isEmpty else { return }
            for family in new.sorted() {
                Analytics.capture("widget_installed", ["family": family])
            }
            defaults.set(Array(seen.union(new)).sorted(), forKey: key)
        }
    }

    private static func familyName(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: "system_small"
        case .systemMedium: "system_medium"
        case .systemLarge: "system_large"
        case .systemExtraLarge: "system_extra_large"
        case .accessoryCircular: "accessory_circular"
        case .accessoryRectangular: "accessory_rectangular"
        case .accessoryInline: "accessory_inline"
        @unknown default: "other"
        }
    }
}
