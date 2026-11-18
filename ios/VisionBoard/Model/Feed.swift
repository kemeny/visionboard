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
    // A done clipping is kept in about 3 feed rounds in 10
    static let achievedWeight = 0.3

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

    // Clippings hidden from For You with the long-press dial. Per device, like
    // the view stats: hiding is about this feed, not about the board.
    private static let hiddenKey = "feed-hidden"

    static func loadHidden() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
    }

    static func saveHidden(_ hidden: Set<String>) {
        UserDefaults.standard.set(Array(hidden).sorted(), forKey: hiddenKey)
    }

    static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

    static func isFeedItem(_ item: BoardItem) -> Bool {
        switch item.type {
        case .image: !item.content.isEmpty
        case .text: !item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPlaceholderText(item.content)
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
    // Liked shows every liked clipping, hidden or not.
    static func round(_ items: [BoardItem], stats: [String: Stats], avoid: [String] = [], likedOnly: Bool = false, hidden: Set<String> = []) -> [BoardItem] {
        let now = nowMs()
        let eligible = items.filter { isFeedItem($0) && (likedOnly ? $0.isLiked : !hidden.contains($0.id)) }
        // Done goals still come back, just less often. Liked keeps everything
        // liked, and a board where everything is done still has a feed.
        let thin = !likedOnly && eligible.contains { !$0.isAchieved }
        let pool = thin ? eligible.filter { !$0.isAchieved || Double.random(in: 0..<1) < achievedWeight } : eligible
        let ranked = pool
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
// Same rotation as the Worker's pickReminder, so web and phone agree: goals
// marked done step aside unless every goal is done, and done photos come
// round 3 times in 10.
struct DailyCard: Equatable, Hashable {
    var text: String
    var image: String?

    static func pick(from items: [BoardItem], on date: Date = .now) -> DailyCard {
        // Local calendar day, so the goal turns over at the user's own midnight.
        // Kept non-negative for the modulo below.
        let day = max(0, WidgetSnapshot.dayNumber(date))
        let allTexts = items.filter { $0.type == .text && Feed.isFeedItem($0) }
        let openTexts = allTexts.filter { !$0.isAchieved }
        let texts = (openTexts.isEmpty ? allTexts : openTexts)
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        let imageItems = items.filter {
            $0.type == .image && (ImageStore.isCloud($0.content) || ImageStore.isLocal($0.content) || ImageStore.isUnsplash($0.content))
        }
        let images: [String]
        if imageItems.contains(where: \.isAchieved) {
            // Done photos join rounds 0, 3 and 6 only: 3 in 10.
            var rotation: [String] = []
            for round in 0..<10 {
                let includeDone: Bool = round % 3 == 0 && round < 9
                for item in imageItems where includeDone || !item.isAchieved {
                    rotation.append(item.content)
                }
            }
            images = rotation
        } else {
            images = imageItems.map(\.content)
        }
        return DailyCard(
            text: texts.isEmpty ? String(localized: "Take a minute with your vision board today.") : texts[day % texts.count],
            image: images.isEmpty ? nil : images[day % images.count]
        )
    }
}
