import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers
import UserNotifications

// Daily reminders as local notifications. Unlike the web app these need no
// server: the next two weeks are scheduled on the device and topped up
// whenever the app opens or the board changes.
@MainActor
@Observable
final class Reminders {
    private static let enabledKey = "reminders-enabled"
    private static let hourKey = "reminders-hour"
    private static let minuteKey = "reminders-minute"
    private static let idPrefix = "daily-"
    private static let daysAhead = 14

    // Bumped by every reschedule and by disable(), so a reschedule that is
    // still awaiting stops adding once a newer one started or reminders
    // were turned off
    @ObservationIgnored private var generation = 0

    var isEnabled = UserDefaults.standard.bool(forKey: Reminders.enabledKey)
    var hour: Int = UserDefaults.standard.object(forKey: Reminders.hourKey) as? Int ?? 8
    // Older installs saved only the hour, so they keep firing on the hour
    var minute: Int = UserDefaults.standard.object(forKey: Reminders.minuteKey) as? Int ?? 0
    var errorMessage: String?
    var testMessage: String?

    func enable(hour: Int, minute: Int = 0, items: [BoardItem]) async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                errorMessage = String(localized: "Notifications are off for VisionBoard. Turn them on in Settings.")
                isEnabled = false
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        errorMessage = nil
        if !isEnabled { Analytics.capture("reminders_enabled", ["hour": hour]) }
        isEnabled = true
        self.hour = hour
        self.minute = minute
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        UserDefaults.standard.set(hour, forKey: Self.hourKey)
        UserDefaults.standard.set(minute, forKey: Self.minuteKey)
        await reschedule(items: items)
    }

    func disable() {
        generation += 1
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        Task { await Self.removePending() }
    }

    // Reschedules run one after another, so an older one can never finish
    // its adds after a newer one and leave a stale reminder behind
    @ObservationIgnored private var lastReschedule: Task<Void, Never>?

    func reschedule(items: [BoardItem]) async {
        generation += 1
        let mine = generation
        let previous = lastReschedule
        let task = Task { @MainActor in
            await previous?.value
            await self.run(items: items, mine: mine)
        }
        lastReschedule = task
        await task.value
    }

    private func run(items: [BoardItem], mine: Int) async {
        guard generation == mine else { return }
        await Self.removePending()
        guard isEnabled, generation == mine else { return }
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<Self.daysAhead {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: now),
                let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                fire > now
            else { continue }
            let card = DailyCard.pick(from: items, on: fire)
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Your vision board")
            content.body = card.text
            content.sound = .default
            content.userInfo = ["text": card.text, "image": card.image ?? ""]
            // Attachments are moved into the system's store, so hand over a copy.
            // Only the next few days, to keep the copies small.
            if offset < 4, let image = card.image, let attachment = await Self.attachment(for: image) {
                content.attachments = [attachment]
            }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            // The awaits above can outlast a toggle off or a newer reschedule
            guard isEnabled, generation == mine else { return }
            try? await Self.add(
                content,
                id: Self.idPrefix + "\(offset)",
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            // Turned off while that add was in flight: take everything back out
            if !isEnabled {
                await Self.removePending()
                return
            }
        }
    }

    func sendTest(items: [BoardItem]) async {
        testMessage = nil
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else {
                errorMessage = String(localized: "Notifications are off for VisionBoard. Turn them on in Settings.")
                return
            }
        default:
            errorMessage = String(localized: "Notifications are off for VisionBoard. Turn them on in the Settings app, under Notifications.")
            return
        }
        let card = DailyCard.pick(from: items)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your vision board")
        content.body = card.text
        content.userInfo = ["text": card.text, "image": card.image ?? ""]
        if let image = card.image, let attachment = await Self.attachment(for: image) {
            content.attachments = [attachment]
        }
        do {
            try await Self.add(content, id: "test-\(UUID().uuidString)", trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
            errorMessage = nil
            testMessage = String(localized: "Sent. It arrives in a few seconds.")
        } catch {
            errorMessage = String(localized: "Couldn't send the test: \(error.localizedDescription)")
        }
    }

    // A photo the system can't use would make the whole reminder fail, so
    // fall back to sending it without one
    private static func add(_ content: UNMutableNotificationContent, id: String, trigger: UNNotificationTrigger) async throws {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch where !content.attachments.isEmpty {
            content.attachments = []
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    private static func removePending() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // Photos synced from the web are often WebP, which notifications can't
    // show. Re-encode a small JPEG copy (the system moves the file it's given).
    private static func attachment(for content: String) async -> UNNotificationAttachment? {
        guard let image = await ImageStore.shared.image(for: content, maxPixels: 1200) else { return nil }
        let scale = min(1, 1200 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: size, format: format)
            .jpegData(withCompressionQuality: 0.8) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".jpg")
        do {
            try jpeg.write(to: url)
            return try UNNotificationAttachment(
                identifier: "image",
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.jpeg.identifier]
            )
        } catch {
            return nil
        }
    }
}
