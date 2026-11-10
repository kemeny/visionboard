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
    var label: String { String(localized: String.LocalizationValue(rawValue.capitalized)) }
}

enum PaperColor: String, CaseIterable, Identifiable {
    case moleskine, cream, gray, stone, white
    var id: String { rawValue }
    var label: String { String(localized: String.LocalizationValue(rawValue.capitalized)) }
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

// The pannable, zoomable board. Drag empty paper to pan (it keeps gliding
// when flicked), pinch to zoom around your fingers, double-tap paper to zoom
// in or back out to the whole board. Drag any clipping to move it; pinch or
// twist the selected one to resize or rotate it. Pinching a clipping that
// isn't selected zooms the board, so a photo never gets resized by accident.
struct BoardCanvas: View {
    @Environment(BoardStore.self) private var store
    @Binding var selection: String?
    @Binding var camera: CanvasCamera
    @Binding var viewport: CGSize
    var pattern: CanvasPattern
    var paper: PaperColor
    var onEditText: (String) -> Void
    var onShowStyle: () -> Void

    private struct Pinch: Equatable {
        var scale: CGFloat = 1
        var anchor: CGPoint?
    }

    @GestureState private var pan: CGSize = .zero
    @GestureState private var pinch = Pinch()
    // A pinch that started on a clipping that isn't selected
    @State private var itemPinch: CGFloat = 1
    @State private var didInitialFit = false

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let live = liveCamera(center: center)
            ZStack(alignment: .topLeading) {
                PaperBackground(pattern: pattern, paper: paper, camera: live)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in zoomStep(at: location, in: geo.size) }
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
                            },
                            onBoardPinch: { itemPinch = $0 },
                            onBoardPinchEnded: { scale in
                                camera = camera.zoomed(by: scale, around: center)
                                itemPinch = 1
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
                        .onEnded { value in glide(value) },
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in
                            state = Pinch(scale: value.magnification, anchor: value.startLocation)
                        }
                        .onEnded { value in camera = camera.zoomed(by: value.magnification, around: value.startLocation) }
                )
            )
            .sensoryFeedback(.selection, trigger: selection) { _, new in new != nil }
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
        var cam = camera.zoomed(by: pinch.scale, around: pinch.anchor ?? center)
        if itemPinch != 1 { cam = cam.zoomed(by: itemPinch, around: center) }
        cam.offset.width += pan.width
        cam.offset.height += pan.height
        return cam
    }

    // A flick keeps the paper moving and slowing down, like a scroll view
    private func glide(_ value: DragGesture.Value) {
        let flingX = (value.predictedEndTranslation.width - value.translation.width) * 0.6
        let flingY = (value.predictedEndTranslation.height - value.translation.height) * 0.6
        if hypot(flingX, flingY) > 30 {
            withAnimation(.easeOut(duration: 0.5)) {
                camera.offset.width += value.translation.width + flingX
                camera.offset.height += value.translation.height + flingY
            }
        } else {
            camera.offset.width += value.translation.width
            camera.offset.height += value.translation.height
        }
    }

    // Double-tap paper: zoom in on that spot, or when already close, show the whole board
    private func zoomStep(at location: CGPoint, in size: CGSize) {
        withAnimation(.snappy) {
            if camera.zoom < 1.9 {
                camera = camera.zoomed(by: min(2, 2.5 / camera.zoom), around: location)
            } else {
                camera = .fitting(store.items, in: size)
            }
        }
    }
}

// Animatable so the dots glide with the clippings when the camera animates
private struct PaperBackground: View, Animatable {
    var pattern: CanvasPattern
    var paper: PaperColor
    var camera: CanvasCamera

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(camera.zoom, AnimatablePair(camera.offset.width, camera.offset.height)) }
        set {
            camera.zoom = newValue.first
            camera.offset = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

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

private typealias ManipulationValue = SimultaneousGesture<DragGesture, SimultaneousGesture<MagnifyGesture, RotateGesture>>.Value

// What the fingers are doing to one clipping right now
private struct LiveTransform: Equatable {
    var translation: CGSize = .zero
    var magnification: CGFloat = 1
    var rotation: Angle = .zero
    // Two fingers are down (a pinch or a twist)
    var pinched = false

    init() {}

    init(_ value: ManipulationValue) {
        translation = value.first?.translation ?? .zero
        magnification = value.second?.first?.magnification ?? 1
        rotation = value.second?.second?.rotation ?? .zero
        pinched = value.second?.first != nil || value.second?.second != nil
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
    var onBoardPinch: (CGFloat) -> Void = { _ in }
    var onBoardPinchEnded: (CGFloat) -> Void = { _ in }

    @GestureState private var live = LiveTransform()
    @State private var drops = 0
    @State private var lockedTaps = 0

    private static let minSide: Double = 40
    // A twist this close to straight (or a quarter turn) lands exactly on it
    private static let snapDegrees: Double = 4

    var body: some View {
        // Pinching a clipping that isn't selected zooms the board instead
        let boardPinch = !isSelected && live.pinched
        let translation = boardPinch ? .zero : live.translation
        let scale = isSelected ? clampedScale(live.magnification) : 1
        let rawRotation = (item.rotation ?? 0) + (isSelected ? live.rotation.degrees : 0)
        let rotation = Self.snapped(rawRotation)
        let snappedTo: Double? = isSelected && live.rotation != .zero && rotation != rawRotation ? rotation : nil
        let lifted = translation != .zero || (isSelected && live.pinched)

        ClippingView(item: item)
            .frame(width: CGFloat(item.width), height: CGFloat(item.height))
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
            // Picked up: a little bigger, with a deeper shadow, above everything else
            .animation(.snappy(duration: 0.2)) { content in
                content
                    .scaleEffect(lifted ? 1.03 : 1)
                    .shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: 18, y: 12)
            }
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .offset(
                x: CGFloat(item.x) + translation.width / zoom,
                y: CGFloat(item.y) + translation.height / zoom
            )
            .zIndex(lifted ? 1 : 0)
            .gesture(manipulation, including: item.isLocked ? .subviews : .all)
            .onTapGesture(count: 2) {
                onSelect()
                // A locked goal can't be edited; a buzz says so, and the bar offers Unlock
                if item.isLocked { lockedTaps += 1 } else if item.type == .text { onEditText() }
            }
            .onTapGesture { onSelect() }
            .onChange(of: boardPinch ? live.magnification : 1) { _, scale in onBoardPinch(scale) }
            .sensoryFeedback(.alignment, trigger: snappedTo) { _, new in new != nil }
            .sensoryFeedback(.impact(weight: .light), trigger: drops)
            .sensoryFeedback(.warning, trigger: lockedTaps)
            .contextMenu { ItemActions(item: item, onEditText: onEditText, onShowStyle: onShowStyle) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.type == .text ? item.content : String(localized: "Photo"))
            .accessibilityHint(item.type == .text ? String(localized: "Selects this goal. Double-tap twice to edit it.") : String(localized: "Selects this photo."))
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { onSelect() }
            .accessibilityActions { ItemActions(item: item, onEditText: onEditText, onShowStyle: onShowStyle) }
    }

    static func snapped(_ degrees: Double) -> Double {
        let nearest = (degrees / 90).rounded() * 90
        return abs(degrees - nearest) < snapDegrees ? nearest : degrees
    }

    // Keeps the shorter side at least minSide points
    private func clampedScale(_ factor: CGFloat) -> CGFloat {
        let shorter = CGFloat(min(item.width, item.height))
        guard shorter > 0 else { return factor }
        return max(factor, CGFloat(Self.minSide) / shorter)
    }

    private var manipulation: some Gesture {
        let id = item.id
        let selected = isSelected
        let zoom = zoom
        return DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .simultaneously(with: MagnifyGesture().simultaneously(with: RotateGesture()))
            .updating($live) { value, state, _ in state = LiveTransform(value) }
            .onEnded { value in
                let done = LiveTransform(value)
                if !selected && done.pinched {
                    onBoardPinchEnded(done.magnification)
                    return
                }
                let factor = selected ? Double(clampedScale(done.magnification)) : 1
                onSelect()
                drops += 1
                store.update(id) { item in
                    item.x += Double(done.translation.width / zoom)
                    item.y += Double(done.translation.height / zoom)
                    guard selected else { return }
                    if factor != 1 {
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
                    if done.rotation != .zero {
                        let degrees = Self.snapped((item.rotation ?? 0) + done.rotation.degrees)
                        item.rotation = (degrees * 10).rounded() / 10
                    }
                }
            }
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
    @Environment(\.preloadedImages) private var preloaded
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            // ImageRenderer draws in one pass, so wallpapers hand over their photos up front
            if let image = image ?? preloaded[content] {
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
            guard preloaded[content] == nil else { return }
            image = await ImageStore.shared.image(for: content)
            failed = image == nil
        }
    }
}

extension EnvironmentValues {
    @Entry var preloadedImages: [String: UIImage] = [:]
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
        Button(item.isLiked ? String(localized: "Unlike") : String(localized: "Like"), systemImage: item.isLiked ? "heart.slash" : "heart") {
            store.toggleLike(item.id)
        }
        Button("Bring to Front", systemImage: "square.3.layers.3d.top.filled") { store.bringToFront(item.id) }
        Button("Send to Back", systemImage: "square.3.layers.3d.bottom.filled") { store.sendToBack(item.id) }
        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(item.id) }
        Button(item.isLocked ? String(localized: "Unlock") : String(localized: "Lock"), systemImage: item.isLocked ? "lock.open" : "lock") {
            store.update(item.id) { $0.locked = $0.isLocked ? nil : true }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item.id) }
    }
}
