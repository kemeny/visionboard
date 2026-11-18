import SwiftUI
import UIKit

// Sends one clipping to friends through the iOS share sheet.
//
// Original: a photo goes as the photo itself. Words go as a picture of the
// clipping on board paper, with the words as text too, so apps that drop the
// picture still get the goal.
//
// Story: a 1080 x 1920 picture of the clipping centered on the board paper,
// with the "Made with VisionBoard" mark for free plans (see StoryShare).
//
// Both carry a link to the web app so messaging apps show a link preview.
enum ClippingShare {
    enum Format: String {
        case original, story
    }

    @MainActor
    static func share(_ item: BoardItem, format: Format = .original) async {
        let mark = format == .story && StoryShare.showsMark
        let prepared: [Any]?
        switch format {
        case .original: prepared = await activityItems(for: item)
        case .story: prepared = await storyItems(for: item, showMark: mark)
        }
        guard var activityItems = prepared else { return }
        activityItems.append(StoryShare.link)

        let properties: [String: Any] = [
            "kind": item.type == .image ? "photo" : "text",
            "format": format.rawValue,
            "has_mark": mark,
        ]
        StoryShare.present(activityItems) {
            Analytics.capture("clipping_shared", properties)
        }
    }

    @MainActor
    static func activityItems(for item: BoardItem) async -> [Any]? {
        switch item.type {
        case .image:
            guard let image = await ImageStore.shared.image(for: item.content) else { return nil }
            return [image]
        case .text:
            var shared: [Any] = []
            if let card = renderCard(item) { shared.append(card) }
            let words = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty && words != placeholderText { shared.append(words) }
            return shared.isEmpty ? nil : shared
        }
    }

    @MainActor
    private static func storyItems(for item: BoardItem, showMark: Bool) async -> [Any]? {
        let photos = await StoryShare.photos(for: [item])
        if item.type == .image && photos[item.content] == nil { return nil }
        let story = ClippingStory(item: item, paper: StoryShare.paper, showMark: showMark)
        guard let image = StoryShare.render(story, photos: photos) else { return nil }
        return [image]
    }

    // The clipping at its board size on a sheet of paper, drawn about 1080 px wide
    @MainActor
    private static func renderCard(_ item: BoardItem) -> UIImage? {
        let size = CGSize(width: max(120, item.width), height: max(60, item.height))
        let margin = max(24, size.width * 0.12)
        let card = ClippingView(item: item)
            .frame(width: size.width, height: size.height)
            .padding(margin)
            .background(PaperColor.moleskine.color)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = min(6, max(2, 1080 / (size.width + margin * 2)))
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// The share actions used in a clipping's menus: the clipping as it is, or
// as a story-sized picture
struct ShareClippingButton: View {
    let item: BoardItem
    @State private var preparing = false

    var body: some View {
        Button("Share", systemImage: "square.and.arrow.up") { share(.original) }
            .disabled(preparing)
        Button("Share as Story", systemImage: "rectangle.portrait") { share(.story) }
            .disabled(preparing)
    }

    private func share(_ format: ClippingShare.Format) {
        guard !preparing else { return }
        preparing = true
        Task {
            await ClippingShare.share(item, format: format)
            preparing = false
        }
    }
}
