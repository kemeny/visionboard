import SwiftUI

// Where the board is looked at from: canvas points times zoom, plus offset, gives screen points
struct CanvasCamera: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 0.15...4

    var zoom: CGFloat = 1
    var offset: CGSize = .zero

    func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) / zoom, y: (point.y - offset.height) / zoom)
    }

    // Zoom by a factor while keeping `anchor` (a screen point) still
    func zoomed(by factor: CGFloat, around anchor: CGPoint) -> CanvasCamera {
        let newZoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let ratio = newZoom / zoom
        return CanvasCamera(
            zoom: newZoom,
            offset: CGSize(width: anchor.x - (anchor.x - offset.width) * ratio, height: anchor.y - (anchor.y - offset.height) * ratio)
        )
    }

    // Frames every item inside a viewport, leaving a margin
    static func fitting(_ items: [BoardItem], in size: CGSize) -> CanvasCamera {
        guard !items.isEmpty, size.width > 0, size.height > 0 else { return CanvasCamera() }
        let minX = items.map(\.x).min()!, minY = items.map(\.y).min()!
        let maxX = items.map { $0.x + $0.width }.max()!, maxY = items.map { $0.y + $0.height }.max()!
        let bounds = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
        let zoom = min(max(min(size.width / bounds.width, size.height / bounds.height) * 0.88, zoomRange.lowerBound), 1.5)
        return CanvasCamera(
            zoom: zoom,
            offset: CGSize(width: size.width / 2 - bounds.midX * zoom, height: size.height / 2 - bounds.midY * zoom)
        )
    }
}

enum CanvasPattern: String, CaseIterable, Identifiable {
    case dots, grid, blank
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PaperColor: String, CaseIterable, Identifiable {
    case moleskine, cream, gray, stone, white
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    // Each paper has a night version, so the board follows Dark Mode like the bars around it
    var color: Color {
        switch self {
        case .moleskine: Color(light: "#f5f0e8", dark: "#1f1c18")
        case .cream: Color(light: "#faf6ef", dark: "#24201a")
        case .gray: Color(light: "#f0f0ee", dark: "#1c1c1e")
        case .stone: Color(light: "#eae6df", dark: "#2a2622")
        case .white: Color(light: "#ffffff", dark: "#000000")
        }
    }
}

// The pannable, zoomable board. Drag empty paper to pan, pinch to zoom; drag
// a clipping to move it, pinch or twist it to resize or rotate.
struct BoardCanvas: View {
    @Environment(BoardStore.self) private var store
    @Binding var selection: String?
    @Binding var camera: CanvasCamera
    @Binding var viewport: CGSize
    var pattern: CanvasPattern
    var paper: PaperColor
    var onEditText: (String) -> Void
    var onShowStyle: () -> Void

    @GestureState private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @State private var didInitialFit = false

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let live = liveCamera(center: center)
            ZStack(alignment: .topLeading) {
                PaperBackground(pattern: pattern, paper: paper, camera: live)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }
                    .accessibilityHidden(true)

                ZStack(alignment: .topLeading) {
                    ForEach(store.sortedItems) { item in
                        BoardItemView(
                            item: item,
                            isSelected: selection == item.id,
                            zoom: live.zoom,
                            onSelect: { selection = item.id },
                            onEditText: { onEditText(item.id) },
                            onShowStyle: {
                                selection = item.id
                                onShowStyle()
                            }
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .scaleEffect(live.zoom, anchor: .topLeading)
                .offset(live.offset)
            }
            .clipped()
            .gesture(
                SimultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .updating($pan) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            camera.offset.width += value.translation.width
                            camera.offset.height += value.translation.height
                        },
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in camera = camera.zoomed(by: value.magnification, around: center) }
                )
            )
            .onAppear {
                viewport = geo.size
                if !didInitialFit {
                    didInitialFit = true
                    camera = .fitting(store.items, in: geo.size)
                }
            }
            // Opening or folding iPhone Duo resizes the board. Keep the same
            // spot in the middle rather than jumping, so nothing is lost.
            .onChange(of: geo.size) { old, new in
                viewport = new
                camera.offset.width += (new.width - old.width) / 2
                camera.offset.height += (new.height - old.height) / 2
            }
        }
    }

    private func liveCamera(center: CGPoint) -> CanvasCamera {
        var cam = camera.zoomed(by: pinch, around: center)
        cam.offset.width += pan.width
        cam.offset.height += pan.height
        return cam
    }
}

private struct PaperBackground: View {
    var pattern: CanvasPattern
    var paper: PaperColor
    var camera: CanvasCamera

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper.color))
            guard pattern != .blank else { return }
            let spacing = 24 * camera.zoom
            guard spacing >= 6 else { return }
            let startX = camera.offset.width.truncatingRemainder(dividingBy: spacing) - spacing
            let startY = camera.offset.height.truncatingRemainder(dividingBy: spacing) - spacing
            let ink = Color(light: "#000000", dark: "#ffffff").opacity(pattern == .dots ? 0.16 : 0.07)
            if pattern == .dots {
                let r = max(1, 1.2 * camera.zoom)
                var path = Path()
                for x in stride(from: startX, through: size.width, by: spacing) {
                    for y in stride(from: startY, through: size.height, by: spacing) {
                        path.addEllipse(in: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r))
                    }
                }
                context.fill(path, with: .color(ink))
            } else {
                var path = Path()
                for x in stride(from: startX, through: size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: startY, through: size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(ink), lineWidth: 1)
            }
        }
    }
}

struct BoardItemView: View {
    @Environment(BoardStore.self) private var store
    let item: BoardItem
    let isSelected: Bool
    let zoom: CGFloat
    var onSelect: () -> Void
    var onEditText: () -> Void
    var onShowStyle: () -> Void

    @GestureState private var drag: CGSize = .zero
    @GestureState private var scale: CGFloat = 1
    @GestureState private var spin: Angle = .zero

    private static let minSide: Double = 40

    var body: some View {
        let width = CGFloat(max(item.width * Double(scale), Self.minSide))
        let height = CGFloat(max(item.height * Double(scale), Self.minSide))
        ClippingView(item: item)
            .frame(width: width, height: height)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor, lineWidth: 2 / zoom)
                        .padding(-5 / zoom)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.isLocked && isSelected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12 / zoom))
                        .padding(5 / zoom)
                        .background(.orange, in: Circle())
                        .foregroundStyle(.white)
                        .offset(x: 10 / zoom, y: -10 / zoom)
                }
            }
            .rotationEffect(.degrees((item.rotation ?? 0) + spin.degrees))
            .offset(
                x: CGFloat(item.x) - (width - CGFloat(item.width)) / 2 + drag.width / zoom,
                y: CGFloat(item.y) - (height - CGFloat(item.height)) / 2 + drag.height / zoom
            )
            .gesture(manipulation, including: item.isLocked ? .subviews : .all)
            .onTapGesture(count: 2) {
                onSelect()
                if item.type == .text && !item.isLocked { onEditText() }
            }
            .onTapGesture { onSelect() }
            .contextMenu { ItemActions(item: item, onEditText: onEditText, onShowStyle: onShowStyle) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.type == .text ? item.content : "Photo")
            .accessibilityHint(item.type == .text ? "Double-tap to select. Double-tap twice to edit." : "Double-tap to select.")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { onSelect() }
            .accessibilityActions { ItemActions(item: item, onEditText: onEditText, onShowStyle: onShowStyle) }
    }

    private var manipulation: some Gesture {
        let id = item.id
        let move = DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                onSelect()
                store.update(id) {
                    $0.x += Double(value.translation.width / zoom)
                    $0.y += Double(value.translation.height / zoom)
                }
            }
        let resize = MagnifyGesture()
            .updating($scale) { value, state, _ in state = value.magnification }
            .onEnded { value in
                let factor = Double(value.magnification)
                store.update(id) { item in
                    let newWidth = max(item.width * factor, Self.minSide)
                    let newHeight = max(item.height * factor, Self.minSide)
                    item.x -= (newWidth - item.width) / 2
                    item.y -= (newHeight - item.height) / 2
                    item.width = newWidth.rounded()
                    item.height = newHeight.rounded()
                    if item.type == .text, let size = item.fontSize {
                        item.fontSize = min(max((size * factor).rounded(), 10), 160)
                    }
                }
            }
        let rotate = RotateGesture()
            .updating($spin) { value, state, _ in state = value.rotation }
            .onEnded { value in
                store.update(id) { item in
                    let degrees = (item.rotation ?? 0) + value.rotation.degrees
                    item.rotation = (degrees * 10).rounded() / 10
                }
            }
        return move.simultaneously(with: resize.simultaneously(with: rotate))
    }
}

// One clipping drawn the way the web app draws it
struct ClippingView: View {
    let item: BoardItem

    var body: some View {
        switch item.type {
        case .image:
            BoardImage(content: item.content)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        case .text:
            let style = TextStyle(item.fontStyle)
            let size = CGFloat(item.fontSize ?? 18)
            let background = Color(css: item.bgColor)
            Text(style.uppercased ? item.content.uppercased() : item.content)
                .font(style.font(size: size))
                .tracking(style.trackingEm * size)
                .lineSpacing(max(0, (style.lineHeight - 1.2) * size))
                .foregroundStyle(Self.textColor(item, onBackground: background != nil))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background ?? .clear, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

extension ClippingView {
    // Words written straight on the paper in the default ink (or white) flip
    // with the paper, so they stay readable in both modes. Text on its own
    // colored background, and any other ink color, keeps the color chosen.
    static func textColor(_ item: BoardItem, onBackground: Bool) -> Color {
        let css = item.color?.lowercased() ?? Palette.ink
        if !onBackground && css == Palette.ink { return Color(light: Palette.ink, dark: "#f2ede4") }
        if !onBackground && css == "#ffffff" { return Color(light: "#ffffff", dark: Palette.ink) }
        return Color(css: css) ?? Color(css: Palette.ink)!
    }
}

struct BoardImage: View {
    let content: String
    var mode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: mode)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if failed {
                            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .task(id: content) {
            image = await ImageStore.shared.image(for: content)
            failed = image == nil
        }
    }
}

// Shared by the context menu, VoiceOver actions and the inspector
struct ItemActions: View {
    @Environment(BoardStore.self) private var store
    let item: BoardItem
    var onEditText: () -> Void
    var onShowStyle: () -> Void

    var body: some View {
        if item.type == .text {
            Button("Edit Text", systemImage: "character.cursor.ibeam", action: onEditText)
            Button("Random Style", systemImage: "dice") {
                withAnimation(.snappy) { store.update(item.id) { $0.applyRandomLook() } }
            }
        }
        Button("Style", systemImage: "paintbrush", action: onShowStyle)
        Button(item.isLiked ? "Unlike" : "Like", systemImage: item.isLiked ? "heart.slash" : "heart") {
            store.toggleLike(item.id)
        }
        Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { store.bringToFront(item.id) }
        Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { store.sendToBack(item.id) }
        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(item.id) }
        Button(item.isLocked ? "Unlock" : "Lock", systemImage: item.isLocked ? "lock.open" : "lock") {
            store.update(item.id) { $0.locked = $0.isLocked ? nil : true }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item.id) }
    }
}
