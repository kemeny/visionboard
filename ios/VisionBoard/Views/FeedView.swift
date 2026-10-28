import SwiftUI

// A full-screen, endless feed of the board's clippings, one per page.
// Double-tap to like; likes sync with the board.
struct FeedView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Filter: String, CaseIterable, Identifiable {
        case forYou = "For You", liked = "Liked"
        var id: String { rawValue }
    }

    private struct Page: Identifiable, Hashable {
        let id: Int
        let itemID: String
    }

    @State private var filter: Filter = .forYou
    @State private var pages: [Page] = []
    @State private var position: Int?
    @State private var stats: [String: Feed.Stats] = [:]
    @State private var shownAt = Date()
    @State private var burst: Int?

    // Under this, a glance doesn't count as a view
    private static let minViewSeconds = 0.6

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    ContentUnavailableView(
                        filter == .liked ? "No Likes Yet" : "Nothing to Show",
                        systemImage: filter == .liked ? "heart" : "rectangle.stack",
                        description: Text(filter == .liked ? "Double-tap anything in For You to keep it here." : "Add photos and goals to your board first.")
                    )
                } else {
                    feed
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Feed", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: filter) { rebuild() }
        .onDisappear { logView(position) }
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(pages) { page in
                    if let item = store.item(page.itemID) {
                        card(item, page: page.id)
                            .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .onChange(of: position) { old, new in
            logView(old)
            shownAt = Date()
            // Endless: queue another round before the end comes into view
            if let new, new >= pages.count - 3 {
                appendRound(avoid: pages.suffix(3).map(\.itemID))
            }
        }
    }

    private func card(_ item: BoardItem, page: Int) -> some View {
        ZStack {
            switch item.type {
            case .image:
                BoardImage(content: item.content, mode: .fit)
            case .text:
                // Words without their own background sit on a sheet of board paper
                ClippingView(item: item)
                    .frame(minHeight: 220)
                    .background(
                        Color(css: item.bgColor) == nil ? PaperColor.moleskine.color : .clear,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .padding(32)
                    .frame(maxWidth: 560)
            }
            if burst == page {
                Image(systemName: "heart.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(.white)
                    .shadow(radius: 12)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { like(item, page: page) }
        .overlay(alignment: .bottomTrailing) {
            Button {
                store.toggleLike(item.id)
            } label: {
                Label(item.isLiked ? "Unlike" : "Like", systemImage: item.isLiked ? "heart.fill" : "heart")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .foregroundStyle(item.isLiked ? .red : .white)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: item.isLiked)
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.type == .text ? item.content : "Photo from your board")
        .accessibilityAction(named: item.isLiked ? "Unlike" : "Like") { store.toggleLike(item.id) }
    }

    private func like(_ item: BoardItem, page: Int) {
        if !item.isLiked { store.toggleLike(item.id) }
        withAnimation(.spring(duration: 0.3)) { burst = page }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation { if burst == page { burst = nil } }
        }
    }

    private func rebuild() {
        stats = Feed.loadStats()
        pages = []
        appendRound(avoid: [])
        position = pages.first?.id
        shownAt = Date()
    }

    private func appendRound(avoid: [String]) {
        let round = Feed.round(store.items, stats: stats, avoid: avoid, likedOnly: filter == .liked)
        let start = (pages.last?.id ?? -1) + 1
        pages += round.enumerated().map { Page(id: start + $0.offset, itemID: $0.element.id) }
    }

    private func logView(_ index: Int?) {
        guard let index, let page = pages.first(where: { $0.id == index }) else { return }
        let dwell = Date().timeIntervalSince(shownAt)
        guard dwell >= Self.minViewSeconds else { return }
        Feed.recordView(&stats, id: page.itemID, dwellMs: min(dwell, 60) * 1000)
        Feed.saveStats(stats)
    }
}
