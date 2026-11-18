import SwiftUI

// "Create with AI": a few sentences about the year someone wants become goals
// with photos. Claude writes the goals, Unsplash finds the photos (worker/src/ai.ts).
// They pick what to keep, then the clippings are laid out on the board.
struct AIBoardView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    // Middle of the visible board, used when the board is still empty
    let center: CGPoint
    var source: String = "board_menu"
    var onAdded: ([BoardItem]) -> Void = { _ in }

    private enum Phase: Equatable {
        case writing, generating, preview, adding
    }

    @State private var prompt = ""
    @State private var phase: Phase = .writing
    @State private var suggestions: [AIBoardAPI.Suggestion] = []
    @State private var removed: Set<Int> = []
    @State private var errorMessage: String?
    @State private var loggedStart = false
    @FocusState private var editorFocused: Bool

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var keptCount: Int {
        suggestions.filter { !removed.contains($0.id) }.count
    }

    private var examples: [String] {
        [
            String(localized: "I want to run a half marathon, cook more at home and take my mom to Japan."),
            String(localized: "This is the year I launch my own business and save for a house."),
            String(localized: "More calm, less phone. Read 20 books, sleep well, see friends every week."),
        ]
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .writing, .generating:
                    writing
                case .preview, .adding:
                    preview
                }
            }
            .navigationTitle("Create with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .disabled(phase == .adding)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .interactiveDismissDisabled(phase == .generating || phase == .adding)
        .onAppear {
            guard !loggedStart else { return }
            loggedStart = true
            Analytics.capture("ai_board_started", ["source": source])
        }
    }

    // MARK: Writing

    private var writing: some View {
        Form {
            Section {
                TextEditor(text: $prompt)
                    .focused($editorFocused)
                    .frame(minHeight: 160)
                    .disabled(phase == .generating)
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Health, work, travel, people, money. Anything that matters to you.")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Tell me about the year you want")
            } footer: {
                Text("\(prompt.count) of \(AIBoardAPI.maxPromptLength)")
            }

            Section("Need Ideas?") {
                ForEach(examples, id: \.self) { example in
                    Button {
                        prompt = example
                    } label: {
                        Text(example)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .disabled(phase == .generating)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .onChange(of: prompt) { _, value in
            if value.count > AIBoardAPI.maxPromptLength {
                prompt = String(value.prefix(AIBoardAPI.maxPromptLength))
            }
        }
    }

    // MARK: Preview

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap anything that doesn't feel like you to leave it out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(suggestions) { suggestion in
                        SuggestionCard(suggestion: suggestion, kept: !removed.contains(suggestion.id)) {
                            toggle(suggestion.id)
                        }
                    }
                }
                Text("Photos from Unsplash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .disabled(phase == .adding)
    }

    private func toggle(_ id: Int) {
        if removed.contains(id) {
            removed.remove(id)
        } else {
            removed.insert(id)
        }
    }

    // MARK: Actions

    private var bottomBar: some View {
        VStack(spacing: 8) {
            switch phase {
            case .writing, .generating:
                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: 8) {
                        if phase == .generating {
                            ProgressView().tint(.white)
                            Text("Making your board…")
                        } else {
                            Label("Generate", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedPrompt.isEmpty || phase == .generating)
            case .preview, .adding:
                Button {
                    Task { await add() }
                } label: {
                    HStack(spacing: 8) {
                        if phase == .adding {
                            ProgressView().tint(.white)
                            Text("Adding…")
                        } else {
                            Label("Add to Board", systemImage: "plus")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(keptCount == 0 || phase == .adding)
                Button("Start Over", systemImage: "arrow.counterclockwise") {
                    suggestions = []
                    removed = []
                    phase = .writing
                }
                .disabled(phase == .adding)
            }
        }
        .padding()
        .background(.bar)
    }

    private func generate() async {
        let text = trimmedPrompt
        guard !text.isEmpty, phase == .writing else { return }
        editorFocused = false
        errorMessage = nil
        phase = .generating
        let started = Date()
        do {
            let result = try await AIBoardAPI.generate(prompt: text)
            suggestions = result
            removed = []
            phase = .preview
            Analytics.capture("ai_board_generated", [
                "count": result.count,
                "latency_ms": Int(Date().timeIntervalSince(started) * 1000),
            ])
        } catch {
            let reason = (error as? AIBoardAPI.Failure)?.reason ?? "unknown"
            Analytics.capture("ai_board_failed", ["reason": reason])
            errorMessage = Self.message(for: reason)
            phase = .writing
        }
    }

    private func add() async {
        let kept = suggestions.filter { !removed.contains($0.id) }
        guard !kept.isEmpty, phase == .preview else { return }
        phase = .adding

        let photos = await Self.downloadPhotos(kept)
        let pieces = kept.map { suggestion -> AIBoardLayout.Piece in
            if let photo = photos[suggestion.id] {
                return AIBoardLayout.Piece(text: suggestion.text, image: photo.content, aspect: photo.aspect, credit: suggestion.credit)
            }
            return AIBoardLayout.Piece(text: suggestion.text, image: nil, aspect: 1, credit: nil)
        }
        let added = store.addItems(AIBoardLayout.items(for: pieces, existing: store.items, center: center))

        // Unsplash counts a download for each photo that made it onto the board
        for suggestion in kept where photos[suggestion.id] != nil {
            if let url = suggestion.downloadURL {
                Task { await AIBoardAPI.reportDownload(url) }
            }
        }

        let wanted = kept.filter { $0.imageURL != nil }.count
        if photos.count < wanted {
            Analytics.capture("ai_board_failed", ["reason": "photo_download", "missing": wanted - photos.count])
        }
        Analytics.capture("ai_board_added", ["kept": kept.count, "removed": suggestions.count - kept.count, "photos": photos.count])
        onAdded(added)
        dismiss()
    }

    private struct Downloaded: Sendable {
        let id: Int
        let content: String
        let aspect: Double
    }

    // Fetches the kept photos in parallel and stores them like any picked photo
    private static func downloadPhotos(_ suggestions: [AIBoardAPI.Suggestion]) async -> [Int: Downloaded] {
        let jobs: [(id: Int, url: URL)] = suggestions.compactMap { suggestion -> (id: Int, url: URL)? in
            guard let url = suggestion.imageURL else { return nil }
            return (suggestion.id, url)
        }
        return await withTaskGroup(of: Downloaded?.self, returning: [Int: Downloaded].self) { group in
            for job in jobs {
                let id = job.id
                let url = job.url
                group.addTask {
                    guard let pair = try? await URLSession.shared.data(from: url),
                          (pair.1 as? HTTPURLResponse)?.statusCode == 200,
                          let imported = try? await ImageStore.shared.importPhoto(pair.0)
                    else { return nil }
                    return Downloaded(id: id, content: imported.content, aspect: imported.aspect)
                }
            }
            var result: [Int: Downloaded] = [:]
            for await entry in group {
                if let entry { result[entry.id] = entry }
            }
            return result
        }
    }

    private static func message(for reason: String) -> String {
        switch reason {
        case "rate_limited":
            String(localized: "You've made a lot of boards this hour. Try again a bit later.")
        case "ai_unavailable", "not_configured":
            String(localized: "Create with AI isn't available right now.")
        case "network":
            String(localized: "Couldn't connect. Check your connection and try again.")
        case "refused", "invalid_prompt":
            String(localized: "Couldn't make a board from that. Try describing your year another way.")
        default:
            String(localized: "Something went wrong. Try again.")
        }
    }
}

private struct SuggestionCard: View {
    let suggestion: AIBoardAPI.Suggestion
    let kept: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 0) {
                photo
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let name = suggestion.photographer, !name.isEmpty {
                        Text("Photo by \(name)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(10)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, kept ? Color.accentColor : Color.black.opacity(0.35))
                    .padding(8)
            }
            .opacity(kept ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(suggestion.text)
        .accessibilityValue(kept ? Text("Kept") : Text("Left out"))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to keep or leave out")
    }

    @ViewBuilder
    private var photo: some View {
        if let url = suggestion.imageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "textformat")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// Places the new clippings as a loose three-column collage: each photo with
// its goal overlapping the bottom edge like a cut-out label. On an empty board
// the collage is centered on screen; otherwise it goes below what's there.
enum AIBoardLayout {
    struct Piece {
        var text: String
        var image: String?
        var aspect: Double
        var credit: BoardItem.Credit?
    }

    private static let columns = 3
    private static let columnWidth = 260.0
    private static let gap = 48.0
    private static let maxPhotoHeight = 360.0

    static func items(for pieces: [Piece], existing: [BoardItem], center: CGPoint) -> [BoardItem] {
        let blockWidth = Double(columns) * columnWidth + Double(columns - 1) * gap
        let originX: Double
        let originY: Double
        if existing.isEmpty {
            originX = Double(center.x) - blockWidth / 2
            originY = Double(center.y) - 320
        } else {
            let minX = existing.map(\.x).min() ?? 0
            let maxX = existing.map { $0.x + $0.width }.max() ?? 0
            let maxY = existing.map { $0.y + $0.height }.max() ?? 0
            originX = (minX + maxX) / 2 - blockWidth / 2
            originY = maxY + 120
        }

        // Readable on top of a photo: only looks with a solid background
        let solid = TextLook.all.filter { $0.background != "transparent" }
        let looks = solid.isEmpty ? TextLook.all : solid
        let lookOffset = Int.random(in: 0..<looks.count)

        // The middle column starts lower so the rows don't line up like a table
        var heights = Array(repeating: 0.0, count: columns)
        heights[1] = 70

        var result: [BoardItem] = []
        for (index, piece) in pieces.enumerated() {
            var column = 0
            for candidate in heights.indices where heights[candidate] < heights[column] {
                column = candidate
            }
            let columnX = originX + Double(column) * (columnWidth + gap)
            let top = originY + heights[column]
            let tilt: Double = index.isMultiple(of: 2) ? -1 : 1
            let look = looks[(index + lookOffset) % looks.count]
            var bottom = top

            var textX = columnX
            var textY = top
            var textWidth = columnWidth

            if let image = piece.image {
                let aspect = max(piece.aspect, 0.1)
                var width = columnWidth
                var height = width / aspect
                if height > maxPhotoHeight {
                    height = maxPhotoHeight
                    width = height * aspect
                }
                width = width.rounded()
                height = height.rounded()
                result.append(BoardItem(
                    id: BoardItem.newID(), type: .image,
                    x: columnX + (columnWidth - width) / 2, y: top, width: width, height: height,
                    content: image, zIndex: 0,
                    rotation: tilt * halfDegrees(in: 1...3),
                    credit: piece.credit
                ))
                textX = columnX + 10
                textWidth = columnWidth - 20
                textY = top + height
                bottom = top + height
            }

            let size = fontSize(for: piece.text)
            let textHeight = estimatedHeight(piece.text, size: size, style: look.font, width: textWidth)
            if piece.image != nil {
                // Overlap the photo's bottom edge
                textY -= (textHeight * 0.55).rounded()
            }
            result.append(BoardItem(
                id: BoardItem.newID(), type: .text,
                x: textX, y: textY, width: textWidth, height: textHeight,
                content: piece.text, zIndex: 0,
                fontStyle: look.font.rawValue, fontSize: size, color: look.color, bgColor: look.background,
                rotation: -tilt * halfDegrees(in: 1...3)
            ))
            bottom = max(bottom, textY + textHeight)
            heights[column] = bottom - originY + gap
        }
        return result
    }

    // Sizes from the inspector's list, so the Size picker shows the right one
    private static func fontSize(for text: String) -> Double {
        switch text.count {
        case ..<14: 32
        case ..<30: 24
        default: 18
        }
    }

    private static func estimatedHeight(_ text: String, size: Double, style: TextStyle, width: Double) -> Double {
        let charWidth = size * (style.uppercased ? 0.68 : 0.56)
        let perLine = max(4, Int((width - 32) / charWidth))
        let lines = max(1, (text.count + perLine - 1) / perLine)
        return (Double(lines) * size * Double(style.lineHeight) + 32).rounded()
    }

    private static func halfDegrees(in range: ClosedRange<Double>) -> Double {
        (Double.random(in: range) * 2).rounded() / 2
    }
}
