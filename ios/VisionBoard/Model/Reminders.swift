import Foundation
import Observation
import UserNotifications

// Daily reminders as local notifications. Unlike the web app these need no
// server: the next two weeks are scheduled on the device and topped up
// whenever the app opens or the board changes.
@MainActor
@Observable
final class Reminders {
    private static let enabledKey = "reminders-enabled"
    private static let hourKey = "reminders-hour"
    private static let idPrefix = "daily-"
    private static let daysAhead = 14

    var isEnabled = UserDefaults.standard.bool(forKey: Reminders.enabledKey)
    var hour: Int = UserDefaults.standard.object(forKey: Reminders.hourKey) as? Int ?? 8
    var errorMessage: String?

    func enable(hour: Int, items: [BoardItem]) async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                errorMessage = "Notifications are off for VisionBoard. Turn them on in Settings."
                isEnabled = false
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        isEnabled = true
        self.hour = hour
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        UserDefaults.standard.set(hour, forKey: Self.hourKey)
        await reschedule(items: items)
    }

    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        Task { await Self.removePending() }
    }

    func reschedule(items: [BoardItem]) async {
        await Self.removePending()
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<Self.daysAhead {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: now),
                let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                fire > now
            else { continue }
            let card = DailyCard.pick(from: items, on: fire)
            let content = UNMutableNotificationContent()
            content.title = "Your vision board"
            content.body = card.text
            content.sound = .default
            content.userInfo = ["text": card.text, "image": card.image ?? ""]
            // Attachments are moved into the system's store, so hand over a copy.
            // Only the next few days, to keep the copies small.
            if offset < 4, let image = card.image, let attachment = await Self.attachment(for: image) {
                content.attachments = [attachment]
            }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(
                identifier: Self.idPrefix + "\(offset)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func sendTest(items: [BoardItem]) async {
        let card = DailyCard.pick(from: items)
        let content = UNMutableNotificationContent()
        content.title = "Your vision board"
        content.body = card.text
        content.userInfo = ["text": card.text, "image": card.image ?? ""]
        if let image = card.image, let attachment = await Self.attachment(for: image) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func removePending() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func attachment(for content: String) async -> UNNotificationAttachment? {
        guard let source = await ImageStore.shared.fileURL(for: content) else { return nil }
        let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".jpg")
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            return try UNNotificationAttachment(identifier: "image", url: copy)
        } catch {
            return nil
        }
    }
}
