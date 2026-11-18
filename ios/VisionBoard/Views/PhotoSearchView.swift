import SwiftUI

// Search Photos in the board's add menu: free Unsplash photos, picked in a
// grid and added together. Like Create with AI, the clipping keeps the
// images.unsplash.com address (hotlinked, never copied to our storage) and the
// photographer's credit, and each added photo is reported to Unsplash.
struct PhotoSearchView: View {
    let center: CGPoint
    var onAdded: ([BoardItem]) -> Void

    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var searched = ""
    @State private var photos: [AIBoardAPI.Photo] = []
    @State private var picked: [String] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    private static let ideas: [LocalizedStringResource] = [
        "beach house", "running", "Japan", "healthy food", "home office", "mountains",
    ]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    if searched.isEmpty && !loading {
                        ideasView
                    } else if photos.isEmpty && !loading && errorMessage == nil {
                        ContentUnavailableView.search(text: searched)
                    }
                    grid
                    if hasMore {
                        Button {
                            Task { await run(searched, page: page + 1) }
                        } label: {
                            if loading { ProgressView() } else { Text("Show More") }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(loading)
                    }
                    if !photos.isEmpty {
                        Link(destination: URL(string: "https://unsplash.com/?utm_source=visionboard&utm_medium=referral")!) {
                            Text("Photos from Unsplash")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .overlay {
                if loading && photos.isEmpty { ProgressView() }
            }
            .navigationTitle("Search Photos")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Beach house, marathon, Tokyo…"))
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { Task { await run(query) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(picked.isEmpty ? String(localized: "Add") : String(localized: "Add \(picked.count)")) { add() }
                        .disabled(picked.isEmpty)
                }
            }
            .onAppear { searchFocused = true }
        }
    }

    private var ideasView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Free photos from Unsplash. Try one of these:")
                .font(.callout)
                .foregroundStyle(.secondary)
            FlowRow(spacing: 8) {
                ForEach(Self.ideas.indices, id: \.self) { index in
                    let idea = String(localized: Self.ideas[index])
                    Button(idea) {
                        query = idea
                        Task { await run(idea) }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            Text("Your search words are sent to Unsplash to find photos.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(photos) { photo in
                let order = picked.firstIndex(of: photo.id)
                Button {
                    toggle(photo)
                } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            AsyncImage(url: URL(string: photo.thumbUrl)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            if let order {
                                Text("\(order + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.accentColor))
                                    .padding(6)
                            }
                        }
                        .overlay {
                            if order != nil {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(photo.alt ?? String(localized: "Photo"))
                .accessibilityValue(photo.credit.map { String(localized: "Photo by \($0.name) on Unsplash") } ?? "")
                .accessibilityAddTraits(order != nil ? .isSelected : [])
                .contextMenu {
                    if let credit = photo.credit {
                        Text("Photo by \(credit.name) on Unsplash")
                        if let link = credit.url, let url = URL(string: link), url.host?.hasSuffix("unsplash.com") == true {
                            Button("View on Unsplash", systemImage: "arrow.up.right.square") { openURL(url) }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ photo: AIBoardAPI.Photo) {
        if let index = picked.firstIndex(of: photo.id) {
            picked.remove(at: index)
        } else {
            picked.append(photo.id)
        }
    }

    private func run(_ words: String, page nextPage: Int = 1) async {
        let text = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil
        if nextPage == 1 {
            photos = []
            picked = []
            hasMore = false
        }
        defer { loading = false }
        do {
            let result = try await AIBoardAPI.searchPhotos(text, page: nextPage)
            let known = Set(photos.map(\.id))
            photos += result.photos.filter { !known.contains($0.id) }
            hasMore = result.hasMore
            page = nextPage
            searched = text
            if nextPage == 1 { Analytics.capture("photo_searched", ["results": result.photos.count]) }
        } catch {
            let reason = (error as? AIBoardAPI.Failure)?.reason ?? "unknown"
            Analytics.capture("photo_search_failed", ["reason": reason])
            searched = text
            errorMessage = Self.message(for: reason)
        }
    }

    private func add() {
        let chosen = picked.compactMap { id in photos.first { $0.id == id } }
        guard !chosen.isEmpty else { return }
        let width = 300.0
        let newItems = chosen.enumerated().map { index, photo in
            let height = (width / max(photo.aspect, 0.1)).rounded()
            let offset = Double(index) * 30
            return BoardItem(
                id: BoardItem.newID(), type: .image,
                x: center.x - width / 2 + offset, y: center.y - height / 2 + offset, width: width, height: height,
                content: photo.imageUrl, zIndex: 0, rotation: 0,
                credit: photo.credit
            )
        }
        let added = store.addItems(newItems)
        for _ in added {
            Analytics.capture("item_added", ["source": "photo_search", "board_item_count": store.items.count])
        }
        for photo in chosen {
            if let url = photo.unsplashDownloadUrl {
                Task { await AIBoardAPI.reportDownload(url) }
            }
        }
        onAdded(added)
        dismiss()
    }

    private static func message(for reason: String) -> String {
        switch reason {
        case "rate_limited":
            String(localized: "You've searched a lot this hour. Try again a bit later.")
        case "ai_unavailable", "not_configured":
            String(localized: "Photo search isn't available right now.")
        default:
            String(localized: "Couldn't search right now. Check your connection and try again.")
        }
    }
}

// Lays the idea chips out in rows that wrap
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
