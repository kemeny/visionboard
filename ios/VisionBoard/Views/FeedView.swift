import SwiftUI

// A full-screen, endless feed of the board's clippings, one per page.
// Double-tap to like; likes sync with the board. Share sends one to friends.
// Press and hold for the action dial: Share, Like, Show on Board, Hide.
struct FeedView: View {
    @Environment(BoardStore.self) private var store
    @Environment(AppRouter.self) private var router
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
    @State private var sharing: String?
    @State private var hidden: Set<String> = []
    // The last clipping hidden, while its Undo shows
    @State private var justHidden: String?

    // Under this, a glance doesn't count as a view
    private static let minViewSeconds = 0.6

    var body: some View {
        NavigationStack {
            Group {
                if visiblePages.isEmpty {
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
                if !hidden.isEmpty && filter == .forYou {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("More", systemImage: "ellipsis") {
                            Button("Show Hidden Clippings", systemImage: "eye") { unhideAll() }
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if justHidden != nil { undoHideBar }
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: filter) { rebuild() }
        .onDisappear { logView(position) }
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(visiblePages) { page in
                    if let item = store.item(page.itemID) {
                        card(item, page: page.id)
                            .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollDisabled(ActionDial.shared.isShown)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .onChange(of: position) { old, new in
            logView(old)
            shownAt = Date()
            // Endless: queue another round before the end comes into view
            if let new, new >= (pages.last?.id ?? 0) - 3 {
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
        .gesture(DialPress { dialActions(itemID: item.id, page: page) })
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 18) {
                Button {
                    share(item)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .foregroundStyle(.white)
                        .opacity(sharing == item.id ? 0.4 : 1)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(sharing != nil)
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
            }
            .shadow(color: .black.opacity(0.35), radius: 6)
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.type == .text ? item.content : "Photo from your board")
        .accessibilityAction(named: item.isLiked ? "Unlike" : "Like") { store.toggleLike(item.id) }
        .accessibilityAction(named: "Share") { share(item) }
    }

    private var visiblePages: [Page] {
        filter == .liked ? pages : pages.filter { !hidden.contains($0.itemID) }
    }

    private func dialActions(itemID: String, page: Int) -> [DialAction]? {
        guard let item = store.item(itemID) else { return nil }
        var actions = [
            DialAction(id: "share", title: String(localized: "Share"), symbol: "square.and.arrow.up") { share(item) },
            DialAction(
                id: "like",
                title: item.isLiked ? String(localized: "Unlike") : String(localized: "Like"),
                symbol: item.isLiked ? "heart.slash" : "heart",
                tint: .red
            ) {
                if item.isLiked { store.toggleLike(item.id) } else { like(item, page: page) }
            },
            DialAction(id: "board", title: String(localized: "Show on Board"), symbol: "square.on.square") {
                router.focusItem = item.id
                router.tab = .board
            },
        ]
        if filter == .forYou {
            actions.append(DialAction(id: "hide", title: String(localized: "Hide from Feed"), symbol: "eye.slash") { hide(item.id) })
        }
        return actions
    }

    private var undoHideBar: some View {
        HStack(spacing: 14) {
            Text("Hidden from Feed")
            Button("Undo") { undoHide() }
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(white: 0.18), in: Capsule())
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task(id: justHidden) {
            // A newer hide restarts the clock
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            withAnimation { justHidden = nil }
        }
    }

    private func hide(_ id: String) {
        withAnimation(.snappy) {
            hidden.insert(id)
            justHidden = id
        }
        Feed.saveHidden(hidden)
        // The next clipping slides in; if that was the last one, start a new round
        if visiblePages.isEmpty { appendRound(avoid: []) }
    }

    private func undoHide() {
        guard let id = justHidden else { return }
        withAnimation(.snappy) {
            hidden.remove(id)
            justHidden = nil
        }
        Feed.saveHidden(hidden)
    }

    private func unhideAll() {
        hidden = []
        justHidden = nil
        Feed.saveHidden(hidden)
        rebuild()
    }

    private func share(_ item: BoardItem) {
        guard sharing == nil else { return }
        sharing = item.id
        Task {
            await ClippingShare.share(item)
            sharing = nil
        }
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
        hidden = Feed.loadHidden()
        pages = []
        appendRound(avoid: [])
        position = visiblePages.first?.id
        shownAt = Date()
    }

    private func appendRound(avoid: [String]) {
        let round = Feed.round(store.items, stats: stats, avoid: avoid, likedOnly: filter == .liked, hidden: hidden)
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
