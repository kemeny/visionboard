import Foundation

// Port of lib/feed.ts: an Instagram-style "for you" order over the board's
// clippings. Likes live on the items (so they sync); views and dwell time are
// per-device signals kept in UserDefaults.
enum Feed {
    struct Stats: Codable {
        var views: Int
        var dwellMs: Double
        var lastSeen: Double
    }

    private static let statsKey = "feed-stats"
    private static let hourMs = 60.0 * 60 * 1000

    static func loadStats() -> [String: Stats] {
        guard let data = UserDefaults.standard.data(forKey: statsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Stats].self, from: data)) ?? [:]
    }

    static func saveStats(_ stats: [String: Stats]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(stats), forKey: statsKey)
    }

    static func recordView(_ stats: inout [String: Stats], id: String, dwellMs: Double, now: Double = nowMs()) {
        let prev = stats[id] ?? Stats(views: 0, dwellMs: 0, lastSeen: 0)
        stats[id] = Stats(views: prev.views + 1, dwellMs: prev.dwellMs + dwellMs, lastSeen: now)
    }

    static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    static func isFeedItem(_ item: BoardItem) -> Bool {
        switch item.type {
        case .image: !item.content.isEmpty
        case .text: !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.content != placeholderText
        }
    }

    // Higher is shown sooner. Gentle weights plus jitter keep each load different.
    static func score(_ item: BoardItem, _ stats: Stats?, now: Double) -> Double {
        var score = 1.0
        if item.isLiked { score += 0.9 }
        if let stats {
            let avgDwellSec = stats.dwellMs / Double(max(1, stats.views)) / 1000
            score += 0.4 * min(avgDwellSec / 6, 1)
            score += 0.6 * min((now - stats.lastSeen) / (24 * hourMs), 1)
        } else {
            score += 0.8
        }
        return score + Double.random(in: 0..<0.9)
    }

    // One ranked pass over every clipping, with recently shown ones pushed back
    // and never more than two text cards in a row when a photo can break them up
    static func round(_ items: [BoardItem], stats: [String: Stats], avoid: [String] = [], likedOnly: Bool = false) -> [BoardItem] {
        let now = nowMs()
        let ranked = items
            .filter { isFeedItem($0) && (!likedOnly || $0.isLiked) }
            .map { ($0, score($0, stats[$0.id], now: now)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        let avoidSet = Set(avoid)
        let fresh = ranked.filter { !avoidSet.contains($0.id) }
        let recent = ranked.filter { avoidSet.contains($0.id) }
        let half = (fresh.count + 1) / 2
        var queue = Array(fresh.prefix(half)) + recent + Array(fresh.dropFirst(half))

        var out: [BoardItem] = []
        while !queue.isEmpty {
            let lastTwoText = out.count >= 2 && out[out.count - 1].type == .text && out[out.count - 2].type == .text
            let index = lastTwoText ? (queue.firstIndex { $0.type == .image } ?? 0) : 0
            out.append(queue.remove(at: index))
        }
        return out
    }
}

// Today's goal and photo, rotating through the board so each day differs.
// Same rotation as the Worker's pickReminder, so web and phone agree.
struct DailyCard: Equatable, Hashable {
    var text: String
    var image: String?

    static func pick(from items: [BoardItem], on date: Date = .now) -> DailyCard {
        let day = Int(floor(date.timeIntervalSince1970 / 86_400))
        let texts = items
            .filter { $0.type == .text && Feed.isFeedItem($0) }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        let images = items
            .filter { $0.type == .image && (ImageStore.isCloud($0.content) || ImageStore.isLocal($0.content)) }
            .map(\.content)
        return DailyCard(
            text: texts.isEmpty ? "Take a minute with your vision board today." : texts[day % texts.count],
            image: images.isEmpty ? nil : images[day % images.count]
        )
    }
}
