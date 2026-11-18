import Foundation
import WidgetKit

// App-level events: app_opened each time the app comes back from the
// background, widget_installed the first time each widget size shows up,
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
            properties["days_since_last_open"] = max(0, Int(now.timeIntervalSince(last) / 86_400))
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
            let seen = Set(defaults.stringArray(forKey: key) ?? [])
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
