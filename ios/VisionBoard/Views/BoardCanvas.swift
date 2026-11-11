import SwiftUI

// Where the board is looked at from: canvas points times zoom, plus offset, gives screen points
struct CanvasCamera: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 0.05...4

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

// The board. Moving around is a UIScrollView (BoardInput): one finger drags
// the board, even across clippings, two fingers pinch and move it at once,
// flicks glide and the edges rubber-band like any iOS scroll view. A tap
// selects a clipping, a tap on paper lets it go, double-tap paper zooms in and
// again goes back. The selected clipping moves with one finger, and its
// corner handle resizes and turns it.
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

    @State private var didInitialFit = false
    // Where a double-tap zoomed in from, so the next one goes back there
    @State private var zoomReturn: CanvasCamera?
    // The clipping being moved, resized or turned right now
    @State private var live: ItemGesture?
    @State private var drops = 0
    @State private var lockedTaps = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                PaperBackground(pattern: pattern, paper: paper, camera: camera)
                    .accessibilityHidden(true)

                ZStack(alignment: .topLeading) {
                    ForEach(store.sortedItems) { item in
                        BoardItemView(
                            item: item,
                            isSelected: selection == item.id,
                            zoom: camera.zoom,
                            live: live?.id == item.id ? live : nil,
                            onSelect: { selection = item.id },
                            onEditText: { onEditText(item.id) },
                            onShowStyle: {
                                selection = item.id
                                onShowStyle()
                            }
                        )
                        .equatable()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .scaleEffect(camera.zoom, anchor: .topLeading)
                .offset(camera.offset)
                .allowsHitTesting(false)

                BoardInput(
                    camera: camera,
                    itemBounds: itemBounds,
                    target: target(at:),
                    onCamera: { moved in
                        if zoomReturn != nil { zoomReturn = nil }
                        var instant = Transaction()
                        instant.disablesAnimations = true
                        withTransaction(instant) { camera = moved }
                    },
                    onTap: tapped,
                    onDoubleTap: { target, point in doubleTapped(target, at: point, in: geo.size) },
                    onDrag: dragged,
                    menu: menu(for:),
                    outline: outline(of:)
                )
            }
            .clipped()
            // A clipping removed from a menu or by Undo can't stay selected
            .onChange(of: store.items.count) {
                if selection != nil, store.item(selection) == nil { selection = nil }
            }
            .sensoryFeedback(.selection, trigger: selection) { _, new in new != nil }
            .sensoryFeedback(.impact(weight: .light), trigger: drops)
            .sensoryFeedback(.warning, trigger: lockedTaps)
            .onAppear {
                viewport = geo.size
                bottomInset = geo.safeAreaInsets.bottom
                if !didInitialFit {
                    didInitialFit = true
                    camera = .fitting(store.items, in: geo.size, bottomInset: geo.safeAreaInsets.bottom)
                }
            }
            .onChange(of: geo.safeAreaInsets.bottom) { _, new in bottomInset = new }
            // Opening or folding iPhone Duo resizes the board. Keep the same
            // spot in the middle rather than jumping, so nothing is lost.
            .onChange(of: geo.size) { old, new in
                viewport = new
                camera.offset.width += (new.width - old.width) / 2
                camera.offset.height += (new.height - old.height) / 2
            }
        }
    }

    private var itemBounds: CGRect? {
        store.items.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }.reduce(nil) { $0?.union($1) ?? $1 }
    }

    // MARK: Hit testing

    private func target(at point: CGPoint) -> BoardTarget {
        let zoom = camera.zoom
        if let id = selection, let item = store.item(id), !item.isLocked {
            let corner = Self.rotate(
                CGPoint(x: item.width / 2 - 5 / zoom, y: item.height / 2 - 5 / zoom),
                by: Self.shownRotation(item)
            )
            let handle = screen(CGPoint(x: item.x + item.width / 2 + corner.x, y: item.y + item.height / 2 + corner.y))
            if hypot(point.x - handle.x, point.y - handle.y) <= 26 { return .handle(id) }
        }
        let canvas = camera.toCanvas(point)
        for item in store.sortedItems.reversed() where Self.contains(item, canvas, slop: 4 / zoom) {
            return item.id == selection && !item.isLocked ? .movable(item.id) : .item(item.id)
        }
        return .paper
    }

    private func screen(_ canvas: CGPoint) -> CGPoint {
        CGPoint(x: canvas.x * camera.zoom + camera.offset.width, y: canvas.y * camera.zoom + camera.offset.height)
    }

    static func shownRotation(_ item: BoardItem) -> Double { BoardItemView.snapped(item.rotation ?? 0) }

    static func rotate(_ point: CGPoint, by degrees: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: point.x * cos(r) - point.y * sin(r), y: point.x * sin(r) + point.y * cos(r))
    }

    private static func contains(_ item: BoardItem, _ point: CGPoint, slop: CGFloat) -> Bool {
        let local = rotate(
            CGPoint(x: point.x - (item.x + item.width / 2), y: point.y - (item.y + item.height / 2)),
            by: -shownRotation(item)
        )
        return abs(local.x) <= item.width / 2 + slop && abs(local.y) <= item.height / 2 + slop
    }

    // The clipping's on-screen bounding box
    private func outline(of id: String) -> CGRect? {
        guard let item = store.item(id) else { return nil }
        let corners = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { sx, sy in
            let p = Self.rotate(CGPoint(x: sx * item.width / 2, y: sy * item.height / 2), by: Self.shownRotation(item))
            return screen(CGPoint(x: item.x + item.width / 2 + p.x, y: item.y + item.height / 2 + p.y))
        }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    // MARK: Touches

    private func tapped(_ target: BoardTarget, _ point: CGPoint) {
        selection = target.itemID
    }

    private func doubleTapped(_ target: BoardTarget, at point: CGPoint, in size: CGSize) {
        guard let id = target.itemID, let item = store.item(id) else {
            zoomStep(at: point, in: size)
            return
        }
        selection = id
        // A locked goal can't be edited; a buzz says so, and the bar offers Unlock
        if item.isLocked { lockedTaps += 1 } else if item.type == .text { onEditText(id) }
    }

    private func dragged(_ drag: BoardDrag) {
        guard let id = drag.target.itemID, let item = store.item(id) else { return }
        let change: ItemGesture
        switch drag.target {
        case .movable:
            change = ItemGesture(id: id, translation: CGSize(width: drag.location.x - drag.start.x, height: drag.location.y - drag.start.y))
        case .handle:
            change = handleChange(item, from: drag.start, to: drag.location)
        default:
            return
        }
        switch drag.phase {
        case .changed:
            live = change
        case .ended:
            live = nil
            commit(change, resize: drag.target == .handle(id))
        case .cancelled:
            live = nil
        }
    }

    // How far from the middle of the clipping the finger is sets its size,
    // and the angle around the middle sets its tilt
    private func handleChange(_ item: BoardItem, from start: CGPoint, to location: CGPoint) -> ItemGesture {
        let center = screen(CGPoint(x: item.x + item.width / 2, y: item.y + item.height / 2))
        let from = CGPoint(x: start.x - center.x, y: start.y - center.y)
        let to = CGPoint(x: location.x - center.x, y: location.y - center.y)
        let startDistance = hypot(from.x, from.y)
        guard startDistance > 1 else { return ItemGesture(id: item.id) }
        var radians = atan2(to.y, to.x) - atan2(from.y, from.x)
        if radians > .pi { radians -= 2 * .pi }
        if radians < -.pi { radians += 2 * .pi }
        return ItemGesture(id: item.id, scale: hypot(to.x, to.y) / startDistance, rotation: .radians(radians))
    }

    // Writes a finished move, resize or turn to the board as one undo step
    private func commit(_ change: ItemGesture, resize: Bool) {
        guard let item = store.item(change.id) else { return }
        let zoom = camera.zoom
        let factor = resize ? Double(BoardItemView.clampedScale(change.scale, for: item)) : 1
        selection = change.id
        drops += 1
        store.update(change.id) { item in
            item.x += Double(change.translation.width / zoom)
            item.y += Double(change.translation.height / zoom)
            guard resize else { return }
            if factor != 1 {
                let newWidth = max(item.width * factor, BoardItemView.minSide)
                let newHeight = max(item.height * factor, BoardItemView.minSide)
                item.x -= (newWidth - item.width) / 2
                item.y -= (newHeight - item.height) / 2
                item.width = newWidth.rounded()
                item.height = newHeight.rounded()
                if item.type == .text, let size = item.fontSize {
                    item.fontSize = min(max((size * factor).rounded(), 10), 160)
                }
            }
            if change.rotation != .zero {
                var degrees = BoardItemView.snapped((item.rotation ?? 0) + change.rotation.degrees)
                degrees = degrees.truncatingRemainder(dividingBy: 360)
                item.rotation = (degrees * 10).rounded() / 10
            }
        }
    }

    // Double-tap paper: zoom in on that spot. Double-tap again to go back to
    // where you were, or to the whole board if you've moved since.
    private func zoomStep(at location: CGPoint, in size: CGSize) {
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

    // MARK: Long-press menu

    private func menu(for id: String) -> UIMenu? {
        guard let item = store.item(id) else { return nil }
        let store = store
        func action(_ title: String, _ symbol: String, destructive: Bool = false, _ run: @escaping () -> Void) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol), attributes: destructive ? .destructive : []) { _ in run() }
        }
        var edit: [UIMenuElement] = []
        if item.type == .text {
            edit.append(action(String(localized: "Edit Text"), "character.cursor.ibeam") { onEditText(id) })
            edit.append(action(String(localized: "Random Style"), "dice") {
                withAnimation(.snappy) { store.update(id) { $0.applyRandomLook() } }
            })
        }
        edit.append(action(String(localized: "Style"), "paintbrush") {
            selection = id
            onShowStyle()
        })
        edit.append(action(item.isLiked ? String(localized: "Unlike") : String(localized: "Like"), item.isLiked ? "heart.slash" : "heart") {
            store.toggleLike(id)
        })
        let arrange: [UIMenuElement] = [
            action(String(localized: "Bring to Front"), "square.3.layers.3d.top.filled") { store.bringToFront(id) },
            action(String(localized: "Send to Back"), "square.3.layers.3d.bottom.filled") { store.sendToBack(id) },
            action(String(localized: "Duplicate"), "plus.square.on.square") { selection = store.duplicate(id)?.id },
            action(item.isLocked ? String(localized: "Unlock") : String(localized: "Lock"), item.isLocked ? "lock.open" : "lock") {
                store.update(id) { $0.locked = $0.isLocked ? nil : true }
            },
        ]
        let delete = action(String(localized: "Delete"), "trash", destructive: true) {
            if selection == id { selection = nil }
            store.delete(id)
        }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: edit),
            UIMenu(options: .displayInline, children: arrange),
            delete,
        ])
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

    // The grid moves and scales with the board, but stays between 20 and 40
    // points apart on screen: zooming out, every other line fades away and
    // the spacing doubles; zooming in, finer lines fade in between.
    private static let base: CGFloat = 24
    private static let closest: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper.color))
            guard pattern != .blank, camera.zoom > 0 else { return }
            let onScreen = Self.base * camera.zoom
            let level = ceil(log2(Self.closest / onScreen))
            let fine = onScreen * pow(2, level)
            // The in-between lines are fully there at 40 points and gone at 20
            let fade = min(max((fine - Self.closest) / Self.closest, 0), 1)
            let firstX = Int(floor(-camera.offset.width / fine))
            let firstY = Int(floor(-camera.offset.height / fine))
            let columns = Int(size.width / fine) + 2
            let rows = Int(size.height / fine) + 2
            func x(_ i: Int) -> CGFloat { CGFloat(i) * fine + camera.offset.width }
            func y(_ j: Int) -> CGFloat { CGFloat(j) * fine + camera.offset.height }
            let ink = Color(light: "#000000", dark: "#ffffff")
            var main = Path()
            var between = Path()

            if pattern == .dots {
                let d: CGFloat = 2.4
                for i in firstX..<(firstX + columns) {
                    for j in firstY..<(firstY + rows) {
                        let dot = CGRect(x: x(i) - d / 2, y: y(j) - d / 2, width: d, height: d)
                        if i.isMultiple(of: 2) && j.isMultiple(of: 2) {
                            main.addEllipse(in: dot)
                        } else {
                            between.addEllipse(in: dot)
                        }
                    }
                }
                context.fill(main, with: .color(ink.opacity(0.2)))
                if fade > 0.01 { context.fill(between, with: .color(ink.opacity(0.2 * fade))) }
            } else {
                for i in firstX..<(firstX + columns) {
                    var line = Path()
                    line.move(to: CGPoint(x: x(i), y: 0))
                    line.addLine(to: CGPoint(x: x(i), y: size.height))
                    if i.isMultiple(of: 2) { main.addPath(line) } else { between.addPath(line) }
                }
                for j in firstY..<(firstY + rows) {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y(j)))
                    line.addLine(to: CGPoint(x: size.width, y: y(j)))
                    if j.isMultiple(of: 2) { main.addPath(line) } else { between.addPath(line) }
                }
                context.stroke(main, with: .color(ink.opacity(0.09)), lineWidth: 1)
                if fade > 0.01 { context.stroke(between, with: .color(ink.opacity(0.09 * fade)), lineWidth: 1) }
            }
        }
    }
}

// A clipping being moved (translation in screen points), or resized and
// turned by its corner handle
struct ItemGesture: Equatable {
    var id: String
    var translation: CGSize = .zero
    var scale: CGFloat = 1
    var rotation: Angle = .zero
}

// One clipping on the board. It takes no touches itself: BoardInput decides
// what a touch means, and BoardCanvas passes the live change in.
struct BoardItemView: View, Equatable {
    @Environment(BoardStore.self) private var store
    let item: BoardItem
    let isSelected: Bool
    let zoom: CGFloat
    let live: ItemGesture?
    var onSelect: () -> Void
    var onEditText: () -> Void
    var onShowStyle: () -> Void

    static let minSide: Double = 40
    // A twist this close to straight (or a quarter turn) lands exactly on it
    private static let snapDegrees: Double = 4

    nonisolated static func == (a: BoardItemView, b: BoardItemView) -> Bool {
        a.item == b.item && a.isSelected == b.isSelected && a.zoom == b.zoom && a.live == b.live
    }

    var body: some View {
        let translation = live?.translation ?? .zero
        let scale = isSelected ? Self.clampedScale(live?.scale ?? 1, for: item) : 1
        let turning = live?.rotation ?? .zero
        let rawRotation = (item.rotation ?? 0) + turning.degrees
        let rotation = Self.snapped(rawRotation)
        let snappedTo: Double? = turning != .zero && rotation != rawRotation ? rotation : nil
        let lifted = live != nil

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
            .sensoryFeedback(.alignment, trigger: snappedTo) { _, new in new != nil }
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
    static func clampedScale(_ factor: CGFloat, for item: BoardItem) -> CGFloat {
        let shorter = CGFloat(min(item.width, item.height))
        guard shorter > 0 else { return factor }
        return max(factor, CGFloat(minSide) / shorter)
    }

    // Drawn here; BoardCanvas finds it by position when a finger lands on it
    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11 / zoom, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26 / zoom, height: 26 / zoom)
            .background(Color.accentColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2 / zoom))
            .shadow(color: .black.opacity(0.2), radius: 3 / zoom, y: 1 / zoom)
            .frame(width: 44 / zoom, height: 44 / zoom)
            .offset(x: 17 / zoom, y: 17 / zoom)
            .accessibilityHidden(true)
    }
}

// One clipping drawn the way the web app draws it
struct ClippingView: View {
    let item: BoardItem

    var body: some View {
        switch item.type {
        case .image:
            // Filled and cropped to the clipping's own frame, like object-fit: cover
            // on the web. A photo never spills past the box you select and drag.
            Color.clear
                .overlay { BoardImage(content: item.content) }
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
