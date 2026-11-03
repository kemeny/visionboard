import Photos
import SwiftUI

// Turns the board into a Lock Screen wallpaper, sized to this iPhone's screen.
// "Whole Board" fits every clipping below the clock; "Today" is today's photo
// full screen with today's goal on it.
struct WallpaperSheet: View {
    let items: [BoardItem]
    let paper: PaperColor

    enum Style: String, CaseIterable, Identifiable {
        case board, today
        var id: String { rawValue }
        var label: String { self == .board ? String(localized: "Whole Board") : String(localized: "Today") }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var style: Style = .board
    @State private var rendered: UIImage?
    @State private var status: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Style", selection: $style) {
                    ForEach(Style.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    if let rendered {
                        Image(uiImage: rendered)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                            .accessibilityLabel("Wallpaper preview")
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxHeight: .infinity)

                if let status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await save() }
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(rendered == nil || saving)
            }
            .padding()
            .navigationTitle("Wallpaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let rendered {
                        let image = Image(uiImage: rendered)
                        ShareLink(item: image, preview: SharePreview("VisionBoard wallpaper", image: image))
                    }
                }
            }
            .task(id: style) {
                rendered = nil
                status = nil
                rendered = await render()
            }
        }
    }

    private var screenSize: CGSize {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        return screen?.bounds.size ?? CGSize(width: 393, height: 852)
    }

    private func render() async -> UIImage? {
        let size = screenSize
        let card = DailyCard.pick(from: items)
        var photos: [String: UIImage] = [:]
        let needed = style == .board ? items.filter { $0.type == .image }.map(\.content) : [card.image].compactMap { $0 }
        for content in Set(needed) {
            photos[content] = await ImageStore.shared.image(for: content)
        }

        let content = Group {
            switch style {
            case .board: BoardWallpaper(items: items, paper: paper, size: size)
            case .today: TodayWallpaper(card: card, paper: paper, size: size)
            }
        }
        .environment(\.preloadedImages, photos)
        .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = displayScale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    private func save() async {
        guard let rendered else { return }
        saving = true
        defer { saving = false }
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else {
            status = String(localized: "VisionBoard can't save to Photos. Turn it on in Settings > Apps > VisionBoard > Photos.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: rendered)
            }
            status = String(localized: "Saved. In Photos, open it, tap Share, then Use as Wallpaper.")
        } catch {
            status = String(localized: "Couldn't save: \(error.localizedDescription)")
        }
    }
}

// Every clipping, fitted into the space below the Lock Screen clock and above
// the flashlight and camera buttons
private struct BoardWallpaper: View {
    let items: [BoardItem]
    let paper: PaperColor
    let size: CGSize

    var body: some View {
        let area = CGSize(width: size.width, height: size.height * 0.58)
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
            .offset(x: camera.offset.width, y: size.height * 0.3 + camera.offset.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}

// Today's photo full screen, today's goal in the lower third
private struct TodayWallpaper: View {
    let card: DailyCard
    let paper: PaperColor
    let size: CGSize

    var body: some View {
        ZStack(alignment: .bottom) {
            if let image = card.image {
                BoardImage(content: image)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            } else {
                paper.color
            }
            Text(card.text)
                .font(.custom("Georgia", size: 34))
                .foregroundStyle(card.image == nil ? Color(light: Palette.ink, dark: "#f2ede4") : .white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(card.image == nil ? 0 : 0.4), radius: 6, y: 2)
                .padding(.horizontal, 32)
                .padding(.bottom, size.height * 0.2)
        }
        .frame(width: size.width, height: size.height)
    }
}
