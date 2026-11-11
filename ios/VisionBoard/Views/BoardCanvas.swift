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
    // `bottomInset` is the part of the viewport hidden under bars
    static func fitting(_ items: [BoardItem], in viewport: CGSize, bottomInset: CGFloat = 0) -> CanvasCamera {
        let size = CGSize(width: viewport.width, height: viewport.height - bottomInset)
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
// in and again to go back. Drag any clipping to move it; drag the corner
// handle of the selected one, or pinch and twist it, to resize or rotate it.
// Pinching a clipping that isn't selected zooms the board, so a photo never
// gets resized by accident.
struct BoardCanvas: View {
    @Environment(BoardStore.self) private var store
    @Binding var selection: String?
    @Binding var camera: CanvasCamera
    @Binding var viewport: CGSize
    // How much of the bottom of the viewport sits under the action bar and tab bar
    @Binding var bottomInset: CGFloat
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
    @State private var itemPinch = Pinch()
    @State private var didInitialFit = false
    // The paper gliding after a flick; any new touch stops it
    @State private var glideTask: Task<Void, Never>?
    // Where a double-tap zoomed in from, so the next one goes back there
    @State private var zoomReturn: CanvasCamera?

    static let space = "board"

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let live = liveCamera(center: center)
            let origin = geo.frame(in: .global).origin
            ZStack(alignment: .topLeading) {
                PaperBackground(pattern: pattern, paper: paper, camera: live)
                    .contentShape(Rectangle())
                    // A single tap acts at once; the double tap is an extra on top of it
                    .onTapGesture { selection = nil }
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2).onEnded { zoomStep(at: $0.location, in: geo.size) }
                    )
                    .accessibilityHidden(true)

                ZStack(alignment: .topLeading) {
                    ForEach(store.sortedItems) { item in
                        BoardItemView(
                            item: item,
                            isSelected: selection == item.id,
                            camera: live,
                            onSelect: { selection = item.id },
                            onEditText: { onEditText(item.id) },
                            onShowStyle: {
                                selection = item.id
                                onShowStyle()
                            },
                            onBoardPinch: { scale, finger in
                                itemPinch = Pinch(scale: scale, anchor: finger.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) })
                            },
                            onBoardPinchEnded: { scale, finger in
                                let anchor = finger.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) } ?? center
                                camera = camera.zoomed(by: scale, around: anchor)
                                itemPinch = Pinch()
                                zoomReturn = nil
                            }
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .scaleEffect(live.zoom, anchor: .topLeading)
                .offset(live.offset)
            }
            .clipped()
            .coordinateSpace(.named(Self.space))
            .gesture(
                SimultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .updating($pan) { value, state, _ in state = value.translation }
                        .onEnded { value in glide(value) },
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in
                            state = Pinch(scale: value.magnification, anchor: value.startLocation)
                        }
                        .onEnded { value in
                            camera = camera.zoomed(by: value.magnification, around: value.startLocation)
                            zoomReturn = nil
                        }
                )
            )
            // A finger landing anywhere stops the paper, like catching a scroll view
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in stopGlide() })
            // A clipping removed from a menu or by Undo can't stay selected
            .onChange(of: store.items.count) {
                if selection != nil, store.item(selection) == nil { selection = nil }
            }
            .sensoryFeedback(.selection, trigger: selection) { _, new in new != nil }
            .onAppear {
                viewport = geo.size
                bottomInset = geo.safeAreaInsets.bottom
                if !didInitialFit {
                    didInitialFit = true
                    camera = .fitting(store.items, in: geo.size, bottomInset: geo.safeAreaInsets.bottom)
                }
            }
            .onChange(of: geo.safeAreaInsets.bottom) { _, new in bottomInset = new }
            .onDisappear { stopGlide() }
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
        if itemPinch.scale != 1 { cam = cam.zoomed(by: itemPinch.scale, around: itemPinch.anchor ?? center) }
        cam.offset.width += pan.width
        cam.offset.height += pan.height
        return cam
    }

    // A flick keeps the paper moving and slowing down at the rate a scroll
    // view does. It runs frame by frame so a touch can stop it where it is.
    private func glide(_ value: DragGesture.Value) {
        camera.offset.width += value.translation.width
        camera.offset.height += value.translation.height
        zoomReturn = nil
        let flick = value.velocity
        guard hypot(flick.width, flick.height) > 120 else { return }
        stopGlide()
        glideTask = Task { @MainActor in
            var velocity = flick
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled, hypot(velocity.width, velocity.height) > 12 {
                try? await Task.sleep(for: .milliseconds(8))
                guard !Task.isCancelled else { return }
                let now = clock.now
                let elapsed = now - last
                last = now
                let dt = min(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, 0.05)
                camera.offset.width += velocity.width * dt
                camera.offset.height += velocity.height * dt
                let decay = pow(0.998, dt * 1000)
                velocity.width *= decay
                velocity.height *= decay
            }
        }
    }

    private func stopGlide() {
        glideTask?.cancel()
        glideTask = nil
    }

    // Double-tap paper: zoom in on that spot. Double-tap again to go back to
    // where you were, or to the whole board if you've moved since.
    private func zoomStep(at location: CGPoint, in size: CGSize) {
        stopGlide()
        withAnimation(.snappy) {
            if let back = zoomReturn {
                camera = back
                zoomReturn = nil
            } else if camera.zoom < 1.9 {
                let before = camera
                camera = camera.zoomed(by: min(2, 2.5 / camera.zoom), around: location)
                zoomReturn = before
            } else {
                camera = .fitting(store.items, in: size, bottomInset: bottomInset)
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
    // Where the first finger landed, in screen points
    var finger: CGPoint?

    init() {}

    init(_ value: ManipulationValue) {
        translation = value.first?.translation ?? .zero
        finger = value.first?.startLocation
        magnification = value.second?.first?.magnification ?? 1
        rotation = value.second?.second?.rotation ?? .zero
        pinched = value.second?.first != nil || value.second?.second != nil
    }
}

// The corner handle being dragged: how far from the middle of the clipping
// the finger is sets its size, and the angle sets its tilt
private struct HandleDrag: Equatable {
    var scale: CGFloat = 1
    var rotation: Angle = .zero
    var active = false
}

struct BoardItemView: View {
    @Environment(BoardStore.self) private var store
    let item: BoardItem
    let isSelected: Bool
    let camera: CanvasCamera
    var onSelect: () -> Void
    var onEditText: () -> Void
    var onShowStyle: () -> Void
    // Scale so far, and where the first finger landed on screen
    var onBoardPinch: (CGFloat, CGPoint?) -> Void = { _, _ in }
    var onBoardPinchEnded: (CGFloat, CGPoint?) -> Void = { _, _ in }

    @GestureState private var live = LiveTransform()
    @GestureState private var handle = HandleDrag()
    private var zoom: CGFloat { camera.zoom }
    @State private var drops = 0
    @State private var lockedTaps = 0

    private static let minSide: Double = 40
    // A twist this close to straight (or a quarter turn) lands exactly on it
    private static let snapDegrees: Double = 4

    var body: some View {
        // Pinching a clipping that isn't selected zooms the board instead
        let boardPinch = !isSelected && live.pinched
        let translation = boardPinch ? .zero : live.translation
        let scale = isSelected ? clampedScale(live.magnification * handle.scale) : 1
        let turning = Angle.degrees(live.rotation.degrees + handle.rotation.degrees)
        let rawRotation = (item.rotation ?? 0) + (isSelected ? turning.degrees : 0)
        let rotation = Self.snapped(rawRotation)
        let snappedTo: Double? = isSelected && turning != .zero && rotation != rawRotation ? rotation : nil
        let lifted = translation != .zero || (isSelected && live.pinched) || handle.active

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
            .overlay(alignment: .bottomTrailing) {
                if isSelected && !item.isLocked { resizeHandle }
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
            // A single tap selects at once; the double tap is an extra on top of it
            .onTapGesture { onSelect() }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onSelect()
                    // A locked goal can't be edited; a buzz says so, and the bar offers Unlock
                    if item.isLocked { lockedTaps += 1 } else if item.type == .text { onEditText() }
                }
            )
            .onChange(of: boardPinch ? live.magnification : 1) { _, scale in onBoardPinch(scale, live.finger) }
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

    // One finger on the corner resizes and turns the clipping around its
    // middle, which is easier than a pinch on something small
    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11 / zoom, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26 / zoom, height: 26 / zoom)
            .background(Color.accentColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2 / zoom))
            .shadow(color: .black.opacity(0.2), radius: 3 / zoom, y: 1 / zoom)
            // A 44 point target on screen, whatever the zoom
            .frame(width: 44 / zoom, height: 44 / zoom)
            .contentShape(Rectangle())
            .offset(x: 17 / zoom, y: 17 / zoom)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BoardCanvas.space))
                    .updating($handle) { value, state, _ in state = handleDrag(value) }
                    .onEnded { value in
                        let done = handleDrag(value)
                        guard done.active else { return }
                        commit(translation: .zero, magnification: done.scale, rotation: done.rotation, resize: true)
                    }
            )
            .accessibilityHidden(true)
    }

    private func handleDrag(_ value: DragGesture.Value) -> HandleDrag {
        // The middle of the clipping in the board's screen space
        let center = CGPoint(
            x: CGFloat(item.x + item.width / 2) * zoom + camera.offset.width,
            y: CGFloat(item.y + item.height / 2) * zoom + camera.offset.height
        )
        let from = CGPoint(x: value.startLocation.x - center.x, y: value.startLocation.y - center.y)
        let to = CGPoint(x: value.location.x - center.x, y: value.location.y - center.y)
        let startDistance = hypot(from.x, from.y)
        guard startDistance > 1 else { return HandleDrag() }
        var radians = atan2(to.y, to.x) - atan2(from.y, from.x)
        if radians > .pi { radians -= 2 * .pi }
        if radians < -.pi { radians += 2 * .pi }
        return HandleDrag(scale: hypot(to.x, to.y) / startDistance, rotation: .radians(radians), active: true)
    }

    // Writes a finished move, resize or turn to the board as one undo step
    private func commit(translation: CGSize, magnification: CGFloat, rotation: Angle, resize: Bool) {
        let factor = resize ? Double(clampedScale(magnification)) : 1
        let zoom = self.zoom
        onSelect()
        drops += 1
        store.update(item.id) { item in
            item.x += Double(translation.width / zoom)
            item.y += Double(translation.height / zoom)
            guard resize else { return }
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
            if rotation != .zero {
                var degrees = Self.snapped((item.rotation ?? 0) + rotation.degrees)
                degrees = degrees.truncatingRemainder(dividingBy: 360)
                item.rotation = (degrees * 10).rounded() / 10
            }
        }
    }

    // Keeps the shorter side at least minSide points
    private func clampedScale(_ factor: CGFloat) -> CGFloat {
        let shorter = CGFloat(min(item.width, item.height))
        guard shorter > 0 else { return factor }
        return max(factor, CGFloat(Self.minSide) / shorter)
    }

    private var manipulation: some Gesture {
        let selected = isSelected
        return DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .simultaneously(with: MagnifyGesture().simultaneously(with: RotateGesture()))
            .updating($live) { value, state, _ in state = LiveTransform(value) }
            .onEnded { value in
                let done = LiveTransform(value)
                if !selected && done.pinched {
                    onBoardPinchEnded(done.magnification, done.finger)
                    return
                }
                commit(translation: done.translation, magnification: done.magnification, rotation: done.rotation, resize: selected)
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
