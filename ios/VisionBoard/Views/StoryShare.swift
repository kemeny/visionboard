import SwiftUI
import UIKit

// Story images for Instagram, WhatsApp status and the like: a 1080 x 1920
// picture on board paper with a small "Made with VisionBoard" mark at the
// bottom. Pro removes the mark. Every share also carries a link to the web
// app, so messaging apps show a link preview.
enum StoryShare {
    // Laid out at 360 x 640 points and drawn at 3x, so the image is exactly 1080 x 1920 pixels
    static let canvas = CGSize(width: 360, height: 640)
    static let scale: CGFloat = 3

    static let link = URL(string: "https://visionboard.kemenystudio.com/?ref=share")!

    // Free plans carry the mark; Pro is the way to remove it
    @MainActor
    static var showsMark: Bool { !ProAccess.shared.isPro }

    // The paper picked in the board menu (BoardView keeps it in @AppStorage)
    static var paper: PaperColor {
        PaperColor(rawValue: UserDefaults.standard.string(forKey: "canvas-paper") ?? "") ?? .moleskine
    }

    // ImageRenderer draws in one pass, so photos are loaded first and handed
    // to BoardImage through the environment
    @MainActor
    static func photos(for items: [BoardItem]) async -> [String: UIImage] {
        var photos: [String: UIImage] = [:]
        let needed = Set(items.filter { $0.type == .image }.map(\.content))
        for content in needed {
            photos[content] = await ImageStore.shared.image(for: content)
        }
        return photos
    }

    // Draws a story-sized view into a 1080 x 1920 image (scale 1, so the
    // pixel size is the point size wherever the image goes)
    @MainActor
    static func render<Content: View>(_ content: Content, photos: [String: UIImage]) -> UIImage? {
        let framed = content
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.preloadedImages, photos)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: framed)
        renderer.proposedSize = ProposedViewSize(canvas)
        renderer.scale = scale
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    // Shows the system share sheet from the top-most screen. `onShared` runs
    // only when the person finished sharing, not when they cancelled.
    @MainActor
    static func present(_ activityItems: [Any], onShared: @escaping () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }

        let sheet = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            if completed { onShared() }
        }
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
        }
        top.present(sheet, animated: true)
    }
}

// The small mark at the bottom of a story
struct StoryMark: View {
    var body: some View {
        VStack(spacing: 2) {
            Text("Made with VisionBoard")
                .font(.system(size: 12, weight: .semibold))
            Text(verbatim: "visionboard.kemenystudio.com")
                .font(.system(size: 10))
        }
        .foregroundStyle(Color.black.opacity(0.5))
        .padding(.bottom, 34)
        .accessibilityElement(children: .combine)
    }
}

// One clipping, centered on board paper
struct ClippingStory: View {
    let item: BoardItem
    let paper: PaperColor
    let showMark: Bool

    var body: some View {
        let width = max(60, CGFloat(item.width))
        let height = max(40, CGFloat(item.height))
        let box = CGSize(width: StoryShare.canvas.width - 70, height: StoryShare.canvas.height - 200)
        let fit = min(3, min(box.width / width, box.height / height))
        ZStack {
            paper.color
            ClippingView(item: item)
                .frame(width: width, height: height)
                .scaleEffect(fit)
                .frame(width: width * fit, height: height * fit)
                .offset(y: showMark ? -16 : 0)
        }
        .frame(width: StoryShare.canvas.width, height: StoryShare.canvas.height)
        .overlay(alignment: .bottom) {
            if showMark { StoryMark() }
        }
    }
}

// Every clipping of the board, fitted into the story frame
struct BoardStory: View {
    let items: [BoardItem]
    let paper: PaperColor
    let showMark: Bool

    var body: some View {
        let size = StoryShare.canvas
        let top: CGFloat = 48
        let bottom: CGFloat = showMark ? 96 : 48
        let area = CGSize(width: size.width, height: size.height - top - bottom)
        let camera = CanvasCamera.fitting(items, in: area)
        ZStack(alignment: .topLeading) {
            paper.color
            ZStack(alignment: .topLeading) {
                ForEach(items) { item in
                    ClippingView(item: item)
                        .frame(width: CGFloat(item.width), height: CGFloat(item.height))
                        .rotationEffect(.degrees(item.rotation ?? 0))
                        .offset(x: CGFloat(item.x), y: CGFloat(item.y))
                }
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .scaleEffect(camera.zoom, anchor: .topLeading)
            .offset(x: camera.offset.width, y: top + camera.offset.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .bottom) {
            if showMark { StoryMark() }
        }
    }
}

// Board menu > Share Board
enum BoardShare {
    @MainActor
    static func share(_ items: [BoardItem], paper: PaperColor) async {
        guard !items.isEmpty else { return }
        let mark = StoryShare.showsMark
        let photos = await StoryShare.photos(for: items)
        guard let image = StoryShare.render(BoardStory(items: items, paper: paper, showMark: mark), photos: photos) else { return }
        let properties: [String: Any] = ["format": "story", "has_mark": mark, "board_item_count": items.count]
        StoryShare.present([image, StoryShare.link]) {
            Analytics.capture("board_shared", properties)
        }
    }
}
