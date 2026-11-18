import Foundation
import SwiftUI
import UIKit

// The progress loop: which days this person looked at their board (kept on
// this device only), what got marked "I Did It", and the counts the weekly
// and yearly recaps show.
enum ProgressLog {
    private static let daysKey = "progress-days-opened"
    // A little over two years, so last year's recap still has its days
    private static let keepDays = 800

    // Called each time the app comes to the front
    static func recordOpen(on date: Date = .now) {
        var days = openedDays
        let key = dayKey(date)
        guard !days.contains(key) else { return }
        days.insert(key)
        var sorted = days.sorted()
        if sorted.count > keepDays { sorted.removeFirst(sorted.count - keepDays) }
        UserDefaults.standard.set(sorted, forKey: daysKey)
    }

    static var openedDays: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: daysKey) ?? [])
    }

    static func wasOpened(on date: Date) -> Bool {
        openedDays.contains(dayKey(date))
    }

    // Days opened from `start` through `end`, both included
    static func daysOpened(from start: Date, through end: Date) -> Int {
        let calendar = Calendar.current
        let days = openedDays
        var count = 0
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var guardCount = 0
        while day <= last && guardCount < 400 {
            if days.contains(dayKey(day)) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            guardCount += 1
        }
        return count
    }

    static func daysOpened(inYear year: Int) -> Int {
        let prefix = String(format: "%04ld-", year)
        return openedDays.filter { $0.hasPrefix(prefix) }.count
    }

    // The seven days of this calendar week (in the person's locale), first day first
    static func weekDays(containing date: Date = .now) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // Gregorian year, month and day in the local time zone, so keys stay the
    // same whatever calendar the phone is set to
    static func dayKey(_ date: Date) -> String {
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

// Counts over every board on this device. The board on screen comes from the
// store (it may have unsaved-to-disk changes); the others are read from disk.
enum ProgressStats {
    @MainActor
    static func allItems(store: BoardStore, library: BoardLibrary) -> [BoardItem] {
        var items = store.items
        for board in library.boards where board.id != store.boardID {
            guard
                let data = try? Data(contentsOf: BoardLibrary.fileURL(for: board.id)),
                let file = try? JSONDecoder().decode(BoardFile.self, from: data)
            else { continue }
            items += file.items
        }
        return items
    }

    static func achieved(_ items: [BoardItem], from start: Date, to end: Date) -> Int {
        items.filter { item in
            guard let date = item.achievedDate else { return false }
            return date >= start && date < end
        }.count
    }

    static func achievedInMonth(_ items: [BoardItem], containing date: Date) -> Int {
        guard let month = Calendar.current.dateInterval(of: .month, for: date) else { return 0 }
        return achieved(items, from: month.start, to: month.end)
    }

    static func achievedInWeek(_ items: [BoardItem], containing date: Date) -> Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return achieved(items, from: week.start, to: week.end)
    }

    static func achievedInYear(_ items: [BoardItem], _ year: Int) -> Int {
        items.filter { item in
            guard let date = item.achievedDate else { return false }
            return ProgressLog.gregorian.component(.year, from: date) == year
        }.count
    }

    static func photosAdded(_ items: [BoardItem], inYear year: Int) -> Int {
        items.filter { item in
            guard item.type == .image, let created = item.createdDate else { return false }
            return ProgressLog.gregorian.component(.year, from: created) == year
        }.count
    }
}

// "Your Year": shown from December 15 to January 15, about the year that is
// ending (or just ended)
enum YearRecap {
    static func year(on date: Date = .now) -> Int? {
        let calendar = ProgressLog.gregorian
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12 && day >= 15 { return year }
        if month == 1 && day <= 15 { return year - 1 }
        return nil
    }
}

// A short, gentle "well done": one success tap, no confetti
enum Celebrate {
    @MainActor
    static func toggleAchieved(_ item: BoardItem, in store: BoardStore) {
        let achieving = !item.isAchieved
        withAnimation(.spring(duration: 0.45, bounce: 0.45)) {
            _ = store.setAchieved(item.id, achieving)
        }
        if achieving {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// The seal a done clipping wears on the board and in the feed
struct AchievedSeal: View {
    var size: CGFloat = 22
    @State private var appeared = false

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.green)
            .background(Circle().fill(Color.white).padding(size * 0.12))
            .shadow(color: .black.opacity(0.2), radius: size * 0.15, y: size * 0.05)
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.5)) { appeared = true }
            }
            .accessibilityLabel("Done")
    }
}
