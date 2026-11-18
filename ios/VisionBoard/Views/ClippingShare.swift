import SwiftUI
import UIKit

// Sends one clipping to friends through the iOS share sheet. A photo goes as
// the photo itself. Words go as a picture of the clipping on board paper, with
// the words as text too, so apps that drop the picture still get the goal.
enum ClippingShare {
    @MainActor
    static func share(_ item: BoardItem) async {
        guard let activityItems = await activityItems(for: item) else { return }
        present(activityItems, kind: item.type == .image ? "photo" : "text")
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

    @MainActor
    private static func present(_ activityItems: [Any], kind: String) {
        presentSheet(activityItems) {
            Analytics.capture("clipping_shared", ["kind": kind])
        }
    }

    // The system share sheet over whatever is on screen. onCompleted runs
    // only when something was actually sent or saved.
    @MainActor
    static func presentSheet(_ activityItems: [Any], onCompleted: @escaping () -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }

        let sheet = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            if completed { onCompleted() }
        }
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
        }
        top.present(sheet, animated: true)
    }
}

// The share button used on the Feed and on a selected clipping
struct ShareClippingButton: View {
    let item: BoardItem
    @State private var preparing = false

    var body: some View {
        Button("Share", systemImage: "square.and.arrow.up") {
            guard !preparing else { return }
            preparing = true
            Task {
                await ClippingShare.share(item)
                preparing = false
            }
        }
        .disabled(preparing)
    }
}
