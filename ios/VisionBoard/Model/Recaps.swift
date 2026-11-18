import Foundation
import UserNotifications

// Two local notifications that close the progress loop, both laid out again
// each time the app comes to the front or the board changes:
//
// - Weekly recap, Sunday at the reminder time (6 PM when daily reminders are
//   off): how many days this week the board was opened, or how many goals
//   were done this month. Tapping it opens RecapView.
// - Win-back, 7 days out: "Your board misses you" with that day's goal.
//   Opening the app pushes it another 7 days out, so it only arrives after a
//   week away. Skipped while daily reminders are on, since those already
//   check in every day.
//
// Neither ever asks for notification permission on its own. They go out
// only when VisionBoard may already send notifications, and only while
// Settings > Weekly Recap and Check-ins is on (it is on by default).
enum Recaps {
    static let enabledKey = "checkins-enabled"
    static let weeklyID = "recap-weekly"
    static let winbackID = "winback"
    private static let fallbackHour = 18
    // Bumped by every reschedule, so one still awaiting stops adding once a
    // newer one started (for example the one setEnabled(false) runs)
    @MainActor private static var generation = 0

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @MainActor
    static func setEnabled(_ on: Bool, store: BoardStore, library: BoardLibrary, reminders: Reminders) async {
        UserDefaults.standard.set(on, forKey: enabledKey)
        if on {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
        await reschedule(store: store, library: library, reminders: reminders)
    }

    @MainActor
    static func reschedule(store: BoardStore, library: BoardLibrary, reminders: Reminders) async {
        generation += 1
        let mine = generation
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyID, winbackID])
        guard isEnabled else { return }
        let settings = await center.notificationSettings()
        // Turned off, or rescheduled again, while that was answering
        guard isEnabled, generation == mine else { return }
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let hour = reminders.isEnabled ? reminders.hour : fallbackHour
        let minute = reminders.isEnabled ? reminders.minute : 0
        let now = Date()
        let allItems = ProgressStats.allItems(store: store, library: library)

        if let sunday = nextSunday(after: now, hour: hour, minute: minute) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Your week on VisionBoard")
            content.body = weeklyBody(items: allItems, on: sunday)
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: weeklyID, content: content, trigger: trigger(for: sunday)))
        }
        guard isEnabled, generation == mine else {
            if !isEnabled { center.removePendingNotificationRequests(withIdentifiers: [weeklyID, winbackID]) }
            return
        }

        if !reminders.isEnabled,
           let day = Calendar.current.date(byAdding: .day, value: 7, to: now),
           let fire = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
            let card = DailyCard.pick(from: store.items, on: fire)
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Your board misses you")
            content.body = card.text
            content.sound = .default
            // Same keys as a daily reminder, so tapping it opens the goal full screen
            content.userInfo = ["text": card.text, "image": card.image ?? ""]
            try? await center.add(UNNotificationRequest(identifier: winbackID, content: content, trigger: trigger(for: fire)))
        }
        // Turned off while the adds were in flight
        if !isEnabled { center.removePendingNotificationRequests(withIdentifiers: [weeklyID, winbackID]) }
    }

    static func weeklyBody(items: [BoardItem], on date: Date) -> String {
        let achieved = ProgressStats.achievedInMonth(items, containing: date)
        if achieved == 1 { return String(localized: "You achieved 1 goal this month. What's one step for next week?") }
        if achieved > 1 { return String(localized: "You achieved \(achieved) goals this month. What's one step for next week?") }
        let start = Calendar.current.date(byAdding: .day, value: -6, to: date) ?? date
        let days = ProgressLog.daysOpened(from: start, through: date)
        if days == 0 { return String(localized: "Take a minute with your board and pick one step for next week.") }
        if days == 1 { return String(localized: "This week you looked at your board 1 day. What's one step for next week?") }
        return String(localized: "This week you looked at your board \(days) days. What's one step for next week?")
    }

    private static func nextSunday(after date: Date, hour: Int, minute: Int) -> Date? {
        // Weekday 1 is Sunday in the Gregorian calendar, whatever day the week starts on
        ProgressLog.gregorian.nextDate(
            after: date,
            matching: DateComponents(hour: hour, minute: minute, weekday: 1),
            matchingPolicy: .nextTime
        )
    }

    private static func trigger(for date: Date) -> UNCalendarNotificationTrigger {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }
}
